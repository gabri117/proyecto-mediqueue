-- Validate MediQueue Phase 1 database unification.
-- Run with:
-- psql -h localhost -p 55461 -U mediqueue -d mediqueue -f infra/docker/validate-mediqueue-schemas.sql

SELECT current_database() AS database_name;

SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('patient', 'schedule', 'appointment', 'payment', 'notification')
ORDER BY schema_name;

SELECT n.nspname AS schema_name,
       pg_catalog.pg_get_userbyid(n.nspowner) AS owner
FROM pg_catalog.pg_namespace n
WHERE n.nspname IN ('patient', 'schedule', 'appointment', 'payment', 'notification')
ORDER BY n.nspname;

SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('patient', 'schedule', 'appointment', 'payment', 'notification')
ORDER BY table_schema, table_name;

SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name = 'flyway_schema_history'
ORDER BY table_schema;

SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
