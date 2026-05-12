import http from "k6/http";
import { check } from "k6";
import exec from "k6/execution";
import { Counter } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://host.docker.internal:8080";
const RUN_ID = __ENV.RUN_ID || String(Date.now());

const approvedPayments = new Counter("approved_payments");
const rejectedPayments = new Counter("rejected_payments");
const timeoutPayments = new Counter("timeout_payments");
const rateLimitedRequests = new Counter("rate_limited_requests");
const serviceUnavailableRequests = new Counter("service_unavailable_requests");
const badRequests = new Counter("bad_requests");
const conflicts = new Counter("conflicts");
const unexpectedResponses = new Counter("unexpected_responses");

export const options = {
  scenarios: {
    payment_load_constant_rate: {
      executor: "constant-arrival-rate",

      // Cantidad de requests por segundo.
      rate: Number(__ENV.RATE || 500),

      timeUnit: "1s",

      // Duración de la prueba.
      // Para 500,000 pagos:
      // RATE=1000 y DURATION=8m20s
      // RATE=500 y DURATION=16m40s
      duration: __ENV.DURATION || "5m",

      // VUs reservados para sostener la tasa.
      preAllocatedVUs: Number(__ENV.PRE_ALLOCATED_VUS || 1000),
      maxVUs: Number(__ENV.MAX_VUS || 5000),
    },
  },

  thresholds: {
    http_req_duration: ["p(95)<5000"],
  },

  summaryTrendStats: ["min", "avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

function uuidFromNumber(n, prefix, group) {
  const hex = Number(n).toString(16).padStart(12, "0");
  return `${prefix}-0000-4000-${group}-${hex}`;
}

function safeJson(response) {
  try {
    return response.json();
  } catch (error) {
    return {};
  }
}

export default function () {
  const i = exec.scenario.iterationInTest + 1;

  const appointmentId = uuidFromNumber(i, "70000000", "8000");
  const patientId = uuidFromNumber(i, "80000000", "9000");

  const payload = JSON.stringify({
    appointmentId: appointmentId,
    patientId: patientId,
    amount: 150.00,
    currency: "GTQ",
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": `arrival-payment-${RUN_ID}-${i}`,
      "X-Client-Id": `arrival-client-${i % 10000}`,
      "X-Correlation-Id": `arrival-correlation-${RUN_ID}-${i}`,
    },
    timeout: "30s",
  };

  const res = http.post(`${BASE_URL}/api/payments`, payload, params);

  const ok = res.status === 200 || res.status === 201 || res.status === 202;
  const rateLimited = res.status === 429;
  const unavailable = res.status === 503;
  const badRequest = res.status === 400;
  const conflict = res.status === 409;

  check(res, {
    "controlled response": () =>
      ok || rateLimited || unavailable || badRequest || conflict,
  });

  if (ok) {
    const body = safeJson(res);

    if (body.paymentStatus === "APPROVED") {
      approvedPayments.add(1);
    } else if (body.paymentStatus === "REJECTED") {
      rejectedPayments.add(1);
    } else if (body.paymentStatus === "TIMEOUT") {
      timeoutPayments.add(1);
    }
  } else if (rateLimited) {
    rateLimitedRequests.add(1);
  } else if (unavailable) {
    serviceUnavailableRequests.add(1);
  } else if (badRequest) {
    badRequests.add(1);
    console.log(`BAD_REQUEST status=${res.status} body=${res.body}`);
  } else if (conflict) {
    conflicts.add(1);
  } else {
    unexpectedResponses.add(1);
    console.log(`UNEXPECTED status=${res.status} body=${res.body}`);
  }
}