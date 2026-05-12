-- =============================================================================
-- patient-service - Esqueleto mínimo
-- BD: mediqueue_patient (instancia Postgres dedicada)
-- Migración Flyway: V1__patient_service_init.sql
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- ENUMS
-- =============================================================================
CREATE TYPE patient_status AS ENUM ('ACTIVE', 'INACTIVE');

-- =============================================================================
-- TABLA: patients
-- Una sola tabla con lo indispensable para identificar a un paciente.
-- =============================================================================
CREATE TABLE patients (
    patient_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    first_name        VARCHAR(100)  NOT NULL,
    last_name         VARCHAR(100)  NOT NULL,
    email             VARCHAR(150)  NOT NULL,
    phone             VARCHAR(30),
    document_number   VARCHAR(50)   NOT NULL,
    status            patient_status NOT NULL DEFAULT 'ACTIVE',
    created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_patients_email           UNIQUE (email),
    CONSTRAINT uq_patients_document_number UNIQUE (document_number)
);

CREATE INDEX idx_patients_status ON patients(status);

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

CREATE TRIGGER trg_patients_updated_at
    BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();
