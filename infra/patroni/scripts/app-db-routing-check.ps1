param(
    [string]$AppComposeFile = "docker-compose.patroni-apps.yml"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml", "-f", $AppComposeFile)
$services = @("patient-service", "schedule-service", "appointment-service", "payment-service", "notification-service")
$failed = $false

Push-Location $root
try {
    $config = docker compose @composeArgs config --format json
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose config failed."
    }

    $model = ($config -join "`n") | ConvertFrom-Json

    foreach ($service in $services) {
        $serviceModel = $model.services.$service

        if (-not $serviceModel) {
            Write-Host "APP_DB_ROUTING_ERROR service=$service reason=missing"
            $failed = $true
            continue
        }

        $environmentJson = $serviceModel.environment | ConvertTo-Json -Compress -Depth 10
        $dependsJson = $serviceModel.depends_on | ConvertTo-Json -Compress -Depth 10

        $usesPatroni = $environmentJson -match "jdbc:postgresql://patroni-postgres-lb:5432/mediqueue"
        $usesOldPostgres = $environmentJson -match "jdbc:postgresql://postgres-lb:5432"
        $dependsPatroni = $dependsJson -match "patroni-postgres-lb"
        $dependsOldPostgres = $false
        if ($serviceModel.depends_on) {
            $dependsOldPostgres = @($serviceModel.depends_on.PSObject.Properties.Name) -contains "postgres-lb"
        }

        Write-Host "APP_DB_ROUTING service=$service uses_patroni=$usesPatroni depends_patroni=$dependsPatroni uses_old_postgres=$usesOldPostgres depends_old_postgres=$dependsOldPostgres"

        if (-not $usesPatroni -or -not $dependsPatroni -or $usesOldPostgres -or $dependsOldPostgres) {
            $failed = $true
        }
    }

    if ($failed) {
        Write-Host "APP_DB_ROUTING_STATUS=ERROR"
        exit 1
    }

    Write-Host "APP_DB_ROUTING_STATUS=OK"
}
finally {
    Pop-Location
}
