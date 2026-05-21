param(
    [string]$ComposeFile = "docker-compose.patroni.yml"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)
$nodes = @(
    @{ Name = "patroni-postgres-1"; Port = 18008 },
    @{ Name = "patroni-postgres-2"; Port = 18009 },
    @{ Name = "patroni-postgres-3"; Port = 18010 }
)

function Get-PatroniNodeStatus {
    param(
        [string]$Name,
        [int]$Port
    )

    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/patroni" -Method Get -TimeoutSec 3
        [pscustomobject]@{
            Node = $Name
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
            Node = $Name
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
    $nodes | ForEach-Object { Get-PatroniNodeStatus -Name $_.Name -Port $_.Port } | Format-Table -AutoSize

    Write-Host "WRITER_ENDPOINT=127.0.0.1:55432"
    Write-Host "READER_ENDPOINT=127.0.0.1:55433"
    Write-Host "HAPROXY_STATS=http://127.0.0.1:57000/"
}
finally {
    Pop-Location
}
