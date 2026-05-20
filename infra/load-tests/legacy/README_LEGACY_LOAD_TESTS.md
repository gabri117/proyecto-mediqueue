# Legacy Load Tests

These tests are preserved for historical reference and are not part of the official Block 2 appointment load-testing suite.

Official Block 2 scripts live in:

```text
infra/load-tests/appointments/
```

## Legacy Scripts Detected

- `infra/load-tests/scripts/00-smoke.js`
- `infra/load-tests/scripts/01-patient-load.js`
- `infra/load-tests/scripts/02-schedule-load.js`
- `infra/load-tests/scripts/03-payment-load.js`
- `infra/load-tests/scripts/04-notification-load.js`
- `infra/load-tests/scripts/05-appointment-hostile.js`
- `infra/load-tests/scripts/06-e2e-flow.js`
- `infra/load-tests/scripts/07-gateway-rate-limit.js`
- `infra/load-tests/scenario-a-slots.js`
- `infra/load-tests/scenario-b-concurrency.js`
- `infra/load-tests/scenario-c-full-flow.js`
- `tests/load-test.js`
- `k6-tests/gateway-redis-chaos-small.js`
- `k6-tests/gateway-redis-chaos-50k.js`
- `services/api-gateway/tests/gateway-payment-test.js`
- `services/api-gateway/tests/gateway-payment-arrival-rate-test.js`
- `services/api-gateway/tests/gateway-payment-500k-test.js`
- `services/payment-service/tests/payment-2000-test.js`

## Why Legacy

Some previous scripts are useful for service-specific smoke, Redis chaos, payment checks, or old checkpoint flows. They should not be used as the main evidence for Block 2 appointment creation throughput because several are not aligned with the current appointment contract:

- Some appointment payloads omit required fields such as `amount`.
- Some scripts refer to stale routes such as `/api/schedule/slots`.
- Some scripts use old response field names such as `patient.id`, `slot.id`, or `appointment.id` instead of current `patientId`, `slotId`, and `appointmentId`.
- Some flows pick random available slots, which can create uncontrolled `409 Conflict` results under concurrency.
- Some tests are gateway/payment/chaos focused rather than appointment creation throughput.

Do not delete these files without a separate cleanup task. Keep Block 2 evidence under `infra/load-tests/appointments/results/`.
