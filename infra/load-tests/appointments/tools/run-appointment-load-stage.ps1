param(
    [Parameter(Mandatory = $true)][int]$RatePerMinute,
    [Parameter(Mandatory = $true)][int]$TotalLimit,
    [Parameter(Mandatory = $true)][int]$DataOffset,
    [Parameter(Mandatory = $true)][int]$PreAllocatedVus,
    [Parameter(Mandatory = $true)][int]$MaxVus,
    [string]$BaseUrl = "http://localhost:8080",
    [string]$DataFile = ".\infra\load-tests\appointments\data\appointments-50000.json",
    [string]$Duration = "1m",
    [string]$SummaryFile,
    [string]$HttpTimeout = "60s",
    [switch]$DebugResponses,
    [switch]$Allow50k,
    [int]$DebugResponseLimit = 10,
    [int]$DebugResponseEvery = 500,
    [string]$ClientMode = "per-vu"
)

$ErrorActionPreference = "Stop"

function Read-JsonArray {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Dataset no encontrado: $Path"
    }

    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    $raw = $raw.TrimStart([char]0xFEFF)
    $json = $raw | ConvertFrom-Json
    if ($json -isnot [System.Array]) {
        throw "Dataset invalido: se esperaba un array puro de appointments."
    }
    return @($json)
}

function Get-MetricCount {
    param($Summary, [string]$Name)
    if ($Summary.metrics.$Name -and $Summary.metrics.$Name.values.count -ne $null) {
        return [int]$Summary.metrics.$Name.values.count
    }
    return 0
}

if ($RatePerMinute -eq 50000 -and -not $Allow50k) {
    throw "50,000/min requiere confirmacion explicita. Vuelve a ejecutar con -Allow50k en la maquina potente y con dataset limpio."
}

if ($RatePerMinute -lt 1 -or $TotalLimit -lt 1 -or $DataOffset -lt 0 -or $PreAllocatedVus -lt 1 -or $MaxVus -lt $PreAllocatedVus) {
    throw "Parametros invalidos. Revisa RatePerMinute, TotalLimit, DataOffset, PreAllocatedVus y MaxVus."
}

$dataset = Read-JsonArray -Path $DataFile
$required = $DataOffset + $TotalLimit
if ($required -gt $dataset.Count) {
    throw "Dataset insuficiente. Se requieren $required registros, pero $DataFile tiene $($dataset.Count)."
}

if (-not $SummaryFile) {
    $safeRate = "$RatePerMinute".Replace("/", "-")
    $SummaryFile = ".\infra\load-tests\appointments\results\appointment-rpm-$safeRate-summary.json"
}

$summaryDir = Split-Path -Parent $SummaryFile
if ($summaryDir) {
    New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
}

$env:BASE_URL = $BaseUrl
$env:DATA_FILE = $DataFile
$env:RATE_PER_MINUTE = "$RatePerMinute"
$env:DURATION = $Duration
$env:TOTAL_LIMIT = "$TotalLimit"
$env:DATA_OFFSET = "$DataOffset"
$env:PRE_ALLOCATED_VUS = "$PreAllocatedVus"
$env:MAX_VUS = "$MaxVus"
$env:CLIENT_MODE = $ClientMode
$env:HTTP_TIMEOUT = $HttpTimeout
$env:DEBUG_RESPONSES = if ($DebugResponses) { "true" } else { "false" }
$env:DEBUG_RESPONSE_LIMIT = "$DebugResponseLimit"
$env:DEBUG_RESPONSE_EVERY = "$DebugResponseEvery"

Write-Host "Running appointment load stage"
Write-Host "rate_per_minute=$RatePerMinute"
Write-Host "total_limit=$TotalLimit"
Write-Host "data_offset=$DataOffset"
Write-Host "pre_allocated_vus=$PreAllocatedVus"
Write-Host "max_vus=$MaxVus"
Write-Host "data_file=$DataFile"
Write-Host "summary_file=$SummaryFile"

k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export $SummaryFile
$exitCode = $LASTEXITCODE

if (Test-Path -LiteralPath $SummaryFile) {
    $summary = Get-Content -Raw -LiteralPath $SummaryFile | ConvertFrom-Json
    $created = Get-MetricCount -Summary $summary -Name "appointments_created"
    $serverError = Get-MetricCount -Summary $summary -Name "appointments_server_error"
    $timeouts = Get-MetricCount -Summary $summary -Name "appointments_timeout"
    $status503 = Get-MetricCount -Summary $summary -Name "appointments_503"
    $validation = Get-MetricCount -Summary $summary -Name "appointments_validation_error"
    $conflict = Get-MetricCount -Summary $summary -Name "appointments_conflict"
    $unexpected = Get-MetricCount -Summary $summary -Name "appointments_unexpected"
    $dropped = Get-MetricCount -Summary $summary -Name "dropped_iterations"

    Write-Host ""
    Write-Host "Stage summary"
    Write-Host "appointments_created=$created"
    Write-Host "appointments_503=$status503"
    Write-Host "appointments_server_error=$serverError"
    Write-Host "appointments_timeout=$timeouts"
    Write-Host "appointments_validation_error=$validation"
    Write-Host "appointments_conflict=$conflict"
    Write-Host "appointments_unexpected=$unexpected"
    Write-Host "dropped_iterations=$dropped"

    if ($created -eq $TotalLimit -and $status503 -eq 0 -and $serverError -eq 0 -and $timeouts -eq 0 -and $validation -eq 0 -and $conflict -eq 0 -and $unexpected -eq 0 -and $dropped -eq 0) {
        Write-Host "PASS"
    } else {
        Write-Warning "FAIL: no cumple criterios oficiales de Bloque 2."
    }
}

exit $exitCode
