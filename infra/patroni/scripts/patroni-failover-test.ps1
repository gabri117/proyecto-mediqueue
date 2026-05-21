param(
    [switch]$Execute,
    [switch]$RestartStoppedPrimary,
    [int[]]$RestPorts = @(18008, 18009, 18010)
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")

function Get-PrimaryContainer {
    foreach ($port in $RestPorts) {
        try {
            $status = Invoke-RestMethod -Uri "http://127.0.0.1:$port/patroni" -TimeoutSec 3
            if ($status.role -eq "primary" -or $status.role -eq "master") {
                return $status.name
            }
        }
        catch {
            continue
        }
    }
    return $null
}

$primary = Get-PrimaryContainer
if (-not $primary) {
    throw "No se encontro primario para probar failover."
}

if (-not $Execute) {
    Write-Host "DRY_RUN: failover test no ejecutado."
    Write-Host "Primario actual: $primary"
    Write-Host "Use -Execute para detener temporalmente el primario y observar la promocion."
    exit 0
}

Push-Location $root
try {
    Write-Host "FAILOVER_TEST_STOP_PRIMARY name=$primary"
    docker compose @composeArgs stop $primary

    Start-Sleep -Seconds 20
    $newPrimary = Get-PrimaryContainer
    Write-Host "FAILOVER_TEST_NEW_PRIMARY name=$newPrimary"

    if (-not $newPrimary -or $newPrimary -eq $primary) {
        throw "Failover no confirmado."
    }

    if ($RestartStoppedPrimary) {
        Write-Host "FAILOVER_TEST_RESTART_OLD_PRIMARY name=$primary"
        docker compose @composeArgs start $primary
    }
}
finally {
    Pop-Location
}
