param(
    [string]$DataFile = ".\infra\load-tests\appointments\data\appointments-50000.json",
    [int]$SampleSize = 20,
    [int]$ExpectedCount = 0
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $DataFile)) {
    throw "DataFile no encontrado: $DataFile"
}
if ($SampleSize -lt 1) {
    throw "SampleSize debe ser mayor que cero."
}

function Read-JsonNoBom {
    param([string]$Path)

    $raw = Get-Content -Raw -Path $Path
    $raw = $raw.TrimStart([char]0xFEFF)
    return $raw | ConvertFrom-Json
}

function Test-RequiredText {
    param([object]$Value)
    return $null -ne $Value -and ([string]$Value).Trim().Length -gt 0
}

function ConvertTo-ObjectArray {
    param([object]$Value)

    $rows = @($Value)
    if ($rows.Count -eq 1 -and $rows[0] -is [array]) {
        return @($rows[0])
    }
    return $rows
}

function Get-RootType {
    param([object]$Json)

    if ($Json -is [array]) {
        return "array"
    }
    if ($null -ne $Json.appointments) {
        return "object_with_appointments"
    }
    if ($Json -is [pscustomobject]) {
        return "object"
    }
    if ($null -eq $Json) {
        return "null"
    }
    return $Json.GetType().FullName
}

$json = Read-JsonNoBom -Path $DataFile
$rootType = Get-RootType -Json $json
$isPureArray = $json -is [array]
$items = if ($isPureArray) { ConvertTo-ObjectArray $json } elseif ($null -ne $json.appointments) { ConvertTo-ObjectArray $json.appointments } else { @() }

$missingFields = New-Object System.Collections.Generic.List[string]
$slotCounts = @{}
$duplicateSlots = 0
$sampleCount = [Math]::Min($SampleSize, $items.Count)

for ($i = 0; $i -lt $sampleCount; $i++) {
    $item = $items[$i]
    foreach ($field in @("patientId", "dentistId", "slotId", "appointmentDate", "startTime", "endTime", "amount", "notes")) {
        if (-not (Test-RequiredText $item.$field)) {
            $missingFields.Add("index=$i field=$field")
        }
    }
}

foreach ($item in $items) {
    $slotId = [string]$item.slotId
    if (-not (Test-RequiredText $slotId)) {
        continue
    }

    if ($slotCounts.ContainsKey($slotId)) {
        $slotCounts[$slotId]++
    } else {
        $slotCounts[$slotId] = 1
    }
}

foreach ($entry in $slotCounts.GetEnumerator()) {
    if ([int]$entry.Value -gt 1) {
        $duplicateSlots++
    }
}

$isValidForK6 = $isPureArray -and $items.Count -gt 0 -and $missingFields.Count -eq 0 -and $duplicateSlots -eq 0
if ($ExpectedCount -gt 0 -and $items.Count -ne $ExpectedCount) {
    $isValidForK6 = $false
}

Write-Host "Dataset inspection"
Write-Host "data_file=$((Resolve-Path $DataFile).Path)"
Write-Host "root_type=$rootType"
Write-Host "is_pure_array=$isPureArray"
Write-Host "total_items=$($items.Count)"
if ($ExpectedCount -gt 0) {
    Write-Host "expected_items=$ExpectedCount"
}
Write-Host "sample_size=$sampleCount"
Write-Host "missing_fields=$($missingFields.Count)"
Write-Host "duplicate_slot_ids=$duplicateSlots"
Write-Host "valid_for_k6=$isValidForK6"

if ($items.Count -gt 0) {
    Write-Host ""
    Write-Host "First item"
    $items[0] | ConvertTo-Json -Depth 8
}

if ($missingFields.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing fields sample"
    $missingFields | Select-Object -First 20
}

if ($ExpectedCount -gt 0 -and $items.Count -ne $ExpectedCount) {
    Write-Host "count_mismatch=True"
}

if (-not $isValidForK6) {
    exit 2
}
