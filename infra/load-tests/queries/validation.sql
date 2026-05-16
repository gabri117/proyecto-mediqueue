-- MediQueue load-test validation queries.
-- Ejecuta cada bloque en la base indicada en el comentario.

-- 1. Citas por estado.
-- Base: mediqueue_appointments
SELECT appointment_status, COUNT(*) AS total
FROM appointments
GROUP BY appointment_status
ORDER BY total DESC;

-- 2. Verificar doble reserva activa por slot.
-- Base: mediqueue_appointments
-- Resultado esperado: 0 filas.
SELECT slot_id, COUNT(*) AS active_appointments
FROM appointments
WHERE appointment_status IN ('PENDING_PAYMENT', 'CONFIRMED')
GROUP BY slot_id
HAVING COUNT(*) > 1;

-- 3. Pagos por estado.
-- Base: mediqueue_payments
SELECT payment_status, COUNT(*) AS total
FROM payments
GROUP BY payment_status
ORDER BY total DESC;

-- 4. Verificar doble pago aprobado por cita.
-- Base: mediqueue_payments
-- Resultado esperado: 0 filas.
SELECT appointment_id, COUNT(*) AS approved_payments
FROM payments
WHERE payment_status = 'APPROVED'
GROUP BY appointment_id
HAVING COUNT(*) > 1;

-- 5. Notificaciones por tipo/routing/status.
-- Base: mediqueue_notifications
SELECT event_type, notification_status, channel, COUNT(*) AS total
FROM notifications
GROUP BY event_type, notification_status, channel
ORDER BY total DESC;

-- 6. Outbox appointment pendiente.
-- Base: mediqueue_appointments
SELECT event_type, publication_status, COUNT(*) AS total
FROM outbox_events
WHERE publication_status = 'PENDING'
GROUP BY event_type, publication_status
ORDER BY total DESC;

-- 7. Outbox payment pendiente.
-- Base: mediqueue_payments
SELECT event_type, publication_status, COUNT(*) AS total
FROM payment_events_outbox
WHERE publication_status = 'PENDING'
GROUP BY event_type, publication_status
ORDER BY total DESC;
