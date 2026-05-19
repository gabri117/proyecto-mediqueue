param(
    [string]$BaseUrl = "http://localhost:8080",
    [Alias("TotalAppointments")]
    [int]$Total = 10,
    [int[]]$Totals = @(),
    [Alias("OutputPath")]
    [string]$OutputFile,
    [string]$OutputDir = ".\infra\load-tests\appointments\data",
    [decimal]$Amount = 150.00,
    [string[]]$PatientIds = @(),
    [string]$PatientIdsFile,
    [string]$AvailableSlotsFile,
    [string]$ClientId = "dataset-generator-block2"
)

$ErrorActionPreference = "Stop"

if ($Total -lt 1) {
    throw "Total debe ser mayor que cero."
}
if ($Totals.Count -eq 0) {
    $Totals = @($Total)
}
if ($Amount -le 0) {
    throw "amount debe existir y ser mayor que cero."
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

        $json = Get-Content -Raw -Path $PatientIdsFile | ConvertFrom-Json
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

function Read-AvailableSlots {
    if ($AvailableSlotsFile -and $AvailableSlotsFile.Trim().Length -gt 0) {
        if (-not (Test-Path -Path $AvailableSlotsFile)) {
            throw "Archivo de slots no encontrado: $AvailableSlotsFile"
        }

        Write-Host "Reading available slots from $AvailableSlotsFile ..."
        $json = Get-Content -Raw -Path $AvailableSlotsFile | ConvertFrom-Json
        if ($json -is [array]) {
            return @($json)
        }
        if ($null -ne $json.slots) {
            return @($json.slots)
        }
        throw "El archivo de slots debe ser un arreglo o un objeto con propiedad slots."
    }

    Write-Host "Checking gateway health at $BaseUrl ..."
    $health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/actuator/health" -Headers (New-Headers)
    Write-Host "Gateway health: $($health.status)"

    Write-Host "Fetching available slots from $BaseUrl/api/slots/available ..."
    return @(Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/slots/available" -Headers (New-Headers))
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

function Write-JsonNoBom {
    param(
        [object]$Value,
        [string]$Path,
        [int]$Depth = 8
    )

    $jsonContent = $Value | ConvertTo-Json -Depth $Depth
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $jsonContent, $utf8NoBom)
}

function New-AppointmentDataset {
    param(
        [object[]]$Slots,
        [string[]]$PatientPool,
        [int]$DatasetTotal
    )

    $appointments = New-Object System.Collections.Generic.List[object]
    $usedSlotIds = New-Object "System.Collections.Generic.HashSet[string]"

    for ($i = 0; $i -lt $DatasetTotal; $i++) {
        $slot = $Slots[$i]
        $slotId = [string]$slot.slotId
        $dentistId = [string]$slot.dentistId
        $patientId = [string]$PatientPool[$i % $PatientPool.Count]

        Assert-Guid -Value $patientId -Name "patientId"
        Assert-Guid -Value $slotId -Name "slotId"
        Assert-Guid -Value $dentistId -Name "dentistId"

        if (-not $usedSlotIds.Add($slotId)) {
            throw "slotId repetido detectado: $slotId"
        }

        $appointmentDate = if ($null -ne $slot.appointmentDate) { [string]$slot.appointmentDate } else { [string]$slot.slotDate }

        $appointments.Add([ordered]@{
            patientId = $patientId
            dentistId = $dentistId
            slotId = $slotId
            appointmentDate = $appointmentDate
            startTime = Normalize-Time $slot.startTime
            endTime = Normalize-Time $slot.endTime
            amount = [decimal]$Amount
            notes = "Block 2 generated appointment $($i + 1)"
        })
    }

    return [ordered]@{
        metadata = [ordered]@{
            name = if ($DatasetTotal -eq 10) { "appointments.sample" } else { "appointments-$DatasetTotal" }
            generatedAt = (Get-Date).ToUniversalTime().ToString("o")
            baseUrl = $BaseUrl
            total = $DatasetTotal
            amount = [decimal]$Amount
            source = if ($AvailableSlotsFile) { $AvailableSlotsFile } else { "GET /api/slots/available" }
            slotRule = "slotId is unique per appointment row"
            patientRule = "patientId values may be reused"
        }
        appointments = $appointments
    }
}

$patientPool = Read-PatientIds
if ($patientPool.Count -lt 1) {
    throw "No hay pacientes reales para generar citas. Ejecuta primero el seed y vuelve a pasar patientId con -PatientIdsFile o -PatientIds."
}

$rawSlots = Read-AvailableSlots
$slots = @($rawSlots | Where-Object {
    $null -ne $_.slotId -and
    $null -ne $_.dentistId -and
    $null -ne $_.slotDate -and
    $null -ne $_.startTime -and
    $null -ne $_.endTime -and
    ($null -eq $_.status -or [string]$_.status -eq "AVAILABLE")
} | Sort-Object slotId -Unique)

$maxTotal = ($Totals | Measure-Object -Maximum).Maximum
if ($slots.Count -lt $maxTotal) {
    throw "No hay suficientes slots unicos para generar $maxTotal citas. Ejecuta primero el seed."
}

foreach ($datasetTotal in $Totals) {
    if ($datasetTotal -lt 1) {
        throw "Todos los valores en Totals deben ser mayores que cero."
    }

    $targetFile = if ($Totals.Count -eq 1 -and $OutputFile) {
        $OutputFile
    } else {
        $name = if ($datasetTotal -eq 10) { "appointments.sample.json" } else { "appointments-$datasetTotal.json" }
        Join-Path $OutputDir $name
    }

    $parent = Split-Path -Parent $targetFile
    if ($parent -and -not (Test-Path -Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $dataset = New-AppointmentDataset -Slots $slots -PatientPool $patientPool -DatasetTotal $datasetTotal
    if ($dataset.appointments.Count -lt $datasetTotal) {
        throw "dataset.length menor que total solicitado para $targetFile"
    }

    Write-JsonNoBom -Value $dataset -Path $targetFile -Depth 8
    Write-Host "Dataset written to $targetFile"
    Write-Host "Rows: $($dataset.appointments.Count)"
}
