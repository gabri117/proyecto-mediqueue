# MediQueue Block 2 - Appointment Load Tests

Official k6 suite for appointment creation through the API Gateway.

Target clarification:

- `50,000 citas totales` means a fixed total of 50,000 appointment attempts, regardless of elapsed time.
- `50,000 citas por minuto` means 50,000 appointment attempts in 1 minute.
- `50,000/min` equals approximately `833.33 req/s`.

## Endpoint Contract

```http
POST http://localhost:8080/api/appointments
Content-Type: application/json
Accept: application/json
X-Idempotency-Key: <unique-key>
X-Client-Id: <client-id>
```

Payload:

```json
{
  "patientId": "uuid",
  "dentistId": "uuid",
  "slotId": "uuid",
  "appointmentDate": "2026-07-01",
  "startTime": "08:00:00",
  "endTime": "08:30:00",
  "amount": 150.00,
  "notes": "Block 2 load test"
}
```

`amount` is required. Each successful appointment needs a unique `slotId`.

## Scripts

- `scripts/appointment-smoke.js`: validates the contract with a small dataset.
- `scripts/appointment-fixed-total.js`: creates a fixed number of attempts, for example 1,000, 10,000, or 50,000 total.
- `scripts/appointment-rpm.js`: drives an arrival rate, including 50,000/min.
- `scripts/appointment-hostile-same-slot.js`: intentionally reuses one slot to prove the backend prevents double reservation.

## Dataset

The generator does not invent UUIDs. It reads real available slots from:

```http
GET /api/slots/available
```

Because there is no patient list endpoint, pass real patient IDs with `-PatientIds` or `-PatientIdsFile`.

Generate sample:

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -Total 10 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -OutputFile .\infra\load-tests\appointments\data\appointments.sample.json `
  -Amount 150.00
```

Generate official datasets:

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -Total 1000 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -OutputFile .\infra\load-tests\appointments\data\appointments-1000.json
```

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -Total 10000 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -OutputFile .\infra\load-tests\appointments\data\appointments-10000.json
```

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -Total 50000 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -OutputFile .\infra\load-tests\appointments\data\appointments-50000.json
```

If there are not enough unique slots, the generator stops with:

```text
No hay suficientes slots unicos para generar N citas. Ejecuta primero el seed.
```

## Run Smoke

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments.sample.json"
$env:TOTAL_APPOINTMENTS="10"
$env:VUS="5"
k6 run .\infra\load-tests\appointments\scripts\appointment-smoke.js --summary-export .\infra\load-tests\appointments\results\appointment-smoke-summary.json
```

## Run Fixed Total

Use this when the requirement is a total number of appointment attempts.

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-50000.json"
$env:TOTAL_APPOINTMENTS="50000"
$env:VUS="200"
$env:MAX_DURATION="10m"
$env:CLIENT_MODE="per-iteration"
k6 run .\infra\load-tests\appointments\scripts\appointment-fixed-total.js --summary-export .\infra\load-tests\appointments\results\appointment-fixed-50000-summary.json
```

## Run 50,000/min

Use this when the requirement is appointment attempts per minute. `RATE_PER_MINUTE=50000` means about `833.33 req/s`.

Small run:

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-1000.json"
$env:RATE_PER_MINUTE="1000"
$env:DURATION="1m"
$env:PRE_ALLOCATED_VUS="100"
$env:MAX_VUS="300"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-1000-summary.json
```

Strong run:

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-50000.json"
$env:RATE_PER_MINUTE="50000"
$env:DURATION="1m"
$env:PRE_ALLOCATED_VUS="1000"
$env:MAX_VUS="3000"
$env:CLIENT_MODE="per-iteration"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json
```

## Hostile Same Slot

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments.sample.json"
$env:TOTAL_ATTEMPTS="1000"
$env:VUS="500"
$env:SAME_SLOT_INDEX="0"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-hostile-same-slot.js --summary-export .\infra\load-tests\appointments\results\appointment-hostile-same-slot-summary.json
```

In this test, many `409 Conflict` responses are desired. They show that the backend blocks double reservation of the same slot under concurrency.

## Client IDs

`CLIENT_MODE` controls `X-Client-Id`:

- `per-vu`: one client ID per VU.
- `single`: one client ID for all requests.
- `per-iteration`: one client ID per request.

If many `429` responses appear, the run is measuring gateway rate limiting instead of backend capacity.

## Response Interpretation

- `200/201/202`: appointment creation accepted by the API.
- `409`: slot conflict, duplicate `slotId`, or dataset already consumed. This is expected only in hostile same-slot tests.
- `400/422`: invalid payload, missing `amount`, stale IDs, or contract mismatch.
- `429`: gateway rate limit.
- `5xx`: real gateway/backend/server error.

If `dropped_iterations` appears in k6 output, k6 could not maintain the requested arrival rate. Increase VUs or investigate slow backend responses.

## Prometheus Remote Write

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-50000.json"
$env:RATE_PER_MINUTE="50000"
$env:DURATION="1m"
$env:PRE_ALLOCATED_VUS="1000"
$env:MAX_VUS="3000"
$env:CLIENT_MODE="per-iteration"
k6 run -o experimental-prometheus-rw .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json
```

Do not set `K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM` with the current Prometheus setup. The existing Prometheus/Grafana configuration expects standard k6 remote-write series such as `k6_http_req_duration_p95`, not native histogram storage/query behavior.

## Dashboard

Import:

```text
infra/load-tests/appointments/dashboards/mediqueue-appointment-load-dashboard.json
```

The dashboard focuses on k6 appointment metrics, gateway HTTP status, appointment-service latency, RabbitMQ queue depth, and Redis command rate.

## Evidence Checklist

- Dataset file used for the run.
- k6 command and env vars.
- k6 `--summary-export` JSON.
- Screenshot/export of the appointment load dashboard.
- Counts for created, conflict, validation error, rate limited, server error, unexpected error, and dataset exhausted.
- Evidence that `dropped_iterations` is zero or an explanation if it is not.
- Gateway, appointment-service, RabbitMQ, Redis, PostgreSQL, payment-service, and notification-service observations during the run.

## Local Environment Risks

- 50,000/min can saturate a laptop before it measures backend capacity.
- Gateway rate limiting can dominate results unless `CLIENT_MODE` and gateway env vars are chosen intentionally.
- Reusing a dataset after successful creation will produce `409` because slots were consumed.
- RabbitMQ/payment/notification work is asynchronous; appointment `201` only proves appointment-service accepted creation.
- Container CPU, memory, disk I/O, and PostgreSQL connection limits can produce bottlenecks unrelated to business logic.
