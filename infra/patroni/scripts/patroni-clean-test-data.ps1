param(
    [switch]$ConfirmDelete,
    [switch]$IncludeVolumes
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml")
$patroniVolumes = @(
    "proyectobdiimicroservivios_etcd-1-data",
    "proyectobdiimicroservivios_etcd-2-data",
    "proyectobdiimicroservivios_etcd-3-data",
    "proyectobdiimicroservivios_patroni-postgres-1-data",
    "proyectobdiimicroservivios_patroni-postgres-2-data",
    "proyectobdiimicroservivios_patroni-postgres-3-data"
)

Write-Host "DRY_RUN=$(-not $ConfirmDelete)"
Write-Host "Esta limpieza solo aplica al stack Patroni paralelo."
Write-Host "No toca el volumen postgres-data del PostgreSQL principal."

Push-Location $root
try {
    Write-Host "PATRONI_CONTAINERS"
    docker compose @composeArgs ps -a etcd-1 etcd-2 etcd-3 patroni-postgres-1 patroni-postgres-2 patroni-postgres-3 patroni-postgres-lb

    Write-Host "PATRONI_VOLUMES"
    foreach ($volume in $patroniVolumes) {
        docker volume ls --format "{{.Name}}" | Select-String -SimpleMatch $volume
    }

    if (-not $ConfirmDelete) {
        Write-Host "CLEANUP_STATUS=DRY_RUN"
        Write-Host "Para eliminar contenedores del stack Patroni: .\infra\patroni\scripts\patroni-clean-test-data.ps1 -ConfirmDelete"
        Write-Host "Para eliminar tambien volumenes Patroni: .\infra\patroni\scripts\patroni-clean-test-data.ps1 -ConfirmDelete -IncludeVolumes"
        exit 0
    }

    if ($IncludeVolumes) {
        docker compose @composeArgs down --volumes --remove-orphans
    }
    else {
        docker compose @composeArgs down --remove-orphans
    }

    Write-Host "CLEANUP_STATUS=OK"
}
finally {
    Pop-Location
}
