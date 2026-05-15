ALTER TABLE notifications
    ADD COLUMN source_event_id UUID,
    ADD COLUMN source_event_type VARCHAR(100),
    ADD COLUMN source_service VARCHAR(80),
    ADD COLUMN event_key VARCHAR(255),
    ADD COLUMN routing_key VARCHAR(120),
    ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX uq_notifications_event_key
    ON notifications(event_key)
    WHERE event_key IS NOT NULL;

CREATE INDEX idx_notifications_appointment ON notifications(appointment_id);
