# MediQueue Block 2 - Appointment Load Tests

Official k6 suite for appointment creation through the API Gateway.

Target clarification:

- `50,000 citas totales` means a fixed total of 50,000 appointment attempts.
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
  "appointmentDate": "2026-08-01",
  "startTime": "08:00:00",
  "endTime": "08:30:00",
  "amount": 150.00,
  "notes": "Block 2 load test"
}
```

`amount` is required. Slots must not repeat for successful appointment tests.

## Step 1 - Start Stack

```powershell
docker compose up -d --build
```

## Step 2 - Prepare Data

There are three supported preparation paths.

### A. API Mode

Safest and closest to production behavior, but slow for repeated official runs because it creates every patient, dentist, and slot through public APIs.

Preferred path: create real data through public APIs.

```powershell
.\infra\load-tests\appointments\tools\prepare-appointment-load-data.ps1 `
  -BaseUrl http://localhost:8080 `
  -TotalPatients 100 `
  -TotalDentists 20 `
  -TotalSlots 50000 `
  -Amount 1500.00 `
  -Mode api
```

### B. SQL Mode

Fast load-test setup. This inserts only base data directly into PostgreSQL:

- `patient.patients`
- `schedule.dentists`
- `schedule.dentist_slots`

It does **not** insert rows into `appointment.appointments`. k6 must still create every appointment through `POST /api/appointments`.

```powershell
.\infra\load-tests\appointments\tools\prepare-appointment-load-data.ps1 `
  -BaseUrl http://localhost:8080 `
  -TotalPatients 100 `
  -TotalDentists 20 `
  -TotalSlots 50000 `
  -Amount 1500.00 `
  -Mode sql
```

SQL mode uses the real schemas detected in the running stack:

- `patient.patients`
- `schedule.dentists`
- `schedule.dentist_slots`

Use SQL mode only for load testing. It does not validate the patient/dentist/slot creation endpoints.

### C. Dump/Restore

Fastest repeat path for official runs. First prepare base data once, then create a dump:

```powershell
.\infra\load-tests\appointments\tools\create-appointment-seed-dump.ps1 `
  -OutputFile .\infra\load-tests\appointments\data\appointment-load-seed.dump
```

The dump includes only base data: patients, dentists, and slots. It excludes appointments, holds, outbox, payments, notifications, and audit/runtime data.
Keep the generated `appointments-*.json` files together with the dump. Restore brings back the same IDs into PostgreSQL; the JSON files are still the k6 input.

Recommended restore sequence:

```powershell
docker compose down -v
docker compose up -d --build

.\infra\load-tests\appointments\tools\restore-appointment-seed-dump.ps1 `
  -InputFile .\infra\load-tests\appointments\data\appointment-load-seed.dump
```

To rerun k6 without rebuilding base data, clear only runtime data:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-runtime-data.ps1
```

If async queues still contain messages from the prior run and you intentionally want a clean async baseline:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-runtime-data.ps1 -PurgeRabbitMqQueues
```

Purging queues deletes pending async test messages. Do it only between load-test runs.

This creates:

- `patient-ids.json`
- `dentist-ids.json`
- `available-slots.json`
- `appointments.sample.json`
- `appointments-1000.json`
- `appointments-10000.json`
- `appointments-50000.json`
- `load-data-manifest-<RunStamp>.json`

Patients and dentists can be reused. Slots cannot be reused. The preparation script distributes unique 30-minute slots across dentists from `2026-08-01` onward.
If a requested dataset cannot be generated because the run did not create enough slots, the preparation script removes any stale dataset file with that name so old IDs are not reused accidentally.

The appointment dataset files are intentionally **pure JSON arrays** of appointment payloads. They must not be wrapped as `{ "appointments": [...] }`.

Inspect the generated dataset before k6:

```powershell
.\infra\load-tests\appointments\tools\inspect-appointment-dataset.ps1 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -ExpectedCount 50000
```

Expected shape:

```text
root_type=array
is_pure_array=True
total_items=50000
valid_for_k6=True
```

## Generate Datasets From Existing IDs

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -AvailableSlotsFile .\infra\load-tests\appointments\data\available-slots.json `
  -Totals 10,1000,10000,50000 `
  -OutputDir .\infra\load-tests\appointments\data `
  -Amount 150.00
```

The generator validates:

- At least one real patient ID exists.
- Enough unique slots exist for the requested total.
- `slotId` does not repeat inside each dataset.
- `amount` exists and is greater than zero.
- The first 20 generated records have all required fields.

JSON files generated by the PowerShell tools are written as UTF-8 without BOM. The k6 scripts also strip an initial BOM defensively before `JSON.parse(open(DATA_FILE))`.

## Export Existing IDs

```powershell
.\infra\load-tests\appointments\tools\export-load-test-ids.ps1 `
  -BaseUrl http://localhost:8080 `
  -OutputDir .\infra\load-tests\appointments\data
```

Current contracts expose `GET /api/slots/available`, but not global `GET /api/patients` or global `GET /api/dentists`. Warnings for those endpoints are expected.

## Step 3 - Smoke

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments.sample.json"
$env:TOTAL_APPOINTMENTS="10"
$env:VUS="5"
k6 run .\infra\load-tests\appointments\scripts\appointment-smoke.js --summary-export .\infra\load-tests\appointments\results\appointment-smoke-summary.json
```

## Step 4 - Run 1,000/min

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

`TOTAL_LIMIT` tells the script how many real appointment requests should be sent. If k6 schedules an extra boundary iteration, that extra iteration is counted as `appointments_skipped_after_limit` and no HTTP request is sent.

`DATA_OFFSET` selects the starting row in the dataset. For example, `DATA_OFFSET=1000` uses rows 1000 through 1999 for a 1000-request run, which avoids reusing slots consumed by a previous run.

## Step 5 - Run 10,000/min

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

## Scaled Local Profile For 10k-25k/min

The clean 5,000/min result proves the dataset and appointment contract are valid. Failures at 10,000/min and 25,000/min with only `503` and no validation/conflict errors indicate saturation in the gateway/upstream path.

The load-test Docker profile now routes hot paths through internal HAProxy services:

- `api-gateway -> appointment-lb -> appointment-service replicas`
- `appointment-service -> schedule-lb -> schedule-service replicas`
- `appointment-service -> patient-lb -> patient-service replicas`

Start the scaled profile:

```powershell
docker compose up -d --build `
  --scale api-gateway=2 `
  --scale appointment-service=4 `
  --scale schedule-service=3 `
  --scale patient-service=2 `
  --scale payment-service=3 `
  --scale notification-service=2
```

Gateway appointment route target:

```text
APPOINTMENT_SERVICE_URL=http://appointment-lb:8080
```

Appointment-service validation targets:

```text
PATIENT_SERVICE_URL=http://patient-lb:8080
SCHEDULE_SERVICE_URL=http://schedule-lb:8080
```

Rate limit notes:

- `10,000/min` is about `166.67 req/s`.
- `50,000/min` is about `833.33 req/s`.
- Default load-test appointment limit is `RATE_LIMIT_APPOINTMENT_REPLENISH=300` and `RATE_LIMIT_APPOINTMENT_BURST=600`.
- Keep `CLIENT_MODE=per-vu` for backend capacity tests. `per-iteration` bypasses client-level rate shaping too aggressively.

Gateway circuit breaker remains enabled. Load-test defaults are less aggressive:

- `GATEWAY_CB_SLIDING_WINDOW_SIZE=500`
- `GATEWAY_CB_MINIMUM_CALLS=100`
- `GATEWAY_CB_FAILURE_RATE_THRESHOLD=90`
- `GATEWAY_CB_HALF_OPEN_CALLS=25`
- `GATEWAY_TIMELIMITER_TIMEOUT_SECONDS=15`

Gateway bulkhead remains enabled too. In scaled appointment tests, fast `503` responses with
`BulkheadFullException` mean the gateway rejected the request before the upstream finished. The load-test defaults are:

- `GATEWAY_BULKHEAD_DEFAULT_MAX_CONCURRENT_CALLS=300`
- `GATEWAY_BULKHEAD_APPOINTMENT_MAX_CONCURRENT_CALLS=1000`
- `GATEWAY_BULKHEAD_MAX_WAIT_MILLIS=0`

If `5,000/min` fails with fast `503`, inspect gateway fallback logs before changing service pools.

Scaled-routing diagnosis:

```powershell
.\infra\load-tests\appointments\tools\diagnose-scaled-routing.ps1 `
  -Since 10m `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-5000-summary.json
```

Known finding: after scaling, fast gateway `503` at `5,000/min` were caused by
`BulkheadFullException` on the `appointment-service` circuit breaker path. Increasing the
appointment bulkhead for the load-test profile restored a clean `5,000/min` run.

Timeout diagnosis:

- `appointments_timeout` counts k6 responses with `status=0`.
- `appointments_timeout > 0` means the client did not receive an HTTP response before `HTTP_TIMEOUT`.
- Default `HTTP_TIMEOUT=60s` matches the HAProxy client/server timeout and should not be raised to call a run successful.
- Use `DEBUG_RESPONSE_EVERY=500` to sample errors without flooding Docker Desktop logs.

Run a live sampler in another PowerShell while k6 is running:

```powershell
.\infra\load-tests\appointments\tools\diagnose-scaled-routing.ps1 `
  -Since 5m `
  -SampleSeconds 90 `
  -SampleIntervalSeconds 5
```

### Hikari And PostgreSQL Connection Budget

Current local PostgreSQL `max_connections` is `100`.

Recommended scaled E2E budget:

```text
appointment-service: 4 replicas * 8  = 32
schedule-service:    3 replicas * 6  = 18
patient-service:     2 replicas * 4  = 8
payment-service:     3 replicas * 4  = 12
notification-service:2 replicas * 10 = 20
-----------------------------------------
estimated maximum pool total          = 90
```

That leaves a small margin for admin sessions and migrations. Do not raise Hikari pools without increasing PostgreSQL capacity or reducing replicas.

### Matrix 5k-25k/min

Use fresh dataset ranges. If a previous run consumed a range, move `DATA_OFFSET`.

5,000/min:

```powershell
$env:DATA_FILE="../data/appointments-50000.json"
$env:RATE_PER_MINUTE="5000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="5000"
$env:DATA_OFFSET="0"
$env:PRE_ALLOCATED_VUS="300"
$env:MAX_VUS="800"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-5000-summary.json
```

10,000/min:

```powershell
$env:DATA_FILE="../data/appointments-50000.json"
$env:RATE_PER_MINUTE="10000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="10000"
$env:DATA_OFFSET="5000"
$env:PRE_ALLOCATED_VUS="500"
$env:MAX_VUS="1200"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-10000-summary.json
```

15,000/min:

```powershell
$env:DATA_FILE="../data/appointments-50000.json"
$env:RATE_PER_MINUTE="15000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="15000"
$env:DATA_OFFSET="15000"
$env:PRE_ALLOCATED_VUS="800"
$env:MAX_VUS="1800"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-15000-summary.json
```

20,000/min:

```powershell
$env:DATA_FILE="../data/appointments-50000.json"
$env:RATE_PER_MINUTE="20000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="20000"
$env:DATA_OFFSET="0"
$env:PRE_ALLOCATED_VUS="1000"
$env:MAX_VUS="2200"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-20000-summary.json
```

25,000/min:

```powershell
$env:DATA_FILE="../data/appointments-50000.json"
$env:RATE_PER_MINUTE="25000"
$env:DURATION="1m"
$env:TOTAL_LIMIT="25000"
$env:DATA_OFFSET="25000"
$env:PRE_ALLOCATED_VUS="1200"
$env:MAX_VUS="2600"
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-25000-summary.json
```

Before each run, inspect and validate the intended range. Do not run 50,000/min until 10k, 15k, 20k, and 25k pass cleanly.

## Step 6 - Run 50,000/min

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

Do not run 50,000/min automatically during setup. Generate data and run smoke first.

For the official 50,000/min run, use a clean or freshly generated dataset. If any slots in the dataset were already used by earlier runs, the backend should correctly return `409 Conflict`.

## Fixed Total

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-50000.json"
$env:TOTAL_APPOINTMENTS="50000"
$env:VUS="200"
$env:MAX_DURATION="10m"
$env:CLIENT_MODE="per-iteration"
k6 run .\infra\load-tests\appointments\scripts\appointment-fixed-total.js --summary-export .\infra\load-tests\appointments\results\appointment-fixed-50000-summary.json
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

Many `409 Conflict` responses are desired in this hostile test. They prove the backend prevents double reservation of one slot.

## Prometheus Remote Write

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
k6 run -o experimental-prometheus-rw .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json
```

Do not set `K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM` with the current Prometheus setup.

## Step 7 - Validate Results

Current milestone:

- `5,000 citas/min` has passed cleanly for `POST /api/appointments` creation.
- The creation-path result does not automatically mean the full async E2E path is drained.
- `confirm_skipped ... EXPIRED -> CONFIRMED` means a `PaymentSucceeded` event arrived after the hold had expired. That warning does not invalidate the POST creation measurement, but it does show the payment/expiration path is lagging for E2E validation.

Interpretation:

- `200/201/202`: appointment creation accepted.
- `409`: slot conflict, duplicated slot, or reused dataset. Expected only in hostile same-slot tests.
- `400/422`: invalid payload, stale IDs, missing `amount`, or contract mismatch.
- `429`: gateway rate limit; this measures throttling, not backend capacity.
- `5xx`: real gateway/backend/server error.
- `dropped_iterations`: k6 could not sustain the requested rate with configured VUs or backend latency was too high.
- `appointments_skipped_after_limit`: planned skip after `TOTAL_LIMIT`; useful for harmless extra iterations from `constant-arrival-rate`.
- `appointments_dataset_exhausted`: real error. The script expected to send a request, but `DATA_OFFSET + iterationInTest` exceeded dataset length.

Before running k6 against a dataset range, validate that the backend can still see those IDs and that the slots are available:

```powershell
.\infra\load-tests\appointments\tools\validate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -StartIndex 5000 `
  -Limit 20 `
  -ExpectedCount 50000
```

The validator fails if the file is not a pure JSON array, if `patientId`/`dentistId`/`slotId` are empty, if `amount` is invalid, if slots duplicate inside the inspected range, or if referenced backend entities are missing/unavailable.

To debug one appointment payload and see the real backend response body:

```powershell
.\infra\load-tests\appointments\tools\debug-single-appointment.ps1 `
  -BaseUrl http://localhost:8080 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -Index 5000
```

For k6 response diagnostics, enable the first error responses:

```powershell
$env:DEBUG_RESPONSES="true"
$env:DEBUG_RESPONSE_LIMIT="10"
```

Evidence to deliver:

- Dataset file used.
- k6 command and env vars.
- k6 summary JSON.
- Dashboard screenshot/export.
- Counts for created, conflict, validation error, rate limited, server error, unexpected error, and dataset exhausted.
- Notes on `dropped_iterations`.

Read counter values from `--summary-export` with `.metrics.<metric>.values.count`:

```powershell
$summary = Get-Content .\infra\load-tests\appointments\results\appointment-rpm-1000-offset-1000-summary.json -Raw | ConvertFrom-Json
$summary.metrics.appointments_server_error.values.count
$summary.metrics.appointments_created.values.count
$summary.metrics.dropped_iterations.values.count
$summary.metrics.http_req_duration.values.'p(95)'
```

`appointment-rpm.js` also writes a flat JSON next to the regular handleSummary artifact in `infra/load-tests/appointments/results`, with top-level fields such as `appointments_server_error`, `http_reqs`, and `http_req_duration_p95`.

## Diagnostics For 503 And Load-Test Regressions

Count gateway 503 responses:

```powershell
docker compose logs --since 10m api-gateway |
  Select-String -Pattern "status=503 method=POST path=/api/appointments"
```

Check appointment hold expiration failures:

```powershell
docker compose logs --since 10m appointment-service |
  Select-String -Pattern "hold_expiration_failed|LazyInitializationException|Hikari|ERROR|WARN"
```

Check schedule-service Hikari warnings:

```powershell
docker compose logs --since 10m schedule-service |
  Select-String -Pattern "HikariPool|connection has been closed|Failed to validate connection"
```

Database checks:

```powershell
docker compose exec postgres psql -U mediqueue -d mediqueue -c "select appointment_status, count(*) from appointment.appointments group by appointment_status order by appointment_status;"
docker compose exec postgres psql -U mediqueue -d mediqueue -c "select slot_id, count(*) from appointment.appointments where appointment_status in ('PENDING_PAYMENT','CONFIRMED') group by slot_id having count(*) > 1;"
docker compose exec postgres psql -U mediqueue -d mediqueue -c "select publication_status, count(*) from appointment.outbox_events group by publication_status order by publication_status;"
docker compose exec rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
docker compose exec rabbitmq rabbitmqctl list_bindings
```

For load-test stability, appointment-service and schedule-service expose Hikari settings via environment variables:

- `HIKARI_MAX_POOL_SIZE`, default `20`
- `HIKARI_MIN_IDLE`, default `5`
- `HIKARI_CONNECTION_TIMEOUT_MS`, default `10000`
- `HIKARI_VALIDATION_TIMEOUT_MS`, default `3000`
- `HIKARI_MAX_LIFETIME_MS`, default `180000`
- `HIKARI_KEEPALIVE_TIME_MS`, default `30000`
- `HIKARI_IDLE_TIMEOUT_MS`, default `60000`

Do not raise pool sizes blindly. Verify PostgreSQL `max_connections` and multiply every service pool by its replica count before increasing these values.

Collect evidence after a failed appointment load run:

```powershell
.\infra\load-tests\appointments\tools\collect-appointment-load-evidence.ps1 `
  -Since 30m `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-1000-offset-2000-summary.json
```

## Creation Test vs Async E2E Test

The official `appointment-rpm.js` result measures synchronous creation through `POST /api/appointments`: gateway, Redis/idempotency, patient validation, schedule validation, appointment persistence, hold creation, and outbox publication. Payment and notification processing continue asynchronously after the HTTP response.

For an E2E async run, capture RabbitMQ and status evidence after k6 finishes. Watch:

- `payment.appointment-held.queue`: should drain; high ready/unacked means payment-service cannot keep up.
- `payment.succeeded` / `payment.failed`: should be consumed by appointment-service.
- `notification.appointment.queue` / `notification.payment.queue`: should drain if notification-service is part of the E2E target.
- `appointment.confirmed` and `appointment.expired`: currently service-declared event queues with no consumers. Treat backlog there as diagnostic/audit backlog, not creation-path failure, until a service owner assigns consumers or removes those queue declarations from a load-test RabbitMQ profile.

Recommended load-test async profile:

```powershell
$env:APPOINTMENT_HOLD_TTL_MINUTES="30"
$env:PAYMENT_SIM_MIN_DELAY_MS="50"
$env:PAYMENT_SIM_MAX_DELAY_MS="200"
$env:PAYMENT_TIMEOUT_SECONDS="10"
$env:PAYMENT_SIM_APPROVAL_RATE="1.0"
$env:PAYMENT_RABBITMQ_LISTENER_CONCURRENCY="8"
$env:PAYMENT_RABBITMQ_LISTENER_MAX_CONCURRENCY="16"
docker compose up -d --build appointment-service payment-service
```

These settings are for load testing, not production. They do not allow `EXPIRED -> CONFIRMED`; they reduce late payment events by extending hold TTL and making the simulator faster.

For load-test stability, the gateway circuit breaker uses a larger sample than the default tiny window:

- `GATEWAY_CB_SLIDING_WINDOW_SIZE=500`
- `GATEWAY_CB_MINIMUM_CALLS=100`
- `GATEWAY_CB_FAILURE_RATE_THRESHOLD=90`
- `GATEWAY_CB_WAIT_OPEN_SECONDS=5`
- `GATEWAY_CB_HALF_OPEN_CALLS=25`
- `GATEWAY_TIMELIMITER_TIMEOUT_SECONDS=15`

The gateway bulkhead is also explicit for load tests:

- `GATEWAY_BULKHEAD_DEFAULT_MAX_CONCURRENT_CALLS=300`
- `GATEWAY_BULKHEAD_APPOINTMENT_MAX_CONCURRENT_CALLS=1000`
- `GATEWAY_BULKHEAD_MAX_WAIT_MILLIS=0`

This keeps genuine upstream failures visible as `503`, but avoids opening the route after only a few transient failures during a controlled load test.

## Cleanup

API cleanup is not available because the services do not expose DELETE endpoints. Generate reviewed SQL for a preparation run:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-load-data.ps1 `
  -RunStamp 1770000000000 `
  -IncludeDockerExecExamples
```

Review the generated SQL before running it. It deletes test appointments by `notes LIKE '%RunStamp%'` and seed data by emails/license/document numbers containing the stamp. It intentionally does not delete `appointment_audit`, which is immutable by design.

## Local Risks

- 50,000/min can saturate Docker Desktop or laptop hardware before measuring backend capacity.
- Gateway rate limiting can dominate unless `CLIENT_MODE` is chosen intentionally.
- Reusing a consumed dataset produces `409`.
- Payment and notification work is asynchronous after appointment creation.
- PostgreSQL connection limits, RabbitMQ queue depth, Redis latency, CPU, memory, and disk I/O can all become bottlenecks.
