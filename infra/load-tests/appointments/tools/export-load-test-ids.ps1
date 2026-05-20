param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$OutputDir = ".\infra\load-tests\appointments\data",
    [string]$ClientId = "block2-export-ids"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

function New-Headers {
    return @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "X-Client-Id" = $ClientId
    }
}

function Try-GetJson {
    param([string]$Path)

    try {
        return Invoke-RestMethod -Method Get -Uri "$BaseUrl$Path" -Headers (New-Headers)
    } catch {
        Write-Warning "GET $Path no esta disponible o fallo: $($_.Exception.Message)"
        return $null
    }
}

function Export-Json {
    param(
        [object]$Value,
        [string]$Path
    )
    $Value | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

$health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/actuator/health" -Headers (New-Headers)
Write-Host "Gateway health: $($health.status)"

$patients = Try-GetJson -Path "/api/patients"
if ($null -ne $patients) {
    $patientArray = @($patients)
    Export-Json -Value ([ordered]@{
        source = "GET /api/patients"
        patientIds = @($patientArray | ForEach-Object { $_.patientId })
        patients = $patientArray
    }) -Path (Join-Path $OutputDir "patient-ids.json")
    Write-Host "Wrote patient-ids.json"
} else {
    Write-Warning "No existe GET /api/patients global en el contrato actual. Usa prepare-appointment-load-data.ps1 o provee patient-ids.json manualmente."
}

$dentists = Try-GetJson -Path "/api/dentists"
if ($null -ne $dentists) {
    $dentistArray = @($dentists)
    Export-Json -Value ([ordered]@{
        source = "GET /api/dentists"
        dentistIds = @($dentistArray | ForEach-Object { $_.dentistId })
        dentists = $dentistArray
    }) -Path (Join-Path $OutputDir "dentist-ids.json")
    Write-Host "Wrote dentist-ids.json"
} else {
    Write-Warning "No existe GET /api/dentists global en el contrato actual; requiere query por email. Usa prepare-appointment-load-data.ps1 para generar dentist-ids.json."
}

$slots = Try-GetJson -Path "/api/slots/available"
if ($null -ne $slots) {
    $slotArray = @($slots | Where-Object { $null -ne $_.slotId })
    Export-Json -Value ([ordered]@{
        source = "GET /api/slots/available"
        total = $slotArray.Count
        slots = $slotArray
    }) -Path (Join-Path $OutputDir "available-slots.json")
    Write-Host "Wrote available-slots.json with $($slotArray.Count) slots"
}
