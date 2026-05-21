param(
    [string]$ComposeFile = "docker-compose.patroni.yml",
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"
$hasPrimary = $false
$reachableNodes = 0
$replicaCount = 0
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)
$nodes = @(
    @{ Service = "patroni-postgres-1"; Port = 18008 },
    @{ Service = "patroni-postgres-2"; Port = 18009 },
    @{ Service = "patroni-postgres-3"; Port = 18010 }
)

function Test-Etcd {
    try {
        docker compose @composeArgs exec -T etcd-1 etcdctl --endpoints=http://etcd-1:2379,http://etcd-2:2379,http://etcd-3:2379 endpoint health | Out-Host
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

Push-Location $root
try {
    $etcdOk = Test-Etcd
    Write-Host "ETCD_HEALTH_OK=$etcdOk"

    foreach ($node in $nodes | Where-Object { $RestPorts -contains $_.Port }) {
        try {
            $port = $node.Port
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$port/patroni" -TimeoutSec 3
            $name = if ($status.name) { $status.name } else { $node.Service }
            $reachableNodes++
            if ($status.role -eq "primary" -or $status.role -eq "master") {
                $hasPrimary = $true
                Write-Host "PATRONI_PRIMARY_OK name=$name port=$port role=$($status.role)"
            }
            elseif ($status.role -eq "replica" -or $status.role -eq "standby_leader") {
                $replicaCount++
                Write-Host "PATRONI_REPLICA_OK name=$name port=$port role=$($status.role) state=$($status.state)"
            }
            else {
                Write-Host "PATRONI_NODE_WARNING name=$name port=$port role=$($status.role) state=$($status.state)"
            }
        }
        catch {
            Write-Host "PATRONI_NODE_ERROR port=$port unreachable"
        }
    }

    Write-Host "PATRONI_REACHABLE_NODES=$reachableNodes"
    Write-Host "PATRONI_HAS_PRIMARY=$hasPrimary"
    Write-Host "PATRONI_REPLICA_COUNT=$replicaCount"

    if (-not $etcdOk -or -not $hasPrimary -or $reachableNodes -lt 3 -or $replicaCount -lt 2) {
        Write-Host "PATRONI_HEALTH_STATUS=ERROR"
        exit 1
    }

    Write-Host "PATRONI_HEALTH_STATUS=OK"
}
finally {
    Pop-Location
}
