param(
    [string]$ComposeFile = "docker-compose.patroni.yml",
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", $ComposeFile)
$services = @("etcd-1", "etcd-2", "etcd-3")
$clusterEndpoints = "http://etcd-1:2379,http://etcd-2:2379,http://etcd-3:2379"

function Get-ServiceContainerId {
    param([string]$ServiceName)

    $id = docker compose @composeArgs ps -q $ServiceName
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo consultar el servicio $ServiceName."
    }

    return ($id | Select-Object -First 1)
}

function Get-ContainerHealth {
    param([string]$ContainerId)

    if (-not $ContainerId) {
        return "missing"
    }

    $health = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $ContainerId
    if ($LASTEXITCODE -ne 0) {
        return "inspect_error"
    }

    return ($health | Select-Object -First 1)
}

Push-Location $root
try {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $allHealthy = $false

    do {
        $statuses = foreach ($service in $services) {
            $containerId = Get-ServiceContainerId -ServiceName $service
            [pscustomobject]@{
                Service = $service
                ContainerId = $containerId
                Health = Get-ContainerHealth -ContainerId $containerId
            }
        }

        $allHealthy = ($statuses | Where-Object { $_.Health -ne "healthy" }).Count -eq 0
        if (-not $allHealthy) {
            Start-Sleep -Seconds 3
        }
    } while (-not $allHealthy -and (Get-Date) -lt $deadline)

    Write-Host "ETCD_CONTAINER_HEALTH"
    $statuses | Format-Table -AutoSize

    if (-not $allHealthy) {
        Write-Host "ETCD_STATUS=ERROR container healthcheck failed"
        exit 1
    }

    Write-Host "ETCD_ENDPOINT_HEALTH"
    docker compose @composeArgs exec -T etcd-1 etcdctl --endpoints=$clusterEndpoints endpoint health
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ETCD_STATUS=ERROR endpoint health failed"
        exit 1
    }

    Write-Host "ETCD_MEMBER_LIST"
    docker compose @composeArgs exec -T etcd-1 etcdctl --endpoints=$clusterEndpoints member list
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ETCD_WARNING member list unavailable"
    }

    Write-Host "ETCD_STATUS=OK"
}
finally {
    Pop-Location
}
