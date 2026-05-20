param(
    [Parameter(Mandatory = $true)]
    [string]$RunStamp,
    [string]$OutputFile,
    [switch]$IncludeDockerExecExamples
)

$ErrorActionPreference = "Stop"

if (-not $OutputFile -or $OutputFile.Trim().Length -eq 0) {
    $OutputFile = ".\infra\load-tests\appointments\data\cleanup-$RunStamp.sql"
}

$sql = @"
-- Cleanup SQL for MediQueue Block 2 appointment load data.
-- Review before executing. RunStamp: $RunStamp
-- This SQL targets the root docker-compose.yml unified database layout with schemas:
-- appointment, payment, notification, schedule, patient.
BEGIN;

-- Appointment-side generated data. The appointment datasets include RunStamp in notes.
CREATE TEMP TABLE block2_target_appointments AS
SELECT appointment_id
FROM appointment.appointments
WHERE notes LIKE '%$RunStamp%';

DELETE FROM notification.notifications
WHERE appointment_id IN (SELECT appointment_id FROM block2_target_appointments);

DELETE FROM payment.payment_events_outbox
WHERE payment_id IN (
  SELECT payment_id
  FROM payment.payments
  WHERE appointment_id IN (SELECT appointment_id FROM block2_target_appointments)
);

DELETE FROM payment.payments
WHERE appointment_id IN (SELECT appointment_id FROM block2_target_appointments);

DELETE FROM appointment.outbox_events
WHERE aggregate_id IN (SELECT appointment_id FROM block2_target_appointments)
   OR payload LIKE '%$RunStamp%';

DELETE FROM appointment.idempotency_keys
WHERE idempotency_key LIKE '%$RunStamp%';

DELETE FROM appointment.appointment_holds
WHERE appointment_id IN (SELECT appointment_id FROM block2_target_appointments);

-- appointment_audit is intentionally immutable by trigger. Do not delete it.
DELETE FROM appointment.appointments
WHERE appointment_id IN (SELECT appointment_id FROM block2_target_appointments);

DROP TABLE block2_target_appointments;

-- Seed data created by prepare-appointment-load-data.ps1.
-- Slots do not have a notes field, so they are identified through dentists created with RunStamp.
DELETE FROM schedule.dentist_slots
WHERE dentist_id IN (
  SELECT dentist_id FROM schedule.dentists
  WHERE email LIKE '%$RunStamp%' OR license_number LIKE '%$RunStamp%'
);

DELETE FROM schedule.dentists
WHERE email LIKE '%$RunStamp%' OR license_number LIKE '%$RunStamp%';

DELETE FROM patient.patients
WHERE email LIKE '%$RunStamp%' OR document_number LIKE '%$RunStamp%';

COMMIT;
"@

$parent = Split-Path -Parent $OutputFile
if ($parent -and -not (Test-Path -Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

$sql | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "Cleanup SQL written to $OutputFile"

if ($IncludeDockerExecExamples) {
    Write-Host ""
    Write-Host "Example for root docker-compose.yml unified database:"
    Write-Host "docker compose exec -T postgres psql -U mediqueue -d mediqueue < $OutputFile"
    Write-Host ""
    Write-Host "If using infra/docker-compose.yml separated databases, adapt schema-qualified statements to each database manually."
}
