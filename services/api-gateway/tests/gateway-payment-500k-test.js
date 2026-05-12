import http from "k6/http";
import { check, sleep } from "k6";
import exec from "k6/execution";
import { Counter } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://host.docker.internal:8080";

const TOTAL_PAYMENTS = Number(__ENV.TOTAL_PAYMENTS || 500000);
const VUS = Number(__ENV.VUS || 50000);
const MAX_DURATION = __ENV.MAX_DURATION || "30m";
const CLIENT_POOL = Number(__ENV.CLIENT_POOL || 50000);
const RUN_ID = __ENV.RUN_ID || String(Date.now());

const approvedPayments = new Counter("approved_payments");
const rejectedPayments = new Counter("rejected_payments");
const timeoutPayments = new Counter("timeout_payments");
const processingPayments = new Counter("processing_payments");
const successfulHttp = new Counter("successful_http");
const rateLimitedRequests = new Counter("rate_limited_requests");
const serviceUnavailableRequests = new Counter("service_unavailable_requests");
const badRequests = new Counter("bad_requests");
const conflictRequests = new Counter("conflict_requests");
const unexpectedResponses = new Counter("unexpected_responses");

export const options = {
  scenarios: {
    massive_payment_load: {
      executor: "shared-iterations",
      vus: VUS,
      iterations: TOTAL_PAYMENTS,
      maxDuration: MAX_DURATION,
      gracefulStop: "1m",
    },
  },

  thresholds: {
    http_req_failed: ["rate<0.20"],
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

  const appointmentId = uuidFromNumber(i, "50000000", "8000");
  const patientId = uuidFromNumber(i, "60000000", "9000");

  const payload = JSON.stringify({
    appointmentId: appointmentId,
    patientId: patientId,
    amount: 150.00,
    currency: "GTQ",
  });

  const clientNumber = i % CLIENT_POOL;

  const params = {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": `massive-payment-${RUN_ID}-${i}`,
      "X-Client-Id": `massive-client-${clientNumber}`,
      "X-Correlation-Id": `massive-correlation-${RUN_ID}-${i}`,
    },
    timeout: "30s",
  };

  const res = http.post(`${BASE_URL}/api/payments`, payload, params);

  const acceptedHttp =
    res.status === 200 ||
    res.status === 201 ||
    res.status === 202;

  const rateLimited = res.status === 429;
  const serviceUnavailable = res.status === 503;
  const badRequest = res.status === 400;
  const conflict = res.status === 409;

  check(res, {
    "accepted, rate limited, or controlled failure": () =>
      acceptedHttp || rateLimited || serviceUnavailable || badRequest || conflict,
  });

  if (acceptedHttp) {
    successfulHttp.add(1);

    const body = safeJson(res);

    if (body.paymentStatus === "APPROVED") {
      approvedPayments.add(1);
    } else if (body.paymentStatus === "REJECTED") {
      rejectedPayments.add(1);
    } else if (body.paymentStatus === "TIMEOUT") {
      timeoutPayments.add(1);
    } else {
      processingPayments.add(1);
    }
  } else if (rateLimited) {
    rateLimitedRequests.add(1);
  } else if (serviceUnavailable) {
    serviceUnavailableRequests.add(1);
  } else if (badRequest) {
    badRequests.add(1);
    console.log(`BAD_REQUEST i=${i} status=${res.status} body=${res.body}`);
  } else if (conflict) {
    conflictRequests.add(1);
  } else {
    unexpectedResponses.add(1);
    console.log(`UNEXPECTED i=${i} status=${res.status} body=${res.body}`);
  }

  sleep(0.001);
}