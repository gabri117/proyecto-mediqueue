param(
    [string]$ComposeFile = "docker-compose.patroni.yml"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)
$nodes = @(
    @{ Service = "patroni-postgres-1"; Port = 18008 },
    @{ Service = "patroni-postgres-2"; Port = 18009 },
    @{ Service = "patroni-postgres-3"; Port = 18010 }
)

function Get-PatroniNodeStatus {
    param(
        [string]$Service,
        [int]$Port
    )

    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/patroni" -Method Get -TimeoutSec 3
        $nodeName = if ($response.name) { $response.name } else { $Service }
        [pscustomobject]@{
            Service = $Service
            Name = $nodeName
            Port = $Port
            Reachable = $true
            Role = $response.role
            State = $response.state
            Leader = $response.leader
            Timeline = $response.timeline
        }
    }
    catch {
        [pscustomobject]@{
            Service = $Service
            Name = ""
            Port = $Port
            Reachable = $false
            Role = "unknown"
            State = "unreachable"
            Leader = ""
            Timeline = ""
        }
    }
}

Push-Location $root
try {
    Write-Host "PATRONI_COMPOSE_STATUS"
    docker compose @composeArgs ps etcd-1 etcd-2 etcd-3 patroni-postgres-1 patroni-postgres-2 patroni-postgres-3 patroni-postgres-lb

    Write-Host ""
    Write-Host "PATRONI_REST_STATUS"
    $statuses = $nodes | ForEach-Object { Get-PatroniNodeStatus -Service $_.Service -Port $_.Port }
    $statuses | Format-Table -AutoSize

    $leader = $statuses | Where-Object { $_.Role -in @("primary", "master") } | Select-Object -First 1
    $replicas = $statuses | Where-Object { $_.Role -in @("replica", "standby_leader") }

    if ($leader) {
        Write-Host "PATRONI_LEADER=$($leader.Service)"
    }
    else {
        Write-Host "PATRONI_LEADER=NONE"
    }

    Write-Host "PATRONI_REPLICAS=$(@($replicas).Count)"

    Write-Host "WRITER_ENDPOINT=127.0.0.1:55432"
    Write-Host "READER_ENDPOINT=127.0.0.1:55433"
    Write-Host "HAPROXY_STATS=http://127.0.0.1:7000/"
}
finally {
    Pop-Location
}
