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

## Stronger Machine Checklist

Recommended baseline:

- CPU: 12+ logical cores available to Docker.
- RAM: 32 GB minimum, 48-64 GB preferred for 25k-50k/min attempts.
- Docker Desktop/WSL: allocate enough CPU/RAM and keep the project on the Linux/WSL filesystem when possible.
- Disk: SSD with free space for PostgreSQL WAL, container logs, and k6 summaries.
- Close unrelated heavy workloads before 15k+ runs.

Preflight:

```powershell
docker compose config --quiet
.\infra\load-tests\appointments\tools\inspect-appointment-dataset.ps1 -DataFile .\infra\load-tests\appointments\data\appointments-50000.json -ExpectedCount 50000
.\infra\load-tests\appointments\tools\validate-appointment-dataset.ps1 -BaseUrl http://localhost:8080 -DataFile .\infra\load-tests\appointments\data\appointments-50000.json -StartIndex 0 -Limit 20 -ExpectedCount 50000
```

## Clean-Run Guardrails

Use this when 25k/50k must start from a clean database and fresh dataset. It resets volumes, starts scaled services, waits for real gateway health, prepares SQL base data, inspects/validates the dataset, optionally prewarms, runs k6, and collects evidence.

Scale presets:

```text
medium  = api-gateway=2, appointment=4, schedule=3, patient=2, payment=3, notification=2
high    = api-gateway=3, appointment=6, schedule=4, patient=3, payment=3, notification=2
extreme = api-gateway=4, appointment=8, schedule=4, patient=3, payment=3, notification=2
```

Clean 20k:

```powershell
.\infra\load-tests\appointments\tools\run-clean-appointment-load-stage.ps1 `
  -RatePerMinute 20000 `
  -TotalLimit 20000 `
  -PreAllocatedVus 1200 `
  -MaxVus 2600 `
  -ScalePreset medium `
  -PrewarmCache $true `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-clean-20000-summary.json
```

Clean 25k:

```powershell
.\infra\load-tests\appointments\tools\run-clean-appointment-load-stage.ps1 `
  -RatePerMinute 25000 `
  -TotalLimit 25000 `
  -PreAllocatedVus 1800 `
  -MaxVus 4000 `
  -ScalePreset high `
  -PrewarmCache $true `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-clean-25000-summary.json
```

Clean 50k:

```powershell
.\infra\load-tests\appointments\tools\run-clean-appointment-load-stage.ps1 `
  -RatePerMinute 50000 `
  -TotalLimit 50000 `
  -PreAllocatedVus 3000 `
  -MaxVus 6000 `
  -ScalePreset extreme `
  -PrewarmCache $true `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-clean-50000-summary.json `
  -Allow50k
```

`extreme` requires substantial CPU/RAM and probably will not be valid on a 16 GB PC.

If clean-run prints `Usage: docker [OPTIONS] COMMAND`, Docker Compose was not invoked with separated native arguments. The script should show:

```text
Executing: docker compose down -v --remove-orphans
Exit code: 0
Executing: docker compose up -d --build --scale api-gateway=2 ...
Exit code: 0
Validating: docker compose ps
```

Any non-zero Docker exit code aborts before dataset preparation.

Manual flow validation, capped at `1000/min`:

```powershell
.\infra\load-tests\appointments\tools\run-clean-appointment-load-stage.ps1 `
  -RatePerMinute 1000 `
  -TotalLimit 1000 `
  -PreAllocatedVus 100 `
  -MaxVus 300 `
  -ScalePreset medium `
  -PrewarmCache $false `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-clean-1000-summary.json
```

### A. API Mode

Safest path, but slow. It creates patients, dentists, and slots through the public APIs.

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

Fast load-test setup. It inserts only base data into PostgreSQL:

- `patient.patients`
- `schedule.dentists`
- `schedule.dentist_slots`

It must not insert appointments. The actual appointment load test is still `POST /api/appointments` via k6.

```powershell
.\infra\load-tests\appointments\tools\prepare-appointment-load-data.ps1 `
  -BaseUrl http://localhost:8080 `
  -TotalPatients 100 `
  -TotalDentists 20 `
  -TotalSlots 50000 `
  -Amount 1500.00 `
  -Mode sql
```

SQL mode is faster but does not test patient/dentist/slot creation endpoints.

### C. Dump/Restore

After preparing base data once, create a seed dump:

```powershell
.\infra\load-tests\appointments\tools\create-appointment-seed-dump.ps1 `
  -OutputFile .\infra\load-tests\appointments\data\appointment-load-seed.dump
```

Keep the generated `appointments-*.json` files with the dump. The restore puts the same IDs back into PostgreSQL; k6 still reads the JSON files.

Restore it after a fresh volume reset:

```powershell
docker compose down -v
docker compose up -d --build

.\infra\load-tests\appointments\tools\restore-appointment-seed-dump.ps1 `
  -InputFile .\infra\load-tests\appointments\data\appointment-load-seed.dump
```

To repeat k6 against the same base data without deleting patients/dentists/slots:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-runtime-data.ps1
```

Use queue purge only between runs when intentionally discarding async messages:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-runtime-data.ps1 -PurgeRabbitMqQueues
```

Outputs:

- `infra/load-tests/appointments/data/patient-ids.json`
- `infra/load-tests/appointments/data/dentist-ids.json`
- `infra/load-tests/appointments/data/available-slots.json`
- `infra/load-tests/appointments/data/appointments.sample.json`
- `infra/load-tests/appointments/data/appointments-1000.json`
- `infra/load-tests/appointments/data/appointments-10000.json`
- `infra/load-tests/appointments/data/appointments-50000.json`

If the preparation run creates fewer than 50,000 slots, `appointments-50000.json` is intentionally not kept. Stale dataset files are removed to prevent running k6 with IDs from a previous volume/database.

The `appointments-*.json` files must be pure JSON arrays of appointment payloads. A wrapper such as `{ "appointments": [...] }` is not valid for the official Block 2 datasets.

Inspect before k6:

```powershell
.\infra\load-tests\appointments\tools\inspect-appointment-dataset.ps1 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -ExpectedCount 50000
```

A valid 50,000 dataset reports:

```text
root_type=array
is_pure_array=True
total_items=50000
valid_for_k6=True
```

Optional prewarm:

```powershell
.\infra\load-tests\appointments\tools\prewarm-appointment-cache.ps1 `
  -BaseUrl http://localhost:8080 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -StartIndex 0 `
  -Limit 50000
```

This calls `GET /api/patients/{id}` and `GET /api/slots/{id}` for unique IDs from the dataset. It does not remove validation from `POST /api/appointments`.

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
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-10000-summary.json
```

## Scaled Local Infrastructure

Observed results:

- `5,000/min`: clean.
- `10,000/min`: clean after increasing the appointment gateway bulkhead.
- `15,000/min`: failed on the current PC with k6 `status=0` request timeouts and local saturation.

This points to host/Docker/gateway/upstream capacity limits, not dataset quality. Repeat the next stages on the stronger machine before changing business logic.

Scaled local topology:

- `api-gateway-lb` balances `api-gateway` replicas.
- `appointment-lb` balances `appointment-service` replicas.
- `schedule-lb` balances `schedule-service` replicas because appointment creation validates slots.
- `patient-lb` balances `patient-service` replicas because appointment creation validates patients.
- `payment-lb` already balances payment-service for async payment work.

Start scaled profile:

```powershell
docker compose up -d --build `
  --scale api-gateway=2 `
  --scale appointment-service=4 `
  --scale schedule-service=3 `
  --scale patient-service=2 `
  --scale payment-service=3 `
  --scale notification-service=2
```

PostgreSQL connection budget with `max_connections=100`:

```text
appointment-service: 4 * 8  = 32
schedule-service:    3 * 6  = 18
patient-service:     2 * 4  = 8
payment-service:     3 * 4  = 12
notification-service:2 * 10 = 20
total max pools              = 90
```

This is intentionally conservative. Raising pool sizes without raising PostgreSQL capacity can move the bottleneck into the database.

Additional budgets:

```text
Creation-only, moderate:
appointment-service 4 * 8  = 32
schedule-service    3 * 6  = 18
patient-service     2 * 4  = 8
payment/notification paused = 0
total                    58

E2E, larger:
appointment-service 6 * 8  = 48
schedule-service    4 * 6  = 24
patient-service     3 * 4  = 12
payment-service     3 * 4  = 12
notification-service2 * 10 = 20
total                   116

E2E, aggressive:
appointment-service 8 * 8  = 64
schedule-service    4 * 6  = 24
patient-service     3 * 4  = 12
payment-service     3 * 4  = 12
notification-service2 * 10 = 20
total                   132
```

Check before increasing replicas:

```sql
show max_connections;
select state, wait_event_type, wait_event, count(*) from pg_stat_activity group by state, wait_event_type, wait_event;
select mode, granted, count(*) from pg_locks group by mode, granted;
```

Gateway appointment rate limit for load testing defaults to:

```text
RATE_LIMIT_APPOINTMENT_REPLENISH=2000
RATE_LIMIT_APPOINTMENT_BURST=4000
```

That supports `10,000/min` with `CLIENT_MODE=per-vu`. Do not use `per-iteration` for backend capacity readings unless the goal is to bypass client-level shaping.

Circuit breaker remains enabled with load-test defaults:

```text
GATEWAY_CB_SLIDING_WINDOW_SIZE=5000
GATEWAY_CB_MINIMUM_CALLS=1000
GATEWAY_CB_FAILURE_RATE_THRESHOLD=95
GATEWAY_CB_HALF_OPEN_CALLS=25
GATEWAY_TIMELIMITER_TIMEOUT_SECONDS=30
```

Gateway bulkhead remains enabled and is configured explicitly for the scaled appointment route:

```text
GATEWAY_BULKHEAD_DEFAULT_MAX_CONCURRENT_CALLS=1000
GATEWAY_BULKHEAD_APPOINTMENT_MAX_CONCURRENT_CALLS=3000
GATEWAY_BULKHEAD_MAX_WAIT_MILLIS=0
```

Appointment-service exposes low-cardinality Micrometer timing for creation stages:

```text
mediqueue_appointment_create_stage_duration_seconds{stage="patient_validation|slot_validation|idempotency_lookup|active_hold_check|appointment_save|hold_save|audit_save|outbox_save|idempotency_success_save|response_mapping|total"}
```

Use it to see whether a higher stage is blocked in validation, database writes, or outbox persistence.

Creation-only load-test switches:

```powershell
$env:LOADTEST_DIRECT_DB_VALIDATION_ENABLED="true"
$env:LOADTEST_HOLD_EXPIRATION_ENABLED="false"
$env:LOADTEST_OUTBOX_PUBLISHER_ENABLED="false"
```

These do not remove appointment creation rules and do not skip outbox inserts. They only pause hold expiration and outbox publishing so the synchronous POST path can be measured separately from async payment/notification work. Set both to `true` for E2E runs.

`LOADTEST_DIRECT_DB_VALIDATION_ENABLED=true` keeps validation enabled but moves patient/slot checks into PostgreSQL reads from `patient.patients` and `schedule.dentist_slots`. Use it for high-rate creation-only runs on limited hardware, because validating every unique slot through HTTP creates internal fan-out that can saturate `patient-lb` and `schedule-lb` before the appointment write path is measured. Disable it for strict E2E boundary testing.

For E2E async load testing, keep appointment creation optimized but turn RabbitMQ publishing back on:

```powershell
$env:LOADTEST_DIRECT_DB_VALIDATION_ENABLED="true"
$env:LOADTEST_HOLD_EXPIRATION_ENABLED="false"
$env:LOADTEST_OUTBOX_PUBLISHER_ENABLED="true"
$env:APPOINTMENT_OUTBOX_PUBLISH_INTERVAL_MS="200"
$env:APPOINTMENT_OUTBOX_BATCH_SIZE="500"
$env:PAYMENT_RABBITMQ_PREFETCH="50"
$env:PAYMENT_RABBITMQ_LISTENER_CONCURRENCY="8"
$env:PAYMENT_RABBITMQ_LISTENER_MAX_CONCURRENCY="16"
$env:PAYMENT_OUTBOX_PUBLISH_INTERVAL_MS="200"
$env:PAYMENT_OUTBOX_BATCH_SIZE="500"
$env:PAYMENT_SIM_MIN_DELAY_MS="0"
$env:PAYMENT_SIM_MAX_DELAY_MS="50"
$env:PAYMENT_SIM_APPROVAL_RATE="1.0"
$env:NOTIFICATION_RABBITMQ_PREFETCH="50"
$env:NOTIFICATION_RABBITMQ_LISTENER_CONCURRENCY="4"
$env:NOTIFICATION_RABBITMQ_LISTENER_MAX_CONCURRENCY="12"
```

In this mode, `appointments_created` proves synchronous creation, while RabbitMQ queue depth, payment rows, notification rows, and appointment status distribution prove asynchronous completion. Do not call an E2E run complete until the relevant queues drain.

If gateway fallback logs show `BulkheadFullException`, the request was rejected by the gateway concurrency guard before a useful upstream result could be returned. That is different from an open circuit (`CallNotPermittedException`) or a timeout (`TimeoutException`).

Use the scaled-routing evidence collector after any failed scaled run:

```powershell
.\infra\load-tests\appointments\tools\diagnose-scaled-routing.ps1 `
  -Since 10m `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-5000-summary.json
```

For timeout investigations, run the collector during the load window:

```powershell
.\infra\load-tests\appointments\tools\diagnose-scaled-routing.ps1 `
  -Since 5m `
  -SampleSeconds 90 `
  -SampleIntervalSeconds 5
```

For the stronger machine, run the monitor in a second PowerShell:

```powershell
.\infra\load-tests\appointments\tools\monitor-loadtest.ps1 `
  -DurationSeconds 90 `
  -IntervalSeconds 5 `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-15000-summary.json
```

`appointments_timeout` is reserved for k6 `status=0` results. It must remain `0` for an official pass. Raising `HTTP_TIMEOUT` is useful only to measure queue depth and latency collapse; it does not make a timeout-heavy run successful.

Prometheus uses Docker DNS service discovery for replicated Spring services so multiple A records can be scraped.

Run order after scaling:

1. `5,000/min` baseline.
2. `10,000/min` first target.
3. `15,000/min` only if 10k is clean.
4. `20,000/min` only if 15k is clean.
5. `25,000/min` only if 20k is clean.
6. Do not run 50k automatically.

Preferred runner:

```powershell
.\infra\load-tests\appointments\tools\run-appointment-load-stage.ps1 `
  -RatePerMinute 10000 `
  -TotalLimit 10000 `
  -DataOffset 0 `
  -PreAllocatedVus 500 `
  -MaxVus 1200 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-10000-summary.json
```

The runner validates dataset size before k6 and refuses `50,000/min` unless `-Allow50k` is passed explicitly.

Success criteria at each step:

- `appointments_server_error=0`
- `appointments_503=0`
- `appointments_validation_error=0`
- `appointments_conflict=0`
- `appointments_dataset_exhausted=0`
- `dropped_iterations=0`
- gateway fallback logs `0`
- no Hikari pending/timeout spike
- no double reservation rows

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
$env:CLIENT_MODE="per-vu"
k6 run .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json
```

Preferred guarded runner:

```powershell
.\infra\load-tests\appointments\tools\run-appointment-load-stage.ps1 `
  -RatePerMinute 50000 `
  -TotalLimit 50000 `
  -DataOffset 0 `
  -PreAllocatedVus 3000 `
  -MaxVus 6000 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json `
  -HttpTimeout 60s `
  -Allow50k
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

Current milestone:

- `5,000 citas/min` has passed cleanly for synchronous `POST /api/appointments` creation.
- `10,000 citas/min` has passed cleanly after the gateway bulkhead fix.
- `15,000 citas/min` failed on the current PC with request timeouts, so the next attempt should run on a stronger machine.
- That result validates creation-path throughput, not complete async draining.
- `confirm_skipped ... EXPIRED -> CONFIRMED` means payment success arrived after hold expiration. The business rule is correct to reject it; for E2E load tests, tune TTL/payment throughput so success events arrive before expiration.

- `201`: successful appointment creation.
- `409`: slot conflict or dataset reuse. Expected in hostile same-slot only.
- `400/422`: invalid payload, stale IDs, missing `amount`, or contract mismatch.
- `429`: gateway rate limiting, not backend capacity.
- `5xx`: backend/gateway failure.
- `appointments_503_html_haproxy`: HAProxy returned HTML, usually "No server is available"; the load balancer had no healthy backend.
- `appointments_503_json_gateway`: api-gateway returned JSON `SERVICE_UNAVAILABLE`; inspect fallback logs for `BulkheadFullException`, `TimeoutException`, `CallNotPermittedException`, or upstream failures.
- `appointments_connection_refused`: k6 received `status=0` with connect refused/connectex; gateway port or Docker networking was unavailable.
- `dropped_iterations`: k6 could not sustain the requested rate.
- `appointments_skipped_after_limit`: planned skip after `TOTAL_LIMIT`, not a failure.
- `appointments_dataset_exhausted`: real dataset range error.

Validate a dataset range before k6:

```powershell
.\infra\load-tests\appointments\tools\validate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -StartIndex 5000 `
  -Limit 20 `
  -ExpectedCount 50000
```

The validator exits non-zero when the dataset is not a pure array, required IDs are empty, `amount` is invalid, slots repeat in the inspected range, or backend entities are missing/unavailable.

Debug one appointment and print the real response:

```powershell
.\infra\load-tests\appointments\tools\debug-single-appointment.ps1 `
  -BaseUrl http://localhost:8080 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -Index 5000
```

Enable k6 response diagnostics:

```powershell
$env:DEBUG_RESPONSES="true"
$env:DEBUG_RESPONSE_LIMIT="10"
```

In the JSON generated by `--summary-export`, k6 counter values are under `metrics.<metric>.values.count`:

```powershell
$summary = Get-Content .\infra\load-tests\appointments\results\appointment-rpm-1000-offset-1000-summary.json -Raw | ConvertFrom-Json
$summary.metrics.appointments_server_error.values.count
$summary.metrics.appointments_created.values.count
$summary.metrics.dropped_iterations.values.count
$summary.metrics.http_req_duration.values.'p(95)'
```

`appointment-rpm.js` also writes a flat summary JSON from `handleSummary` with top-level fields for the custom appointment counters.

Failure source guide:

- Dataset: validation errors, `409`, duplicate slot reports, or validator `invalid_items > 0`.
- Gateway LB: `appointments_503_html_haproxy > 0`, api-gateway-lb logs showing backends `DOWN`, or `/actuator/health` returning HAProxy HTML.
- api-gateway: `appointments_503_json_gateway > 0`, fallback logs with exception class/message.
- appointment-service: gateway JSON 503 plus service ERROR/WARN/Hikari, or slow `mediqueue_appointment_create_stage_duration_seconds{stage="total"}`.
- PostgreSQL: Hikari pending/timeout, `pg_stat_activity` active/wait spikes, locks, or connections near `max_connections`.
- Docker Desktop/host: Docker API 500, connection refused to localhost:8080, pinned CPU/RAM in `docker stats`, or container restarts.

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
docker compose exec rabbitmq rabbitmqctl list_bindings
```

Appointment-service and schedule-service Hikari defaults for load testing are configurable with:

- `HIKARI_MAX_POOL_SIZE=20`
- `HIKARI_MIN_IDLE=5`
- `HIKARI_CONNECTION_TIMEOUT_MS=10000`
- `HIKARI_VALIDATION_TIMEOUT_MS=3000`
- `HIKARI_MAX_LIFETIME_MS=180000`
- `HIKARI_KEEPALIVE_TIME_MS=30000`
- `HIKARI_IDLE_TIMEOUT_MS=60000`

Raise these only after checking PostgreSQL `max_connections` against the total number of service replicas.

Collect evidence after a run:

```powershell
.\infra\load-tests\appointments\tools\collect-appointment-load-evidence.ps1 `
  -Since 30m `
  -SummaryFile .\infra\load-tests\appointments\results\appointment-rpm-1000-offset-2000-summary.json
```

## Creation vs Async E2E

`appointment-rpm.js` measures the synchronous creation path: gateway, idempotency, patient validation, slot validation, database write, hold creation, and outbox publication. Payment and notification are asynchronous.

For E2E validation, RabbitMQ must drain after the HTTP test:

- `payment.appointment-held.queue` is consumed by payment-service. Ready/unacked backlog means payment cannot keep up.
- `payment.succeeded` and `payment.failed` are consumed by appointment-service.
- `notification.appointment.queue` and `notification.payment.queue` are consumed by notification-service.
- `appointment.confirmed` and `appointment.expired` are currently event queues with no consumers. Treat backlog there as diagnostic/audit backlog unless a service explicitly starts consuming them or a load-test RabbitMQ profile removes those declarations.

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

This profile is for load testing only. It does not relax appointment state transitions or permit `EXPIRED -> CONFIRMED`; it gives async payment processing more time and more consumer capacity.

Gateway circuit breaker load-test defaults:

- `GATEWAY_CB_SLIDING_WINDOW_SIZE=5000`
- `GATEWAY_CB_MINIMUM_CALLS=1000`
- `GATEWAY_CB_FAILURE_RATE_THRESHOLD=95`
- `GATEWAY_CB_WAIT_OPEN_SECONDS=5`
- `GATEWAY_CB_HALF_OPEN_CALLS=25`
- `GATEWAY_TIMELIMITER_TIMEOUT_SECONDS=30`

Gateway bulkhead load-test defaults:

- `GATEWAY_BULKHEAD_DEFAULT_MAX_CONCURRENT_CALLS=1000`
- `GATEWAY_BULKHEAD_APPOINTMENT_MAX_CONCURRENT_CALLS=3000`
- `GATEWAY_BULKHEAD_MAX_WAIT_MILLIS=0`

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
