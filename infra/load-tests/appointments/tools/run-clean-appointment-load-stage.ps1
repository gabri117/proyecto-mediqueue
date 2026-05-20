param(
    [Parameter(Mandatory = $true)][int]$RatePerMinute,
    [Parameter(Mandatory = $true)][int]$TotalLimit,
    [Parameter(Mandatory = $true)][int]$PreAllocatedVus,
    [Parameter(Mandatory = $true)][int]$MaxVus,
    [decimal]$Amount = 1500.00,
    [ValidateSet("medium", "high", "extreme")]
    [string]$ScalePreset = "medium",
    [bool]$PrewarmCache = $false,
    [string]$BaseUrl = "http://localhost:8080",
    [string]$DataFile = ".\infra\load-tests\appointments\data\appointments-50000.json",
    [string]$SummaryFile,
    [string]$HttpTimeout = "60s",
    [switch]$Allow50k
)

$ErrorActionPreference = "Stop"

if ($RatePerMinute -eq 50000 -and -not $Allow50k) {
    throw "50,000/min requiere confirmacion explicita. Vuelve a ejecutar con -Allow50k."
}

function Get-Scale {
    param([string]$Preset)

    switch ($Preset) {
        "medium" {
            return [ordered]@{
                "api-gateway" = 2
                "appointment-service" = 4
                "schedule-service" = 3
                "patient-service" = 2
                "payment-service" = 3
                "notification-service" = 2
            }
        }
        "high" {
            return [ordered]@{
                "api-gateway" = 3
                "appointment-service" = 6
                "schedule-service" = 4
                "patient-service" = 3
                "payment-service" = 3
                "notification-service" = 2
            }
        }
        "extreme" {
            return [ordered]@{
                "api-gateway" = 4
                "appointment-service" = 8
                "schedule-service" = 4
                "patient-service" = 3
                "payment-service" = 3
                "notification-service" = 2
            }
        }
    }
}

function Invoke-Docker {
    param([string[]]$Args)

    & docker @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($Args -join ' ') fallo con exit code $LASTEXITCODE"
    }
}

function Wait-GatewayHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 180
    )

    $uri = [Uri]$Url
    $healthUrl = "$($uri.Scheme)://$($uri.Authority)/actuator/health"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -Headers @{ Accept = "application/json" } -UseBasicParsing -TimeoutSec 5
            $body = [string]$response.Content
            if ([int]$response.StatusCode -eq 200 -and $body -notmatch "<html" -and $body -notmatch "No server is available") {
                Write-Host "gateway_health=OK"
                return
            }
        } catch {
            Start-Sleep -Seconds 3
            continue
        }
        Start-Sleep -Seconds 3
    }

    throw "api-gateway no quedo healthy antes del timeout."
}

if (-not $SummaryFile) {
    $SummaryFile = ".\infra\load-tests\appointments\results\appointment-rpm-clean-$RatePerMinute-summary.json"
}

$scale = Get-Scale -Preset $ScalePreset

try {
    Write-Host "Clean run: docker compose down -v --remove-orphans"
    Invoke-Docker -Args @("compose", "down", "-v", "--remove-orphans")

    $upArgs = @("compose", "up", "-d", "--build")
    foreach ($service in $scale.Keys) {
        $upArgs += @("--scale", "$service=$($scale[$service])")
    }

    Write-Host "Clean run: docker $($upArgs -join ' ')"
    Invoke-Docker -Args $upArgs

    Wait-GatewayHealth -Url $BaseUrl

    Write-Host "Clean run: preparing SQL dataset"
    & .\infra\load-tests\appointments\tools\prepare-appointment-load-data.ps1 `
        -BaseUrl $BaseUrl `
        -TotalPatients 100 `
        -TotalDentists 20 `
        -TotalSlots 50000 `
        -Amount $Amount `
        -Mode sql
    if ($LASTEXITCODE -ne 0) {
        throw "prepare-appointment-load-data.ps1 fallo."
    }

    & .\infra\load-tests\appointments\tools\inspect-appointment-dataset.ps1 `
        -DataFile $DataFile `
        -ExpectedCount 50000
    if ($LASTEXITCODE -ne 0) {
        throw "inspect-appointment-dataset.ps1 fallo."
    }

    & .\infra\load-tests\appointments\tools\validate-appointment-dataset.ps1 `
        -BaseUrl $BaseUrl `
        -DataFile $DataFile `
        -StartIndex 0 `
        -Limit 20 `
        -ExpectedCount 50000
    if ($LASTEXITCODE -ne 0) {
        throw "validate-appointment-dataset.ps1 fallo."
    }

    if ($PrewarmCache) {
        & .\infra\load-tests\appointments\tools\prewarm-appointment-cache.ps1 `
            -BaseUrl $BaseUrl `
            -DataFile $DataFile `
            -StartIndex 0 `
            -Limit 50000
        if ($LASTEXITCODE -ne 0) {
            throw "prewarm-appointment-cache.ps1 fallo."
        }
    }

    $runnerArgs = @(
        "-RatePerMinute", "$RatePerMinute",
        "-TotalLimit", "$TotalLimit",
        "-DataOffset", "0",
        "-PreAllocatedVus", "$PreAllocatedVus",
        "-MaxVus", "$MaxVus",
        "-BaseUrl", $BaseUrl,
        "-DataFile", $DataFile,
        "-SummaryFile", $SummaryFile,
        "-HttpTimeout", $HttpTimeout
    )
    if ($Allow50k) {
        $runnerArgs += "-Allow50k"
    }

    & .\infra\load-tests\appointments\tools\run-appointment-load-stage.ps1 @runnerArgs
    $runnerExit = $LASTEXITCODE

    & .\infra\load-tests\appointments\tools\monitor-loadtest.ps1 `
        -DurationSeconds 1 `
        -IntervalSeconds 1 `
        -Since 20m `
        -SummaryFile $SummaryFile

    exit $runnerExit
} catch {
    Write-Error $_.Exception.Message
    if ($SummaryFile -and (Test-Path -LiteralPath $SummaryFile)) {
        & .\infra\load-tests\appointments\tools\monitor-loadtest.ps1 `
            -DurationSeconds 1 `
            -IntervalSeconds 1 `
            -Since 20m `
            -SummaryFile $SummaryFile
    }
    exit 1
}
