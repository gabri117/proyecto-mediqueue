import http from 'k6/http';
import { group, sleep } from 'k6';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkJsonResponse, checkStatus } from '../lib/checks.js';
import { randomInt, uuidv4 } from '../lib/ids.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 409));

const includeIdempotency = (__ENV.INCLUDE_PAYMENT_IDEMPOTENCY || 'false').toLowerCase() === 'true';

export const options = {
  scenarios: {
    payment_write_load: {
      executor: 'constant-vus',
      vus: Number(__ENV.PAYMENT_VUS || 50),
      duration: __ENV.PAYMENT_DURATION || '2m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000', 'p(99)<4000'],
    'http_req_failed{scenario:payment_idempotency}': ['rate<0.01'],
  },
};

function paymentBody(override = {}) {
  return {
    appointmentId: __ENV.APPOINTMENT_ID || uuidv4(),
    patientId: __ENV.PATIENT_ID || uuidv4(),
    amount: Number(__ENV.PAYMENT_AMOUNT || randomInt(100, 500)),
    currency: 'GTQ',
    ...override,
  };
}

function postPayment(body, key, name, allowed = [200, 201, 202, 409]) {
  const res = http.post(url('/api/payments'), JSON.stringify(body), {
    headers: jsonHeaders({
      'X-Idempotency-Key': key,
      'X-Correlation-Id': correlationId('payment'),
    }),
    tags: { service: 'payment-service', endpoint: '/api/payments', name },
  });
  checkStatus(name, allowed)(res);
  if ([200, 201, 202, 409].includes(res.status)) {
    checkJsonResponse(name)(res);
  }
  return res;
}

export default function () {
  const body = paymentBody();
  postPayment(body, `payment-${uuidv4()}`, 'create payment');

  if (includeIdempotency && __ITER === 0) {
    group('payment idempotency', () => {
      const key = `payment-idem-${uuidv4()}`;
      const idemBody = paymentBody({ appointmentId: uuidv4(), patientId: uuidv4(), amount: 150 });
      postPayment(idemBody, key, 'idempotency first request');
      postPayment(idemBody, key, 'idempotency same key same body');
      postPayment({ ...idemBody, amount: 175 }, key, 'idempotency same key different body', [409]);
    });
  }

  sleep(1);
}
