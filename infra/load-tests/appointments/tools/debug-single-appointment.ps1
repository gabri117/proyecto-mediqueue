param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$DataFile = ".\infra\load-tests\appointments\data\appointments-50000.json",
    [int]$Index = 0,
    [string]$RunId = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()),
    [string]$ClientId = "block2-debug-single"
)

$ErrorActionPreference = "Stop"

if ($Index -lt 0) { throw "Index debe ser mayor o igual a cero." }
if (-not (Test-Path -Path $DataFile)) { throw "DataFile no encontrado: $DataFile" }

function Read-JsonNoBom {
    param([string]$Path)

    $raw = Get-Content -Raw -Path $Path
    $raw = $raw.TrimStart([char]0xFEFF)
    return $raw | ConvertFrom-Json
}

function Get-Appointments {
    param([object]$Json)

    if ($Json -is [array]) { return @($Json) }
    if ($null -ne $Json.appointments) { return @($Json.appointments) }
    throw "El dataset debe ser un arreglo o un objeto con propiedad appointments."
}

function Normalize-Time {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ($text.Length -eq 5) { return "$text`:00" }
    return $text
}

$json = Read-JsonNoBom -Path $DataFile
$appointments = Get-Appointments -Json $json

if ($Index -ge $appointments.Count) {
    throw "Index $Index esta fuera del dataset. Total=$($appointments.Count)."
}

$item = $appointments[$Index]
$body = [ordered]@{
    patientId = [string]$item.patientId
    dentistId = [string]$item.dentistId
    slotId = [string]$item.slotId
    appointmentDate = [string]$item.appointmentDate
    startTime = Normalize-Time $item.startTime
    endTime = Normalize-Time $item.endTime
    amount = [decimal]$item.amount
    notes = if ($item.notes) { [string]$item.notes } else { "Block 2 debug single appointment" }
}

$idempotencyKey = "appointment-debug-$RunId-$Index"
$headers = @{
    "Content-Type" = "application/json"
    "Accept" = "application/json"
    "X-Client-Id" = $ClientId
    "X-Idempotency-Key" = $idempotencyKey
}

Write-Host "POST $BaseUrl/api/appointments"
Write-Host "DataFile=$DataFile"
Write-Host "Index=$Index"
Write-Host "X-Idempotency-Key=$idempotencyKey"
Write-Host "Request body:"
$requestJson = $body | ConvertTo-Json -Depth 8
Write-Host $requestJson

try {
    $response = Invoke-WebRequest -Method Post -Uri "$BaseUrl/api/appointments" -Headers $headers -Body $requestJson -UseBasicParsing
    Write-Host ""
    Write-Host "StatusCode=$($response.StatusCode)"
    Write-Host "Headers:"
    $response.Headers.GetEnumerator() | ForEach-Object { Write-Host "$($_.Key): $($_.Value)" }
    Write-Host "Response body:"
    Write-Host $response.Content
} catch {
    $status = 0
    $bodyText = $_.Exception.Message
    $headersText = ""
    if ($null -ne $_.Exception.Response) {
        $status = [int]$_.Exception.Response.StatusCode
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $bodyText = $reader.ReadToEnd()
        } catch {
            $bodyText = $_.Exception.Message
        }
        try {
            $responseHeaders = $_.Exception.Response.Headers
            $headersText = ($responseHeaders.AllKeys | ForEach-Object { "${_}: $($responseHeaders[$_])" }) -join [Environment]::NewLine
        } catch {
            $headersText = ""
        }
    }

    Write-Host ""
    Write-Host "StatusCode=$status"
    if ($headersText) {
        Write-Host "Headers:"
        Write-Host $headersText
    }
    Write-Host "Response body:"
    Write-Host $bodyText
    exit 2
}
