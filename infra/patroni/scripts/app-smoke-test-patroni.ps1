param(
    [string]$BaseUrl = "http://localhost:8080",
    [int]$TimeoutSeconds = 360,
    [switch]$SkipUp,
    [switch]$ForceRecreate
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$composeArgs = @("-f", "docker-compose.yml", "-f", "docker-compose.patroni.yml", "-f", "docker-compose.patroni-apps.yml")

function Wait-HttpOk {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return $response
            }
        }
        catch {
            Start-Sleep -Seconds 5
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timeout waiting for $Url"
}

Push-Location $root
try {
    if (-not $SkipUp) {
        Write-Host "APP_SMOKE_UP_START"
        $upArgs = @("up", "-d")
        if ($ForceRecreate) {
            $upArgs += "--force-recreate"
        }
        $upArgs += @("patroni-postgres-lb", "patient-service", "schedule-service", "appointment-service", "payment-service", "notification-service", "patient-lb", "schedule-lb", "appointment-lb", "payment-lb", "api-gateway", "api-gateway-lb")
        docker compose @composeArgs @upArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "APP_SMOKE_STATUS=ERROR compose up failed"
            exit 1
        }
    }

    Write-Host "APP_SMOKE_HEALTHCHECKS"
    docker compose @composeArgs ps patient-service schedule-service appointment-service payment-service notification-service api-gateway api-gateway-lb

    $health = Wait-HttpOk -Url "$BaseUrl/actuator/health" -TimeoutSeconds $TimeoutSeconds
    Write-Host "APP_SMOKE_GATEWAY_HEALTH_STATUS_CODE=$($health.StatusCode)"

    $basicEndpoints = @(
        "$BaseUrl/api/patients",
        "$BaseUrl/api/schedules"
    )

    foreach ($endpoint in $basicEndpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 10
            Write-Host "APP_SMOKE_ENDPOINT url=$endpoint status=$($response.StatusCode)"
        }
        catch {
            Write-Host "APP_SMOKE_ENDPOINT_WARNING url=$endpoint message=$($_.Exception.Message)"
        }
    }

    Write-Host "APP_SMOKE_STATUS=OK"
}
finally {
    Pop-Location
}
