-- =============================================================================
-- schedule-service - Esqueleto mínimo (clínica odontológica)
-- BD: mediqueue_schedule (instancia Postgres dedicada)
-- Migración Flyway: V1__schedule_service_init.sql
-- =============================================================================


-- =============================================================================
-- ENUMS
-- =============================================================================
SELECT pg_advisory_xact_lock(hashtext('mediqueue:schedule:V1__schedule_service_init'));

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

DO $$
BEGIN
    CREATE TYPE dentist_status AS ENUM ('ACTIVE', 'INACTIVE');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
    CREATE TYPE slot_display_status AS ENUM ('AVAILABLE', 'HELD', 'BOOKED', 'BLOCKED');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

-- =============================================================================
-- TABLA: dentists
-- Catálogo de odontólogos. Sin specialty separada (todos son odontólogos
-- y la sub-especialidad va como campo simple).
-- =============================================================================
CREATE TABLE IF NOT EXISTS dentists (
    dentist_id      UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    license_number  VARCHAR(50)  NOT NULL,
    specialty       VARCHAR(80)  NOT NULL DEFAULT 'GENERAL',  -- GENERAL, ORTODONCIA, ENDODONCIA, etc.
    email           VARCHAR(150) NOT NULL,
    status          dentist_status NOT NULL DEFAULT 'ACTIVE',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_dentists_license UNIQUE (license_number),
    CONSTRAINT uq_dentists_email   UNIQUE (email)
);

CREATE INDEX IF NOT EXISTS idx_dentists_status    ON dentists(status);
CREATE INDEX IF NOT EXISTS idx_dentists_specialty ON dentists(specialty);

-- =============================================================================
-- TABLA: dentist_working_hours
-- Horario semanal del odontólogo. day_of_week: 0=Domingo .. 6=Sábado
-- =============================================================================
CREATE TABLE IF NOT EXISTS dentist_working_hours (
    working_hour_id        UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    dentist_id             UUID NOT NULL,
    day_of_week            INT  NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time             TIME NOT NULL,
    end_time               TIME NOT NULL,
    slot_duration_minutes  INT  NOT NULL DEFAULT 30 CHECK (slot_duration_minutes > 0),
    is_active              BOOLEAN NOT NULL DEFAULT true,
    created_at             TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_working_hours_range CHECK (end_time > start_time),
    CONSTRAINT fk_working_hours_dentist
        FOREIGN KEY (dentist_id) REFERENCES dentists(dentist_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_working_hours_dentist ON dentist_working_hours(dentist_id, day_of_week);

-- =============================================================================
-- TABLA: dentist_slots
-- Slots concretos con fecha y hora. Generados a partir de working_hours.
-- display_status es informativo (cacheable). La verdad transaccional la lleva
-- appointment-service vía sus holds e índices parciales.
-- =============================================================================
CREATE TABLE IF NOT EXISTS dentist_slots (
    slot_id         UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    dentist_id      UUID NOT NULL,
    slot_date       DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    display_status  slot_display_status NOT NULL DEFAULT 'AVAILABLE',
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_slot_time CHECK (end_time > start_time),
    CONSTRAINT uq_dentist_slot_unique
        UNIQUE (dentist_id, slot_date, start_time),
    CONSTRAINT fk_slots_dentist
        FOREIGN KEY (dentist_id) REFERENCES dentists(dentist_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_slots_dentist_date ON dentist_slots(dentist_id, slot_date);
CREATE INDEX IF NOT EXISTS idx_slots_date_status  ON dentist_slots(slot_date, display_status);

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

DO $$
BEGIN
    CREATE TRIGGER trg_dentists_updated_at
        BEFORE UPDATE ON dentists
        FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
    CREATE TRIGGER trg_slots_updated_at
        BEFORE UPDATE ON dentist_slots
        FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;
