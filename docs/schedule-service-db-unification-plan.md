# Plan de Unificacion DB + HA para schedule-service

## 1. Objetivo

Migrar `schedule-service` al modelo de una sola base logica PostgreSQL
`mediqueue`, usando el schema dedicado `schedule` y conectandose por el endpoint
HA `postgres-lb:5432`.

Conexion objetivo:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=schedule
```

El servicio debe conservar ownership de odontologos, horarios laborales y slots
de agenda. La disponibilidad sigue exponiendose por API, no por consultas
directas desde otros schemas.

## 2. Estado Actual

Configuracion actual principal:

- Archivo: `services/schedule-service/src/main/resources/application.properties`
- Datasource actual:

```properties
spring.datasource.url=${SCHEDULE_DB_URL}
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}
spring.jpa.hibernate.ddl-auto=validate
spring.flyway.enabled=true
spring.flyway.baseline-on-migrate=true
```

Variables usadas:

- `SCHEDULE_DB_URL`
- `DB_USER`
- `DB_PASSWORD`

Migracion actual:

- `services/schedule-service/src/main/resources/db/migration/V1__schedule_service_init.sql`

Objetos actuales:

- Tablas:
  - `dentists`
  - `dentist_working_hours`
  - `dentist_slots`
- Enums:
  - `dentist_status`
  - `slot_display_status`
- Funcion:
  - `trg_set_updated_at`
- Triggers:
  - `trg_dentists_updated_at`
  - `trg_slots_updated_at`
- Indices principales:
  - `idx_dentists_status`
  - `idx_dentists_specialty`
  - `idx_working_hours_dentist`
  - `idx_slots_dentist_date`
  - `idx_slots_date_status`

## 3. Cambios Requeridos

### 3.1 Datasource

Actualizar `SCHEDULE_DB_URL`:

```text
SCHEDULE_DB_URL=jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=schedule
```

Mantener compatibilidad con las variables existentes:

```properties
spring.datasource.url=${SCHEDULE_DB_URL}
spring.datasource.username=${DB_USERNAME:${DB_USER:mediqueue}}
spring.datasource.password=${DB_PASSWORD:mediqueue}
```

### 3.2 Flyway

Agregar configuracion de schema:

```properties
spring.flyway.enabled=true
spring.flyway.baseline-on-migrate=true
spring.flyway.schemas=schedule
spring.flyway.default-schema=schedule
spring.flyway.create-schemas=false
```

El schema `schedule` debe ser creado por infraestructura.

### 3.3 Migraciones

La migracion debe ejecutarse dentro del schema `schedule`.

Puntos a revisar:

- `CREATE TYPE dentist_status` y `CREATE TYPE slot_display_status` deben quedar
  en `schedule`.
- Las tablas `dentists`, `dentist_working_hours` y `dentist_slots` deben quedar
  en `schedule`.
- La funcion `trg_set_updated_at` debe quedar aislada en `schedule`.
- Los triggers deben llamar la funcion del mismo schema.
- Las foreign keys internas entre `dentist_working_hours`, `dentist_slots` y
  `dentists` se mantienen porque son dentro del mismo bounded context.

### 3.4 Entidades JPA

Entidades actuales:

- `Dentist` con `@Table(name = "dentists")`
- `DentistWorkingHours` con `@Table(name = "dentist_working_hours")`
- `DentistSlot` con `@Table(name = "dentist_slots")`

No se requiere renombrar tablas ni fijar schema en anotaciones si se usa
`currentSchema=schedule`.

## 4. Reglas de Aislamiento

`schedule-service` es dueño del catalogo y agenda base.

Reglas:

- No crear FK real desde `schedule.dentist_slots` hacia
  `appointment.appointments`.
- No consultar `appointment`, `payment` ni `patient` directamente.
- Exponer slots por API para que `appointment-service` valide disponibilidad.
- Mantener `slot_id` y `dentist_id` como UUID logicos consumidos por otros
  servicios.

## 5. Validaciones Tecnicas

Validar schema:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'schedule';
```

Validar historial Flyway:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'schedule'
  AND table_name = 'flyway_schema_history';
```

Validar tablas:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'schedule'
ORDER BY table_name;
```

Validar enums:

```sql
SELECT n.nspname AS schema_name, t.typname AS type_name
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'schedule'
  AND t.typname IN ('dentist_status', 'slot_display_status')
ORDER BY t.typname;
```

Validar triggers:

```sql
SELECT event_object_schema, event_object_table, trigger_name
FROM information_schema.triggers
WHERE event_object_schema = 'schedule'
ORDER BY event_object_table, trigger_name;
```

## 6. Pruebas Funcionales

Casos minimos:

- Crear odontologo.
- Rechazar odontologo con email duplicado.
- Rechazar odontologo con `license_number` duplicado.
- Crear horario laboral.
- Crear slot.
- Rechazar slot duplicado para el mismo odontologo, fecha y hora.
- Listar slots disponibles.
- Activar/desactivar slot y validar cambio de estado.

Comando recomendado:

```bash
mvn -pl services/schedule-service -am test
```

## 7. Pruebas HA

Validar reconexion por `postgres-lb`:

- Crear odontologo y slot antes de switchover.
- Ejecutar switchover PostgreSQL.
- Consultar y crear slots despues del switchover.
- Confirmar que no se cambia `SCHEDULE_DB_URL`.

## 8. Rollback Operacional

Si falla la migracion:

- Detener `schedule-service`.
- Reapuntar `SCHEDULE_DB_URL` al origen anterior.
- Restaurar backup del schema `schedule` o DB anterior.
- Evitar que dos instancias del servicio escriban en destinos distintos durante
  el rollback.

## 9. Criterios de Aceptacion

La migracion de `schedule-service` estara lista cuando:

- Use `mediqueue?currentSchema=schedule`.
- Flyway cree `schedule.flyway_schema_history`.
- Las tablas e indices de agenda existan en `schedule`.
- Los enums de estado existan en `schedule`.
- Las FK internas hacia `dentists` sigan funcionando.
- La disponibilidad de slots siga funcionando despues de switchover/failover.

