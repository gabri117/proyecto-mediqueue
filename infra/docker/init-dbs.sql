-- =============================================================================
-- MediQueue Platform — Database initialization
-- Executed automatically by postgres on first start via docker-entrypoint-initdb.d
-- =============================================================================

CREATE DATABASE mediqueue_appointments;
CREATE DATABASE mediqueue_notifications;
CREATE DATABASE mediqueue_payments;
CREATE DATABASE mediqueue_patients;
CREATE DATABASE mediqueue_schedules;

-- Grant privileges to the default user (POSTGRES_USER from docker-compose)
GRANT ALL PRIVILEGES ON DATABASE mediqueue_appointments TO mediqueue;
GRANT ALL PRIVILEGES ON DATABASE mediqueue_notifications TO mediqueue;
GRANT ALL PRIVILEGES ON DATABASE mediqueue_payments TO mediqueue;
GRANT ALL PRIVILEGES ON DATABASE mediqueue_patients TO mediqueue;
GRANT ALL PRIVILEGES ON DATABASE mediqueue_schedules TO mediqueue;
