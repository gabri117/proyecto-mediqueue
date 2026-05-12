/**
 * Escenario A — Carga sostenida de consultas de slots
 * Objetivo: 50,000 peticiones GET /api/schedule/slots en 2-3 minutos
 * Concurrencia: 200 VUs
 * Demuestra: caché Redis funciona y lecturas escalan
 */
import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";

const errorRate = new Rate("error_rate");
const slotResponseTime = new Trend("slot_response_time", true);
const totalRequests = new Counter("total_requests");

const GATEWAY_URL = __ENV.GATEWAY_URL || "http://localhost:8080";
const DOCTOR_IDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const DATES = ["2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05"];

export const options = {
  stages: [
    { duration: "30s", target: 50 },
    { duration: "30s", target: 100 },
    { duration: "30s", target: 200 },
    { duration: "90s", target: 200 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_duration: ["p(95)<500", "p(99)<1000"],
    error_rate: ["rate<0.01"],
    http_req_failed: ["rate<0.01"],
  },
};

export default function () {
  const doctorId = DOCTOR_IDS[Math.floor(Math.random() * DOCTOR_IDS.length)];
  const date = DATES[Math.floor(Math.random() * DATES.length)];

  const url = `${GATEWAY_URL}/api/schedule/slots?doctorId=${doctorId}&date=${date}`;
  const params = {
    headers: { "Accept": "application/json" },
    tags: { name: "GET /api/schedule/slots" },
  };

  const res = http.get(url, params);

  const ok = check(res, {
    "status is 200": (r) => r.status === 200,
    "body is not empty": (r) => r.body && r.body.length > 0,
    "response time < 500ms": (r) => r.timings.duration < 500,
  });

  errorRate.add(!ok);
  slotResponseTime.add(res.timings.duration);
  totalRequests.add(1);

  sleep(0.1);
}

export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    scenario: "A - Carga sostenida de slots",
    totalRequests: data.metrics.total_requests ? data.metrics.total_requests.values.count : 0,
    errorRate: data.metrics.error_rate ? data.metrics.error_rate.values.rate : 0,
    p95: data.metrics.http_req_duration ? data.metrics.http_req_duration.values["p(95)"] : 0,
    p99: data.metrics.http_req_duration ? data.metrics.http_req_duration.values["p(99)"] : 0,
    avgDuration: data.metrics.http_req_duration ? data.metrics.http_req_duration.values.avg : 0,
  };

  console.log("\n==============================");
  console.log("RESUMEN ESCENARIO A");
  console.log("==============================");
  console.log(`Total requests:  ${summary.totalRequests}`);
  console.log(`Error rate:      ${(summary.errorRate * 100).toFixed(2)}%`);
  console.log(`Avg duration:    ${summary.avgDuration.toFixed(2)}ms`);
  console.log(`p95 duration:    ${summary.p95.toFixed(2)}ms`);
  console.log(`p99 duration:    ${summary.p99.toFixed(2)}ms`);
  console.log("==============================\n");

  return {
    "results/scenario-a-summary.json": JSON.stringify(summary, null, 2),
    stdout: JSON.stringify(data, null, 2),
  };
}
