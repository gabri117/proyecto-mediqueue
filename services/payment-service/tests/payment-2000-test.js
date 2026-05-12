import http from "k6/http";
import { check, sleep } from "k6";
import exec from "k6/execution";
import { Counter } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8084";

const uniqueApproved = new Counter("unique_approved");
const uniqueFailed = new Counter("unique_failed");
const duplicateRejected = new Counter("duplicate_rejected");
const duplicateUnexpected = new Counter("duplicate_unexpected");

export const options = {
  scenarios: {
    unique_payments: {
      executor: "shared-iterations",
      exec: "uniquePayments",
      vus: 100,
      iterations: 1500,
      maxDuration: "3m"
    },

    duplicate_payments: {
      executor: "shared-iterations",
      exec: "duplicatePayments",
      startTime: "35s",
      vus: 50,
      iterations: 500,
      maxDuration: "2m"
    }
  }
};

function uuidFromNumber(n, group) {
  const hex = String(n).padStart(12, "0");
  return `00000000-0000-4000-${group}-${hex}`;
}

function parseJson(response) {
  try {
    return response.json();
  } catch (error) {
    return {};
  }
}

export function uniquePayments() {
  const i = exec.scenario.iterationInTest + 1;

  const appointmentId = uuidFromNumber(i, "8000");
  const patientId = uuidFromNumber(i, "9000");

  const payload = JSON.stringify({
    appointmentId: appointmentId,
    patientId: patientId,
    amount: 150.00,
    currency: "GTQ"
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": `unique-payment-${i}`
    },
    timeout: "30s"
  };

  const res = http.post(`${BASE_URL}/payments`, payload, params);
  const body = parseJson(res);

  const approved =
    (res.status === 200 || res.status === 201) &&
    body.paymentStatus === "APPROVED";

  check(res, {
    "unique payment approved": () => approved
  });

  if (approved) {
    uniqueApproved.add(1);
  } else {
    uniqueFailed.add(1);
    console.log(`UNIQUE FAILED i=${i} status=${res.status} body=${res.body}`);
  }

  sleep(0.01);
}

export function duplicatePayments() {
  const i = exec.scenario.iterationInTest + 1;

  const appointmentId = uuidFromNumber(i, "8000");
  const patientId = uuidFromNumber(i, "9000");

  const payload = JSON.stringify({
    appointmentId: appointmentId,
    patientId: patientId,
    amount: 150.00,
    currency: "GTQ"
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": `duplicate-payment-${i}`
    },
    timeout: "30s"
  };

  const res = http.post(`${BASE_URL}/payments`, payload, params);
  const body = parseJson(res);

  const duplicateWasRejected =
    res.status === 409 ||
    ((res.status === 200 || res.status === 201) && body.paymentStatus === "REJECTED");

  check(res, {
    "duplicate payment rejected or conflict": () => duplicateWasRejected
  });

  if (duplicateWasRejected) {
    duplicateRejected.add(1);
  } else {
    duplicateUnexpected.add(1);
    console.log(`DUPLICATE UNEXPECTED i=${i} status=${res.status} body=${res.body}`);
  }

  sleep(0.01);
}