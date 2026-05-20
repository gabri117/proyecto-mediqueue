SELECT pg_advisory_xact_lock(hashtext('mediqueue:notification:V2__notification_event_deduplication'));

ALTER TABLE notifications
    ADD COLUMN IF NOT EXISTS source_event_id UUID,
    ADD COLUMN IF NOT EXISTS source_event_type VARCHAR(100),
    ADD COLUMN IF NOT EXISTS source_service VARCHAR(80),
    ADD COLUMN IF NOT EXISTS event_key VARCHAR(255),
    ADD COLUMN IF NOT EXISTS routing_key VARCHAR(120),
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_event_key
    ON notifications(event_key)
    WHERE event_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_appointment ON notifications(appointment_id);
