# Plan de Unificacion DB + HA para patient-service

## 1. Objetivo

Migrar `patient-service` al modelo de una sola base logica PostgreSQL
`mediqueue`, usando el schema dedicado `patient` y conectandose por el endpoint
HA `postgres-lb:5432`.

Conexion objetivo:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=patient
```

El servicio debe conservar ownership exclusivo de los datos de pacientes y no
debe crear dependencias directas hacia schemas de otros microservicios.

## 2. Estado Actual

Configuracion actual principal:

- Archivo: `services/patient-service/src/main/resources/application.properties`
- Datasource actual:

```properties
spring.datasource.url=${DB_URL:jdbc:postgresql://localhost:5432/mediqueue_patients}
spring.datasource.username=${DB_USER:mediqueue}
spring.datasource.password=${DB_PASSWORD:mediqueue}
spring.jpa.hibernate.ddl-auto=validate
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
```

Variables usadas:

- `DB_URL`
- `DB_USER`
- `DB_PASSWORD`

Migracion actual:

- `services/patient-service/src/main/resources/db/migration/V1__patient_service_init.sql`

Objetos actuales:

- Tabla: `patients`
- Enum: `patient_status`
- Funcion: `trg_set_updated_at`
- Trigger: `trg_patients_updated_at`
- Indice: `idx_patients_status`
- Restricciones unicas:
  - `uq_patients_email`
  - `uq_patients_document_number`

## 3. Cambios Requeridos

### 3.1 Datasource

Actualizar la URL del servicio para usar la base unica y el schema `patient`:

```properties
spring.datasource.url=${DB_URL:jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=patient}
spring.datasource.username=${DB_USERNAME:${DB_USER:mediqueue}}
spring.datasource.password=${DB_PASSWORD:mediqueue}
```

En Docker Compose o despliegue:

```text
DB_URL=jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=patient
DB_USERNAME=mediqueue
DB_PASSWORD=mediqueue
```

### 3.2 Flyway

Agregar configuracion de schema:

```properties
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
spring.flyway.schemas=patient
spring.flyway.default-schema=patient
spring.flyway.create-schemas=false
```

El schema `patient` debe ser creado por infraestructura antes del arranque del
servicio.

### 3.3 Migraciones

La migracion debe ejecutarse dentro del schema `patient`. No debe depender del
schema `public`.

Puntos a revisar:

- `CREATE TYPE patient_status` debe crear el enum en `patient`.
- `CREATE TABLE patients` debe crear la tabla en `patient`.
- `CREATE OR REPLACE FUNCTION trg_set_updated_at()` debe quedar aislada en
  `patient`, evitando conflicto con funciones del mismo nombre en otros schemas.
- El trigger `trg_patients_updated_at` debe apuntar a la funcion del schema
  `patient`.

Si se usa `currentSchema=patient` y `spring.flyway.default-schema=patient`, los
objetos no calificados deben quedar en el schema correcto.

### 3.4 Entidad JPA

La entidad actual `Patient` usa:

```java
@Table(name = "patients")
```

No es necesario renombrar tabla ni agregar schema en la anotacion si la conexion
usa `currentSchema=patient`. Mantener esta forma para no acoplar el codigo a un
schema fijo y permitir configuracion por entorno.

## 4. Reglas de Aislamiento

`patient-service` debe seguir siendo la unica fuente de verdad de pacientes.

Reglas:

- No crear foreign keys desde `patient.patients` hacia `appointment`, `payment`
  o `notification`.
- No consultar directamente tablas de otros schemas.
- Exponer informacion de pacientes por API, no por joins cross-schema.
- Mantener `patient_id` como UUID logico usado por otros servicios.

## 5. Validaciones Tecnicas

Validar existencia del schema:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'patient';
```

Validar historial Flyway:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'patient'
  AND table_name = 'flyway_schema_history';
```

Validar objetos principales:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'patient'
ORDER BY table_name;
```

Validar enum:

```sql
SELECT n.nspname AS schema_name, t.typname AS type_name
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'patient'
  AND t.typname = 'patient_status';
```

Validar trigger:

```sql
SELECT event_object_schema, event_object_table, trigger_name
FROM information_schema.triggers
WHERE event_object_schema = 'patient'
  AND event_object_table = 'patients';
```

## 6. Pruebas Funcionales

Casos minimos:

- Crear paciente nuevo.
- Consultar paciente creado.
- Intentar crear paciente con email duplicado y confirmar rechazo.
- Intentar crear paciente con `document_number` duplicado y confirmar rechazo.
- Actualizar paciente y confirmar que `updated_at` cambia por trigger.
- Reiniciar el servicio y confirmar que Flyway no intenta recrear objetos.

Comando recomendado:

```bash
mvn -pl services/patient-service -am test
```

## 7. Pruebas HA

Validar que el servicio use solamente `postgres-lb`:

- Arrancar `patient-service` con la URL objetivo.
- Crear un paciente antes de un switchover.
- Ejecutar switchover del cluster PostgreSQL.
- Crear otro paciente despues del switchover.
- Confirmar que no se requiere cambiar configuracion del servicio.

## 8. Rollback Operacional

Si la migracion al modelo unificado falla:

- Detener `patient-service`.
- Apuntar `DB_URL` al origen anterior temporalmente.
- Restaurar backup del schema `patient` o de la DB anterior segun el punto de
  corte.
- No ejecutar migraciones nuevas contra ambos destinos al mismo tiempo.

## 9. Criterios de Aceptacion

La migracion de `patient-service` estara lista cuando:

- Use `mediqueue?currentSchema=patient`.
- Flyway cree `patient.flyway_schema_history`.
- La tabla `patient.patients` exista con indices y restricciones esperadas.
- El enum `patient.patient_status` exista.
- Las unicidades de email y documento sigan funcionando.
- El servicio opere correctamente despues de switchover/failover de PostgreSQL.

