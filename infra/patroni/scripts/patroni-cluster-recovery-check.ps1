param(
    [int[]]$RestPorts = @(18008, 18009, 18010),
    [string]$Database = "mediqueue",
    [string]$User = "mediqueue",
    [string]$Password = "mediqueue",
    [string]$AdminUser = "postgres",
    [string]$AdminPassword = "postgres",
    [int]$MaxLagBytes = 1048576
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
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = if ($status.name) { $status.name } else { $node.Service }
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

function Get-RunnerService {
    param([object[]]$Statuses)

    $runner = $Statuses |
        Where-Object { $_.Role -in @("primary", "master", "replica", "standby_leader") -and $_.Reachable -and $_.State -eq "running" } |
        Select-Object -First 1

    if (-not $runner) {
        throw "No running Patroni service is available to execute psql."
    }

    return $runner.Service
}

function Invoke-PsqlScalar {
    param(
        [string]$Port,
        [string]$Sql,
        [string]$RunnerService
    )

    $result = docker compose @composeArgs exec -T -e "PGPASSWORD=$Password" $RunnerService `
        psql -h patroni-postgres-lb -p $Port -U $User -d $Database -At -v ON_ERROR_STOP=1 -c $Sql

    if ($LASTEXITCODE -ne 0) {
        throw "psql failed on HAProxy port $Port"
    }

    return (($result | Select-Object -First 1) -as [string]).Trim()
}

Push-Location $root
try {
    $statuses = Get-NodeStatuses
    $reachable = @($statuses | Where-Object { $_.Reachable }).Count
    $leaders = @($statuses | Where-Object { $_.Role -in @("primary", "master") })
    $replicas = @($statuses | Where-Object { $_.Role -in @("replica", "standby_leader") })

    $statuses | ForEach-Object {
        Write-Host "RECOVERY_NODE name=$($_.Name) service=$($_.Service) role=$($_.Role) state=$($_.State) reachable=$($_.Reachable)"
    }

    Write-Host "RECOVERY_REACHABLE_NODES=$reachable"
    Write-Host "RECOVERY_LEADER_COUNT=$(@($leaders).Count)"
    Write-Host "RECOVERY_REPLICA_COUNT=$(@($replicas).Count)"

    $runnerService = Get-RunnerService -Statuses $statuses
    Write-Host "RECOVERY_RUNNER_SERVICE=$runnerService"

    $writerRecovery = Invoke-PsqlScalar -Port "5432" -Sql "SELECT pg_is_in_recovery();" -RunnerService $runnerService
    $readerRecovery = Invoke-PsqlScalar -Port "5433" -Sql "SELECT pg_is_in_recovery();" -RunnerService $runnerService
    Write-Host "RECOVERY_WRITER_PG_IS_IN_RECOVERY=$writerRecovery"
    Write-Host "RECOVERY_READER_PG_IS_IN_RECOVERY=$readerRecovery"

    $lagRows = docker compose @composeArgs exec -T -e "PGPASSWORD=$AdminPassword" $runnerService `
        psql -h patroni-postgres-lb -p 5432 -U $AdminUser -d $Database -At -v ON_ERROR_STOP=1 -c "SELECT COALESCE(max(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)),0)::bigint FROM pg_stat_replication;"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read replication lag."
    }
    $maxLag = [int64]((($lagRows | Select-Object -First 1) -as [string]).Trim())
    Write-Host "RECOVERY_MAX_REPLICA_LAG_BYTES=$maxLag"

    & "$PSScriptRoot\haproxy-db-healthcheck.ps1"
    $haproxyOk = ($LASTEXITCODE -eq 0)
    Write-Host "RECOVERY_HAPROXY_OK=$haproxyOk"

    if ($reachable -ne 3 -or @($leaders).Count -ne 1 -or @($replicas).Count -ne 2 -or $writerRecovery -ne "f" -or $readerRecovery -ne "t" -or $maxLag -gt $MaxLagBytes -or -not $haproxyOk) {
        Write-Host "PATRONI_CLUSTER_RECOVERY_STATUS=ERROR"
        exit 1
    }

    Write-Host "PATRONI_CLUSTER_RECOVERY_STATUS=OK"
}
catch {
    Write-Host "PATRONI_CLUSTER_RECOVERY_STATUS=ERROR message=$($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}
