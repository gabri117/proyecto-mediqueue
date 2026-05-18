param(
    [string]$BaseUrl = "http://localhost:8080",
    [Alias("TotalAppointments")]
    [int]$Total = 10,
    [Alias("OutputPath")]
    [string]$OutputFile,
    [decimal]$Amount = 150.00,
    [string[]]$PatientIds = @(),
    [string]$PatientIdsFile,
    [string]$ClientId = "dataset-generator-block2"
)

$ErrorActionPreference = "Stop"

if ($Total -lt 1) {
    throw "Total debe ser mayor que cero."
}

if (-not $OutputFile -or $OutputFile.Trim().Length -eq 0) {
    $fileName = if ($Total -eq 10) { "appointments.sample.json" } else { "appointments-$Total.json" }
    $OutputFile = Join-Path "infra\load-tests\appointments\data" $fileName
}

function New-Headers {
    return @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "X-Client-Id" = $ClientId
    }
}

function Read-PatientIds {
    $ids = New-Object System.Collections.Generic.List[string]

    foreach ($id in $PatientIds) {
        if ($id -and $id.Trim().Length -gt 0) {
            $ids.Add($id.Trim())
        }
    }

    if ($PatientIdsFile -and $PatientIdsFile.Trim().Length -gt 0) {
        if (-not (Test-Path -Path $PatientIdsFile)) {
            throw "Archivo de pacientes no encontrado: $PatientIdsFile"
        }

        $raw = Get-Content -Raw -Path $PatientIdsFile
        $json = $raw | ConvertFrom-Json

        if ($json -is [array]) {
            foreach ($item in $json) {
                if ($item -is [string]) {
                    $ids.Add($item)
                } elseif ($null -ne $item.patientId) {
                    $ids.Add([string]$item.patientId)
                } elseif ($null -ne $item.id) {
                    $ids.Add([string]$item.id)
                }
            }
        } elseif ($null -ne $json.patientIds) {
            foreach ($id in $json.patientIds) {
                $ids.Add([string]$id)
            }
        } elseif ($null -ne $json.patients) {
            foreach ($patient in $json.patients) {
                if ($null -ne $patient.patientId) {
                    $ids.Add([string]$patient.patientId)
                } elseif ($null -ne $patient.id) {
                    $ids.Add([string]$patient.id)
                }
            }
        } else {
            throw "El archivo de pacientes debe ser un arreglo de UUIDs, un arreglo de objetos con patientId, o un objeto con patientIds/patients."
        }
    }

    return @($ids | Select-Object -Unique)
}

function Assert-Guid {
    param(
        [string]$Value,
        [string]$Name
    )

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$parsed)) {
        throw "$Name no es un UUID valido: $Value"
    }
}

function Normalize-Time {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $text = [string]$Value
    if ($text.Length -eq 5) {
        return "$text`:00"
    }
    return $text
}

Write-Host "Checking gateway health at $BaseUrl ..."
$health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/actuator/health" -Headers (New-Headers)
Write-Host "Gateway health: $($health.status)"

$patientPool = Read-PatientIds
if ($patientPool.Count -lt $Total) {
    throw "No hay suficientes pacientes reales para generar $Total citas. Se recibieron $($patientPool.Count). Ejecuta primero el seed y vuelve a pasar los patientId con -PatientIdsFile o -PatientIds."
}

foreach ($patientId in $patientPool) {
    Assert-Guid -Value $patientId -Name "patientId"
}

Write-Host "Fetching available slots from $BaseUrl/api/slots/available ..."
$slotsResponse = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/slots/available" -Headers (New-Headers)
$slots = @($slotsResponse | Where-Object {
    $null -ne $_.slotId -and
    $null -ne $_.dentistId -and
    $null -ne $_.slotDate -and
    $null -ne $_.startTime -and
    $null -ne $_.endTime -and
    ($null -eq $_.status -or [string]$_.status -eq "AVAILABLE")
} | Sort-Object slotId -Unique)

if ($slots.Count -lt $Total) {
    throw "No hay suficientes slots únicos para generar $Total citas. Ejecuta primero el seed."
}

$appointments = New-Object System.Collections.Generic.List[object]
$usedSlotIds = New-Object "System.Collections.Generic.HashSet[string]"

for ($i = 0; $i -lt $Total; $i++) {
    $slot = $slots[$i]
    $slotId = [string]$slot.slotId
    $dentistId = [string]$slot.dentistId
    $patientId = [string]$patientPool[$i]

    Assert-Guid -Value $slotId -Name "slotId"
    Assert-Guid -Value $dentistId -Name "dentistId"

    if (-not $usedSlotIds.Add($slotId)) {
        throw "slotId repetido detectado desde backend: $slotId"
    }

    $appointments.Add([ordered]@{
        patientId = $patientId
        dentistId = $dentistId
        slotId = $slotId
        appointmentDate = [string]$slot.slotDate
        startTime = Normalize-Time $slot.startTime
        endTime = Normalize-Time $slot.endTime
        amount = [decimal]$Amount
        notes = "Block 2 generated appointment $($i + 1)"
    })
}

$output = [ordered]@{
    metadata = [ordered]@{
        name = if ($Total -eq 10) { "appointments.sample" } else { "appointments-$Total" }
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
        baseUrl = $BaseUrl
        total = $Total
        amount = [decimal]$Amount
        source = "GET /api/slots/available plus caller-provided real patient IDs"
        slotRule = "slotId is unique per appointment row"
    }
    appointments = $appointments
}

$parent = Split-Path -Parent $OutputFile
if ($parent -and -not (Test-Path -Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

$output | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "Dataset written to $OutputFile"
Write-Host "Rows: $($appointments.Count)"
