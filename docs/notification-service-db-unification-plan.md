# Plan de Unificacion DB + HA para notification-service

## 1. Objetivo

Migrar `notification-service` al modelo de una sola base logica PostgreSQL
`mediqueue`, usando el schema dedicado `notification` y conectandose por el
endpoint HA `postgres-lb:5432`.

Conexion objetivo:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=notification
```

El servicio debe conservar deduplicacion por evento y seguir usando RabbitMQ
como fuente de datos para notificaciones.

## 2. Estado Actual

Configuracion actual:

- Archivo: `services/notification-service/src/main/resources/application.yml`
- Datasource:

```yaml
spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://localhost:5432/mediqueue_notifications}
    username: ${DB_USER:mediqueue}
    password: ${DB_PASSWORD:mediqueue}
```

Variables usadas:

- `DB_URL`
- `DB_USER`
- `DB_PASSWORD`

Migraciones actuales:

- `services/notification-service/src/main/resources/db/migration/V1__notification_service_init.sql`
- `services/notification-service/src/main/resources/db/migration/V2__notification_event_deduplication.sql`

Objetos actuales:

- Tabla:
  - `notifications`
- Enums:
  - `notification_status`
  - `notification_channel`
- Indices:
  - `idx_notifications_patient`
  - `idx_notifications_status`
  - `idx_notifications_event`
  - `uq_notifications_event_key`
  - `idx_notifications_appointment`

## 3. Cambios Requeridos

### 3.1 Datasource

Actualizar URL:

```text
DB_URL=jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=notification
```

Configuracion recomendada:

```yaml
spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=notification}
    username: ${DB_USERNAME:${DB_USER:mediqueue}}
    password: ${DB_PASSWORD:mediqueue}
```

### 3.2 Flyway

Agregar configuracion:

```yaml
spring:
  flyway:
    enabled: true
    schemas: notification
    default-schema: notification
    create-schemas: false
```

El schema `notification` debe ser creado por infraestructura.

### 3.3 Migraciones

Las migraciones deben ejecutarse dentro del schema `notification`.

Puntos a preservar:

- Enums `notification_status` y `notification_channel` deben quedar en
  `notification`.
- Tabla `notifications` debe quedar en `notification`.
- La migracion V2 debe preservar columnas de trazabilidad:
  - `source_event_id`
  - `source_event_type`
  - `source_service`
  - `event_key`
  - `routing_key`
  - `attempt_count`
- Mantener indice unico parcial:

```sql
CREATE UNIQUE INDEX uq_notifications_event_key
    ON notifications(event_key)
    WHERE event_key IS NOT NULL;
```

### 3.4 Entidad JPA

La entidad actual `Notification` usa:

```java
@Table(name = "notifications")
```

No se requiere fijar schema en la anotacion si la conexion usa
`currentSchema=notification`.

## 4. Reglas de Aislamiento

Reglas:

- No consultar directamente tablas de `appointment`, `payment` o `patient`.
- Mantener RabbitMQ como fuente para eventos de citas y pagos.
- Mantener `patient_id` y `appointment_id` como referencias logicas.
- Deduplicar por `event_key`, no por joins contra otros schemas.

## 5. Validaciones Tecnicas

Validar schema:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'notification';
```

Validar historial Flyway:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'notification'
  AND table_name = 'flyway_schema_history';
```

Validar tablas:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'notification'
ORDER BY table_name;
```

Validar enums:

```sql
SELECT n.nspname AS schema_name, t.typname AS type_name
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'notification'
  AND t.typname IN ('notification_status', 'notification_channel')
ORDER BY t.typname;
```

Validar indice de deduplicacion:

```sql
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'notification'
  AND indexname = 'uq_notifications_event_key';
```

## 6. Pruebas Funcionales

Casos minimos:

- Consumir evento de cita y crear notificacion.
- Consumir evento de pago y crear notificacion.
- Reentregar el mismo evento y confirmar que no se duplica por `event_key`.
- Consultar notificaciones por paciente.
- Confirmar estados `PENDING`, `SENT` y `FAILED` segun flujo existente.

Comando recomendado:

```bash
mvn -pl services/notification-service -am test
```

## 7. Pruebas HA

Validar continuidad:

- Consumir eventos antes de switchover.
- Ejecutar switchover PostgreSQL.
- Consumir eventos despues del switchover.
- Reentregar eventos durante o despues del switchover y confirmar que la
  deduplicacion se mantiene.
- Confirmar que no se cambia `DB_URL` si `postgres-lb` sigue estable.

## 8. Rollback Operacional

Si falla la migracion:

- Detener `notification-service`.
- Reapuntar `DB_URL` al origen anterior.
- Restaurar backup del schema `notification` o DB anterior.
- Revisar offsets/estado de colas RabbitMQ para evitar reprocesos no deseados.
- Conservar la deduplicacion por `event_key` durante el rollback.

## 9. Criterios de Aceptacion

La migracion de `notification-service` estara lista cuando:

- Use `mediqueue?currentSchema=notification`.
- Flyway cree `notification.flyway_schema_history`.
- La tabla `notification.notifications` exista con columnas V1 y V2.
- Los enums existan en `notification`.
- `uq_notifications_event_key` siga evitando duplicados.
- No existan consultas directas a schemas de otros servicios.
- El servicio opere correctamente despues de switchover/failover.

