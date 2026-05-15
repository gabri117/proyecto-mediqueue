# MediQueue Load Tests

Suite secuencial de k6 para ejecutar pruebas de carga por el `api-gateway-lb`, similar a un Runner de Postman. Todos los scripts usan `BASE_URL` y por defecto apuntan a `http://localhost:8080`.

## Prerrequisitos

- Docker Desktop con Docker Compose.
- k6 local opcional. Si no esta instalado, usa el servicio Docker con profile `loadtest`.
- Stack local levantado con gateway x2 y payment x3:

```powershell
docker compose up -d --build --scale api-gateway=2 --scale payment-service=3
docker compose ps
curl http://localhost:8080/actuator/health
curl http://localhost:9090/-/ready
```

Prometheus: `http://localhost:9090/targets`
Grafana: `http://localhost:3000` (`admin` / `admin`, salvo variables de entorno).

## Rutas Auditadas

Todas las pruebas pasan por el gateway:

- `GET /actuator/health`
- `POST /api/patients`, `GET /api/patients/{id}`, `GET /api/patients?email=...`
- `POST /api/dentists`, `GET /api/dentists/{id}`, `GET /api/dentists?email=...`
- `POST /api/slots`, `GET /api/slots/{id}`, `GET /api/slots/dentist/{dentistId}`, `GET /api/slots/available`
- `POST /api/appointments` con `X-Idempotency-Key`, `GET /api/appointments/{id}`, `GET /api/appointments?patientId=...`
- `POST /api/payments` con `X-Idempotency-Key`, `GET /api/payments`, `GET /api/payments/{id}`
- `GET /api/notifications`, `GET /api/notifications/{id}`, `GET /api/notifications/patient/{patientId}`

No existe endpoint de listado general para pacientes ni citas. No se debe crear `POST /api/notifications`: las notificaciones nacen por eventos RabbitMQ.

## Scripts

- `scripts/00-smoke.js`: salud, pagos, notificaciones y slots disponibles.
- `scripts/01-patient-load.js`: crea pacientes unicos y consulta por email.
- `scripts/02-schedule-load.js`: consulta slots por `DENTIST_ID` o descubre uno desde `/api/slots/available`.
- `scripts/03-payment-load.js`: crea pagos con `X-Idempotency-Key`; prueba de idempotencia opcional con `INCLUDE_PAYMENT_IDEMPOTENCY=true`.
- `scripts/04-notification-load.js`: solo consultas.
- `scripts/05-appointment-hostile.js`: opcional, muchos VUs contra el mismo slot.
- `scripts/06-e2e-flow.js`: opcional y deshabilitado por defecto hasta corregir `AppointmentHeld.amount`.
- `scripts/07-gateway-rate-limit.js`: opcional, valida rate limiting del gateway; `429` es esperado.

## Perfiles de Carga

La suite separa tres perfiles para evitar mezclar comportamiento de negocio con rendimiento tecnico:

- `realistic`: usa el simulador real de payment. Con `PAYMENT_SIM_MAX_DELAY_MS=8000`, el threshold de payment es `p95<9000ms` y `p99<11000ms`.
- `performance`: pensado para medir rendimiento tecnico con latencias artificiales bajas. Debe ejecutarse con `PAYMENT_SIM_MIN_DELAY_MS=50` y `PAYMENT_SIM_MAX_DELAY_MS=500`.
- `smoke`: ejecucion corta, pocos VUs y thresholds estrictos pero razonables.

`03-payment-load.js` falla si se exige `p95<2000ms` mientras `PAYMENT_SIM_MAX_DELAY_MS=8000`, porque el propio negocio simula pagos que pueden tardar hasta 8 segundos. Eso no implica necesariamente error de backend; significa que ese threshold pertenece al perfil `performance`, no al perfil `realistic`.

Thresholds de payment:

| Perfil | http_req_failed | p95 | p99 |
|--------|-----------------|-----|-----|
| `realistic` | `< 5%` | `< 9000ms` | `< 11000ms` |
| `performance` | `< 5%` | `< 2000ms` | `< 4000ms` |
| `smoke` | `< 1%` | `< 3000ms` | `< 5000ms` |

## Ejecucion Local

Smoke:

```powershell
k6 run infra/load-tests/scripts/00-smoke.js
```

Runner secuencial normal:

```powershell
.\infra\load-tests\run-sequential.ps1 -Profile realistic
```

Con profile corto:

```powershell
.\infra\load-tests\run-sequential.ps1 -Profile smoke
```

Con prueba hostil:

```powershell
.\infra\load-tests\run-sequential.ps1 -IncludeHostile -PatientId "..." -DentistId "..." -SlotId "..."
```

Con k6 remote write hacia Prometheus:

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
.\infra\load-tests\run-sequential.ps1 -K6OutputPrometheus
```

El runner se detiene si falla smoke. En fases posteriores se detiene al primer error salvo que uses `-ContinueOnError`.

## Ejecucion con Docker k6

El servicio `k6` usa profile `loadtest`; no se ejecuta con `docker compose up` normal.

```powershell
docker compose --profile loadtest run --rm k6 run /scripts/scripts/00-smoke.js
```

Runner PowerShell usando Docker k6:

```powershell
.\infra\load-tests\run-sequential.ps1 -UseDockerK6 -Profile realistic
```

Runner PowerShell usando Docker k6 con perfil performance:

```powershell
.\infra\load-tests\run-sequential.ps1 -UseDockerK6 -Profile performance
```

Prueba opcional de rate limiting:

```powershell
.\infra\load-tests\run-sequential.ps1 -UseDockerK6 -Profile realistic -IncludeRateLimit
```

Para ejecutar contra el gateway dentro de la red Docker:

```powershell
docker compose --profile loadtest run --rm -e BASE_URL=http://api-gateway-lb:8080 k6 run /scripts/scripts/00-smoke.js
```

## Variables

- `BASE_URL`: default `http://localhost:8080`; en Docker usa `http://api-gateway-lb:8080`.
- `LOAD_PROFILE`: `realistic`, `performance` o `smoke`; default `realistic`.
- `DENTIST_ID`, `DATE`: schedule load.
- `PATIENT_ID`, `APPOINTMENT_ID`: filtros e integraciones.
- `SLOT_ID`, `START_TIME`, `END_TIME`: appointment hostile.
- `INCLUDE_PAYMENT_IDEMPOTENCY=true`: subescenario controlado de idempotencia de pagos.
- `ALLOW_E2E=true`: requerido por `06-e2e-flow.js`.
- `RESULTS_DIR`: default `infra/load-tests/results`; en Docker `/scripts/results`.

## Stack Performance

Stack normal:

```powershell
docker compose up -d --build --scale api-gateway=2 --scale payment-service=3
```

Stack performance con override no invasivo:

```powershell
docker compose -f docker-compose.yml -f docker-compose.loadtest-performance.yml up -d --build --scale api-gateway=2 --scale payment-service=3
```

El override baja latencias artificiales de payment:

- `PAYMENT_SIM_MIN_DELAY_MS=50`
- `PAYMENT_SIM_MAX_DELAY_MS=500`
- `PAYMENT_TIMEOUT_SECONDS=5`

Tambien sube los limites configurables de payment en el gateway con `RATE_LIMIT_PAYMENT_REPLENISH` y `RATE_LIMIT_PAYMENT_BURST` para que una prueba tecnica de payment no mida principalmente rate limiting.

## Interpretacion

- `2xx`: respuesta exitosa.
- `409`: conflicto controlado, esperado en idempotencia o doble pago/cita segun escenario.
- `422`: validacion de negocio, usado solo en pruebas hostiles de citas.
- `429`: rate limiting del gateway. No es error de backend, pero debe reportarse y analizarse.
- `5xx`: error de backend/gateway; no debe aceptarse como exito.
- `p95/p99`: percentiles de latencia. En payment realistic incluyen la demora artificial del simulador.

## Prometheus y Grafana

Prometheus scrapea:

- `api-gateway-lb`
- replicas `api-gateway` por `dns_sd_configs`
- `payment-lb`
- replicas `payment-service` por `dns_sd_configs`
- `patient-service`
- `schedule-service`
- `appointment-service`
- `notification-service`
- `rabbitmq`

No se agregan exporters de PostgreSQL ni Redis. Si no existen exporters, no hay targets para ellos.

Dashboard provisionado: `MediQueue - Load Testing Overview`.

Si un panel no muestra `application`, revisa `job` o `instance`: los servicios fueron configurados con `management.metrics.tags.application`, pero los balanceadores no agregan ese tag.

## Resultados

Cada script exporta resumen JSON y TXT con `handleSummary` a `infra/load-tests/results` cuando k6 tiene permisos de escritura. Si tu runtime no permite escribir archivos, usa:

```powershell
k6 run --summary-export infra/load-tests/results/smoke-summary.json infra/load-tests/scripts/00-smoke.js
```

## Consultas DBeaver

Usa `queries/validation.sql`. La verificacion critica posterior a `05-appointment-hostile.js` es:

```sql
SELECT slot_id, COUNT(*)
FROM appointments
WHERE appointment_status IN ('PENDING_PAYMENT', 'CONFIRMED')
GROUP BY slot_id
HAVING COUNT(*) > 1;
```

Resultado esperado: `0 filas` en `mediqueue_appointments`.

## Criterios de Exito

- `docker compose config` valida sin errores.
- `api-gateway-lb` queda accesible en `localhost:8080`.
- `payment-lb` queda accesible en `localhost:8083`.
- Prometheus muestra UP para gateway, payment, patient, schedule, appointment, notification y RabbitMQ.
- `00-smoke.js` pasa antes de correr carga.
- En carga normal no hay HTTP 500 aceptados.
- La consulta de doble reserva devuelve 0 filas.

## E2E Pendiente

`06-e2e-flow.js` existe pero no corre por defecto. Ejecutalo solo cuando este corregido el pendiente conocido donde `AppointmentHeld` puede no incluir `amount` valido y `payment-service` registra `Invalid AppointmentHeld amount`.

El flujo E2E crea paciente, crea dentista/slot si no se proveen IDs, crea cita, crea pago manual por `/api/payments` y consulta notificaciones. No exige 100% de notificaciones porque `PAYMENT_SIM_APPROVAL_RATE` puede producir aprobados o rechazados.

## Evidencias

Para entregar evidencia:

```powershell
docker compose ps
curl http://localhost:9090/-/ready
k6 run infra/load-tests/scripts/00-smoke.js
.\infra\load-tests\run-sequential.ps1
```

Captura:

- Prometheus `http://localhost:9090/targets`.
- Grafana dashboard `MediQueue - Load Testing Overview`.
- Archivos de `infra/load-tests/results`.
- Resultados de `queries/validation.sql`.
