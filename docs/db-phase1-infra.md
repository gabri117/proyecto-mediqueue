# Fase 1 de infraestructura PostgreSQL

## Objetivo

Esta fase prepara una sola base logica PostgreSQL llamada `mediqueue` con un
schema por microservicio:

- `patient`
- `schedule`
- `appointment`
- `payment`
- `notification`

Tambien agrega el endpoint estable `postgres-lb:5432`. En esta fase
`postgres-lb` es un HAProxy TCP que apunta a una sola instancia PostgreSQL. No
incluye Patroni, etcd ni Consul.

## Conexion desde DBeaver

Usar una conexion PostgreSQL con estos valores:

- Host: `localhost`
- Port: `55461`
- Database: `mediqueue`
- User: `mediqueue`
- Password: `mediqueue`

En Docker, los microservicios usan el endpoint interno:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=<schema>,public
```

## Validacion

Verificar la base activa:

```sql
SELECT current_database() AS database_name;
```

Verificar schemas:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('patient', 'schedule', 'appointment', 'payment', 'notification')
ORDER BY schema_name;
```

Verificar owners:

```sql
SELECT n.nspname AS schema_name,
       pg_catalog.pg_get_userbyid(n.nspowner) AS owner
FROM pg_catalog.pg_namespace n
WHERE n.nspname IN ('patient', 'schedule', 'appointment', 'payment', 'notification')
ORDER BY n.nspname;
```

Verificar tablas por schema:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('patient', 'schedule', 'appointment', 'payment', 'notification')
ORDER BY table_schema, table_name;
```

Verificar historiales Flyway por schema:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name = 'flyway_schema_history'
ORDER BY table_schema;
```

Verificar que no existan tablas de servicios en `public`:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

Las mismas consultas estan disponibles en
`infra/docker/validate-mediqueue-schemas.sql`.

## Alcance excluido

- No se implementa Patroni.
- No se implementa etcd ni Consul.
- No se cambian clases Java.
- No se crean foreign keys entre schemas.
- No se agregan tablas de microservicios en `public`.
