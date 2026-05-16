# Plan de Unificacion de Bases de Datos y Alta Disponibilidad

## 1. Objetivo

Unificar el manejo de datos del monorepo MediQueue en una sola base logica
PostgreSQL, manteniendo separacion por microservicio mediante schemas. El
objetivo operativo es simplificar backups, administracion, observabilidad y alta
disponibilidad, sin romper el aislamiento funcional de cada microservicio.

La arquitectura recomendada es:

- Una sola base logica: `mediqueue`.
- Un schema por microservicio: `patient`, `schedule`, `appointment`, `payment`,
  `notification`.
- Un endpoint estable para aplicaciones: `postgres-lb:5432`.
- Alta disponibilidad real con Patroni, replicas PostgreSQL y HAProxy.
- Switchover controlado y failover automatico a nivel de PostgreSQL.

Este documento no implementa cambios de codigo ni de infraestructura. Define lo
que debe cambiar cada microservicio y la infraestructura para abordar la
unificacion.

## 2. Estado Actual del Monorepo

El monorepo tiene dos enfoques de base de datos:

- `docker-compose.yml` usa una sola instancia PostgreSQL llamada
  `mediqueue-postgres`, pero crea varias bases logicas:
  `mediqueue_appointments`, `mediqueue_notifications`, `mediqueue_payments`,
  `mediqueue_patients` y `mediqueue_schedules`.
- `infra/docker-compose.yml` conserva un modelo anterior con un contenedor
  PostgreSQL por microservicio: `patient-db`, `schedule-db`, `appointment-db`,
  `payment-db` y `notification-db`.
- La alta disponibilidad existente esta enfocada en replicas de servicios, por
  ejemplo `api-gateway` y `payment-service` detras de HAProxy.
- No existe alta disponibilidad real para PostgreSQL. La base sigue siendo un
  punto unico de falla cuando se usa una sola instancia.

La unificacion propuesta no debe mezclar todas las tablas en `public`. Las
migraciones actuales repiten objetos globales como funciones, enums, triggers y
tablas de historial Flyway. Si todo se ejecuta en `public`, habria riesgo de
choques de nombres. Por eso la ruta recomendada es una sola base logica con
schemas separados.

## 3. Arquitectura Objetivo

La base logica objetivo sera:

```text
mediqueue
├── patient
├── schedule
├── appointment
├── payment
└── notification
```

Cada microservicio debe conectarse a la misma base, pero fijando su schema por
JDBC:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=<schema>
```

Ejemplos:

```text
patient-service      -> jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=patient
schedule-service     -> jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=schedule
appointment-service  -> jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=appointment
payment-service      -> jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment
notification-service -> jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=notification
```

La infraestructura de alta disponibilidad debe tener:

- `postgres-1`, `postgres-2`, `postgres-3` como nodos PostgreSQL administrados
  por Patroni.
- etcd o Consul como Distributed Configuration Store para Patroni.
- `postgres-lb` con HAProxy como endpoint estable para los microservicios.
- Un puerto de escritura que siempre apunte al primary actual.
- Opcionalmente, un puerto read-only para consultas hacia replicas.

## 4. Reglas Generales para Todos los Microservicios

Cada microservicio debe mantener ownership de sus datos. La unificacion fisica
no cambia las fronteras del dominio.

Reglas obligatorias:

- Usar la base `mediqueue`.
- Usar exclusivamente el schema asignado al microservicio.
- Configurar `currentSchema` en la URL JDBC.
- Configurar Flyway para ejecutar migraciones solo dentro del schema propio.
- Mantener una tabla `flyway_schema_history` por schema.
- No crear foreign keys reales hacia schemas de otros microservicios.
- Mantener referencias entre servicios como UUID logicos.
- Mantener la comunicacion actual por HTTP y RabbitMQ.
- No consultar directamente tablas de otros schemas desde un microservicio.
- Mantener `spring.jpa.hibernate.ddl-auto=validate` para que Hibernate valide,
  pero no cree ni modifique estructura automaticamente.

Configuracion base recomendada por servicio:

```properties
spring.datasource.url=jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=<schema>
spring.datasource.username=${DB_USERNAME}
spring.datasource.password=${DB_PASSWORD}
spring.flyway.enabled=true
spring.flyway.schemas=<schema>
spring.flyway.default-schema=<schema>
spring.flyway.create-schemas=false
spring.jpa.hibernate.ddl-auto=validate
```

`spring.flyway.create-schemas=false` asume que la infraestructura crea los
schemas antes de iniciar los microservicios. Si se decide que cada servicio cree
su schema, debe cambiarse a `true`, pero la opcion recomendada es centralizar la
creacion en infraestructura.

## 5. Implementacion por Microservicio

### 5.1 patient-service

Schema asignado:

```text
patient
```

Responsabilidad:

- Mantener datos maestros de pacientes.
- Mantener ownership de la tabla `patients`.
- Preservar reglas de unicidad de email y numero de documento.

Cambios requeridos:

- Cambiar la conexion a:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=patient
```

- Configurar Flyway:

```properties
spring.flyway.schemas=patient
spring.flyway.default-schema=patient
```

- Mantener la tabla `patients` sin renombrar, ahora dentro del schema
  `patient`.
- Revisar que el enum `patient_status`, la funcion `trg_set_updated_at` y el
  trigger `trg_patients_updated_at` se creen dentro del schema `patient`.
- No agregar foreign keys desde `patients` hacia citas, pagos o notificaciones.

Validaciones especificas:

- Insertar paciente nuevo.
- Reintentar crear paciente con email duplicado y confirmar que la restriccion
  sigue funcionando.
- Confirmar que `patient.flyway_schema_history` existe y contiene las
  migraciones del servicio.

### 5.2 schedule-service

Schema asignado:

```text
schedule
```

Responsabilidad:

- Mantener catalogo de odontologos.
- Mantener horarios laborales.
- Mantener slots concretos de agenda.
- Exponer disponibilidad para el flujo de citas.

Cambios requeridos:

- Cambiar la conexion a:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=schedule
```

- Mantener compatibilidad con la variable actual `SCHEDULE_DB_URL`, pero
  apuntandola al nuevo endpoint:

```text
SCHEDULE_DB_URL=jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=schedule
```

- Configurar Flyway:

```properties
spring.flyway.schemas=schedule
spring.flyway.default-schema=schedule
```

- Migrar estas tablas al schema `schedule`:
  - `dentists`
  - `dentist_working_hours`
  - `dentist_slots`
- Revisar que los enums `dentist_status` y `slot_display_status` vivan dentro
  del schema `schedule`.
- Revisar que `trg_set_updated_at` y los triggers asociados se creen dentro del
  schema `schedule`.
- No crear FK real desde `schedule.dentist_slots` hacia
  `appointment.appointments`.

Validaciones especificas:

- Crear odontologo.
- Crear horario laboral.
- Generar o registrar slot.
- Confirmar que las restricciones de unicidad de odontologo y slots se
  mantienen.
- Confirmar que `schedule.flyway_schema_history` existe y es independiente.

### 5.3 appointment-service

Schema asignado:

```text
appointment
```

Responsabilidad:

- Ser el servicio transaccional principal del flujo de citas.
- Controlar reservas temporales.
- Evitar doble reserva de un slot.
- Mantener auditoria inmutable.
- Mantener idempotencia.
- Publicar eventos mediante outbox.

Cambios requeridos:

- Cambiar la conexion a:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=appointment
```

- Configurar Flyway:

```properties
spring.flyway.schemas=appointment
spring.flyway.default-schema=appointment
```

- Migrar estas tablas al schema `appointment`:
  - `appointments`
  - `appointment_holds`
  - `appointment_audit`
  - `idempotency_keys`
  - `outbox_events`
- Mantener `patient_id`, `dentist_id` y `slot_id` como referencias logicas.
  Aunque ahora los datos viven en una misma DB fisica, no deben convertirse en
  foreign keys reales hacia `patient` o `schedule`.
- Preservar el indice unico parcial:

```sql
CREATE UNIQUE INDEX uq_appointment_slot_active
    ON appointments(slot_id)
    WHERE appointment_status IN ('PENDING_PAYMENT', 'CONFIRMED');
```

- Preservar el indice unico parcial de holds activos:

```sql
CREATE UNIQUE INDEX uq_holds_one_active_per_slot
    ON appointment_holds(slot_id)
    WHERE hold_status = 'ACTIVE';
```

- Preservar triggers de auditoria inmutable.
- Preservar el outbox pattern para publicar eventos por RabbitMQ.

Validaciones especificas:

- Crear cita con hold activo.
- Intentar reservar el mismo slot dos veces y confirmar rechazo por indice
  unico.
- Confirmar que la auditoria no permite update/delete.
- Confirmar que el outbox publica eventos correctamente.
- Confirmar que `appointment.flyway_schema_history` existe y es independiente.

### 5.4 payment-service

Schema asignado:

```text
payment
```

Responsabilidad:

- Procesar pagos.
- Mantener idempotencia de pagos.
- Evitar doble pago aprobado por cita.
- Publicar eventos de pago mediante outbox.
- Soportar multiples replicas de `payment-service`.

Cambios requeridos:

- Cambiar la conexion a:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment
```

- Configurar Flyway:

```yaml
spring:
  flyway:
    schemas: payment
    default-schema: payment
```

- Migrar estas tablas al schema `payment`:
  - `payments`
  - `payment_idempotency`
  - `payment_events_outbox`
- Revisar que los enums `payment_status`, `idempotency_status` y
  `outbox_publication_status` vivan dentro del schema `payment`.
- Preservar el indice unico parcial:

```sql
CREATE UNIQUE INDEX uq_payments_appointment_approved
    ON payments(appointment_id)
    WHERE payment_status = 'APPROVED';
```

- Preservar el uso de `FOR UPDATE SKIP LOCKED` en el repositorio del outbox para
  que varias replicas no publiquen el mismo evento pendiente.
- No agregar foreign key real desde `payment.payments.appointment_id` hacia
  `appointment.appointments`.

Validaciones especificas:

- Crear pago.
- Repetir request con la misma idempotency key y confirmar que no se duplica.
- Intentar aprobar dos pagos para la misma cita y confirmar rechazo.
- Levantar varias replicas de `payment-service` y validar que el outbox no
  duplica publicaciones.
- Confirmar que `payment.flyway_schema_history` existe y es independiente.

### 5.5 notification-service

Schema asignado:

```text
notification
```

Responsabilidad:

- Consumir eventos desde RabbitMQ.
- Registrar notificaciones.
- Deduplicar eventos consumidos.
- Mantener trazabilidad de origen de eventos.

Cambios requeridos:

- Cambiar la conexion a:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=notification
```

- Configurar Flyway:

```yaml
spring:
  flyway:
    schemas: notification
    default-schema: notification
```

- Migrar la tabla `notifications` al schema `notification`.
- Revisar que los enums `notification_status` y `notification_channel` vivan
  dentro del schema `notification`.
- Preservar el indice unico parcial de deduplicacion:

```sql
CREATE UNIQUE INDEX uq_notifications_event_key
    ON notifications(event_key)
    WHERE event_key IS NOT NULL;
```

- No consultar directamente datos de `appointment`, `patient` o `payment`.
- Mantener RabbitMQ como fuente de eventos.

Validaciones especificas:

- Consumir evento de cita o pago.
- Crear notificacion.
- Reentregar el mismo evento y confirmar que no crea duplicados.
- Confirmar que `notification.flyway_schema_history` existe y es independiente.

## 6. Cambios de Infraestructura Requeridos

### 6.1 Inicializacion de base y schemas

El archivo `infra/docker/init-dbs.sql` debe dejar de crear cinco bases logicas y
pasar a crear una sola:

```sql
CREATE DATABASE mediqueue;
```

Dentro de `mediqueue`, deben existir los schemas:

```sql
CREATE SCHEMA IF NOT EXISTS patient AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS schedule AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS appointment AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS payment AUTHORIZATION mediqueue;
CREATE SCHEMA IF NOT EXISTS notification AUTHORIZATION mediqueue;
```

Tambien debe habilitarse la extension requerida:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

Nota: en PostgreSQL, `CREATE DATABASE` y la creacion de schemas dentro de esa DB
requieren cuidado porque se ejecutan en contextos distintos. Si se mantiene el
script de inicializacion de Docker, se recomienda separar la creacion de la DB y
la inicializacion interna de schemas, o usar un script shell de bootstrap que
ejecute `psql` contra `mediqueue`.

### 6.2 Stack PostgreSQL HA

La infraestructura objetivo debe reemplazar el PostgreSQL simple por:

```text
postgres-lb
    |
    +--> postgres-1 / Patroni
    +--> postgres-2 / Patroni
    +--> postgres-3 / Patroni

Patroni --> etcd o Consul
```

Responsabilidades:

- Patroni controla cual nodo es primary.
- Patroni promueve una replica cuando el primary cae.
- HAProxy detecta el primary actual y enruta escrituras.
- Los microservicios solo conocen `postgres-lb`.

El compose o manifiesto de despliegue debe incluir:

- Tres nodos PostgreSQL con Patroni.
- Tres nodos etcd o un servicio Consul, segun la herramienta elegida.
- HAProxy para PostgreSQL.
- Volumen persistente por nodo PostgreSQL.
- Healthchecks para Patroni y HAProxy.

### 6.3 Variables de entorno

Actualizar `.env.example`:

```text
DB_NAME=mediqueue
DB_USERNAME=mediqueue
DB_PASSWORD=mediqueue
DB_HOST=postgres-lb
DB_PORT=5432
```

Cada servicio puede construir su URL con esas variables o recibir la URL final
por variable especifica.

### 6.4 Backups

Backup logico minimo:

```bash
pg_dump -h postgres-lb -p 5432 -U mediqueue -d mediqueue -Fc -f mediqueue.dump
```

Restore logico:

```bash
createdb -h postgres-lb -p 5432 -U mediqueue mediqueue_restore
pg_restore -h postgres-lb -p 5432 -U mediqueue -d mediqueue_restore mediqueue.dump
```

Para produccion, el backup recomendado debe incluir:

- Backups fisicos.
- Archivado de WAL.
- Retencion definida.
- Pruebas periodicas de restore.
- Herramienta dedicada como Barman, WAL-G o servicio administrado equivalente.

## 7. Switchover y Failover

### 7.1 Switchover manual

Un switchover es una promocion controlada de una replica para convertirla en el
nuevo primary. Debe usarse para mantenimiento planeado.

Flujo esperado:

1. Confirmar que todas las replicas estan sanas.
2. Ejecutar switchover desde Patroni.
3. Verificar que HAProxy detecta el nuevo primary.
4. Confirmar que los microservicios reconectan usando `postgres-lb`.
5. Ejecutar pruebas de escritura.

### 7.2 Failover automatico

Un failover ocurre cuando el primary cae inesperadamente.

Flujo esperado:

1. Patroni detecta perdida del primary.
2. Patroni promueve una replica sana.
3. HAProxy enruta escrituras al nuevo primary.
4. Las conexiones activas pueden fallar temporalmente.
5. Los pools JDBC deben reconectar automaticamente.

Recomendaciones para los microservicios:

- Mantener timeouts razonables en HikariCP.
- Permitir reconexion por pool.
- No cachear conexiones manualmente.
- Asegurar idempotencia en operaciones criticas, especialmente citas y pagos.

## 8. Plan de Migracion

### Fase 1: Preparacion

- Congelar el modelo objetivo: una DB `mediqueue` y schemas por servicio.
- Definir stack HA: Patroni + etcd/Consul + HAProxy.
- Crear ambiente de prueba limpio.
- Documentar rollback.

### Fase 2: Infraestructura base

- Crear `mediqueue`.
- Crear schemas por servicio.
- Configurar permisos.
- Levantar Patroni y HAProxy.
- Validar endpoint `postgres-lb`.

### Fase 3: Ajuste de servicios

- Actualizar variables de conexion por microservicio.
- Agregar configuracion Flyway por schema.
- Revisar migraciones SQL para evitar referencias implicitas a `public`.
- Validar que cada servicio migra solo su schema.

### Fase 4: Pruebas funcionales

- Ejecutar healthchecks.
- Ejecutar flujo E2E completo.
- Validar idempotencia y outbox.
- Validar deduplicacion de notificaciones.

### Fase 5: Pruebas HA

- Apagar una replica PostgreSQL.
- Ejecutar switchover manual.
- Simular caida del primary.
- Confirmar continuidad despues de reconexion.

### Fase 6: Backups y restore

- Ejecutar backup completo.
- Restaurar en ambiente limpio.
- Validar tablas, schemas, indices y datos.

## 9. Plan de Validacion General

Validar estructura de schemas:

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('patient', 'schedule', 'appointment', 'payment', 'notification');
```

Validar historial Flyway por schema:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name = 'flyway_schema_history'
ORDER BY table_schema;
```

Validar tablas principales:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('patient', 'schedule', 'appointment', 'payment', 'notification')
ORDER BY table_schema, table_name;
```

Validar salud de microservicios:

```http
GET http://localhost:8080/actuator/health
GET http://localhost:8081/actuator/health
GET http://localhost:8082/actuator/health
GET http://localhost:8083/actuator/health
GET http://localhost:8084/actuator/health
GET http://localhost:8085/actuator/health
```

Validar flujo E2E:

1. Crear paciente.
2. Crear odontologo.
3. Crear horario y slot.
4. Crear cita.
5. Procesar pago.
6. Confirmar publicacion de eventos.
7. Confirmar notificacion.

Validar HA:

1. Confirmar primary actual.
2. Ejecutar switchover.
3. Crear registros despues del switchover.
4. Simular caida del primary.
5. Confirmar promocion automatica.
6. Confirmar que los servicios vuelven a operar por `postgres-lb`.

## 10. Riesgos y Consideraciones

- Una sola base logica simplifica backups, pero concentra el impacto operativo:
  si el cluster PostgreSQL falla completo, todos los servicios quedan afectados.
- Separar por schemas reduce choques de nombres y mantiene ownership, pero no
  reemplaza una disciplina de limites entre microservicios.
- No deben agregarse joins directos entre schemas solo porque ahora estan en la
  misma DB.
- Las migraciones Flyway deben quedar aisladas por schema para evitar conflictos
  de version.
- El failover puede cortar conexiones activas; los servicios deben tolerar
  reconexion.
- Backups sin pruebas de restore no son suficientes.

## 11. Criterios de Aceptacion

La unificacion estara lista cuando:

- Exista una sola DB logica `mediqueue`.
- Cada microservicio opere en su schema asignado.
- Cada schema tenga su propio `flyway_schema_history`.
- Todas las migraciones corran sin conflictos.
- El flujo E2E paciente-agenda-cita-pago-notificacion funcione.
- `payment-service` mantenga idempotencia y outbox correcto con multiples
  replicas.
- `appointment-service` siga evitando doble reserva de slots.
- `notification-service` siga deduplicando eventos.
- Los servicios se conecten solamente a `postgres-lb`.
- Se haya probado switchover manual.
- Se haya probado failover automatico.
- Se haya probado backup y restore.

