param(
    [string]$ComposeFile = "docker-compose.patroni.yml",
    [string]$Database = "mediqueue",
    [string]$User = "mediqueue",
    [string]$Password = "mediqueue",
    [int[]]$RestPorts = @(18008, 18009, 18010),
    [switch]$SkipReader
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)
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
                Role = $status.role
                State = $status.state
                Reachable = $true
            }
        }
        catch {
            $statuses += [pscustomobject]@{
                Service = $node.Service
                Name = $node.Service
                Role = "unreachable"
                State = "unreachable"
                Reachable = $false
            }
        }
    }
    return $statuses
}

function Get-RunnerService {
    $statuses = Get-NodeStatuses
    $runner = $statuses |
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
    $runnerService = Get-RunnerService
    Write-Host "PATRONI_DB_TEST_RUNNER_SERVICE=$runnerService"

    Write-Host "PATRONI_DB_TEST_WRITER"
    $writerRecovery = Invoke-PsqlScalar -Port "5432" -Sql "SELECT pg_is_in_recovery();" -RunnerService $runnerService
    $writerAddr = Invoke-PsqlScalar -Port "5432" -Sql "SELECT COALESCE(inet_server_addr()::text, 'local');" -RunnerService $runnerService
    Write-Host "WRITER_INET_SERVER_ADDR=$writerAddr"
    Write-Host "WRITER_PG_IS_IN_RECOVERY=$writerRecovery"

    if ($writerRecovery -ne "f") {
        Write-Host "PATRONI_DB_CONNECTION_STATUS=ERROR writer is not primary"
        exit 1
    }

    if (-not $SkipReader) {
        Write-Host "PATRONI_DB_TEST_READER"
        $readerRecovery = Invoke-PsqlScalar -Port "5433" -Sql "SELECT pg_is_in_recovery();" -RunnerService $runnerService
        $readerAddr = Invoke-PsqlScalar -Port "5433" -Sql "SELECT COALESCE(inet_server_addr()::text, 'local');" -RunnerService $runnerService
        Write-Host "READER_INET_SERVER_ADDR=$readerAddr"
        Write-Host "READER_PG_IS_IN_RECOVERY=$readerRecovery"

        if ($readerRecovery -ne "t") {
            Write-Host "PATRONI_DB_CONNECTION_STATUS=ERROR reader did not route to replica"
            exit 1
        }
    }

    Write-Host "PATRONI_DB_CONNECTION_STATUS=OK"
}
finally {
    Pop-Location
}
