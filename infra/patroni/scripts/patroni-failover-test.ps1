param(
    [switch]$PlanOnly,
    [switch]$Execute,
    [switch]$SkipRestartStoppedLeader,
    [int]$TimeoutSeconds = 180,
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
            }
        }
        catch {
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = $node.Service
                Port = $node.Port
                Role = "unreachable"
                State = "unreachable"
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

function Wait-ReplicaState {
    param([string]$ReplicaName)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 5
        $replica = Get-NodeStatuses | Where-Object { $_.Name -eq $ReplicaName -or $_.Service -eq $ReplicaName } | Select-Object -First 1
        if ($replica -and $replica.Role -in @("replica", "standby_leader")) {
            return $replica
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $ReplicaName to return as replica"
}

function Invoke-WriterSql {
    param([string]$Sql)

    $Sql | docker compose @composeArgs exec -T -e "PGPASSWORD=$AdminPassword" patroni-postgres-1 `
        psql -h patroni-postgres-lb -p 5432 -U $AdminUser -d $Database -v ON_ERROR_STOP=1

    if ($LASTEXITCODE -ne 0) {
        throw "Writer SQL validation failed."
    }
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
Write-Host "FAILOVER_TEST_ACTION=stop_container service=$($leader.Service)"
Write-Host "FAILOVER_TEST_SKIP_RESTART_STOPPED_LEADER=$SkipRestartStoppedLeader"

if ($PlanOnly) {
    Write-Host "FAILOVER_TEST_STATUS=PLAN_ONLY"
    Write-Host "FAILOVER_TEST_HINT=Run with -Execute to stop the current leader temporarily."
    exit 0
}

Push-Location $root
try {
    Write-Host "FAILOVER_TEST_STOP_LEADER service=$($leader.Service)"
    docker compose @composeArgs stop $leader.Service
    if ($LASTEXITCODE -ne 0) {
        throw "Could not stop leader container $($leader.Service)"
    }

    $newLeader = Wait-NewLeader -OldLeader $leader.Name
    Write-Host "FAILOVER_TEST_NEW_LEADER=$($newLeader.Name)"

    & "$PSScriptRoot\patroni-db-connection-test.ps1" -SkipReader
    if ($LASTEXITCODE -ne 0) {
        throw "HAProxy writer did not route to the new leader."
    }

    $probeId = [guid]::NewGuid().ToString()
    $probeSql = @"
CREATE SCHEMA IF NOT EXISTS health_check;
CREATE TABLE IF NOT EXISTS health_check.ha_write_probe (
    probe_id uuid PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    old_leader text NOT NULL,
    new_leader text NOT NULL
);
INSERT INTO health_check.ha_write_probe (probe_id, old_leader, new_leader)
VALUES ('$probeId', '$($leader.Name)', '$($newLeader.Name)');
SELECT probe_id, old_leader, new_leader FROM health_check.ha_write_probe WHERE probe_id = '$probeId';
"@
    Invoke-WriterSql -Sql $probeSql
    Write-Host "FAILOVER_TEST_WRITE_PROBE_OK probe_id=$probeId"

    if (-not $SkipRestartStoppedLeader) {
        Write-Host "FAILOVER_TEST_RESTART_OLD_LEADER service=$($leader.Service)"
        docker compose @composeArgs start $leader.Service
        if ($LASTEXITCODE -ne 0) {
            throw "Could not restart stopped leader $($leader.Service)"
        }

        $replica = Wait-ReplicaState -ReplicaName $leader.Name
        Write-Host "FAILOVER_TEST_OLD_LEADER_RETURNED_AS_REPLICA name=$($replica.Name) state=$($replica.State)"
    }
    else {
        Write-Host "FAILOVER_TEST_RESTART_SKIPPED service=$($leader.Service)"
    }

    Write-Host "FAILOVER_TEST_STATUS=OK"
}
catch {
    Write-Host "FAILOVER_TEST_STATUS=ERROR message=$($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}
