param(
    [string]$InputFile = ".\infra\load-tests\appointments\data\appointment-load-seed.dump"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $InputFile)) {
    throw "InputFile no encontrado: $InputFile"
}

$postgresContainer = (docker compose ps -q postgres).Trim()
if (-not $postgresContainer) {
    throw "No se encontro el contenedor postgres. Ejecuta docker compose up -d --build primero."
}

$containerDump = "/tmp/appointment-load-seed.dump"

Write-Host "Copying seed dump into postgres container..."
docker cp $InputFile "$postgresContainer`:$containerDump"
if ($LASTEXITCODE -ne 0) {
    throw "docker cp fallo con exit code $LASTEXITCODE"
}

Write-Host "Restoring base data from dump..."
docker compose exec -T postgres pg_restore `
    -U mediqueue `
    -d mediqueue `
    --data-only `
    --disable-triggers `
    $containerDump

if ($LASTEXITCODE -ne 0) {
    throw "pg_restore fallo con exit code $LASTEXITCODE. Usa este script preferiblemente despues de docker compose down -v y docker compose up -d --build."
}

docker compose exec -T postgres rm -f $containerDump | Out-Null

Write-Host "Seed dump restored."
Write-Host "Recommended sequence:"
Write-Host "  docker compose down -v"
Write-Host "  docker compose up -d --build"
Write-Host "  .\infra\load-tests\appointments\tools\restore-appointment-seed-dump.ps1 -InputFile $InputFile"
