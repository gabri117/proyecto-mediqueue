param(
    [string]$BaseUrl = "http://localhost:8080",
    [switch]$IncludeHostile,
    [switch]$IncludeE2E,
    [switch]$K6OutputPrometheus,
    [ValidateSet("smoke", "normal", "heavy")]
    [string]$DurationProfile = "normal",
    [switch]$ContinueOnError,
    [string]$PatientId,
    [string]$DentistId,
    [string]$SlotId,
    [string]$AppointmentId,
    [string]$Date,
    [string]$K6Binary = "k6",
    [switch]$UseDockerK6
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $Root
$ResultsDir = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Force $ResultsDir | Out-Null

function Set-ProfileDefaults {
    param([string]$Profile)

    if ($Profile -eq "smoke") {
        $env:SMOKE_ITERATIONS = "5"
        $env:PATIENT_VUS = "1"; $env:PATIENT_DURATION = "15s"
        $env:SCHEDULE_VUS = "1"; $env:SCHEDULE_DURATION = "15s"
        $env:PAYMENT_VUS = "1"; $env:PAYMENT_DURATION = "15s"
        $env:NOTIFICATION_VUS = "1"; $env:NOTIFICATION_DURATION = "15s"
    }
    elseif ($Profile -eq "heavy") {
        $env:SMOKE_ITERATIONS = "10"
        $env:PATIENT_VUS = "50"; $env:PATIENT_DURATION = "3m"
        $env:SCHEDULE_VUS = "200"; $env:SCHEDULE_DURATION = "5m"
        $env:PAYMENT_VUS = "100"; $env:PAYMENT_DURATION = "5m"
        $env:NOTIFICATION_VUS = "100"; $env:NOTIFICATION_DURATION = "5m"
    }
}

function Invoke-K6Phase {
    param(
        [string]$Name,
        [string]$Script
    )

    $env:BASE_URL = $BaseUrl
    $env:RESULTS_DIR = $ResultsDir
    $env:K6_SCRIPT_NAME = (Split-Path -Leaf $Script)
    if ($PatientId) { $env:PATIENT_ID = $PatientId }
    if ($DentistId) { $env:DENTIST_ID = $DentistId }
    if ($SlotId) { $env:SLOT_ID = $SlotId }
    if ($AppointmentId) { $env:APPOINTMENT_ID = $AppointmentId }
    if ($Date) { $env:DATE = $Date }
    if ($IncludeE2E) { $env:ALLOW_E2E = "true" }

    $args = @("run")
    if ($K6OutputPrometheus) {
        if (-not $env:K6_PROMETHEUS_RW_SERVER_URL) {
            $env:K6_PROMETHEUS_RW_SERVER_URL = "http://localhost:9090/api/v1/write"
        }
        $args += @("-o", "experimental-prometheus-rw")
    }
    $args += $Script

    Write-Host ""
    Write-Host "==> $Name"
    if ($UseDockerK6) {
        $dockerScript = "/" + ($Script -replace "\\", "/" -replace "^infra/load-tests", "scripts")
        $dockerArgs = @("compose", "--profile", "loadtest", "run", "--rm")
        $dockerEnv = @{
            BASE_URL = if ($BaseUrl -eq "http://localhost:8080") { "http://api-gateway-lb:8080" } else { $BaseUrl }
            RESULTS_DIR = "/scripts/results"
            K6_SCRIPT_NAME = (Split-Path -Leaf $Script)
            PATIENT_ID = $PatientId
            DENTIST_ID = $DentistId
            SLOT_ID = $SlotId
            APPOINTMENT_ID = $AppointmentId
            DATE = $Date
            ALLOW_E2E = $(if ($IncludeE2E) { "true" } else { $env:ALLOW_E2E })
            SMOKE_ITERATIONS = $env:SMOKE_ITERATIONS
            PATIENT_VUS = $env:PATIENT_VUS
            PATIENT_DURATION = $env:PATIENT_DURATION
            SCHEDULE_VUS = $env:SCHEDULE_VUS
            SCHEDULE_DURATION = $env:SCHEDULE_DURATION
            PAYMENT_VUS = $env:PAYMENT_VUS
            PAYMENT_DURATION = $env:PAYMENT_DURATION
            NOTIFICATION_VUS = $env:NOTIFICATION_VUS
            NOTIFICATION_DURATION = $env:NOTIFICATION_DURATION
            K6_PROMETHEUS_RW_SERVER_URL = $(if ($K6OutputPrometheus -and -not $env:K6_PROMETHEUS_RW_SERVER_URL) { "http://prometheus:9090/api/v1/write" } else { $env:K6_PROMETHEUS_RW_SERVER_URL })
        }
        foreach ($item in $dockerEnv.GetEnumerator()) {
            if ($item.Value) {
                $dockerArgs += @("-e", "$($item.Key)=$($item.Value)")
            }
        }
        $dockerArgs += @("k6")
        $dockerK6Args = @("run")
        if ($K6OutputPrometheus) {
            $dockerK6Args += @("-o", "experimental-prometheus-rw")
        }
        $dockerK6Args += $dockerScript
        $dockerArgs += $dockerK6Args
        Write-Host "Command: docker $($dockerArgs -join ' ')"
    }
    else {
        Write-Host "Command: $K6Binary $($args -join ' ')"
    }

    $started = Get-Date
    if ($UseDockerK6) {
        & docker @dockerArgs
    }
    else {
        & $K6Binary @args
    }
    $exitCode = $LASTEXITCODE
    $elapsed = (Get-Date) - $started

    [pscustomobject]@{
        Phase = $Name
        Script = $Script
        ExitCode = $exitCode
        Duration = $elapsed.ToString("hh\:mm\:ss")
    }
}

Set-ProfileDefaults -Profile $DurationProfile

$phases = @(
    @{ Name = "00 Smoke"; Script = "infra/load-tests/scripts/00-smoke.js" },
    @{ Name = "01 Patient Load"; Script = "infra/load-tests/scripts/01-patient-load.js" },
    @{ Name = "02 Schedule Load"; Script = "infra/load-tests/scripts/02-schedule-load.js" },
    @{ Name = "03 Payment Load"; Script = "infra/load-tests/scripts/03-payment-load.js" },
    @{ Name = "04 Notification Load"; Script = "infra/load-tests/scripts/04-notification-load.js" }
)

if ($IncludeHostile) {
    $phases += @{ Name = "05 Appointment Hostile"; Script = "infra/load-tests/scripts/05-appointment-hostile.js" }
}

if ($IncludeE2E) {
    $phases += @{ Name = "06 E2E Flow"; Script = "infra/load-tests/scripts/06-e2e-flow.js" }
}

Push-Location $RepoRoot
try {
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($phase in $phases) {
        $result = Invoke-K6Phase -Name $phase.Name -Script $phase.Script
        $results.Add($result)

        if ($phase.Name -like "00*" -and $result.ExitCode -ne 0) {
            Write-Host "Smoke fallo; se detiene la suite secuencial."
            break
        }

        if ($result.ExitCode -ne 0 -and -not $ContinueOnError) {
            Write-Host "Fase fallo y ContinueOnError no esta activo; se detiene la suite."
            break
        }
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Resumen de ejecucion"
$results | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.ExitCode -ne 0 })
if ($failed.Count -gt 0) {
    exit 1
}

exit 0
