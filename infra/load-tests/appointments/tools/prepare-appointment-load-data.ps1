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

if ($Mode -eq "sql") {
    throw "Mode=sql no esta implementado para insertar datos. Usa Mode=api para respetar endpoints y reglas de negocio."
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

    $Value | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
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
        $appointments.Add([ordered]@{
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

    return [ordered]@{
        metadata = [ordered]@{
            name = $Name
            generatedAt = (Get-Date).ToUniversalTime().ToString("o")
            runStamp = $RunStamp
            baseUrl = $BaseUrl
            total = $Total
            amount = [decimal]$Amount
            slotRule = "Each appointment row uses one unique slotId."
        }
        appointments = $appointments
    }
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

$manifest = [ordered]@{
    runStamp = $RunStamp
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    baseUrl = $BaseUrl
    totalPatients = $patients.Count
    totalDentists = $dentists.Count
    totalSlots = $slots.Count
    amount = [decimal]$Amount
    mode = $Mode
}

Export-Json -Value $manifest -Path (Join-Path $OutputDir "load-data-manifest-$RunStamp.json")
Export-Json -Value ([ordered]@{ runStamp = $RunStamp; patientIds = @($patients | ForEach-Object { $_.patientId }); patients = $patients }) -Path (Join-Path $OutputDir "patient-ids.json")
Export-Json -Value ([ordered]@{ runStamp = $RunStamp; dentistIds = @($dentists | ForEach-Object { $_.dentistId }); dentists = $dentists }) -Path (Join-Path $OutputDir "dentist-ids.json")
Export-Json -Value ([ordered]@{ runStamp = $RunStamp; total = $slots.Count; slots = $slots }) -Path (Join-Path $OutputDir "available-slots.json")

$datasetTargets = @(
    @{ Total = 10; File = "appointments.sample.json"; Name = "appointments.sample" },
    @{ Total = 1000; File = "appointments-1000.json"; Name = "appointments-1000" },
    @{ Total = 10000; File = "appointments-10000.json"; Name = "appointments-10000" },
    @{ Total = 50000; File = "appointments-50000.json"; Name = "appointments-50000" }
)

foreach ($target in $datasetTargets) {
    if ($TotalSlots -lt [int]$target.Total) {
        Write-Warning "Skipping $($target.File): requires $($target.Total) slots, only $TotalSlots were created."
        continue
    }

    $dataset = New-Dataset -Patients $patients -Slots $slots -Total ([int]$target.Total) -Name ([string]$target.Name)
    Export-Json -Value $dataset -Path (Join-Path $OutputDir ([string]$target.File))
    Write-Host "Wrote $($target.File)"
}

Write-Host "Preparation complete."
Write-Host "RunStamp=$RunStamp"
Write-Host "OutputDir=$OutputDir"
