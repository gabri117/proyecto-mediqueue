param(
    [switch]$PurgeRabbitMqQueues
)

$ErrorActionPreference = "Stop"

$sql = @"
BEGIN;

TRUNCATE TABLE
  appointment.appointment_audit,
  appointment.appointment_holds,
  appointment.idempotency_keys,
  appointment.outbox_events,
  appointment.appointments
RESTART IDENTITY;

TRUNCATE TABLE
  payment.payment_events_outbox,
  payment.payment_idempotency,
  payment.payments
RESTART IDENTITY;

TRUNCATE TABLE
  notification.notifications
RESTART IDENTITY;

COMMIT;
"@

Write-Host "Cleaning runtime data only. Base patients, dentists, and slots are preserved."
$sql | docker compose exec -T postgres psql -U mediqueue -d mediqueue -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) {
    throw "Runtime cleanup SQL fallo con exit code $LASTEXITCODE"
}

if ($PurgeRabbitMqQueues) {
    Write-Host "Purging RabbitMQ queues. This removes pending async test messages."
    $queues = @(
        "payment.appointment-held.queue",
        "payment.succeeded",
        "payment.failed",
        "payment.succeeded.queue",
        "payment.failed.queue",
        "appointment.confirmed",
        "appointment.expired",
        "appointment.cancelled",
        "appointment.confirmed.queue",
        "appointment.expired.queue",
        "appointment.cancelled.queue",
        "notification.appointment.queue",
        "notification.payment.queue",
        "schedule.appointment.held",
        "schedule.appointment.confirmed",
        "schedule.appointment.expired",
        "schedule.appointment.cancelled"
    )

    foreach ($queue in $queues) {
        docker compose exec -T rabbitmq rabbitmqctl purge_queue $queue | Out-Null
    }
}

Write-Host "Runtime cleanup complete."
