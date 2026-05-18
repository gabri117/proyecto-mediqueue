# Block 2 - k6 Appointments

This document is the delivery guide for MediQueue appointment load testing.

## Goal

Validate real appointment creation through:

```http
POST http://localhost:8080/api/appointments
```

The strong target is **50,000 appointments per minute**, not 50,000 per second. This equals approximately **833.33 requests per second**.

## Scripts

- `appointment-smoke.js`: small contract validation.
- `appointment-fixed-total.js`: fixed total runs such as 1,000, 10,000, or 50,000 total attempts.
- `appointment-rpm.js`: arrival-rate test for 50,000/min or smaller rates.
- `appointment-hostile-same-slot.js`: concurrency business-rule test where `409 Conflict` is expected.

## Dataset

Every successful appointment requires a unique `slotId`. The generator reads real slots from `/api/slots/available` and combines them with real patient IDs provided by file or parameter.

```powershell
.\infra\load-tests\appointments\tools\generate-appointment-dataset.ps1 `
  -BaseUrl http://localhost:8080 `
  -Total 50000 `
  -PatientIdsFile .\infra\load-tests\appointments\data\patient-ids.json `
  -OutputFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -Amount 150.00
```

## Fixed Total vs Per Minute

Fixed total:

```powershell
$env:BASE_URL="http://localhost:8080"
$env:DATA_FILE="./infra/load-tests/appointments/data/appointments-50000.json"
$env:TOTAL_APPOINTMENTS="50000"
$env:VUS="200"
$env:MAX_DURATION="10m"
$env:CLIENT_MODE="per-iteration"
k6 run .\infra\load-tests\appointments\scripts\appointment-fixed-total.js --summary-export .\infra\load-tests\appointments\results\appointment-fixed-50000-summary.json
```

Per minute:

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

## Prometheus

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
k6 run -o experimental-prometheus-rw .\infra\load-tests\appointments\scripts\appointment-rpm.js --summary-export .\infra\load-tests\appointments\results\appointment-rpm-50000-summary.json
```

Do not use `K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM` with the current Prometheus setup. The dashboard uses standard k6 remote-write series such as `k6_http_req_duration_p95`.

## Dashboard

Import:

```text
infra/load-tests/appointments/dashboards/mediqueue-appointment-load-dashboard.json
```

Main panels:

- Appointment attempts/sec.
- Created/sec.
- Conflicts/sec.
- Validation errors/sec.
- Rate limited/sec.
- Server and unexpected error totals.
- k6 HTTP p95 and request rate.
- Gateway RPS by status and 5xx rate.
- Appointment-service RPS and p95 latency.
- RabbitMQ queue messages if exporter metrics exist.
- Redis commands/sec.

## Interpretation

- `201`: successful appointment creation.
- `409`: slot conflict or dataset reuse. Expected in hostile same-slot only.
- `400/422`: invalid payload, stale IDs, missing `amount`, or contract mismatch.
- `429`: gateway rate limiting, not backend capacity.
- `5xx`: backend/gateway failure.
- `dropped_iterations`: k6 could not sustain the requested rate with configured VUs or backend latency was too high.

## Evidence

Deliver:

- Dataset used.
- k6 command and env vars.
- k6 summary JSON.
- Dashboard screenshot/export.
- Counts for success, conflicts, validation errors, rate limited, server errors, unexpected errors, and dataset exhaustion.
- Notes on `dropped_iterations`.
- Observations from gateway, appointment-service, RabbitMQ, Redis, PostgreSQL, payment-service, and notification-service.

## Risks

- Local Docker Desktop or laptop hardware can bottleneck before the backend.
- Gateway rate limits can hide backend capacity.
- Reusing consumed slots causes `409`.
- Async payment/notification effects may continue after k6 finishes.
