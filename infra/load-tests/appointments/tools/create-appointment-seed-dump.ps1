param(
    [string]$OutputFile = ".\infra\load-tests\appointments\data\appointment-load-seed.dump"
)

$ErrorActionPreference = "Stop"

$parent = Split-Path -Parent $OutputFile
if ($parent -and -not (Test-Path -Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

$postgresContainer = (docker compose ps -q postgres).Trim()
if (-not $postgresContainer) {
    throw "No se encontro el contenedor postgres. Ejecuta docker compose up -d primero."
}

$containerDump = "/tmp/appointment-load-seed.dump"

Write-Host "Creating base-data dump in postgres container..."
docker compose exec -T postgres pg_dump `
    -U mediqueue `
    -d mediqueue `
    --format=custom `
    --data-only `
    --table=patient.patients `
    --table=schedule.dentists `
    --table=schedule.dentist_slots `
    --file=$containerDump

if ($LASTEXITCODE -ne 0) {
    throw "pg_dump fallo con exit code $LASTEXITCODE"
}

docker cp "$postgresContainer`:$containerDump" $OutputFile
if ($LASTEXITCODE -ne 0) {
    throw "docker cp fallo con exit code $LASTEXITCODE"
}

docker compose exec -T postgres rm -f $containerDump | Out-Null

$resolved = Resolve-Path $OutputFile
Write-Host "Seed dump written to $resolved"
Write-Host "Included tables: patient.patients, schedule.dentists, schedule.dentist_slots"
Write-Host "Excluded runtime data: appointments, holds, outbox, payments, notifications, audits."
