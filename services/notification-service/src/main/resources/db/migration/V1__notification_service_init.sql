-- =============================================================================
-- notification-service - Esqueleto mínimo
-- BD: mediqueue_notification (instancia Postgres dedicada)
-- Migración Flyway: V1__notification_service_init.sql
--
-- Servicio liviano. Consume eventos de RabbitMQ y registra notificaciones
-- simuladas. Sin tabla de attempts ni dead-letters (manejo simple: si falla,
-- queda con notification_status='FAILED' y se loguea).
-- =============================================================================


-- =============================================================================
-- ENUMS
-- =============================================================================
SELECT pg_advisory_xact_lock(hashtext('mediqueue:notification:V1__notification_service_init'));

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

DO $$
BEGIN
    CREATE TYPE notification_status AS ENUM ('PENDING', 'SENT', 'FAILED');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
    CREATE TYPE notification_channel AS ENUM ('EMAIL', 'SMS');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

-- =============================================================================
-- TABLA: notifications
-- =============================================================================
CREATE TABLE IF NOT EXISTS notifications (
    notification_id      UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    patient_id           UUID NOT NULL,
    appointment_id       UUID,
    event_type           VARCHAR(80) NOT NULL,   -- APPOINTMENT_CONFIRMED, APPOINTMENT_CANCELLED, etc.
    channel              notification_channel NOT NULL DEFAULT 'EMAIL',
    destination          VARCHAR(200) NOT NULL,
    notification_status  notification_status NOT NULL DEFAULT 'PENDING',
    error_message        VARCHAR(255),
    created_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    sent_at              TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notifications_patient ON notifications(patient_id);
CREATE INDEX IF NOT EXISTS idx_notifications_status  ON notifications(notification_status);
CREATE INDEX IF NOT EXISTS idx_notifications_event   ON notifications(event_type);
