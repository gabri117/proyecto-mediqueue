CREATE INDEX IF NOT EXISTS idx_payments_requested_at_desc
ON payments (requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_payments_status_requested_at_desc
ON payments (payment_status, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_payments_appointment_requested_at_desc
ON payments (appointment_id, requested_at DESC);
