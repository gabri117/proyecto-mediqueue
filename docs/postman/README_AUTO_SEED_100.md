# MediQueue Auto Seed 100

Coleccion Postman automatica para poblar MediQueue con datos sinteticos a traves del API Gateway (`http://localhost:8080`).

No usa CSV externo, no requiere ingresar datos manualmente y no crea notificaciones manualmente. Las notificaciones se validan por lectura porque deben generarse por eventos RabbitMQ emitidos por citas y pagos.

## Archivos

- `docs/postman/MediQueue_Auto_Seed_100.postman_collection.json`
- `docs/postman/run-auto-seed-and-redis-check.ps1`
- `docs/postman/output/` para evidencias generadas por el script

## Rutas reales detectadas

Via API Gateway se usan estas rutas:

- `GET /actuator/health`
- `POST /api/patients`
- `GET /api/patients/{id}`
- `POST /api/dentists`
- `GET /api/dentists?email=...`
- `POST /api/slots`
- `GET /api/slots/available`
- `POST /api/appointments`
- `GET /api/appointments?patientId=...`
- `POST /api/payments`
- `GET /api/payments?page=0&size=20`
- `GET /api/notifications?page=0&size=20`
- `GET /api/notifications/patient/{patientId}?page=0&size=20`

No se detecto endpoint paginado para pacientes, dentistas o appointments generales. Por eso la verificacion usa endpoints reales disponibles: paciente por ID, dentista por email, slots disponibles y appointments por patientId.

## DTOs usados

### PatientRequest

```json
{
  "firstName": "Patient1",
  "lastName": "AutoSeed",
  "email": "patient1.<runStamp>@mediqueue.test",
  "phone": "+50255550001",
  "documentNumber": "PAT-<runStamp>-0001"
}
```

Respuesta esperada: `patientId`.

### DentistRequest

```json
{
  "firstName": "Dentist1",
  "lastName": "AutoSeed",
  "specialty": "Odontologia General",
  "email": "dentist1.<runStamp>@mediqueue.test",
  "licenseNumber": "DEN-<runStamp>-001"
}
```

Respuesta esperada: `dentistId`.

### DentistSlotRequest

```json
{
  "dentistId": "<uuid>",
  "slotDate": "2026-07-01",
  "startTime": "08:00:00",
  "endTime": "08:30:00"
}
```

Respuesta esperada: `slotId`.

### AppointmentRequest

Requiere header `X-Idempotency-Key`.

```json
{
  "patientId": "<uuid>",
  "dentistId": "<uuid>",
  "slotId": "<uuid>",
  "appointmentDate": "2026-07-01",
  "startTime": "08:00:00",
  "endTime": "08:30:00",
  "amount": 150.00,
  "notes": "Auto seed appointment 1"
}
```

Respuesta esperada: `appointmentId`.

### PaymentRequest

Requiere header `X-Idempotency-Key`.

```json
{
  "appointmentId": "<uuid>",
  "patientId": "<uuid>",
  "amount": 150.00,
  "currency": "GTQ"
}
```

Respuesta esperada: `paymentId` cuando el pago se crea. Un `409` se trata como respuesta de negocio controlada porque puede existir un pago aprobado creado por el flujo automatico de eventos.

## Variables internas de la coleccion

La coleccion inicializa automaticamente:

- `baseUrl = http://localhost:8080`
- `runStamp = Date.now()`
- indices `patientIndex`, `dentistIndex`, `slotIndex`, `appointmentIndex`, `paymentIndex`
- totales `totalPatients=100`, `totalDentists=20`, `totalSlots=100`, `totalAppointments=100`, `totalPayments=100`
- arrays `patientIds`, `dentistIds`, `slotIds`, `slotPayloads`, `appointmentIds`, `paymentIds`
- `amount=150.00`
- `currency=GTQ`
- `clientId=postman-auto-seed-100`

## Ejecutar en Postman con un solo Run

1. Importa `docs/postman/MediQueue_Auto_Seed_100.postman_collection.json`.
2. Abre Collection Runner.
3. Selecciona `MediQueue Auto Seed 100`.
4. Iterations: `1`.
5. No selecciones CSV.
6. Ejecuta desde el primer request.
7. Espera a que termine.

La coleccion usa `postman.setNextRequest()` para repetir automaticamente:

1. 100 pacientes
2. 20 dentistas
3. 100 slots
4. 100 citas
5. 100 intentos de pago
6. espera async
7. verificaciones de lectura
8. instrucciones de evidencia Redis

## Ejecutar con Newman

Instalar Newman:

```powershell
npm install -g newman
```

Ejecutar:

```powershell
newman run docs/postman/MediQueue_Auto_Seed_100.postman_collection.json
```

Con reporte JSON:

```powershell
newman run docs/postman/MediQueue_Auto_Seed_100.postman_collection.json --reporters cli,json --reporter-json-export docs/postman/output/seed-100-report.json
```

Tambien puedes usar el script incluido:

```powershell
.\docs\postman\run-auto-seed-and-redis-check.ps1
```

## Redis esperado

Redis no necesariamente guarda el objeto completo de paciente o slot. En este proyecto se detecto Spring Cache en appointment-service:

- cache `patients`, TTL aproximado 300s
- cache `slots`, TTL aproximado 60s

Las keys pueden verse como `patients::<patientId>` y `slots::<slotId>` segun el serializer/prefix de Spring Cache. El API Gateway tambien usa Redis para rate limiting, por lo que puede crear keys temporales de contador/tokens y scripts Lua.

Comandos utiles:

```powershell
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli DBSIZE
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli INFO keyspace
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli --scan
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli --scan --pattern "patients::*"
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli --scan --pattern "slots::*"
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli --scan --pattern "*request*"
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli INFO stats
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli INFO stats | findstr "total_commands_processed keyspace_hits keyspace_misses total_error_replies"
```

Ver tipo, TTL, valor y memoria de una key:

```powershell
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli TYPE "KEY"
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli TTL "KEY"
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli --raw GET "KEY"
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli MEMORY USAGE "KEY"
```

Para ver trafico en vivo:

```powershell
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli MONITOR
```

Usa `MONITOR` solo unos segundos porque genera mucho ruido.

## SQL para validar en DBeaver

Pacientes:

```sql
SELECT COUNT(*) FROM patient.patients;
```

Dentistas:

```sql
SELECT COUNT(*) FROM schedule.dentists;
```

Slots:

```sql
SELECT COUNT(*) FROM schedule.dentist_slots;
```

Appointments:

```sql
SELECT appointment_status, COUNT(*)
FROM appointment.appointments
GROUP BY appointment_status
ORDER BY appointment_status;
```

Payments:

```sql
SELECT payment_status, COUNT(*)
FROM payment.payments
GROUP BY payment_status
ORDER BY payment_status;
```

No doble pago aprobado:

```sql
SELECT appointment_id, COUNT(*) AS approved_count
FROM payment.payments
WHERE payment_status = 'APPROVED'
GROUP BY appointment_id
HAVING COUNT(*) > 1;
```

Notifications:

```sql
SELECT notification_status, event_type, COUNT(*)
FROM notification.notifications
GROUP BY notification_status, event_type
ORDER BY notification_status, event_type;
```

Notificaciones por paciente:

```sql
SELECT patient_id, COUNT(*)
FROM notification.notifications
GROUP BY patient_id
ORDER BY COUNT(*) DESC;
```

## Interpretacion esperada

- 100 pacientes creados.
- 20 dentistas creados.
- 100 slots creados.
- 100 citas creadas o detenidas si una regla critica falla.
- 100 pagos intentados; `409` se registra como controlado si ya existe pago aprobado.
- No debe haber `503`.
- No debe haber `RedisConnectionFailureException` en respuestas.
- Notificaciones aparecen si RabbitMQ y notification-service procesan los eventos.
- Si no aparecen 100 notificaciones, no necesariamente fallo la coleccion: depende de pagos aprobados/rechazados, eventos publicados y consumidores async.
- Redis debe mostrar actividad: `DBSIZE > 0` si aun no expiraron TTLs, `INFO stats` con `total_commands_processed` subiendo, posibles keys `patients::*`, `slots::*` y keys temporales del rate limiter.

## Limitaciones conocidas

- Patients y dentists no tienen endpoint paginado real; se verifican por ID/email.
- Appointments no tiene endpoint paginado general; se verifica por `patientId`.
- Slots `available` puede no listar los slots si algun flujo los marca o si el criterio de disponibilidad cambia.
- Los pagos pueden ser aprobados, rechazados o timeouts segun el simulador; las notificaciones dependen de esos eventos.
- Las keys Redis de cache tienen TTL corto, especialmente `slots` con 60s; ejecuta las evidencias justo al terminar.
