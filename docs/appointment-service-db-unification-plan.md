# Plan de Unificacion DB + HA para appointment-service

## 1. Objetivo

Migrar `appointment-service` al modelo de una sola base logica PostgreSQL
`mediqueue`, usando el schema dedicado `appointment` y conectandose por el
endpoint HA `postgres-lb:5432`.

Conexion objetivo:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=appointment
```

Este servicio es el componente transaccional mas critico del flujo de citas:
controla reservas temporales, idempotencia, auditoria y outbox.

## 2. Estado Actual

Configuracion actual:

- Archivo: `services/appointment-service/src/main/resources/application.properties`
- Datasource:

```properties
spring.datasource.url=${DB_URL}
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}
spring.jpa.hibernate.ddl-auto=validate
spring.flyway.enabled=true
spring.flyway.baseline-on-migrate=true
```

Variables usadas:

- `DB_URL`
- `DB_USER`
- `DB_PASSWORD`

Migracion actual:

- `services/appointment-service/src/main/resources/db/migration/V1__appointment_service_init.sql`

Objetos actuales:

- Tablas:
  - `appointments`
  - `appointment_holds`
  - `appointment_audit`
  - `idempotency_keys`
  - `outbox_events`
- Funcion:
  - `trg_set_updated_at`
  - `trg_audit_immutable`
- Triggers:
  - `trg_appointments_updated_at`
  - `trg_audit_no_update`
  - `trg_audit_no_delete`
- Indices criticos:
  - `uq_appointment_slot_active`
  - `uq_holds_one_active_per_slot`
  - `idx_holds_expiration`
  - `idx_outbox_pending`

## 3. Cambios Requeridos

### 3.1 Datasource

Actualizar URL:

```text
DB_URL=jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=appointment
```

Configuracion recomendada:

```properties
spring.datasource.url=${DB_URL}
spring.datasource.username=${DB_USERNAME:${DB_USER:mediqueue}}
spring.datasource.password=${DB_PASSWORD:mediqueue}
```

### 3.2 Flyway

Agregar configuracion de schema:

```properties
spring.flyway.enabled=true
spring.flyway.baseline-on-migrate=true
spring.flyway.schemas=appointment
spring.flyway.default-schema=appointment
spring.flyway.create-schemas=false
```

El schema `appointment` debe existir antes de iniciar el servicio.

### 3.3 Migraciones

La migracion debe ejecutarse dentro del schema `appointment`.

Puntos a preservar:

- `appointments` debe mantener el indice unico parcial:

```sql
CREATE UNIQUE INDEX uq_appointment_slot_active
    ON appointments(slot_id)
    WHERE appointment_status IN ('PENDING_PAYMENT', 'CONFIRMED');
```

- `appointment_holds` debe mantener el indice unico parcial:

```sql
CREATE UNIQUE INDEX uq_holds_one_active_per_slot
    ON appointment_holds(slot_id)
    WHERE hold_status = 'ACTIVE';
```

- `appointment_audit` debe seguir siendo inmutable con triggers que bloqueen
  `UPDATE` y `DELETE`.
- `outbox_events` debe conservar `idx_outbox_pending`.
- Las FK internas desde holds/auditoria hacia `appointments` se mantienen porque
  son internas al schema `appointment`.

### 3.4 Entidades JPA

Entidades actuales:

- `Appointment` con `@Table(name = "appointments")`
- `AppointmentHold` con `@Table(name = "appointment_holds")`
- `AppointmentAudit` con `@Table(name = "appointment_audit")`
- `IdempotencyKey` con `@Table(name = "idempotency_keys")`
- `OutboxEvent` con `@Table(name = "outbox_events")`

No se recomienda fijar schema en anotaciones. Usar `currentSchema=appointment`.

## 4. Reglas de Aislamiento

Aunque todos los datos vivan en la misma DB fisica, las referencias externas
siguen siendo logicas.

Reglas:

- No crear FK real desde `appointment.patient_id` hacia `patient.patients`.
- No crear FK real desde `appointment.dentist_id` o `appointment.slot_id` hacia
  `schedule`.
- Validar paciente y slot por API, como ya hace el servicio.
- Mantener eventos por RabbitMQ/outbox.
- No consultar tablas de `payment` o `notification`.

## 5. Validaciones Tecnicas

Validar schema:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'appointment';
```

Validar historial Flyway:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'appointment'
  AND table_name = 'flyway_schema_history';
```

Validar tablas:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'appointment'
ORDER BY table_name;
```

Validar indices criticos:

```sql
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'appointment'
  AND indexname IN (
    'uq_appointment_slot_active',
    'uq_holds_one_active_per_slot',
    'idx_outbox_pending'
  )
ORDER BY indexname;
```

Validar triggers de auditoria:

```sql
SELECT event_object_schema, event_object_table, trigger_name
FROM information_schema.triggers
WHERE event_object_schema = 'appointment'
ORDER BY event_object_table, trigger_name;
```

## 6. Pruebas Funcionales

Casos minimos:

- Crear cita con hold activo.
- Intentar crear segunda cita para el mismo slot activo y confirmar rechazo.
- Confirmar cita despues de pago exitoso.
- Cancelar/compensar cita despues de pago fallido.
- Confirmar que `appointment_audit` no permite `UPDATE` ni `DELETE`.
- Confirmar que se genera evento outbox al crear/confirmar/cancelar.
- Confirmar que la idempotencia devuelve la misma respuesta ante retry.

Comando recomendado:

```bash
mvn -pl services/appointment-service -am test
```

## 7. Pruebas HA

Validar continuidad durante switchover/failover:

- Crear cita antes de switchover.
- Ejecutar switchover PostgreSQL.
- Reintentar consulta y crear otra cita.
- Confirmar que no se duplican holds ni outbox events.
- Confirmar que HikariCP reconecta sin cambios de configuracion.

## 8. Rollback Operacional

Si falla la migracion:

- Detener `appointment-service` primero para evitar cambios parciales.
- Reapuntar `DB_URL` al origen anterior.
- Restaurar backup del schema `appointment` o DB anterior.
- Revisar outbox pendiente antes de volver a levantar consumidores/publicadores.
- Evitar que el mismo evento sea publicado desde dos entornos.

## 9. Criterios de Aceptacion

La migracion de `appointment-service` estara lista cuando:

- Use `mediqueue?currentSchema=appointment`.
- Flyway cree `appointment.flyway_schema_history`.
- Los indices parciales de slot/hold activo funcionen.
- La auditoria siga siendo inmutable.
- Idempotencia y outbox sigan funcionando.
- No existan FK reales hacia `patient` o `schedule`.
- El servicio opere correctamente despues de switchover/failover.

