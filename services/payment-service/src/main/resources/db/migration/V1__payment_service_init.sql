CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE payment_status AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED',
    'TIMEOUT'
);

CREATE TYPE idempotency_status AS ENUM (
    'PROCESSING',
    'SUCCEEDED',
    'FAILED'
);

CREATE TYPE outbox_publication_status AS ENUM (
    'PENDING',
    'PUBLISHED',
    'FAILED'
);

CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    appointment_id UUID NOT NULL,
    patient_id UUID NOT NULL,
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    currency VARCHAR(10) NOT NULL DEFAULT 'GTQ',
    payment_status payment_status NOT NULL DEFAULT 'PENDING',
    requested_at TIMESTAMP NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMP
);

CREATE INDEX idx_payments_appointment ON payments(appointment_id);
CREATE INDEX idx_payments_status ON payments(payment_status);
CREATE UNIQUE INDEX uq_payments_appointment_approved
    ON payments(appointment_id)
    WHERE payment_status = 'APPROVED';

CREATE TABLE payment_idempotency (
    payment_idempotency_id UUID PRIMARY KEY,
    idempotency_key VARCHAR(120) UNIQUE NOT NULL,
    request_hash VARCHAR(128) NOT NULL,
    payment_id UUID,
    status idempotency_status NOT NULL DEFAULT 'PROCESSING',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL
);

CREATE TABLE payment_events_outbox (
    event_id UUID PRIMARY KEY,
    payment_id UUID NOT NULL,
    event_type VARCHAR(80) NOT NULL,
    payload TEXT NOT NULL,
    publication_status outbox_publication_status NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    published_at TIMESTAMP
);
