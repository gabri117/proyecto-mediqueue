/**
 * Escenario B — Concurrencia hostil sobre el mismo slot
 * 1000 VUs disparando simultáneamente al mismo slotId
 * Resultado esperado: 1 éxito (201), 999 rechazos (409 Conflict)
 * Demuestra: SELECT FOR UPDATE e índice parcial único evitan race conditions
 */
import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Counter } from "k6/metrics";

const successRate = new Rate("success_rate");
const conflictRate = new Rate("conflict_rate");
const errorRate = new Rate("unexpected_error_rate");
const successCount = new Counter("appointments_created");
const conflictCount = new Counter("conflicts_returned");

const GATEWAY_URL = __ENV.GATEWAY_URL || "http://localhost:8080";
const SLOT_ID = __ENV.SLOT_ID || "1";
const PATIENT_IDS = Array.from({ length: 1000 }, (_, i) => i + 1);

export const options = {
  scenarios: {
    hostile_concurrency: {
      executor: "shared-iterations",
      vus: 1000,
      iterations: 1000,
      maxDuration: "60s",
    },
  },
  thresholds: {
    appointments_created: ["count==1"],
    conflicts_returned: ["count>=999"],
    unexpected_error_rate: ["rate<0.001"],
  },
};

export default function () {
  const vu = __VU;
  const patientId = PATIENT_IDS[(vu - 1) % PATIENT_IDS.length];
  const idempotencyKey = `scenario-b-vu-${vu}-iter-${__ITER}`;

  const payload = JSON.stringify({
    patientId: patientId,
    slotId: parseInt(SLOT_ID),
    notes: `Concurrency test VU-${vu}`,
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": idempotencyKey,
      "Accept": "application/json",
    },
    tags: { name: "POST /api/appointments" },
  };

  const res = http.post(`${GATEWAY_URL}/api/appointments`, payload, params);

  const isSuccess = res.status === 201;
  const isConflict = res.status === 409;
  const isUnexpected = !isSuccess && !isConflict;

  check(res, {
    "is 201 or 409": (r) => r.status === 201 || r.status === 409,
    "no server error": (r) => r.status < 500,
  });

  successRate.add(isSuccess);
  conflictRate.add(isConflict);
  errorRate.add(isUnexpected);

  if (isSuccess) {
    successCount.add(1);
    console.log(`VU ${vu}: RESERVA EXITOSA - appointmentId=${JSON.parse(res.body)?.id}`);
  }
  if (isConflict) {
    conflictCount.add(1);
  }
  if (isUnexpected) {
    console.error(`VU ${vu}: ERROR INESPERADO status=${res.status} body=${res.body}`);
  }
}

export function handleSummary(data) {
  const created = data.metrics.appointments_created?.values?.count || 0;
  const conflicts = data.metrics.conflicts_returned?.values?.count || 0;
  const unexpected = data.metrics.unexpected_error_rate?.values?.rate || 0;

  const passed = created === 1 && conflicts >= 999 && unexpected < 0.001;

  console.log("\n==============================");
  console.log("RESUMEN ESCENARIO B");
  console.log("==============================");
  console.log(`Reservas exitosas:   ${created}  (esperado: 1)`);
  console.log(`Conflictos 409:      ${conflicts}  (esperado: ~999)`);
  console.log(`Errores inesperados: ${(unexpected * 100).toFixed(3)}%`);
  console.log(`RESULTADO:           ${passed ? "✅ PASÓ" : "❌ FALLÓ"}`);
  console.log("==============================\n");

  return {
    "results/scenario-b-summary.json": JSON.stringify({
      timestamp: new Date().toISOString(),
      scenario: "B - Concurrencia hostil",
      appointmentsCreated: created,
      conflicts: conflicts,
      unexpectedErrors: unexpected,
      passed,
    }, null, 2),
    stdout: JSON.stringify(data, null, 2),
  };
}
