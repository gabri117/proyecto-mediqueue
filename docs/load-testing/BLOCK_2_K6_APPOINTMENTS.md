# Block 2 - k6 Appointments

This is the delivery flow for MediQueue appointment load testing.

The target is **50,000 appointments per minute**, not 50,000 per second. That is approximately **833.33 requests per second**.

## Scope

Endpoint:

```http
POST http://localhost:8080/api/appointments
```

Required payload fields:

- `patientId`
- `dentistId`
- `slotId`
- `appointmentDate`
- `startTime`
- `endTime`
- `amount`
- `notes`

For successful creation tests, every row must use a unique `slotId`. Patients and dentists may be reused.

## Data Preparation

Start stack:

```powershell
docker compose up -d --build
```

Prepare real API data:

```powershell
.\infra\load-tests\appointments\tools\prepare-appointment-load-data.ps1 `
  -BaseUrl http://localhost:8080 `
  -TotalPatients 100 `
  -TotalDentists 20 `
  -TotalSlots 50000 `
  -Amount 150.00
```

Outputs:

- `infra/load-tests/appointments/data/patient-ids.json`
- `infra/load-tests/appointments/data/dentist-ids.json`
- `infra/load-tests/appointments/data/available-slots.json`
- `infra/load-tests/appointments/data/appointments.sample.json`
- `infra/load-tests/appointments/data/appointments-1000.json`
- `infra/load-tests/appointments/data/appointments-10000.json`
- `infra/load-tests/appointments/data/appointments-50000.json`

Alternative dataset regeneration:

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -AvailableSlotsFile .\infra\load-tests\appointments\data\available-slots.json `
  -Totals 10,1000,10000,50000 `
  -OutputDir .\infra\load-tests\appointments\data `
  -Amount 150.00
```

## Test Commands

Smoke:

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments.sample.json"
$env:TOTAL_APPOINTMENTS="10"
$env:VUS="5"
k6 run .\infra\load-tests\appointments\scripts\appointment-smoke.js --summary-export .\infra\load-tests\appointments\results\appointment-smoke-summary.json
```

1,000/min:

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="../data/appointments-10000.json"
$env:RATE_PER_MINUTE="1000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="1000"
$env:DATA_OFFSET="1000"
$env:PRE_ALLOCATED_VUS="100"
$env:MAX_VUS="300"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-1000-offset-1000-summary.json
```

10,000/min:

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-10000.json"
$env:RATE_PER_MINUTE="10000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="10000"
$env:DATA_OFFSET="0"
$env:PRE_ALLOCATED_VUS="300"
$env:MAX_VUS="1000"
$env:CLIENT_MODE="per-iteration"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-10000-summary.json
```

50,000/min:

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-50000.json"
$env:RATE_PER_MINUTE="50000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="50000"
$env:DATA_OFFSET="0"
$env:PRE_ALLOCATED_VUS="1000"
$env:MAX_VUS="3000"
$env:CLIENT_MODE="per-iteration"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json
```

Use `TOTAL_LIMIT` to define how many real HTTP requests should be sent. If k6 schedules an extra boundary iteration, the script increments `appointments_skipped_after_limit` and sends no request. Use `DATA_OFFSET` to choose a different dataset range and avoid reusing previously consumed slots.

For the official 50,000/min run, use a clean or freshly generated dataset. Reused slots should produce `409 Conflict`.

Prometheus:

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
k6 run -o experimental-prometheus-rw .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json
```

Do not use `K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM` with the current Prometheus setup.

## Cleanup

There are no DELETE endpoints for this cleanup. Generate SQL by `RunStamp` and review before execution:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-load-data.ps1 `
  -RunStamp 1770000000000 `
  -IncludeDockerExecExamples
```

## Interpretation

- `201`: successful appointment creation.
- `409`: slot conflict or dataset reuse. Expected in hostile same-slot only.
- `400/422`: invalid payload, stale IDs, missing `amount`, or contract mismatch.
- `429`: gateway rate limiting, not backend capacity.
- `5xx`: backend/gateway failure.
- `dropped_iterations`: k6 could not sustain the requested rate.
- `appointments_skipped_after_limit`: planned skip after `TOTAL_LIMIT`, not a failure.
- `appointments_dataset_exhausted`: real dataset range error.

In the JSON generated by `--summary-export`, k6 counter values are under `metrics.<metric>.values.count`:

```powershell
$summary = Get-Content .\infra\load-tests\appointments\results\appointment-rpm-1000-offset-1000-summary.json -Raw | ConvertFrom-Json
$summary.metrics.appointments_server_error.values.count
$summary.metrics.appointments_created.values.count
$summary.metrics.dropped_iterations.values.count
$summary.metrics.http_req_duration.values.'p(95)'
```

`appointment-rpm.js` also writes a flat summary JSON from `handleSummary` with top-level fields for the custom appointment counters.

## Diagnostics

```powershell
docker compose logs --since 10m api-gateway |
  Select-String -Pattern "status=503 method=POST path=/api/appointments|fallback|CircuitBreaker|Timeout"

docker compose logs --since 10m appointment-service |
  Select-String -Pattern "hold_expiration_failed|LazyInitializationException|Hikari|ERROR|WARN"

docker compose logs --since 10m schedule-service |
  Select-String -Pattern "HikariPool|connection has been closed|Failed to validate connection"

docker compose exec postgres psql -U mediqueue -d mediqueue -c "select appointment_status, count(*) from appointment.appointments group by appointment_status order by appointment_status;"
docker compose exec postgres psql -U mediqueue -d mediqueue -c "select slot_id, count(*) from appointment.appointments where appointment_status in ('PENDING_PAYMENT','CONFIRMED') group by slot_id having count(*) > 1;"
docker compose exec postgres psql -U mediqueue -d mediqueue -c "select publication_status, count(*) from appointment.outbox_events group by publication_status order by publication_status;"
docker compose exec rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
```

Appointment-service and schedule-service Hikari defaults for load testing are configurable with:

- `HIKARI_MAX_POOL_SIZE=20`
- `HIKARI_MIN_IDLE=5`
- `HIKARI_CONNECTION_TIMEOUT_MS=10000`
- `HIKARI_VALIDATION_TIMEOUT_MS=3000`
- `HIKARI_MAX_LIFETIME_MS=600000`
- `HIKARI_KEEPALIVE_TIME_MS=120000`

Raise these only after checking PostgreSQL `max_connections` against the total number of service replicas.

## Evidence

- Dataset used.
- k6 command and env vars.
- k6 summary JSON.
- Dashboard screenshot/export.
- Counts for success, conflicts, validation errors, rate limited, server errors, unexpected errors, and dataset exhaustion.
- Notes on `dropped_iterations`.

## Risks

- Local Docker/laptop resources can bottleneck before the backend.
- Gateway rate limits can hide backend capacity.
- Reusing consumed slots causes `409`.
- Async payment/notification effects may continue after k6 finishes.
