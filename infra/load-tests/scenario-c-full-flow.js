/**
 * Escenario C — Flujo completo bajo carga + falla inducida
 * 100 VUs durante 5 minutos: consultar slots → crear cita → pagar → confirmar
 * A la mitad del test se mata una réplica de appointment-service (manual)
 * Resultado esperado: tasa de error < 1%, cero datos corruptos
 */
import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";

const flowErrorRate = new Rate("flow_error_rate");
const flowDuration = new Trend("full_flow_duration_ms", true);
const completedFlows = new Counter("completed_flows");
const failedFlows = new Counter("failed_flows");

const GATEWAY_URL = __ENV.GATEWAY_URL || "http://localhost:8080";

export const options = {
  stages: [
    { duration: "30s", target: 20 },
    { duration: "30s", target: 100 },
    { duration: "240s", target: 100 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    flow_error_rate: ["rate<0.01"],
    http_req_duration: ["p(95)<2000"],
    http_req_failed: ["rate<0.01"],
  },
};

function createPatient(vu) {
  const payload = JSON.stringify({
    firstName: `Test${vu}`,
    lastName: `User${__ITER}`,
    email: `test${vu}.${__ITER}.${Date.now()}@mediqueue.test`,
    documentNumber: `DOC${vu}${__ITER}${Date.now()}`,
    phone: `+549${String(vu).padStart(10, "0")}`,
  });
  return http.post(`${GATEWAY_URL}/api/patients`, payload, {
    headers: { "Content-Type": "application/json" },
    tags: { name: "POST /api/patients" },
  });
}

function getAvailableSlots(doctorId, date) {
  return http.get(`${GATEWAY_URL}/api/schedule/slots?doctorId=${doctorId}&date=${date}`, {
    headers: { "Accept": "application/json" },
    tags: { name: "GET /api/schedule/slots" },
  });
}

function createAppointment(patientId, slotId, idempotencyKey) {
  const payload = JSON.stringify({ patientId, slotId, notes: "Prueba de carga escenario C" });
  return http.post(`${GATEWAY_URL}/api/appointments`, payload, {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": idempotencyKey,
    },
    tags: { name: "POST /api/appointments" },
  });
}

function pollAppointmentStatus(appointmentId, maxRetries = 10) {
  for (let i = 0; i < maxRetries; i++) {
    const res = http.get(`${GATEWAY_URL}/api/appointments/${appointmentId}`, {
      tags: { name: "GET /api/appointments/:id" },
    });
    if (res.status === 200) {
      const body = JSON.parse(res.body);
      if (body.status === "CONFIRMED" || body.status === "CANCELLED" || body.status === "EXPIRED") {
        return body.status;
      }
    }
    sleep(1);
  }
  return "TIMEOUT";
}

export default function () {
  const startTime = Date.now();
  let flowFailed = false;

  const vu = __VU;
  const iter = __ITER;
  const doctorId = (vu % 10) + 1;
  const date = "2026-06-15";
  const idempotencyKey = `scenario-c-vu${vu}-iter${iter}-${Date.now()}`;

  group("1. Crear paciente", () => {
    const res = createPatient(vu);
    const ok = check(res, {
      "patient created (201)": (r) => r.status === 201,
    });
    if (!ok) {
      flowFailed = true;
      return;
    }
    const patient = JSON.parse(res.body);

    group("2. Consultar slots disponibles", () => {
      const slotsRes = getAvailableSlots(doctorId, date);
      const slotsOk = check(slotsRes, {
        "slots returned (200)": (r) => r.status === 200,
        "has slots": (r) => {
          try {
            return JSON.parse(r.body).length > 0;
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
        const apptRes = createAppointment(patient.id, slot.id, idempotencyKey);
        const apptOk = check(apptRes, {
          "appointment created or conflict (201|409)": (r) => r.status === 201 || r.status === 409,
          "no server error": (r) => r.status < 500,
        });
        if (!apptOk || apptRes.status === 409) {
          if (apptRes.status !== 409) flowFailed = true;
          return;
        }

        const appointment = JSON.parse(apptRes.body);

        group("4. Esperar confirmación", () => {
          sleep(2);
          const finalStatus = pollAppointmentStatus(appointment.id);
          const confirmed = check({ status: finalStatus }, {
            "appointment CONFIRMED": (s) => s.status === "CONFIRMED",
          });
          if (!confirmed) {
            console.warn(`VU ${vu} iter ${iter}: cita ${appointment.id} finalizó en ${finalStatus}`);
          }
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

export function handleSummary(data) {
  const completed = data.metrics.completed_flows?.values?.count || 0;
  const failed = data.metrics.failed_flows?.values?.count || 0;
  const errorRate = data.metrics.flow_error_rate?.values?.rate || 0;
  const p95 = data.metrics.http_req_duration?.values?.["p(95)"] || 0;

  console.log("\n==============================");
  console.log("RESUMEN ESCENARIO C");
  console.log("==============================");
  console.log(`Flujos completados: ${completed}`);
  console.log(`Flujos fallidos:    ${failed}`);
  console.log(`Tasa de error:      ${(errorRate * 100).toFixed(2)}% (umbral: <1%)`);
  console.log(`p95 latencia HTTP:  ${p95.toFixed(2)}ms`);
  console.log(`RESULTADO:          ${errorRate < 0.01 ? "✅ PASÓ" : "❌ FALLÓ"}`);
  console.log("==============================\n");

  return {
    "results/scenario-c-summary.json": JSON.stringify({
      timestamp: new Date().toISOString(),
      scenario: "C - Flujo completo bajo carga",
      completedFlows: completed,
      failedFlows: failed,
      errorRate,
      p95DurationMs: p95,
    }, null, 2),
    stdout: JSON.stringify(data, null, 2),
  };
}
