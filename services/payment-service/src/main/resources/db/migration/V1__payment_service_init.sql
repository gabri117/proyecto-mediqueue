CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

SELECT pg_advisory_xact_lock(hashtext('mediqueue:payment:V1__payment_service_init'));

DO $$
BEGIN
    CREATE TYPE payment_status AS ENUM (
        'PENDING',
        'APPROVED',
        'REJECTED',
        'TIMEOUT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
    CREATE TYPE idempotency_status AS ENUM (
        'PROCESSING',
        'SUCCEEDED',
        'FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
    CREATE TYPE outbox_publication_status AS ENUM (
        'PENDING',
        'PUBLISHED',
        'FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

CREATE TABLE IF NOT EXISTS payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_id UUID NOT NULL,
    patient_id UUID NOT NULL,
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(10) NOT NULL DEFAULT 'GTQ',
    payment_status payment_status NOT NULL DEFAULT 'PENDING',
    requested_at TIMESTAMP NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_payments_appointment ON payments(appointment_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(payment_status);
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_appointment_approved
    ON payments(appointment_id)
    WHERE payment_status = 'APPROVED';

CREATE TABLE IF NOT EXISTS payment_idempotency (
    payment_idempotency_id UUID PRIMARY KEY,
    idempotency_key VARCHAR(120) UNIQUE NOT NULL,
    request_hash VARCHAR(128) NOT NULL,
    payment_id UUID,
    status idempotency_status NOT NULL DEFAULT 'PROCESSING',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS payment_events_outbox (
    event_id UUID PRIMARY KEY,
    payment_id UUID NOT NULL,
    event_type VARCHAR(80) NOT NULL,
    payload TEXT NOT NULL,
    publication_status outbox_publication_status NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    published_at TIMESTAMP
);
