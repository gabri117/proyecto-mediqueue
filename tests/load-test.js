/**
 * MediQueue — Prueba de carga E2E (K6)
 *
 * Escenario principal para el Checkpoint 1.
 * Simula el flujo completo: crear paciente → crear cita → verificar estado.
 *
 * Ejecutar:
 *   k6 run tests/load-test.js
 *   k6 run --env GATEWAY_URL=http://localhost:8080 tests/load-test.js
 *
 * Para 50,000 peticiones totales (requerimiento de la rúbrica):
 *   k6 run --iterations 50000 --vus 100 tests/load-test.js
 */
import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";

// ─── Custom Metrics ────────────────────────────────────────────────────────────
const flowErrorRate = new Rate("flow_error_rate");
const flowDuration = new Trend("full_flow_duration_ms", true);
const completedFlows = new Counter("completed_flows");
const failedFlows = new Counter("failed_flows");

// ─── Configuration ─────────────────────────────────────────────────────────────
const GATEWAY_URL = __ENV.GATEWAY_URL || "http://localhost:8080";

export const options = {
  scenarios: {
    // Escenario A: Ramp-up gradual hasta 100 VUs
    ramp_up: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 10 },
        { duration: "30s", target: 50 },
        { duration: "2m", target: 100 },
        { duration: "1m", target: 100 },
        { duration: "30s", target: 0 },
      ],
      gracefulRampDown: "10s",
    },
  },
  thresholds: {
    flow_error_rate: ["rate<0.01"],            // < 1% error rate
    http_req_duration: ["p(95)<2000"],          // p95 < 2s
    http_req_failed: ["rate<0.01"],            // < 1% HTTP failures
    full_flow_duration_ms: ["p(95)<5000"],     // Full flow p95 < 5s
  },
};

// ─── Helper Functions ──────────────────────────────────────────────────────────

function createPatient(vu, iter) {
  const payload = JSON.stringify({
    firstName: `LoadTest${vu}`,
    lastName: `User${iter}`,
    email: `loadtest.vu${vu}.iter${iter}.${Date.now()}@mediqueue.test`,
    phone: `+506${String(vu).padStart(8, "0")}`,
    documentNumber: `LT-${vu}-${iter}-${Date.now()}`,
  });

  return http.post(`${GATEWAY_URL}/api/patients`, payload, {
    headers: { "Content-Type": "application/json" },
    tags: { name: "POST /api/patients" },
  });
}

function getAvailableSlots() {
  return http.get(`${GATEWAY_URL}/api/slots/available`, {
    headers: { Accept: "application/json" },
    tags: { name: "GET /api/slots/available" },
  });
}

function createAppointment(patientId, dentistId, slotId, date, startTime, endTime, idempotencyKey) {
  const payload = JSON.stringify({
    patientId,
    dentistId,
    slotId,
    appointmentDate: date,
    startTime,
    endTime,
    notes: "Prueba de carga — load-test.js",
  });

  return http.post(`${GATEWAY_URL}/api/appointments`, payload, {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": idempotencyKey,
    },
    tags: { name: "POST /api/appointments" },
  });
}

function getAppointment(appointmentId) {
  return http.get(`${GATEWAY_URL}/api/appointments/${appointmentId}`, {
    tags: { name: "GET /api/appointments/:id" },
  });
}

function getPayments(appointmentId) {
  return http.get(`${GATEWAY_URL}/api/payments?appointmentId=${appointmentId}`, {
    tags: { name: "GET /api/payments" },
  });
}

// ─── Main Test Flow ────────────────────────────────────────────────────────────

export default function () {
  const startTime = Date.now();
  let flowFailed = false;

  const vu = __VU;
  const iter = __ITER;
  const idempotencyKey = `lt-vu${vu}-iter${iter}-${Date.now()}`;

  group("1. Crear paciente", () => {
    const res = createPatient(vu, iter);
    const ok = check(res, {
      "patient created (201)": (r) => r.status === 201,
    });

    if (!ok) {
      flowFailed = true;
      return;
    }

    const patient = JSON.parse(res.body);

    group("2. Consultar slots disponibles", () => {
      const slotsRes = getAvailableSlots();
      const slotsOk = check(slotsRes, {
        "slots returned (200)": (r) => r.status === 200,
        "has slots": (r) => {
          try {
            const body = JSON.parse(r.body);
            return Array.isArray(body) && body.length > 0;
          } catch (_) {
            return false;
          }
        },
      });

      if (!slotsOk) {
        flowFailed = true;
        return;
      }

      const slots = JSON.parse(slotsRes.body);
      const slot = slots[Math.floor(Math.random() * slots.length)];

      group("3. Crear cita", () => {
        const apptRes = createAppointment(
          patient.id,
          slot.dentistId,
          slot.id,
          slot.slotDate,
          slot.startTime,
          slot.endTime,
          idempotencyKey
        );

        const apptOk = check(apptRes, {
          "appointment created or conflict (201|409)": (r) =>
            r.status === 201 || r.status === 409,
          "no server error": (r) => r.status < 500,
        });

        if (!apptOk || apptRes.status === 409) {
          if (apptRes.status !== 409) flowFailed = true;
          return;
        }

        const appointment = JSON.parse(apptRes.body);

        group("4. Verificar cita y pago", () => {
          sleep(2);

          const apptCheck = getAppointment(appointment.id);
          check(apptCheck, {
            "appointment retrieved (200)": (r) => r.status === 200,
          });

          const paymentCheck = getPayments(appointment.id);
          check(paymentCheck, {
            "payments query (200)": (r) => r.status === 200,
          });
        });
      });
    });
  });

  const duration = Date.now() - startTime;
  flowDuration.add(duration);
  flowErrorRate.add(flowFailed);

  if (flowFailed) {
    failedFlows.add(1);
  } else {
    completedFlows.add(1);
  }

  sleep(1);
}

// ─── Summary Report ────────────────────────────────────────────────────────────

export function handleSummary(data) {
  const completed = data.metrics.completed_flows?.values?.count || 0;
  const failed = data.metrics.failed_flows?.values?.count || 0;
  const errorRate = data.metrics.flow_error_rate?.values?.rate || 0;
  const p95 = data.metrics.http_req_duration?.values?.["p(95)"] || 0;
  const p99 = data.metrics.http_req_duration?.values?.["p(99)"] || 0;

  console.log("\n══════════════════════════════════════════");
  console.log("  MEDIQUEUE — RESUMEN DE PRUEBA DE CARGA  ");
  console.log("══════════════════════════════════════════");
  console.log(`  Flujos completados:  ${completed}`);
  console.log(`  Flujos fallidos:     ${failed}`);
  console.log(`  Tasa de error:       ${(errorRate * 100).toFixed(2)}% (umbral: <1%)`);
  console.log(`  p95 latencia HTTP:   ${p95.toFixed(2)}ms`);
  console.log(`  p99 latencia HTTP:   ${p99.toFixed(2)}ms`);
  console.log(`  RESULTADO:           ${errorRate < 0.01 ? "✅ PASÓ" : "❌ FALLÓ"}`);
  console.log("══════════════════════════════════════════\n");

  return {
    "tests/results/load-test-summary.json": JSON.stringify(
      {
        timestamp: new Date().toISOString(),
        scenario: "E2E Load Test — Checkpoint 1",
        completedFlows: completed,
        failedFlows: failed,
        errorRate,
        p95DurationMs: p95,
        p99DurationMs: p99,
        passed: errorRate < 0.01,
      },
      null,
      2
    ),
    stdout: JSON.stringify(data, null, 2),
  };
}
