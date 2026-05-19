param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$DataFile = ".\infra\load-tests\appointments\data\appointments-50000.json",
    [int]$StartIndex = 0,
    [int]$Limit = 20,
    [string]$ClientId = "block2-dataset-validator"
)

$ErrorActionPreference = "Stop"

if ($StartIndex -lt 0) { throw "StartIndex debe ser mayor o igual a cero." }
if ($Limit -lt 1) { throw "Limit debe ser mayor que cero." }
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

function Invoke-JsonRequest {
    param(
        [string]$Method,
        [string]$Path
    )

    $uri = "$BaseUrl$Path"
    $headers = @{
        "Accept" = "application/json"
        "X-Client-Id" = $ClientId
    }

    try {
        $response = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -UseBasicParsing
        $json = $null
        if ($response.Content) {
            try { $json = $response.Content | ConvertFrom-Json } catch { $json = $null }
        }
        return [ordered]@{
            ok = $true
            status = [int]$response.StatusCode
            json = $json
            body = [string]$response.Content
            unavailable = $false
        }
    } catch {
        $status = 0
        $body = $_.Exception.Message
        if ($null -ne $_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
            } catch {
                $body = $_.Exception.Message
            }
        }

        return [ordered]@{
            ok = $false
            status = $status
            json = $null
            body = $body
            unavailable = ($status -eq 404 -or $status -eq 405)
        }
    }
}

function Test-Amount {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    try { return ([decimal]$Value) -gt 0 } catch { return $false }
}

function Test-RequiredText {
    param([object]$Value)
    return $null -ne $Value -and ([string]$Value).Trim().Length -gt 0
}

$json = Read-JsonNoBom -Path $DataFile
$appointments = Get-Appointments -Json $json

if ($StartIndex -ge $appointments.Count) {
    throw "StartIndex $StartIndex esta fuera del dataset. Total=$($appointments.Count)."
}

$endExclusive = [Math]::Min($StartIndex + $Limit, $appointments.Count)
$seenSlots = New-Object "System.Collections.Generic.HashSet[string]"

$summary = [ordered]@{
    data_file = (Resolve-Path $DataFile).Path
    base_url = $BaseUrl
    start_index = $StartIndex
    limit = $Limit
    inspected_items = 0
    valid_items = 0
    invalid_items = 0
    missing_patients = 0
    missing_dentists = 0
    missing_slots = 0
    unavailable_slots = 0
    invalid_amount = 0
    duplicate_slots = 0
    invalid_contract_fields = 0
}

for ($i = $StartIndex; $i -lt $endExclusive; $i++) {
    $item = $appointments[$i]
    $summary.inspected_items++
    $errors = New-Object System.Collections.Generic.List[string]

    $slotId = [string]$item.slotId
    if (-not $seenSlots.Add($slotId)) {
        $summary.duplicate_slots++
        $errors.Add("duplicate_slot")
    }

    if (-not (Test-Amount $item.amount)) {
        $summary.invalid_amount++
        $errors.Add("invalid_amount")
    }

    foreach ($field in @("patientId", "dentistId", "slotId", "appointmentDate", "startTime", "endTime")) {
        if (-not (Test-RequiredText $item.$field)) {
            $summary.invalid_contract_fields++
            $errors.Add("missing_$field")
        }
    }

    if (Test-RequiredText $item.patientId) {
        $patient = Invoke-JsonRequest -Method Get -Path "/api/patients/$($item.patientId)"
        if (-not $patient.ok) {
            $summary.missing_patients++
            $errors.Add("patient_not_found_status_$($patient.status)")
        }
    }

    if (Test-RequiredText $item.dentistId) {
        $dentist = Invoke-JsonRequest -Method Get -Path "/api/dentists/$($item.dentistId)"
        if (-not $dentist.ok) {
            $summary.missing_dentists++
            $errors.Add("dentist_not_found_status_$($dentist.status)")
        }
    }

    if (Test-RequiredText $item.slotId) {
        $slot = Invoke-JsonRequest -Method Get -Path "/api/slots/$($item.slotId)"
        if (-not $slot.ok) {
            $summary.missing_slots++
            $errors.Add("slot_not_found_status_$($slot.status)")
        } else {
            $status = [string]$slot.json.status
            if ($status -and $status -ne "AVAILABLE") {
                $summary.unavailable_slots++
                $errors.Add("slot_status_$status")
            }
            if ([string]$slot.json.dentistId -ne [string]$item.dentistId) {
                $summary.invalid_contract_fields++
                $errors.Add("slot_dentist_mismatch")
            }
            if ([string]$slot.json.slotDate -ne [string]$item.appointmentDate) {
                $summary.invalid_contract_fields++
                $errors.Add("slot_date_mismatch")
            }
            if ([string]$slot.json.startTime -ne [string]$item.startTime) {
                $summary.invalid_contract_fields++
                $errors.Add("slot_start_time_mismatch")
            }
            if ([string]$slot.json.endTime -ne [string]$item.endTime) {
                $summary.invalid_contract_fields++
                $errors.Add("slot_end_time_mismatch")
            }
        }
    }

    if ($errors.Count -eq 0) {
        $summary.valid_items++
    } else {
        $summary.invalid_items++
        Write-Host "INVALID index=$i slotId=$slotId errors=$($errors -join ',')"
    }
}

Write-Host ""
Write-Host "Dataset validation summary"
foreach ($key in $summary.Keys) {
    Write-Host "$key=$($summary[$key])"
}

if ($summary.invalid_items -gt 0) {
    exit 2
}
