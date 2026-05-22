param(
    [switch]$PlanOnly,
    [switch]$Execute,
    [switch]$SkipRecovery,
    [int]$TimeoutSeconds = 180,
    [int]$WriterRetrySeconds = 120,
    [int]$WriterRetryIntervalSeconds = 5,
    [string]$Database = "mediqueue",
    [string]$AdminUser = "postgres",
    [string]$AdminPassword = "postgres",
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")
$nodes = @(
    @{ Service = "patroni-postgres-1"; Port = 18008 },
    @{ Service = "patroni-postgres-2"; Port = 18009 },
    @{ Service = "patroni-postgres-3"; Port = 18010 }
)

function Get-NodeStatuses {
    $statuses = @()
    foreach ($node in $nodes | Where-Object { $RestPorts -contains $_.Port }) {
        try {
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$($node.Port)/patroni" -TimeoutSec 3
            $nodeName = if ($status.name) { $status.name } else { $node.Service }
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = $nodeName
                Port = $node.Port
                Role = $status.role
                State = $status.state
                Timeline = $status.timeline
                Reachable = $true
            }
        }
        catch {
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = $node.Service
                Port = $node.Port
                Role = "unreachable"
                State = "unreachable"
                Timeline = ""
                Reachable = $false
            }
        }
    }
    return $statuses
}

function Get-Leader {
    Get-NodeStatuses | Where-Object { $_.Role -in @("primary", "master") } | Select-Object -First 1
}

function Wait-NewLeader {
    param([string]$OldLeader)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 3
        $leader = Get-Leader
        if ($leader -and $leader.Name -ne $OldLeader) {
            return $leader
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for automatic failover from $OldLeader"
}

function Get-RunnerService {
    param([string]$PreferredService)

    $statuses = Get-NodeStatuses
    $candidates = @()
    if ($PreferredService) {
        $candidates += $statuses | Where-Object { $_.Service -eq $PreferredService -and $_.Reachable -and $_.State -eq "running" }
    }
    $candidates += $statuses | Where-Object { $_.Role -in @("primary", "master") -and $_.Reachable -and $_.State -eq "running" }
    $candidates += $statuses | Where-Object { $_.Role -in @("replica", "standby_leader") -and $_.Reachable -and $_.State -eq "running" }

    $runner = $candidates | Select-Object -First 1
    if (-not $runner) {
        throw "No running Patroni service is available to execute psql."
    }

    return $runner.Service
}

function Wait-WriterReady {
    param([string]$RunnerService)

    $deadline = (Get-Date).AddSeconds($WriterRetrySeconds)
    $attempt = 0
    do {
        $attempt++
        try {
            $result = docker compose @composeArgs exec -T -e "PGPASSWORD=$AdminPassword" $RunnerService `
                psql -h patroni-postgres-lb -p 5432 -U $AdminUser -d $Database -At -v ON_ERROR_STOP=1 -c "SELECT pg_is_in_recovery();"
            if ($LASTEXITCODE -eq 0) {
                $value = (($result | Select-Object -First 1) -as [string]).Trim()
                Write-Host "FAILOVER_TEST_WRITER_RETRY attempt=$attempt pg_is_in_recovery=$value"
                if ($value -eq "f") {
                    return $true
                }
            }
            else {
                Write-Host "FAILOVER_TEST_WRITER_RETRY attempt=$attempt exit_code=$LASTEXITCODE"
            }
        }
        catch {
            Write-Host "FAILOVER_TEST_WRITER_RETRY attempt=$attempt error=$($_.Exception.Message)"
        }

        Start-Sleep -Seconds $WriterRetryIntervalSeconds
    } while ((Get-Date) -lt $deadline)

    throw "HAProxy writer did not stabilize within $WriterRetrySeconds seconds."
}

function Invoke-WriterSql {
    param(
        [string]$Sql,
        [string]$RunnerService
    )

    $Sql | docker compose @composeArgs exec -T -e "PGPASSWORD=$AdminPassword" $RunnerService `
        psql -h patroni-postgres-lb -p 5432 -U $AdminUser -d $Database -v ON_ERROR_STOP=1

    if ($LASTEXITCODE -ne 0) {
        throw "Writer SQL validation failed."
    }
}

function Wait-ContainerRunning {
    param(
        [string]$Service,
        [int]$WaitSeconds = $TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        $state = docker compose @composeArgs ps --format json $Service | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0 -and $state -and $state.State -eq "running") {
            return $true
        }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Ensure-ServiceRestartPolicy {
    param([string]$Service)

    $containerId = docker compose @composeArgs ps -a -q $Service
    if ($LASTEXITCODE -eq 0 -and $containerId) {
        docker update --restart unless-stopped $containerId | Out-Null
    }
}

function Ensure-OldLeaderRunning {
    param([object]$OldLeader)

    Ensure-ServiceRestartPolicy -Service $OldLeader.Service

    $running = Wait-ContainerRunning -Service $OldLeader.Service -WaitSeconds 30
    if (-not $running) {
        Write-Host "FAILOVER_TEST_OLD_LEADER_NOT_RUNNING action=up service=$($OldLeader.Service)"
        docker compose @composeArgs up -d $OldLeader.Service
        if ($LASTEXITCODE -ne 0) {
            throw "Could not start old leader service $($OldLeader.Service)"
        }
        $running = Wait-ContainerRunning -Service $OldLeader.Service -WaitSeconds $TimeoutSeconds
    }
    else {
        Write-Host "FAILOVER_TEST_OLD_LEADER_AUTO_RESTARTED service=$($OldLeader.Service)"
    }

    if (-not $running) {
        throw "Old leader service $($OldLeader.Service) did not reach running state."
    }
}

function Wait-ReplicaState {
    param([string]$ReplicaName)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 5
        $replica = Get-NodeStatuses | Where-Object { $_.Name -eq $ReplicaName -or $_.Service -eq $ReplicaName } | Select-Object -First 1
        if ($replica -and $replica.Role -in @("replica", "standby_leader") -and $replica.State -eq "running") {
            return $replica
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $ReplicaName to return as replica"
}

if ($PlanOnly -and $Execute) {
    throw "Use -PlanOnly or -Execute, not both."
}

if (-not $PlanOnly -and -not $Execute) {
    $PlanOnly = $true
}

$leader = Get-Leader
if (-not $leader) {
    throw "No Patroni leader found."
}

Write-Host "FAILOVER_TEST_MODE plan_only=$PlanOnly execute=$Execute"
Write-Host "FAILOVER_TEST_CURRENT_LEADER=$($leader.Name)"
Write-Host "FAILOVER_TEST_ACTION=kill_container service=$($leader.Service)"
Write-Host "FAILOVER_TEST_SKIP_RECOVERY=$SkipRecovery"
Write-Host "FAILOVER_TEST_WRITER_RETRY seconds=$WriterRetrySeconds interval=$WriterRetryIntervalSeconds"

if ($PlanOnly) {
    Write-Host "FAILOVER_TEST_STATUS=PLAN_ONLY"
    Write-Host "FAILOVER_TEST_HINT=Run with -Execute to docker kill the current leader and verify recovery."
    exit 0
}

Push-Location $root
try {
    Write-Host "FAILOVER_TEST_KILL_LEADER service=$($leader.Service)"
    docker compose @composeArgs kill $leader.Service
    if ($LASTEXITCODE -ne 0) {
        throw "Could not kill leader container $($leader.Service)"
    }

    $newLeader = Wait-NewLeader -OldLeader $leader.Name
    Write-Host "FAILOVER_TEST_NEW_LEADER=$($newLeader.Name)"
    if ($newLeader.Name -eq $leader.Name) {
        throw "New leader must be different from old leader."
    }

    $runnerService = Get-RunnerService -PreferredService $newLeader.Service
    Write-Host "FAILOVER_TEST_RUNNER_SERVICE=$runnerService"

    Wait-WriterReady -RunnerService $runnerService | Out-Null
    Write-Host "FAILOVER_TEST_WRITER_READY=True"

    $testName = "patroni-failover-$((Get-Date).ToString('yyyyMMddHHmmss'))"
    $probeSql = @"
CREATE SCHEMA IF NOT EXISTS health_check;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO `$`$
BEGIN
    IF to_regclass('health_check.ha_write_probe') IS NULL THEN
        CREATE TABLE health_check.ha_write_probe (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            test_name text NOT NULL,
            observed_leader text,
            created_at timestamptz DEFAULT now()
        );
    ELSE
        ALTER TABLE health_check.ha_write_probe ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid();
        ALTER TABLE health_check.ha_write_probe ADD COLUMN IF NOT EXISTS test_name text;
        ALTER TABLE health_check.ha_write_probe ADD COLUMN IF NOT EXISTS observed_leader text;
        ALTER TABLE health_check.ha_write_probe ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
        UPDATE health_check.ha_write_probe SET id = gen_random_uuid() WHERE id IS NULL;
    END IF;
END
`$`$;
INSERT INTO health_check.ha_write_probe (test_name, observed_leader)
VALUES ('$testName', '$($newLeader.Name)')
RETURNING id, test_name, observed_leader, created_at;
"@
    Invoke-WriterSql -Sql $probeSql -RunnerService $runnerService
    Write-Host "FAILOVER_TEST_WRITE_PROBE_OK test_name=$testName observed_leader=$($newLeader.Name)"

    if (-not $SkipRecovery) {
        Ensure-OldLeaderRunning -OldLeader $leader

        $replica = Wait-ReplicaState -ReplicaName $leader.Name
        Write-Host "FAILOVER_TEST_OLD_LEADER_RETURNED_AS_REPLICA name=$($replica.Name) state=$($replica.State) timeline=$($replica.Timeline)"

        & "$PSScriptRoot\patroni-cluster-recovery-check.ps1"
        if ($LASTEXITCODE -ne 0) {
            throw "Cluster did not return to full recovery after failover."
        }
    }
    else {
        Write-Host "FAILOVER_TEST_RECOVERY_SKIPPED service=$($leader.Service)"
    }

    Write-Host "FAILOVER_TEST_STATUS=OK"
}
catch {
    if ($Execute -and -not $SkipRecovery -and $leader) {
        try {
            Write-Host "FAILOVER_TEST_RECOVERY_ON_ERROR service=$($leader.Service)"
            Ensure-OldLeaderRunning -OldLeader $leader
            Write-Host "FAILOVER_TEST_RECOVERY_ON_ERROR_DONE service=$($leader.Service)"
        }
        catch {
            Write-Host "FAILOVER_TEST_RECOVERY_ON_ERROR_FAILED message=$($_.Exception.Message)"
        }
    }
    Write-Host "FAILOVER_TEST_STATUS=ERROR message=$($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}
