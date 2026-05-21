param(
    [switch]$Build,
    [switch]$ForceRecreate,
    [int]$ApiGatewayReplicas = 2,
    [int]$AppointmentReplicas = 3,
    [int]$PatientReplicas = 2,
    [int]$ScheduleReplicas = 2,
    [int]$PaymentReplicas = 3,
    [int]$NotificationReplicas = 2,
    [switch]$SkipPrepareSchemas,
    [switch]$SkipObservability,
    [int]$HealthTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
Set-Location $repoRoot

$composeFiles = @(
    "-f", "docker-compose.yml",
    "-f", "docker-compose.patroni.yml",
    "-f", "docker-compose.patroni-apps.yml",
    "-f", "docker-compose.patroni-e2e.yml"
)

function Set-DefaultEnv {
    param(
        [string]$Name,
        [string]$Value
    )

    [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    Write-Host "E2E_ENV $Name=$Value"
}

function Invoke-Compose {
    param([string[]]$ComposeArgs)

    Write-Host "DOCKER_COMPOSE $($ComposeArgs -join ' ')"
    & docker compose @composeFiles @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE. Args: $($ComposeArgs -join ' ')"
    }
}

function Wait-HttpHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    while ((Get-Date) -lt $deadline) {
        $attempt++
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                Write-Host "BACKEND_HEALTH_OK url=$Url attempt=$attempt"
                return
            }
        } catch {
            Write-Host "BACKEND_HEALTH_WAIT url=$Url attempt=$attempt message=$($_.Exception.Message)"
        }
        Start-Sleep -Seconds 5
    }

    throw "Backend did not become healthy before timeout. Url=$Url timeoutSeconds=$TimeoutSeconds"
}

function Wait-PatroniWriter {
    param([int]$TimeoutSeconds)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $query = "select pg_is_in_recovery();"
        $output = & docker compose @composeFiles exec -T -e "PGPASSWORD=mediqueue" patroni-postgres-1 `
            psql -h patroni-postgres-lb -p 5432 -U mediqueue -d mediqueue -tAc $query 2>&1
        if ($LASTEXITCODE -eq 0 -and (($output -join "`n").Trim() -eq "f")) {
            Write-Host "PATRONI_WRITER_READY=True attempt=$attempt"
            return
        }

        Write-Host "PATRONI_WRITER_WAIT attempt=$attempt exit_code=$LASTEXITCODE output=$($output -join ' ')"
        Start-Sleep -Seconds 5
    }

    throw "Patroni writer did not become ready before timeoutSeconds=$TimeoutSeconds"
}

Write-Host "Starting MediQueue Patroni E2E backend"
Write-Host "Build=$($Build.IsPresent) ForceRecreate=$($ForceRecreate.IsPresent)"

Set-DefaultEnv "COMPOSE_HTTP_TIMEOUT" "300"
Set-DefaultEnv "DOCKER_CLIENT_TIMEOUT" "300"

Set-DefaultEnv "GATEWAY_RATE_LIMIT_ENABLED" "false"
Set-DefaultEnv "GATEWAY_ACCESS_LOG_ENABLED" "false"
Set-DefaultEnv "GATEWAY_SLOW_REQUEST_THRESHOLD_MS" "10000"
Set-DefaultEnv "GATEWAY_HTTPCLIENT_POOL_MAX_CONNECTIONS" "3000"
Set-DefaultEnv "GATEWAY_HTTPCLIENT_POOL_ACQUIRE_TIMEOUT_MS" "10000"
Set-DefaultEnv "GATEWAY_BULKHEAD_APPOINTMENT_MAX_CONCURRENT_CALLS" "1800"
Set-DefaultEnv "GATEWAY_BULKHEAD_DEFAULT_MAX_CONCURRENT_CALLS" "1000"
Set-DefaultEnv "GATEWAY_TIMELIMITER_TIMEOUT_SECONDS" "30"
Set-DefaultEnv "GATEWAY_CB_MINIMUM_CALLS" "1000"
Set-DefaultEnv "GATEWAY_CB_SLIDING_WINDOW_SIZE" "5000"
Set-DefaultEnv "GATEWAY_CB_FAILURE_RATE_THRESHOLD" "95"

Set-DefaultEnv "APPOINTMENT_HIKARI_MAX_POOL_SIZE" "48"
Set-DefaultEnv "APPOINTMENT_HIKARI_MIN_IDLE" "12"
Set-DefaultEnv "APPOINTMENT_HIKARI_CONNECTION_TIMEOUT_MS" "10000"
Set-DefaultEnv "APPOINTMENT_TOMCAT_MAX_THREADS" "144"
Set-DefaultEnv "APPOINTMENT_TOMCAT_MIN_SPARE_THREADS" "36"
Set-DefaultEnv "APPOINTMENT_CREATE_MAX_CONCURRENT" "72"
Set-DefaultEnv "APPOINTMENT_CREATE_TIMING_LOG_ENABLED" "false"
Set-DefaultEnv "APPOINTMENT_CREATE_SLOW_THRESHOLD_MS" "3000"
Set-DefaultEnv "LOADTEST_DIRECT_DB_VALIDATION_ENABLED" "true"
Set-DefaultEnv "LOADTEST_DIRECT_VALIDATION_PRELOAD_ENABLED" "true"
Set-DefaultEnv "LOADTEST_HOLD_EXPIRATION_ENABLED" "false"
Set-DefaultEnv "LOADTEST_OUTBOX_PUBLISHER_ENABLED" "true"
Set-DefaultEnv "APPOINTMENT_OUTBOX_PUBLISH_INTERVAL_MS" "1000"
Set-DefaultEnv "APPOINTMENT_OUTBOX_BATCH_SIZE" "75"
Set-DefaultEnv "APPOINTMENT_RABBITMQ_PREFETCH" "5"
Set-DefaultEnv "APPOINTMENT_RABBITMQ_LISTENER_CONCURRENCY" "1"
Set-DefaultEnv "APPOINTMENT_RABBITMQ_LISTENER_MAX_CONCURRENCY" "2"
Set-DefaultEnv "APPOINTMENT_PAYMENT_EVENT_PREFETCH" "1"
Set-DefaultEnv "APPOINTMENT_PAYMENT_EVENT_CONCURRENCY" "1"
Set-DefaultEnv "APPOINTMENT_PAYMENT_EVENT_MAX_CONCURRENCY" "1"

Set-DefaultEnv "PAYMENT_HIKARI_MAX_POOL_SIZE" "12"
Set-DefaultEnv "PAYMENT_HIKARI_MIN_IDLE" "3"
Set-DefaultEnv "PAYMENT_RABBITMQ_PREFETCH" "20"
Set-DefaultEnv "PAYMENT_RABBITMQ_LISTENER_CONCURRENCY" "4"
Set-DefaultEnv "PAYMENT_RABBITMQ_LISTENER_MAX_CONCURRENCY" "8"
Set-DefaultEnv "PAYMENT_SIM_MIN_DELAY_MS" "25"
Set-DefaultEnv "PAYMENT_SIM_MAX_DELAY_MS" "100"
Set-DefaultEnv "PAYMENT_SIM_APPROVAL_RATE" "1.0"
Set-DefaultEnv "PAYMENT_OUTBOX_PUBLISH_INTERVAL_MS" "1000"
Set-DefaultEnv "PAYMENT_OUTBOX_BATCH_SIZE" "75"

Set-DefaultEnv "PATIENT_HIKARI_MAX_POOL_SIZE" "8"
Set-DefaultEnv "PATIENT_HIKARI_MIN_IDLE" "2"
Set-DefaultEnv "SCHEDULE_HIKARI_MAX_POOL_SIZE" "8"
Set-DefaultEnv "SCHEDULE_HIKARI_MIN_IDLE" "2"
Set-DefaultEnv "NOTIFICATION_HIKARI_MAX_POOL_SIZE" "8"
Set-DefaultEnv "NOTIFICATION_HIKARI_MIN_IDLE" "2"

Invoke-Compose -ComposeArgs @("config", "--quiet")

if ($Build) {
    Invoke-Compose -ComposeArgs @("build", "api-gateway", "appointment-service", "patient-service", "schedule-service", "payment-service", "notification-service")
}

$infraServices = @(
    "etcd-1",
    "etcd-2",
    "etcd-3",
    "patroni-postgres-1",
    "patroni-postgres-2",
    "patroni-postgres-3",
    "patroni-postgres-lb",
    "rabbitmq",
    "redis"
)

if (-not $SkipObservability) {
    $infraServices += @(
        "redis-exporter",
        "prometheus",
        "grafana",
        "patroni-postgres-exporter-1",
        "patroni-postgres-exporter-2",
        "patroni-postgres-exporter-3"
    )
}

Invoke-Compose -ComposeArgs (@("up", "-d") + $infraServices)
Wait-PatroniWriter -TimeoutSeconds $HealthTimeoutSeconds

if (-not $SkipPrepareSchemas) {
    & .\infra\patroni\scripts\prepare-patroni-app-schemas.ps1
    if ($LASTEXITCODE -ne 0) {
        throw "prepare-patroni-app-schemas.ps1 failed with exit code $LASTEXITCODE"
    }
}

$upArgs = @(
    "up", "-d"
)

if ($Build) {
    $upArgs += "--build"
}

if ($ForceRecreate) {
    $upArgs += "--force-recreate"
}

$upArgs += @(
    "--scale", "api-gateway=$ApiGatewayReplicas",
    "--scale", "appointment-service=$AppointmentReplicas",
    "--scale", "patient-service=$PatientReplicas",
    "--scale", "schedule-service=$ScheduleReplicas",
    "--scale", "payment-service=$PaymentReplicas",
    "--scale", "notification-service=$NotificationReplicas",
    "api-gateway",
    "appointment-service",
    "patient-service",
    "schedule-service",
    "payment-service",
    "notification-service",
    "api-gateway-lb",
    "appointment-lb",
    "patient-lb",
    "schedule-lb",
    "payment-lb"
)

if (-not $SkipObservability) {
    $upArgs += @("prometheus", "grafana")
}

Invoke-Compose -ComposeArgs $upArgs
Wait-HttpHealth -Url "http://localhost:8080/actuator/health" -TimeoutSeconds $HealthTimeoutSeconds

Write-Host "PATRONI_E2E_BACKEND_READY=True"
Write-Host "API_URL=http://localhost:8080"
Write-Host "DB_WRITER=localhost:55432"
if (-not $SkipObservability) {
    Write-Host "PROMETHEUS_URL=http://localhost:9090"
    Write-Host "GRAFANA_URL=http://localhost:3000"
    Write-Host "RABBITMQ_MANAGEMENT_URL=http://localhost:15672"
}
