param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$DataFile = ".\infra\load-tests\appointments\data\appointments-50000.json",
    [int]$StartIndex = 0,
    [int]$Limit = 50000,
    [int]$TimeoutSeconds = 10,
    [string]$ClientId = "appointment-cache-prewarm"
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

function Invoke-PrewarmGet {
    param(
        [string]$Url,
        [string]$Kind,
        [string]$Id
    )

    try {
        $response = Invoke-WebRequest -Method Get -Uri $Url -TimeoutSec $TimeoutSeconds -Headers @{
            "Accept" = "application/json"
            "X-Client-Id" = $ClientId
        }
        return [pscustomobject]@{ kind = $Kind; id = $Id; ok = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300); status = $response.StatusCode }
    } catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        return [pscustomobject]@{ kind = $Kind; id = $Id; ok = $false; status = $status }
    }
}

$items = Read-JsonArray -Path $DataFile
if ($StartIndex -lt 0 -or $Limit -lt 1) {
    throw "StartIndex debe ser >= 0 y Limit debe ser >= 1."
}
if ($StartIndex -ge $items.Count) {
    throw "StartIndex $StartIndex esta fuera del dataset de $($items.Count) registros."
}

$rangeEnd = [Math]::Min($items.Count, $StartIndex + $Limit)
$range = @($items[$StartIndex..($rangeEnd - 1)])

$patientIds = @($range | Where-Object { $_.patientId } | Select-Object -ExpandProperty patientId -Unique)
$slotIds = @($range | Where-Object { $_.slotId } | Select-Object -ExpandProperty slotId -Unique)

Write-Host "Prewarm dataset=$DataFile start=$StartIndex limit=$Limit"
Write-Host "unique_patients=$($patientIds.Count)"
Write-Host "unique_slots=$($slotIds.Count)"
Write-Host "Nota: este prewarm calienta patient/schedule via gateway y caches/DB aguas abajo. La cache Redis interna de appointment-service se llena cuando appointment-service valida durante POST /api/appointments."

$patientOk = 0
$patientFail = 0
foreach ($id in $patientIds) {
    $result = Invoke-PrewarmGet -Url "$BaseUrl/api/patients/$id" -Kind "patient" -Id $id
    if ($result.ok) { $patientOk++ } else { $patientFail++; Write-Warning "patient prewarm failed id=$id status=$($result.status)" }
}

$slotOk = 0
$slotFail = 0
foreach ($id in $slotIds) {
    $result = Invoke-PrewarmGet -Url "$BaseUrl/api/slots/$id" -Kind "slot" -Id $id
    if ($result.ok) { $slotOk++ } else { $slotFail++; Write-Warning "slot prewarm failed id=$id status=$($result.status)" }
}

Write-Host "patient_ok=$patientOk"
Write-Host "patient_failed=$patientFail"
Write-Host "slot_ok=$slotOk"
Write-Host "slot_failed=$slotFail"

if ($patientFail -gt 0 -or $slotFail -gt 0) {
    exit 1
}
