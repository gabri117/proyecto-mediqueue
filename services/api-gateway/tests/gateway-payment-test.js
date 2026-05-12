import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  vus: 20,
  iterations: 100
};

export default function () {
  const i = __ITER + (__VU * 1000);

  const payload = JSON.stringify({
    appointmentId: `99999999-0000-4000-8000-${String(i).padStart(12, "0")}`,
    patientId: `88888888-0000-4000-9000-${String(i).padStart(12, "0")}`,
    amount: 150.00,
    currency: "GTQ"
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      "X-Idempotency-Key": `gateway-k6-payment-${i}`,
      "X-Client-Id": "gateway-k6-client"
    }
  };

  const res = http.post("http://host.docker.internal:8080/api/payments", payload, params);

  const ok = res.status === 200 || res.status === 201;

check(res, {
  "gateway returns success": () => ok
});

if (!ok) {
  console.log(`FAILED status=${res.status} body=${res.body}`);
}

  sleep(0.1);
}