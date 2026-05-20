param(
    [string]$BaseUrl = "http://localhost:8080",
    [int]$TotalPatients = 100,
    [int]$TotalDentists = 20,
    [int]$TotalSlots = 50000,
    [decimal]$Amount = 150.00,
    [string]$OutputDir = ".\infra\load-tests\appointments\data",
    [string]$RunStamp,
    [ValidateSet("api", "sql")]
    [string]$Mode = "api",
    [datetime]$StartDate = [datetime]"2026-08-01",
    [int]$SlotMinutes = 30,
    [int]$SlotsPerDentistPerDay = 20,
    [int]$StartHour = 8,
    [int]$ClientIdPool = 250
)

$ErrorActionPreference = "Stop"

if (-not $RunStamp -or $RunStamp.Trim().Length -eq 0) {
    $RunStamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
}

if ($TotalPatients -lt 1) { throw "TotalPatients debe ser mayor que cero." }
if ($TotalDentists -lt 1) { throw "TotalDentists debe ser mayor que cero." }
if ($TotalSlots -lt 1) { throw "TotalSlots debe ser mayor que cero." }

if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

function New-Headers {
    param([int]$Index)

    return @{
        "Accept" = "application/json"
        "Content-Type" = "application/json"
        "X-Client-Id" = "block2-prepare-$RunStamp-$($Index % $ClientIdPool)"
    }
}

function Invoke-MediQueueJson {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body,
        [int]$Index
    )

    $uri = "$BaseUrl$Path"
    $headers = New-Headers -Index $Index
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
    }
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 8)
}

function Get-ResponseId {
    param(
        [object]$Response,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($null -ne $Response.$name) {
            return [string]$Response.$name
        }
    }
    throw "La respuesta no incluyo ningun campo ID esperado: $($Names -join ', ')"
}

function Write-ProgressLine {
    param(
        [string]$Label,
        [int]$Current,
        [int]$Total,
        [int]$Every = 500
    )

    if ($Current -eq 1 -or $Current -eq $Total -or ($Current % $Every) -eq 0) {
        Write-Host "$Label $Current/$Total"
    }
}

function Format-Time {
    param([datetime]$Value)
    return $Value.ToString("HH:mm:ss")
}

function Export-Json {
    param(
        [object]$Value,
        [string]$Path
    )

    $jsonContent = $Value | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $jsonContent, $utf8NoBom)
}

function ConvertTo-ObjectArray {
    param([object]$Value)

    $rows = @($Value)
    if ($rows.Count -eq 1 -and $rows[0] -is [array]) {
        return @($rows[0])
    }
    return $rows
}

function Test-AppointmentDatasetShape {
    param(
        [object]$Appointments,
        [int]$ExpectedTotal,
        [string]$Name
    )

    $rows = ConvertTo-ObjectArray $Appointments

    if ($rows.Count -ne $ExpectedTotal) {
        throw "$Name count=$($rows.Count), expected=$ExpectedTotal."
    }

    $usedSlots = New-Object "System.Collections.Generic.HashSet[string]"
    $missingFields = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $rows.Count; $i++) {
        $item = $rows[$i]
        foreach ($field in @("patientId", "dentistId", "slotId", "appointmentDate", "startTime", "endTime", "amount", "notes")) {
            if ($null -eq $item.$field -or ([string]$item.$field).Trim().Length -eq 0) {
                $missingFields.Add("index=$i field=$field")
            }
        }

        if ($null -ne $item.slotId -and -not $usedSlots.Add([string]$item.slotId)) {
            throw "$Name tiene slotId repetido: $($item.slotId)"
        }

        if ($null -eq $item.amount -or ([decimal]$item.amount) -le 0) {
            $missingFields.Add("index=$i field=amount_invalid")
        }
    }

    if ($missingFields.Count -gt 0) {
        throw "$Name tiene campos faltantes o invalidos: $($missingFields[0..([Math]::Min(9, $missingFields.Count - 1))] -join '; ')"
    }
}

function Write-DatasetSummary {
    param(
        [string]$FileName,
        [object[]]$Appointments
    )

    $first = $Appointments[0]
    Write-Host "$FileName count=$($Appointments.Count)"
    Write-Host "$FileName first item: patientId=$($first.patientId) dentistId=$($first.dentistId) slotId=$($first.slotId) appointmentDate=$($first.appointmentDate) startTime=$($first.startTime) endTime=$($first.endTime) amount=$($first.amount)"
}

function Assert-SafeSqlToken {
    param(
        [string]$Value,
        [string]$Name
    )

    if ($Value -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "$Name contiene caracteres no permitidos para SQL mode: $Value"
    }
}

function Invoke-PostgresSql {
    param([string]$Sql)

    $output = $Sql | docker compose exec -T postgres psql -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q
    if ($LASTEXITCODE -ne 0) {
        throw "psql fallo con exit code $LASTEXITCODE"
    }
    return $output
}

function Invoke-PostgresRows {
    param([string]$Sql)

    $output = $Sql | docker compose exec -T postgres psql -U mediqueue -d mediqueue -v ON_ERROR_STOP=1 -q -t -A -F "`t"
    if ($LASTEXITCODE -ne 0) {
        throw "psql query fallo con exit code $LASTEXITCODE"
    }
    return @($output | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}

function Convert-PatientRows {
    param([string[]]$Rows)

    return @($Rows | ForEach-Object {
        $parts = $_ -split "`t"
        [pscustomobject][ordered]@{
            patientId = $parts[0]
            email = $parts[1]
            documentNumber = $parts[2]
        }
    })
}

function Convert-DentistRows {
    param([string[]]$Rows)

    return @($Rows | ForEach-Object {
        $parts = $_ -split "`t"
        [pscustomobject][ordered]@{
            dentistId = $parts[0]
            email = $parts[1]
            licenseNumber = $parts[2]
        }
    })
}

function Convert-SlotRows {
    param([string[]]$Rows)

    return @($Rows | ForEach-Object {
        $parts = $_ -split "`t"
        [pscustomobject][ordered]@{
            slotId = $parts[0]
            dentistId = $parts[1]
            slotDate = $parts[2]
            startTime = Normalize-TimeText $parts[3]
            endTime = Normalize-TimeText $parts[4]
            status = $parts[5]
            runStamp = $RunStamp
        }
    })
}

function Normalize-TimeText {
    param([string]$Value)

    if ($Value.Length -eq 5) {
        return "$Value`:00"
    }
    return $Value
}

function New-SqlLoadData {
    Assert-SafeSqlToken -Value $RunStamp -Name "RunStamp"

    $startDateText = $StartDate.ToString("yyyy-MM-dd")
    $sql = @"
BEGIN;

INSERT INTO patient.patients (first_name, last_name, email, phone, document_number, status)
SELECT
  'Block2Patient' || gs,
  'Load',
  'block2.patient.$RunStamp.' || lpad(gs::text, 6, '0') || '@mediqueue.test',
  '+5025555' || lpad(gs::text, 6, '0'),
  'B2-PAT-$RunStamp-' || lpad(gs::text, 6, '0'),
  'ACTIVE'::patient.patient_status
FROM generate_series(1, $TotalPatients) AS gs
ON CONFLICT (email) DO NOTHING;

INSERT INTO schedule.dentists (first_name, last_name, license_number, specialty, email, status)
SELECT
  'Block2Dentist' || gs,
  'Load',
  'B2-DEN-$RunStamp-' || lpad(gs::text, 6, '0'),
  'Odontologia General',
  'block2.dentist.$RunStamp.' || lpad(gs::text, 6, '0') || '@mediqueue.test',
  'ACTIVE'::schedule.dentist_status
FROM generate_series(1, $TotalDentists) AS gs
ON CONFLICT (email) DO NOTHING;

WITH dentists_ranked AS (
  SELECT dentist_id, row_number() OVER (ORDER BY email) - 1 AS dentist_index
  FROM schedule.dentists
  WHERE email LIKE 'block2.dentist.$RunStamp.%@mediqueue.test'
),
slots_to_create AS (
  SELECT
    d.dentist_id,
    (gs - 1) AS slot_index,
    (date '$startDateText'
      + (((floor(((gs - 1) / $TotalDentists))::int) / $SlotsPerDentistPerDay))::int) AS slot_date,
    (time '$($StartHour.ToString("00")):00:00'
      + ((((floor(((gs - 1) / $TotalDentists))::int) % $SlotsPerDentistPerDay) * $SlotMinutes) * interval '1 minute'))::time AS start_time
  FROM generate_series(1, $TotalSlots) AS gs
  JOIN dentists_ranked d ON d.dentist_index = ((gs - 1) % $TotalDentists)
)
INSERT INTO schedule.dentist_slots (dentist_id, slot_date, start_time, end_time, display_status)
SELECT
  dentist_id,
  slot_date,
  start_time,
  (start_time + ($SlotMinutes * interval '1 minute'))::time,
  'AVAILABLE'::schedule.slot_display_status
FROM slots_to_create
ON CONFLICT (dentist_id, slot_date, start_time) DO NOTHING;

COMMIT;
"@

    Invoke-PostgresSql -Sql $sql | Out-Null

    $patientsRows = Invoke-PostgresRows -Sql "select patient_id, email, document_number from patient.patients where email like 'block2.patient.$RunStamp.%@mediqueue.test' order by email;"
    $dentistRows = Invoke-PostgresRows -Sql "select dentist_id, email, license_number from schedule.dentists where email like 'block2.dentist.$RunStamp.%@mediqueue.test' order by email;"
    $slotRows = Invoke-PostgresRows -Sql "select s.slot_id, s.dentist_id, s.slot_date, s.start_time, s.end_time, s.display_status from schedule.dentist_slots s join schedule.dentists d on d.dentist_id = s.dentist_id where d.email like 'block2.dentist.$RunStamp.%@mediqueue.test' and s.display_status = 'AVAILABLE' order by s.slot_date, s.start_time, s.dentist_id limit $TotalSlots;"

    $patientsSql = Convert-PatientRows -Rows $patientsRows
    $dentistsSql = Convert-DentistRows -Rows $dentistRows
    $slotsSql = Convert-SlotRows -Rows $slotRows

    if ($patientsSql.Count -lt $TotalPatients) {
        throw "SQL mode genero $($patientsSql.Count) pacientes, se esperaban $TotalPatients."
    }
    if ($dentistsSql.Count -lt $TotalDentists) {
        throw "SQL mode genero $($dentistsSql.Count) dentistas, se esperaban $TotalDentists."
    }
    if ($slotsSql.Count -lt $TotalSlots) {
        throw "SQL mode genero $($slotsSql.Count) slots disponibles, se esperaban $TotalSlots."
    }

    return [ordered]@{
        patients = @($patientsSql | Select-Object -First $TotalPatients)
        dentists = @($dentistsSql | Select-Object -First $TotalDentists)
        slots = @($slotsSql | Select-Object -First $TotalSlots)
    }
}

function New-Dataset {
    param(
        [object[]]$Patients,
        [object[]]$Slots,
        [int]$Total,
        [string]$Name
    )

    if ($Slots.Count -lt $Total) {
        throw "No hay suficientes slots unicos para generar $Total citas. Ejecuta primero el seed."
    }
    if ($Patients.Count -lt 1) {
        throw "No hay pacientes disponibles para generar dataset."
    }

    $usedSlots = New-Object "System.Collections.Generic.HashSet[string]"
    $appointments = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $Total; $i++) {
        $slot = $Slots[$i]
        $slotId = [string]$slot.slotId
        if (-not $usedSlots.Add($slotId)) {
            throw "slotId repetido detectado al generar $Name`: $slotId"
        }

        $patient = $Patients[$i % $Patients.Count]
        $appointments.Add([pscustomobject][ordered]@{
            runStamp = $RunStamp
            patientId = [string]$patient.patientId
            dentistId = [string]$slot.dentistId
            slotId = $slotId
            appointmentDate = [string]$slot.slotDate
            startTime = [string]$slot.startTime
            endTime = [string]$slot.endTime
            amount = [decimal]$Amount
            notes = "Block2 load test $RunStamp appointment $($i + 1)"
        })
    }

    $array = @($appointments.ToArray())
    Test-AppointmentDatasetShape -Appointments $array -ExpectedTotal $Total -Name $Name
    return $array
}

function Export-LoadDataOutputs {
    param(
        [object[]]$Patients,
        [object[]]$Dentists,
        [object[]]$Slots
    )

    $manifest = [ordered]@{
        runStamp = $RunStamp
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
        baseUrl = $BaseUrl
        totalPatients = $Patients.Count
        totalDentists = $Dentists.Count
        totalSlots = $Slots.Count
        amount = [decimal]$Amount
        mode = $Mode
    }

    Export-Json -Value $manifest -Path (Join-Path $OutputDir "load-data-manifest-$RunStamp.json")
    Export-Json -Value $manifest -Path (Join-Path $OutputDir "load-data-manifest.latest.json")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $OutputDir "latest-runstamp.txt"), $RunStamp, $utf8NoBom)
    Export-Json -Value ([ordered]@{ runStamp = $RunStamp; patientIds = @($Patients | ForEach-Object { $_.patientId }); patients = $Patients }) -Path (Join-Path $OutputDir "patient-ids.json")
    Export-Json -Value ([ordered]@{ runStamp = $RunStamp; dentistIds = @($Dentists | ForEach-Object { $_.dentistId }); dentists = $Dentists }) -Path (Join-Path $OutputDir "dentist-ids.json")
    Export-Json -Value ([ordered]@{ runStamp = $RunStamp; total = $Slots.Count; slots = $Slots }) -Path (Join-Path $OutputDir "available-slots.json")

    $datasetTargets = @(
        @{ Total = 10; File = "appointments.sample.json"; Name = "appointments.sample" },
        @{ Total = 1000; File = "appointments-1000.json"; Name = "appointments-1000" },
        @{ Total = 10000; File = "appointments-10000.json"; Name = "appointments-10000" },
        @{ Total = 50000; File = "appointments-50000.json"; Name = "appointments-50000" }
    )
    if ($Slots.Count -gt 50000) {
        $datasetTargets += @{ Total = $Slots.Count; File = "appointments-$($Slots.Count).json"; Name = "appointments-$($Slots.Count)" }
    }

    foreach ($target in $datasetTargets) {
        $targetPath = Join-Path $OutputDir ([string]$target.File)
        if ($Slots.Count -lt [int]$target.Total) {
            if (Test-Path -Path $targetPath) {
                Remove-Item -LiteralPath $targetPath -Force
                Write-Warning "Removed stale dataset $($target.File) so it cannot be reused accidentally."
            }
            throw "No hay suficientes slots unicos para generar $($target.Total) citas. Ejecuta primero el seed. appointments-$($target.Total).json no fue generado."
        }

        $dataset = ConvertTo-ObjectArray (New-Dataset -Patients $Patients -Slots $Slots -Total ([int]$target.Total) -Name ([string]$target.Name))
        Export-Json -Value $dataset -Path $targetPath
        $written = ConvertTo-ObjectArray (Get-Content -Raw -Path $targetPath | ConvertFrom-Json)
        Test-AppointmentDatasetShape -Appointments @($written | Select-Object -First ([Math]::Min(20, $written.Count))) -ExpectedTotal ([Math]::Min(20, $written.Count)) -Name "$($target.File) first 20"
        if ($written.Count -ne [int]$target.Total) {
            Remove-Item -LiteralPath $targetPath -Force
            throw "$($target.File) se escribio con $($written.Count) filas, se esperaban $($target.Total). Archivo eliminado."
        }
        Write-Host "Wrote $($target.File)"
        Write-DatasetSummary -FileName ([string]$target.File) -Appointments $written
    }
}

if ($Mode -eq "sql") {
    Write-Host "Preparing appointment load data via SQL"
    Write-Host "RunStamp=$RunStamp"
    Write-Host "SQL mode inserts only base data: patients, dentists, and available slots. It never inserts appointments."

    $sqlData = New-SqlLoadData
    $patients = ConvertTo-ObjectArray $sqlData.patients
    $dentists = ConvertTo-ObjectArray $sqlData.dentists
    $slots = ConvertTo-ObjectArray $sqlData.slots

    Export-LoadDataOutputs -Patients $patients -Dentists $dentists -Slots $slots

    Write-Host "Preparation complete."
    Write-Host "RunStamp=$RunStamp"
    Write-Host "OutputDir=$OutputDir"
    exit 0
}

Write-Host "Preparing appointment load data via API"
Write-Host "BaseUrl=$BaseUrl"
Write-Host "RunStamp=$RunStamp"

$health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/actuator/health" -Headers (New-Headers -Index 0)
Write-Host "Gateway health: $($health.status)"

$patients = New-Object System.Collections.Generic.List[object]
$dentists = New-Object System.Collections.Generic.List[object]
$slots = New-Object System.Collections.Generic.List[object]

Write-Host "Creating $TotalPatients patients..."
for ($i = 0; $i -lt $TotalPatients; $i++) {
    $n = $i + 1
    $patient = Invoke-MediQueueJson -Method Post -Path "/api/patients" -Index $i -Body @{
        firstName = "Block2Patient$n"
        lastName = "Load"
        email = "block2.patient.$RunStamp.$n@mediqueue.test"
        phone = "+5025555$($n.ToString('000000'))"
        documentNumber = "B2-PAT-$RunStamp-$($n.ToString('000000'))"
    }

    $patients.Add([ordered]@{
        patientId = Get-ResponseId -Response $patient -Names @("patientId", "id")
        email = [string]$patient.email
        documentNumber = [string]$patient.documentNumber
    })
    Write-ProgressLine -Label "Patients" -Current $n -Total $TotalPatients -Every 25
}

Write-Host "Creating $TotalDentists dentists..."
for ($i = 0; $i -lt $TotalDentists; $i++) {
    $n = $i + 1
    $dentist = Invoke-MediQueueJson -Method Post -Path "/api/dentists" -Index $i -Body @{
        firstName = "Block2Dentist$n"
        lastName = "Load"
        specialty = "Odontologia General"
        email = "block2.dentist.$RunStamp.$n@mediqueue.test"
        licenseNumber = "B2-DEN-$RunStamp-$($n.ToString('000000'))"
    }

    $dentists.Add([ordered]@{
        dentistId = Get-ResponseId -Response $dentist -Names @("dentistId", "id")
        email = [string]$dentist.email
        licenseNumber = [string]$dentist.licenseNumber
    })
    Write-ProgressLine -Label "Dentists" -Current $n -Total $TotalDentists -Every 10
}

Write-Host "Creating $TotalSlots unique slots..."
for ($i = 0; $i -lt $TotalSlots; $i++) {
    $dentistIndex = $i % $TotalDentists
    $slotIndexForDentist = [math]::Floor($i / $TotalDentists)
    $dayOffset = [math]::Floor($slotIndexForDentist / $SlotsPerDentistPerDay)
    $slotInDay = $slotIndexForDentist % $SlotsPerDentistPerDay
    $date = $StartDate.AddDays($dayOffset)
    $start = $date.Date.AddHours($StartHour).AddMinutes($slotInDay * $SlotMinutes)
    $end = $start.AddMinutes($SlotMinutes)

    $slot = Invoke-MediQueueJson -Method Post -Path "/api/slots" -Index $i -Body @{
        dentistId = $dentists[$dentistIndex].dentistId
        slotDate = $date.ToString("yyyy-MM-dd")
        startTime = Format-Time $start
        endTime = Format-Time $end
    }

    $slots.Add([ordered]@{
        slotId = Get-ResponseId -Response $slot -Names @("slotId", "id")
        dentistId = [string]$slot.dentistId
        slotDate = [string]$slot.slotDate
        startTime = [string]$slot.startTime
        endTime = [string]$slot.endTime
        status = [string]$slot.status
        runStamp = $RunStamp
    })
    Write-ProgressLine -Label "Slots" -Current ($i + 1) -Total $TotalSlots -Every 1000
}

Export-LoadDataOutputs -Patients (ConvertTo-ObjectArray $patients) -Dentists (ConvertTo-ObjectArray $dentists) -Slots (ConvertTo-ObjectArray $slots)

Write-Host "Preparation complete."
Write-Host "RunStamp=$RunStamp"
Write-Host "OutputDir=$OutputDir"
