# Migracion segura: PostgreSQL simple hacia Patroni

Este runbook mueve datos del PostgreSQL actual de MediQueue hacia el cluster Patroni local usando `pg_dump` en formato custom y restauracion por el writer de HAProxy.

La migracion no debe tocar la base origen. No usar `docker compose down -v` ni borrar volumenes durante este procedimiento.

## Arquitectura del flujo

```text
PostgreSQL actual
  service: postgres
  db: mediqueue
        |
        | pg_dump -Fc
        v
infra/backups/dumps/mediqueue_dump_*.dump
        |
        | pg_restore
        v
patroni-postgres-lb:5432
        |
        v
Patroni leader
```

## Precondiciones

- `docker-compose.yml` valida correctamente.
- `docker-compose.patroni.yml` valida correctamente.
- El cluster Patroni esta levantado y sano.
- `patroni-postgres-lb` responde por el writer.
- Las apps no deben escribir durante la ventana de migracion.
- Existe un backup reciente o se generara uno nuevo.

Validaciones iniciales:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml config --quiet
.\infra\patroni\scripts\patroni-healthcheck.ps1
.\infra\patroni\scripts\patroni-db-connection-test.ps1
```

## 1. Ejecutar plan sin cambios

Este comando no genera dump ni restaura datos. Solo valida origen, destino y muestra el plan.

```powershell
.\infra\patroni\scripts\migrate-single-postgres-to-patroni.ps1 -PlanOnly
```

Para planificar usando el ultimo dump existente:

```powershell
.\infra\patroni\scripts\migrate-single-postgres-to-patroni.ps1 -PlanOnly -UseLatestDump
```

## 2. Hacer backup antes de migrar

Generar un `pg_dump` desde el PostgreSQL actual:

```powershell
.\infra\backups\scripts\backup-pgdump.ps1
```

Verificar backups:

```powershell
.\infra\backups\scripts\verify-backups.ps1
```

El dump esperado queda en:

```text
infra/backups/dumps/mediqueue_dump_YYYYMMDD_HHMMSS.dump
```

## 3. Detener microservicios antes del restore

Para evitar escrituras mientras se migra:

```powershell
docker compose stop api-gateway api-gateway-lb patient-service schedule-service appointment-service payment-service notification-service patient-lb schedule-lb appointment-lb payment-lb
```

No detener `postgres`, `postgres-lb`, `rabbitmq`, `redis`, `etcd-*`, `patroni-postgres-*` ni `patroni-postgres-lb`.

## 4. Preparar Patroni para migracion

Validar que el writer es lider:

```powershell
.\infra\patroni\scripts\patroni-db-connection-test.ps1
```

Si el destino esta vacio o es un ambiente de prueba, puede prepararse con:

```powershell
.\infra\patroni\scripts\prepare-patroni-app-schemas.ps1
```

Para una migracion completa y limpia, usar recreacion de la base destino. Esto borra solo la base `mediqueue` del cluster Patroni, no toca PostgreSQL origen.

## 5. Restaurar en Patroni leader

Usando el ultimo dump existente:

```powershell
.\infra\patroni\scripts\migrate-single-postgres-to-patroni.ps1 `
  -UseLatestDump `
  -Execute `
  -RecreateDestination `
  -ConfirmRecreateDestination
```

Generando un dump nuevo y restaurandolo:

```powershell
.\infra\patroni\scripts\migrate-single-postgres-to-patroni.ps1 `
  -Execute `
  -RecreateDestination `
  -ConfirmRecreateDestination
```

Usando un dump especifico:

```powershell
.\infra\patroni\scripts\migrate-single-postgres-to-patroni.ps1 `
  -DumpPath .\infra\backups\dumps\mediqueue_dump_YYYYMMDD_HHMMSS.dump `
  -Execute `
  -RecreateDestination `
  -ConfirmRecreateDestination
```

El script nunca restaura sin `-Execute`. Si se usa `-RecreateDestination`, exige tambien `-ConfirmRecreateDestination`.

## 6. Validaciones post-migracion

Validar conexion por HAProxy writer:

```powershell
.\infra\patroni\scripts\patroni-db-connection-test.ps1
```

Validar estado Patroni:

```powershell
.\infra\patroni\scripts\patroni-status.ps1
```

Validar schemas existentes y conteos de tablas criticas:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T `
  -e PGPASSWORD=postgres patroni-postgres-1 `
  psql -h patroni-postgres-lb -p 5432 -U postgres -d mediqueue -c "
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('patient','schedule','appointment','payment','notification')
ORDER BY schema_name;

SELECT 'patient.patients' AS table_name, count(*)::bigint AS rows FROM patient.patients
UNION ALL SELECT 'schedule.dentists', count(*)::bigint FROM schedule.dentists
UNION ALL SELECT 'schedule.dentist_working_hours', count(*)::bigint FROM schedule.dentist_working_hours
UNION ALL SELECT 'schedule.dentist_slots', count(*)::bigint FROM schedule.dentist_slots
UNION ALL SELECT 'appointment.appointments', count(*)::bigint FROM appointment.appointments
UNION ALL SELECT 'appointment.appointment_holds', count(*)::bigint FROM appointment.appointment_holds
UNION ALL SELECT 'appointment.appointment_audit', count(*)::bigint FROM appointment.appointment_audit
UNION ALL SELECT 'appointment.idempotency_keys', count(*)::bigint FROM appointment.idempotency_keys
UNION ALL SELECT 'appointment.outbox_events', count(*)::bigint FROM appointment.outbox_events
UNION ALL SELECT 'payment.payments', count(*)::bigint FROM payment.payments
UNION ALL SELECT 'payment.payment_idempotency', count(*)::bigint FROM payment.payment_idempotency
UNION ALL SELECT 'payment.payment_events_outbox', count(*)::bigint FROM payment.payment_events_outbox
UNION ALL SELECT 'notification.notifications', count(*)::bigint FROM notification.notifications
ORDER BY table_name;"
```

Validar que el writer no esta en recovery:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T `
  -e PGPASSWORD=postgres patroni-postgres-1 `
  psql -h patroni-postgres-lb -p 5432 -U postgres -d mediqueue `
  -c "SELECT pg_is_in_recovery();"
```

El resultado esperado para writer es:

```text
pg_is_in_recovery = false
```

Validar replicas:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T patroni-postgres-1 patronictl -c /etc/patroni/patroni.yml list
```

Debe existir 1 lider y 2 replicas.

## 7. Apuntar microservicios a Patroni

Preparar/verificar routing:

```powershell
.\infra\patroni\scripts\app-db-routing-check.ps1
```

Levantar apps con overlay Patroni:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml -f docker-compose.patroni-apps.yml up -d
```

Smoke test:

```powershell
.\infra\patroni\scripts\app-smoke-test-patroni.ps1
```

Validar health:

```powershell
Invoke-WebRequest -Uri http://localhost:8080/actuator/health -UseBasicParsing
```

## 8. Rollback

Si la validacion falla antes de mover trafico, no hay que tocar el origen. Volver al modo PostgreSQL simple:

```powershell
docker compose -f docker-compose.yml up -d --force-recreate patient-service schedule-service appointment-service payment-service notification-service api-gateway
```

Si ya se habia restaurado algo en Patroni y se quiere descartar, no borrar volumenes automaticamente. Repetir la migracion con un dump conocido bueno o recrear solo la base Patroni usando el script con confirmacion explicita.

Si el PostgreSQL simple origen necesitara restauracion por una prueba separada, usar los runbooks/scripts de `infra/backups/`. No restaurar sobre la base principal sin una ventana controlada y un dump verificado.

## Riesgos y notas

- El modo `-RecreateDestination` elimina y recrea solo la base destino en Patroni.
- No se elimina ni modifica la base origen `postgres`.
- Detener apps antes de migrar evita divergencia entre origen y destino.
- La restauracion con `pg_restore` puede fallar si se intenta cargar sobre objetos ya existentes sin recrear destino.
- En ambiente real, revisar passwords, cifrado de dumps y ventanas de mantenimiento.
