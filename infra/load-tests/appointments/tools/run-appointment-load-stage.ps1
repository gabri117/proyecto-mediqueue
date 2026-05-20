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
    [int]$DatasetValidationSampleLimit = 20,
    [switch]$SkipBackendDatasetValidation,
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

function Invoke-Preflight {
    param([string]$Url)

    Write-Host "Preflight: Docker compose"
    try {
        $composePs = docker compose ps 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $composePs -match "500 Internal Server Error") {
            throw "docker compose ps fallo o Docker devolvio 500 Internal Server Error. Reinicia Docker Desktop antes de ejecutar carga."
        }
        Write-Host "docker_compose_ps=OK"
    } catch {
        throw "Preflight Docker fallo: $($_.Exception.Message)"
    }

    $uri = [Uri]$Url
    $hostName = $uri.Host
    $port = if ($uri.IsDefaultPort) { if ($uri.Scheme -eq "https") { 443 } else { 80 } } else { $uri.Port }
    Write-Host "Preflight: TCP ${hostName}:$port"
    $tcp = Test-NetConnection -ComputerName $hostName -Port $port -WarningAction SilentlyContinue
    if (-not $tcp.TcpTestSucceeded) {
        throw "Gateway no acepta conexiones TCP en ${hostName}:$port. Revisa api-gateway-lb/api-gateway antes de k6."
    }

    $healthUrl = "$($uri.Scheme)://$($uri.Authority)/actuator/health"
    Write-Host "Preflight: GET $healthUrl"
    try {
        $health = Invoke-WebRequest -Uri $healthUrl -Headers @{ Accept = "application/json" } -UseBasicParsing -TimeoutSec 10
        $body = [string]$health.Content
        if ([int]$health.StatusCode -ne 200) {
            throw "health status=$($health.StatusCode) body=$($body.Substring(0, [Math]::Min(500, $body.Length)))"
        }
        if ($body -match "No server is available" -or $body -match "<html") {
            throw "health devolvio HTML de HAProxy/no backend. api-gateway-lb no tiene servidores sanos."
        }
        Write-Host "gateway_health=OK"
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "No server is available" -or $msg -match "503") {
            throw "Gateway health fallo con 503/HAProxy. Hay LB sin backend sano: $msg"
        }
        throw "Gateway health fallo: $msg"
    }
}

function Test-DatasetRange {
    param(
        [array]$Rows,
        [int]$Offset,
        [int]$Limit
    )

    $seenSlots = New-Object "System.Collections.Generic.HashSet[string]"
    $duplicateSlots = 0
    $invalidItems = 0

    for ($i = $Offset; $i -lt ($Offset + $Limit); $i++) {
        $item = $Rows[$i]
        foreach ($field in @("patientId", "dentistId", "slotId", "appointmentDate", "startTime", "endTime", "amount")) {
            if ($null -eq $item.$field -or ([string]$item.$field).Trim().Length -eq 0) {
                $invalidItems++
                break
            }
        }
        $slotId = [string]$item.slotId
        if ($slotId -and -not $seenSlots.Add($slotId)) {
            $duplicateSlots++
        }
    }

    if ($invalidItems -gt 0 -or $duplicateSlots -gt 0) {
        throw "Dataset invalido en rango. invalid_items=$invalidItems duplicate_slots=$duplicateSlots offset=$Offset limit=$Limit"
    }

    Write-Host "dataset_range=OK offset=$Offset limit=$Limit duplicate_slots=0"
}

function Invoke-DatasetBackendValidation {
    param(
        [string]$Url,
        [string]$Path,
        [int]$Offset,
        [int]$SampleLimit
    )

    if ($SkipBackendDatasetValidation) {
        Write-Warning "Saltando validacion backend del dataset por -SkipBackendDatasetValidation."
        return
    }

    Write-Host "Preflight: backend dataset validation sample=$SampleLimit"
    & .\infra\load-tests\appointments\tools\validate-appointment-dataset.ps1 `
        -BaseUrl $Url `
        -DataFile $Path `
        -StartIndex $Offset `
        -Limit $SampleLimit
    if ($LASTEXITCODE -ne 0) {
        throw "Validacion backend del dataset fallo. El rango puede estar consumido, stale o inconsistente."
    }
}

function Invoke-FailureEvidence {
    param([string]$Summary)

    Write-Warning "Recolectando evidencia automatica por fallo de carga."
    & .\infra\load-tests\appointments\tools\monitor-loadtest.ps1 `
        -DurationSeconds 1 `
        -IntervalSeconds 1 `
        -Since 15m `
        -SummaryFile $Summary
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

Invoke-Preflight -Url $BaseUrl
Test-DatasetRange -Rows $dataset -Offset $DataOffset -Limit $TotalLimit
Invoke-DatasetBackendValidation -Url $BaseUrl -Path $DataFile -Offset $DataOffset -SampleLimit $DatasetValidationSampleLimit

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
    $connectionRefused = Get-MetricCount -Summary $summary -Name "appointments_connection_refused"
    $status503JsonGateway = Get-MetricCount -Summary $summary -Name "appointments_503_json_gateway"
    $status503HtmlHaproxy = Get-MetricCount -Summary $summary -Name "appointments_503_html_haproxy"
    $status503 = Get-MetricCount -Summary $summary -Name "appointments_503"
    $validation = Get-MetricCount -Summary $summary -Name "appointments_validation_error"
    $conflict = Get-MetricCount -Summary $summary -Name "appointments_conflict"
    $unexpected = Get-MetricCount -Summary $summary -Name "appointments_unexpected"
    $dropped = Get-MetricCount -Summary $summary -Name "dropped_iterations"

    Write-Host ""
    Write-Host "Stage summary"
    Write-Host "appointments_created=$created"
    Write-Host "appointments_503=$status503"
    Write-Host "appointments_503_json_gateway=$status503JsonGateway"
    Write-Host "appointments_503_html_haproxy=$status503HtmlHaproxy"
    Write-Host "appointments_connection_refused=$connectionRefused"
    Write-Host "appointments_server_error=$serverError"
    Write-Host "appointments_timeout=$timeouts"
    Write-Host "appointments_validation_error=$validation"
    Write-Host "appointments_conflict=$conflict"
    Write-Host "appointments_unexpected=$unexpected"
    Write-Host "dropped_iterations=$dropped"

    if ($created -eq $TotalLimit -and $status503 -eq 0 -and $serverError -eq 0 -and $timeouts -eq 0 -and $connectionRefused -eq 0 -and $validation -eq 0 -and $conflict -eq 0 -and $unexpected -eq 0 -and $dropped -eq 0) {
        Write-Host "PASS"
    } else {
        Write-Warning "FAIL: no cumple criterios oficiales de Bloque 2."
        if ($status503 -gt 0 -or $dropped -gt 0 -or $connectionRefused -gt 0) {
            Invoke-FailureEvidence -Summary $SummaryFile
        }
    }
}

exit $exitCode
