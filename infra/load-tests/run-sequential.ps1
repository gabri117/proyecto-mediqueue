param(
    [string]$BaseUrl = "http://localhost:8080",
    [ValidateSet("realistic", "performance", "smoke")]
    [string]$Profile = "realistic",
    [switch]$IncludeHostile,
    [switch]$IncludeE2E,
    [switch]$IncludeRateLimit,
    [switch]$K6OutputPrometheus,
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
    param([string]$SelectedProfile)

    $env:LOAD_PROFILE = $SelectedProfile

    if ($SelectedProfile -eq "smoke") {
        $env:SMOKE_ITERATIONS = "5"
        $env:PATIENT_VUS = "1"; $env:PATIENT_DURATION = "15s"
        $env:SCHEDULE_VUS = "1"; $env:SCHEDULE_DURATION = "15s"
        $env:PAYMENT_VUS = "1"; $env:PAYMENT_DURATION = "15s"
        $env:NOTIFICATION_VUS = "1"; $env:NOTIFICATION_DURATION = "15s"
        $env:RATE_LIMIT_VUS = "20"; $env:RATE_LIMIT_DURATION = "10s"
        return
    }

    if ($SelectedProfile -eq "performance") {
        $env:SMOKE_ITERATIONS = "5"
        $env:PATIENT_VUS = "20"; $env:PATIENT_DURATION = "1m"
        $env:SCHEDULE_VUS = "100"; $env:SCHEDULE_DURATION = "2m"
        $env:PAYMENT_VUS = "50"; $env:PAYMENT_DURATION = "2m"
        $env:NOTIFICATION_VUS = "50"; $env:NOTIFICATION_DURATION = "2m"
        $env:RATE_LIMIT_VUS = "40"; $env:RATE_LIMIT_DURATION = "30s"
        return
    }

    $env:SMOKE_ITERATIONS = "5"
    $env:PATIENT_VUS = "20"; $env:PATIENT_DURATION = "1m"
    $env:SCHEDULE_VUS = "100"; $env:SCHEDULE_DURATION = "2m"
    $env:PAYMENT_VUS = "50"; $env:PAYMENT_DURATION = "2m"
    $env:NOTIFICATION_VUS = "50"; $env:NOTIFICATION_DURATION = "2m"
    $env:RATE_LIMIT_VUS = "40"; $env:RATE_LIMIT_DURATION = "30s"
}

function Add-DockerEnv {
    param(
        [System.Collections.Generic.List[string]]$ArgsList,
        [hashtable]$EnvMap
    )

    foreach ($item in $EnvMap.GetEnumerator()) {
        if ($null -ne $item.Value -and $item.Value -ne "") {
            $ArgsList.Add("-e")
            $ArgsList.Add("$($item.Key)=$($item.Value)")
        }
    }
}

function Invoke-External {
    param([string[]]$CommandArgs, [string]$Executable)

    $oldNativePreference = $PSNativeCommandUseErrorActionPreference
    $oldErrorPreference = $ErrorActionPreference
    try {
        $script:PSNativeCommandUseErrorActionPreference = $false
        $ErrorActionPreference = "Continue"
        & $Executable @CommandArgs 2>&1 | ForEach-Object { [Console]::Out.WriteLine($_) }
        return $LASTEXITCODE
    }
    finally {
        $script:PSNativeCommandUseErrorActionPreference = $oldNativePreference
        $ErrorActionPreference = $oldErrorPreference
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

    $commandText = ""
    $started = Get-Date

    Write-Host ""
    Write-Host "==> $Name [$Profile]"

    if ($UseDockerK6) {
        $dockerScript = "/" + ($Script -replace "\\", "/" -replace "^infra/load-tests", "scripts")
        $dockerArgs = [System.Collections.Generic.List[string]]::new()
        @("compose", "--profile", "loadtest", "run", "--rm") | ForEach-Object { $dockerArgs.Add($_) }

        $dockerBaseUrl = if ($BaseUrl -eq "http://localhost:8080") { "http://api-gateway-lb:8080" } else { $BaseUrl }
        $dockerPrometheusUrl = if ($K6OutputPrometheus -and -not $env:K6_PROMETHEUS_RW_SERVER_URL) {
            "http://prometheus:9090/api/v1/write"
        } else {
            $env:K6_PROMETHEUS_RW_SERVER_URL
        }

        Add-DockerEnv -ArgsList $dockerArgs -EnvMap @{
            BASE_URL = $dockerBaseUrl
            RESULTS_DIR = "/scripts/results"
            K6_SCRIPT_NAME = (Split-Path -Leaf $Script)
            LOAD_PROFILE = $Profile
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
            RATE_LIMIT_VUS = $env:RATE_LIMIT_VUS
            RATE_LIMIT_DURATION = $env:RATE_LIMIT_DURATION
            K6_PROMETHEUS_RW_SERVER_URL = $dockerPrometheusUrl
        }

        $dockerArgs.Add("k6")
        $dockerArgs.Add("run")
        if ($K6OutputPrometheus) {
            $dockerArgs.Add("-o")
            $dockerArgs.Add("experimental-prometheus-rw")
        }
        $dockerArgs.Add($dockerScript)

        $commandText = "docker $($dockerArgs -join ' ')"
        Write-Host "Command: $commandText"
        $exitCode = Invoke-External -Executable "docker" -CommandArgs $dockerArgs.ToArray()
    }
    else {
        $k6Args = [System.Collections.Generic.List[string]]::new()
        $k6Args.Add("run")
        if ($K6OutputPrometheus) {
            if (-not $env:K6_PROMETHEUS_RW_SERVER_URL) {
                $env:K6_PROMETHEUS_RW_SERVER_URL = "http://localhost:9090/api/v1/write"
            }
            $k6Args.Add("-o")
            $k6Args.Add("experimental-prometheus-rw")
        }
        $k6Args.Add($Script)

        $commandText = "$K6Binary $($k6Args -join ' ')"
        Write-Host "Command: $commandText"
        $exitCode = Invoke-External -Executable $K6Binary -CommandArgs $k6Args.ToArray()
    }

    $elapsed = (Get-Date) - $started
    $result = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }

    [pscustomobject]@{
        Phase = $Name
        Profile = $Profile
        Command = $commandText
        ExitCode = $exitCode
        Duration = $elapsed.ToString("hh\:mm\:ss")
        Result = $result
    }
}

Set-ProfileDefaults -SelectedProfile $Profile

$phases = @(
    @{ Name = "00 Smoke"; Script = "infra/load-tests/scripts/00-smoke.js" },
    @{ Name = "01 Patient Load"; Script = "infra/load-tests/scripts/01-patient-load.js" },
    @{ Name = "02 Schedule Load"; Script = "infra/load-tests/scripts/02-schedule-load.js" },
    @{ Name = "03 Payment Load"; Script = "infra/load-tests/scripts/03-payment-load.js" },
    @{ Name = "04 Notification Load"; Script = "infra/load-tests/scripts/04-notification-load.js" }
)

if ($IncludeRateLimit) {
    $phases += @{ Name = "07 Gateway Rate Limit"; Script = "infra/load-tests/scripts/07-gateway-rate-limit.js" }
}

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
$results | Select-Object Phase, Profile, ExitCode, Duration, Result, Command | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.ExitCode -ne 0 })
if ($failed.Count -gt 0) {
    exit 1
}

exit 0
