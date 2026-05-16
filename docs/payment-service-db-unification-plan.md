# Plan de Unificacion DB + HA para payment-service

## 1. Objetivo

Migrar `payment-service` al modelo de una sola base logica PostgreSQL
`mediqueue`, usando el schema dedicado `payment` y conectandose por el endpoint
HA `postgres-lb:5432`.

Conexion objetivo:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment
```

El servicio debe conservar sus garantias de idempotencia, unicidad de pago
aprobado por cita y publicacion segura de eventos mediante outbox.

## 2. Estado Actual

Configuracion actual:

- Archivo: `services/payment-service/src/main/resources/application.yml`
- Datasource:

```yaml
spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://localhost:5436/mediqueue_payment}
    username: ${DB_USER:mediqueue}
    password: ${DB_PASSWORD:mediqueue}
```

Variables usadas:

- `DB_URL`
- `DB_USER`
- `DB_PASSWORD`

Migraciones actuales:

- `services/payment-service/src/main/resources/db/migration/V1__payment_service_init.sql`
- `services/payment-service/src/main/resources/db/migration/V2__payment_query_indexes.sql`

Objetos actuales:

- Tablas:
  - `payments`
  - `payment_idempotency`
  - `payment_events_outbox`
- Enums:
  - `payment_status`
  - `idempotency_status`
  - `outbox_publication_status`
- Indices:
  - `idx_payments_appointment`
  - `idx_payments_status`
  - `uq_payments_appointment_approved`
  - `idx_payments_requested_at_desc`
  - `idx_payments_status_requested_at_desc`
  - `idx_payments_appointment_requested_at_desc`

## 3. Cambios Requeridos

### 3.1 Datasource

Actualizar URL:

```text
DB_URL=jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment
```

Configuracion recomendada:

```yaml
spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment}
    username: ${DB_USERNAME:${DB_USER:mediqueue}}
    password: ${DB_PASSWORD:mediqueue}
```

### 3.2 Flyway

Agregar configuracion:

```yaml
spring:
  flyway:
    enabled: true
    schemas: payment
    default-schema: payment
    create-schemas: false
```

El schema `payment` debe ser creado por infraestructura.

### 3.3 Migraciones

Las migraciones deben ejecutarse dentro del schema `payment`.

Puntos a preservar:

- Enums `payment_status`, `idempotency_status` y
  `outbox_publication_status` deben quedar en `payment`.
- Tabla `payments` debe conservar el indice unico parcial:

```sql
CREATE UNIQUE INDEX uq_payments_appointment_approved
    ON payments(appointment_id)
    WHERE payment_status = 'APPROVED';
```

- Los indices de consulta de `V2__payment_query_indexes.sql` deben crearse en
  `payment`.
- `payment_events_outbox` debe seguir soportando procesamiento concurrente.

### 3.4 Repositorios y Concurrencia

El repositorio de outbox usa consulta nativa con:

```sql
FOR UPDATE SKIP LOCKED
```

Esta garantia debe preservarse para que varias replicas de `payment-service` no
publiquen el mismo evento pendiente.

Si se usa `currentSchema=payment`, la consulta nativa puede seguir usando tabla
sin calificar. Si se elimina `currentSchema`, entonces las queries nativas
deberian calificar `payment.payment_events_outbox`.

## 4. Reglas de Aislamiento

Reglas:

- No crear FK real desde `payment.payments.appointment_id` hacia
  `appointment.appointments`.
- No crear FK real desde `payment.payments.patient_id` hacia
  `patient.patients`.
- Mantener `appointment_id` y `patient_id` como UUID logicos.
- Mantener eventos consumidos/publicados por RabbitMQ.
- No consultar tablas de `appointment` para validar pagos; usar eventos/API.

## 5. Validaciones Tecnicas

Validar schema:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'payment';
```

Validar historial Flyway:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'payment'
  AND table_name = 'flyway_schema_history';
```

Validar tablas:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'payment'
ORDER BY table_name;
```

Validar enums:

```sql
SELECT n.nspname AS schema_name, t.typname AS type_name
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'payment'
  AND t.typname IN (
    'payment_status',
    'idempotency_status',
    'outbox_publication_status'
  )
ORDER BY t.typname;
```

Validar indices:

```sql
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'payment'
ORDER BY tablename, indexname;
```

## 6. Pruebas Funcionales

Casos minimos:

- Crear pago.
- Repetir request con misma idempotency key y confirmar misma respuesta.
- Intentar aprobar dos pagos para la misma cita y confirmar rechazo por indice.
- Procesar evento de cita retenida.
- Publicar evento de pago exitoso/fallido por outbox.
- Levantar multiples replicas y confirmar que no se duplican publicaciones.

Comando recomendado:

```bash
mvn -pl services/payment-service -am test
```

## 7. Pruebas HA

Validar comportamiento con replicas:

- Levantar varias replicas de `payment-service`.
- Crear pagos antes de switchover.
- Ejecutar switchover PostgreSQL.
- Crear pagos despues del switchover.
- Confirmar que idempotencia y outbox siguen consistentes.
- Simular failover y verificar reconexion por `postgres-lb`.

## 8. Rollback Operacional

Si falla la migracion:

- Detener replicas de `payment-service`.
- Reapuntar `DB_URL` al origen anterior.
- Restaurar backup del schema `payment` o DB anterior.
- Revisar eventos pendientes en `payment_events_outbox`.
- Evitar publicar dos veces eventos ya enviados antes del rollback.

## 9. Criterios de Aceptacion

La migracion de `payment-service` estara lista cuando:

- Use `mediqueue?currentSchema=payment`.
- Flyway cree `payment.flyway_schema_history`.
- Los enums y tablas existan en `payment`.
- El indice `uq_payments_appointment_approved` siga funcionando.
- `FOR UPDATE SKIP LOCKED` funcione con multiples replicas.
- No existan FK reales hacia `appointment` o `patient`.
- El servicio opere correctamente despues de switchover/failover.

