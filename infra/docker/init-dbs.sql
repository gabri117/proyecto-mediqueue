-- =============================================================================
-- MediQueue Platform - database initialization
-- Executed automatically by postgres on first start via docker-entrypoint-initdb.d
-- Target database is provided by POSTGRES_DB=mediqueue.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;

CREATE SCHEMA IF NOT EXISTS patient AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS schedule AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS appointment AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS payment AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS notification AUTHORIZATION mediqueue;

GRANT CONNECT, TEMPORARY ON DATABASE mediqueue TO mediqueue;

GRANT USAGE, CREATE ON SCHEMA patient TO mediqueue;
GRANT USAGE, CREATE ON SCHEMA schedule TO mediqueue;
GRANT USAGE, CREATE ON SCHEMA appointment TO mediqueue;
GRANT USAGE, CREATE ON SCHEMA payment TO mediqueue;
GRANT USAGE, CREATE ON SCHEMA notification TO mediqueue;

ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA patient
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA schedule
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA appointment
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA payment
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA notification
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mediqueue;

ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA patient
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA schedule
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA appointment
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA payment
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO mediqueue;
ALTER DEFAULT PRIVILEGES FOR ROLE mediqueue IN SCHEMA notification
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO mediqueue;

-- Service migrations call uuid_generate_v4() without a schema qualifier.
-- Keep the extension in public and expose a same-name wrapper inside each
-- service schema so unqualified DDL resolves locally.
CREATE OR REPLACE FUNCTION patient.uuid_generate_v4()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$ SELECT public.uuid_generate_v4(); $$;

CREATE OR REPLACE FUNCTION schedule.uuid_generate_v4()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$ SELECT public.uuid_generate_v4(); $$;

CREATE OR REPLACE FUNCTION appointment.uuid_generate_v4()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$ SELECT public.uuid_generate_v4(); $$;

CREATE OR REPLACE FUNCTION notification.uuid_generate_v4()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$ SELECT public.uuid_generate_v4(); $$;
