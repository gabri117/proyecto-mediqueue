-- =============================================================================
-- appointment-service - Esqueleto mínimo
-- BD: mediqueue_appointment (instancia Postgres dedicada)
-- Migración Flyway: V1__appointment_service_init.sql
--
-- Servicio MÁS CRÍTICO. Concentra:
-- - Control de concurrencia (NO duplicar slot horario)
-- - Reservas temporales (appointment_holds con TTL)
-- - Idempotencia (no duplicar operaciones por reintento)
-- - Outbox Pattern (trazabilidad de eventos publicados)
-- - Auditoría inmutable (historial intocable)
-- =============================================================================





-- =============================================================================
-- TABLA: appointments
-- patient_id y dentist_id son FKs lógicas (otros servicios).
-- =============================================================================
CREATE TABLE appointments (
    appointment_id      UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    patient_id          UUID NOT NULL,
    dentist_id          UUID NOT NULL,
    slot_id             UUID NOT NULL,
    appointment_date    DATE NOT NULL,
    start_time          TIME NOT NULL,
    end_time            TIME NOT NULL,
    appointment_status  VARCHAR(30) NOT NULL DEFAULT 'PENDING_PAYMENT',
    notes               TEXT,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_appointments_patient     ON appointments(patient_id);
CREATE INDEX idx_appointments_dentist     ON appointments(dentist_id, appointment_date);
CREATE INDEX idx_appointments_status      ON appointments(appointment_status);

--  REGLA CRÍTICA: "No duplicar slot horario"
-- Un slot solo puede tener UNA cita activa (PENDING_PAYMENT o CONFIRMED).
-- Índice parcial único: el motor rechaza el INSERT si ya hay una activa.
CREATE UNIQUE INDEX uq_appointment_slot_active
    ON appointments(slot_id)
    WHERE appointment_status IN ('PENDING_PAYMENT', 'CONFIRMED');

-- =============================================================================
-- TABLA: appointment_holds
-- Reserva temporal con TTL. Protege contra reservas zombi por pago colgado.
-- =============================================================================
CREATE TABLE appointment_holds (
    hold_id         UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    appointment_id  UUID NOT NULL,
    slot_id         UUID NOT NULL,
    hold_status     VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    expires_at      TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    released_at     TIMESTAMP,
    CONSTRAINT fk_holds_appointment
        FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE
);

-- Solo un hold ACTIVE por slot
CREATE UNIQUE INDEX uq_holds_one_active_per_slot
    ON appointment_holds(slot_id) WHERE hold_status = 'ACTIVE';

-- Para el scheduler que expira holds vencidos
CREATE INDEX idx_holds_expiration
    ON appointment_holds(expires_at) WHERE hold_status = 'ACTIVE';

-- =============================================================================
-- TABLA: appointment_audit (INMUTABLE)
-- Cumple "historial intocable". Solo INSERT, jamás UPDATE ni DELETE.
-- =============================================================================
CREATE TABLE appointment_audit (
    audit_id          UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    appointment_id    UUID NOT NULL,
    previous_status   VARCHAR(30),
    new_status        VARCHAR(30) NOT NULL,
    change_reason     VARCHAR(200),
    changed_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_audit_appointment
        FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id)
);

CREATE INDEX idx_audit_appointment ON appointment_audit(appointment_id);

-- Refuerzo a nivel de BD: bloquear UPDATE y DELETE en la tabla de auditoría.
CREATE OR REPLACE FUNCTION trg_audit_immutable()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'appointment_audit es inmutable: % no permitido', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON appointment_audit
    FOR EACH ROW EXECUTE FUNCTION trg_audit_immutable();
CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON appointment_audit
    FOR EACH ROW EXECUTE FUNCTION trg_audit_immutable();

-- =============================================================================
-- TABLA: idempotency_keys
-- Cliente envía X-Idempotency-Key. Si ya está SUCCEEDED, devolver respuesta cacheada.
-- =============================================================================
CREATE TABLE idempotency_keys (
    idempotency_id      UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    operation_type      VARCHAR(50)  NOT NULL,
    idempotency_key     VARCHAR(120) NOT NULL,
    request_hash        VARCHAR(128) NOT NULL,
    response_reference  VARCHAR(120),
    status              VARCHAR(30) NOT NULL DEFAULT 'PROCESSING',
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMP NOT NULL,
    CONSTRAINT uq_idempotency_op_key UNIQUE (operation_type, idempotency_key)
);

CREATE INDEX idx_idempotency_expires ON idempotency_keys(expires_at);

-- =============================================================================
-- TABLA: outbox_events
-- Eventos escritos en la MISMA transacción que el cambio de negocio.
-- Publisher background los envía a RabbitMQ y los marca PUBLISHED.
-- =============================================================================
CREATE TABLE outbox_events (
    event_id            UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    aggregate_type      VARCHAR(50)  NOT NULL,
    aggregate_id        UUID         NOT NULL,
    event_type          VARCHAR(80)  NOT NULL,
    payload             TEXT         NOT NULL,
    publication_status  VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    created_at          TIMESTAMP    NOT NULL DEFAULT NOW(),
    published_at        TIMESTAMP
);

CREATE INDEX idx_outbox_pending
    ON outbox_events(created_at) WHERE publication_status = 'PENDING';

-- =============================================================================
-- Trigger updated_at
-- =============================================================================
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_appointments_updated_at
    BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
