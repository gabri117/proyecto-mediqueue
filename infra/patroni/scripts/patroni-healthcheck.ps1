param(
    [string]$ComposeFile = "docker-compose.patroni.yml",
    [int[]]$RestPorts = @(18008, 18009, 18010),
    [string]$Database = "mediqueue",
    [string]$User = "mediqueue",
    [string]$Password = "mediqueue"
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
    docker compose @composeArgs exec -T etcd-1 etcdctl --endpoints=http://etcd-1:2379,http://etcd-2:2379,http://etcd-3:2379 endpoint health | Out-Host
    return ($LASTEXITCODE -eq 0)
}

function Invoke-PsqlScalar {
    param(
        [string]$Port,
        [string]$Sql
    )

    $result = docker compose @composeArgs exec -T -e "PGPASSWORD=$Password" patroni-postgres-1 `
        psql -h patroni-postgres-lb -p $Port -U $User -d $Database -At -v ON_ERROR_STOP=1 -c $Sql

    if ($LASTEXITCODE -ne 0) {
        throw "psql failed on HAProxy port $Port"
    }

    return (($result | Select-Object -First 1) -as [string]).Trim()
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
                Write-Host "PATRONI_PRIMARY_OK name=$name port=$port role=$($status.role) state=$($status.state)"
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

    $writerRecovery = Invoke-PsqlScalar -Port "5432" -Sql "SELECT pg_is_in_recovery();"
    Write-Host "PATRONI_WRITER_PG_IS_IN_RECOVERY=$writerRecovery"
    $writerOk = ($writerRecovery -eq "f")
    Write-Host "PATRONI_WRITER_OK=$writerOk"

    Write-Host "PATRONICTL_LIST"
    docker compose @composeArgs exec -T patroni-postgres-1 patronictl -c /etc/patroni/patroni.yml list
    $patronictlOk = ($LASTEXITCODE -eq 0)
    Write-Host "PATRONICTL_LIST_OK=$patronictlOk"

    if (-not $etcdOk -or -not $hasPrimary -or $reachableNodes -lt 3 -or $replicaCount -lt 2 -or -not $writerOk -or -not $patronictlOk) {
        Write-Host "PATRONI_HEALTH_STATUS=ERROR"
        exit 1
    }

    Write-Host "PATRONI_HEALTH_STATUS=OK"
}
catch {
    Write-Host "PATRONI_HEALTH_STATUS=ERROR message=$($_.Exception.Message)"
    exit 1
}
finally {
    Pop-Location
}
