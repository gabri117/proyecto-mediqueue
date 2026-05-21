param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$DataFile = ".\infra\load-tests\appointments\data\appointments-50000.json",
    [int]$StartIndex = 0,
    [int]$Limit = 20,
    [int]$ExpectedCount = 0,
    [string]$ClientId = "block2-dataset-validator",
    [ValidateSet("http", "single", "patroni")]
    [string]$DatabaseTarget = "http"
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

    if ($Json -is [array]) { return ConvertTo-ObjectArray $Json }
    if ($null -ne $Json.appointments) {
        throw "El dataset no es un array puro. Se detecto un wrapper con propiedad appointments. Regenera el archivo con generate-appointment-dataset.ps1 o prepare-appointment-load-data.ps1 actualizado."
    }
    throw "El dataset debe ser un array puro de payloads de citas."
}

function ConvertTo-ObjectArray {
    param([object]$Value)

    $rows = @($Value)
    if ($rows.Count -eq 1 -and $rows[0] -is [array]) {
        return @($rows[0])
    }
    return $rows
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

function Test-SafeUuid {
    param([object]$Value)

    if (-not (Test-RequiredText $Value)) { return $false }
    return ([string]$Value) -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

function Normalize-TimeText {
    param([string]$Value)

    if ($Value.Length -eq 5) {
        return "$Value`:00"
    }
    return $Value
}

function Invoke-DatabaseRows {
    param([string]$Sql)

    if ($DatabaseTarget -eq "patroni") {
        $output = $Sql | docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T -e PGPASSWORD=mediqueue patroni-postgres-1 psql -h patroni-postgres-lb -p 5432 -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q -t -A -F "`t"
    } elseif ($DatabaseTarget -eq "single") {
        $output = $Sql | docker compose exec -T postgres psql -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q -t -A -F "`t"
    } else {
        throw "Invoke-DatabaseRows solo se usa con DatabaseTarget single o patroni."
    }

    if ($LASTEXITCODE -ne 0) {
        throw "psql query fallo con exit code $LASTEXITCODE"
    }
    return @($output | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}

function Invoke-DatabaseScalar {
    param([string]$Sql)

    $rows = @(Invoke-DatabaseRows -Sql $Sql)
    if ($rows.Count -lt 1) { return "" }
    return $rows[0].Trim()
}

function Assert-DatabaseValidationReady {
    if ($DatabaseTarget -eq "http") {
        return
    }

    if ($DatabaseTarget -eq "patroni") {
        $recovery = Invoke-DatabaseScalar -Sql "select pg_is_in_recovery();"
        $value = $recovery.Trim().ToLowerInvariant()
        if ($value -ne "f" -and $value -ne "false") {
            throw "Patroni writer no esta listo para validar dataset. pg_is_in_recovery()=$recovery"
        }
        Write-Host "PATRONI_WRITER_PG_IS_IN_RECOVERY=false"
    }

    $missing = @(Invoke-DatabaseRows -Sql "select table_name from (values ('patient.patients'),('schedule.dentists'),('schedule.dentist_slots')) as required(table_name) where to_regclass(required.table_name) is null order by table_name;")
    if ($missing.Count -gt 0) {
        throw "Faltan tablas para validar dataset: $($missing -join ', ')."
    }
}

$json = Read-JsonNoBom -Path $DataFile
$appointments = Get-Appointments -Json $json
Assert-DatabaseValidationReady

if ($appointments.Count -lt 1) {
    throw "El dataset no contiene items. Regenera $DataFile."
}

if ($ExpectedCount -gt 0 -and $appointments.Count -ne $ExpectedCount) {
    throw "Dataset count invalido. Esperado=$ExpectedCount actual=$($appointments.Count)."
}

if ($StartIndex -ge $appointments.Count) {
    throw "StartIndex $StartIndex esta fuera del dataset. Total=$($appointments.Count)."
}

$endExclusive = [Math]::Min($StartIndex + $Limit, $appointments.Count)
$seenSlots = New-Object "System.Collections.Generic.HashSet[string]"

$summary = [ordered]@{
    data_file = (Resolve-Path $DataFile).Path
    base_url = $BaseUrl
    database_target = $DatabaseTarget
    start_index = $StartIndex
    limit = $Limit
    expected_count = $ExpectedCount
    total_items = $appointments.Count
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
    if (-not (Test-RequiredText $item.patientId)) {
        $errors.Add("empty_patientId")
    }
    if (-not (Test-RequiredText $item.dentistId)) {
        $errors.Add("empty_dentistId")
    }
    if (-not (Test-RequiredText $item.slotId)) {
        $errors.Add("empty_slotId")
    }

    if ((Test-RequiredText $slotId) -and -not $seenSlots.Add($slotId)) {
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

    if ($DatabaseTarget -eq "http") {
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
    } else {
        if ((Test-RequiredText $item.patientId) -and -not (Test-SafeUuid $item.patientId)) {
            $summary.invalid_contract_fields++
            $errors.Add("invalid_patient_uuid")
        } elseif (Test-RequiredText $item.patientId) {
            $patientCount = Invoke-DatabaseScalar -Sql "select count(*) from patient.patients where patient_id = '$($item.patientId)'::uuid;"
            if ([int]$patientCount -lt 1) {
                $summary.missing_patients++
                $errors.Add("patient_not_found_sql")
            }
        }

        if ((Test-RequiredText $item.dentistId) -and -not (Test-SafeUuid $item.dentistId)) {
            $summary.invalid_contract_fields++
            $errors.Add("invalid_dentist_uuid")
        } elseif (Test-RequiredText $item.dentistId) {
            $dentistCount = Invoke-DatabaseScalar -Sql "select count(*) from schedule.dentists where dentist_id = '$($item.dentistId)'::uuid;"
            if ([int]$dentistCount -lt 1) {
                $summary.missing_dentists++
                $errors.Add("dentist_not_found_sql")
            }
        }

        if ((Test-RequiredText $item.slotId) -and -not (Test-SafeUuid $item.slotId)) {
            $summary.invalid_contract_fields++
            $errors.Add("invalid_slot_uuid")
        } elseif (Test-RequiredText $item.slotId) {
            $slotRows = @(Invoke-DatabaseRows -Sql "select dentist_id::text, slot_date::text, start_time::text, end_time::text, display_status::text from schedule.dentist_slots where slot_id = '$($item.slotId)'::uuid;")
            if ($slotRows.Count -lt 1) {
                $summary.missing_slots++
                $errors.Add("slot_not_found_sql")
            } else {
                $slotParts = $slotRows[0] -split "`t"
                $status = [string]$slotParts[4]
                if ($status -ne "AVAILABLE") {
                    $summary.unavailable_slots++
                    $errors.Add("slot_status_$status")
                }
                if ([string]$slotParts[0] -ne [string]$item.dentistId) {
                    $summary.invalid_contract_fields++
                    $errors.Add("slot_dentist_mismatch")
                }
                if ([string]$slotParts[1] -ne [string]$item.appointmentDate) {
                    $summary.invalid_contract_fields++
                    $errors.Add("slot_date_mismatch")
                }
                if ((Normalize-TimeText ([string]$slotParts[2])) -ne [string]$item.startTime) {
                    $summary.invalid_contract_fields++
                    $errors.Add("slot_start_time_mismatch")
                }
                if ((Normalize-TimeText ([string]$slotParts[3])) -ne [string]$item.endTime) {
                    $summary.invalid_contract_fields++
                    $errors.Add("slot_end_time_mismatch")
                }
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
