import http from 'k6/http';
import { group, sleep } from 'k6';
import { Counter } from 'k6/metrics';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkJsonResponse, checkStatus } from '../lib/checks.js';
import { randomInt, uuidv4 } from '../lib/ids.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 409, 429));

const includeIdempotency = (__ENV.INCLUDE_PAYMENT_IDEMPOTENCY || 'false').toLowerCase() === 'true';
const loadProfile = (__ENV.LOAD_PROFILE || 'realistic').toLowerCase();

const status200 = new Counter('payment_status_200');
const status201 = new Counter('payment_status_201');
const status202 = new Counter('payment_status_202');
const status409 = new Counter('payment_status_409');
const status429 = new Counter('payment_status_429');
const status5xx = new Counter('payment_status_5xx');
const statusOther = new Counter('payment_status_other');

function profileThresholds(profile) {
  if (profile === 'performance') {
    return {
      http_req_failed: ['rate<0.05'],
      http_req_duration: ['p(95)<2000', 'p(99)<4000'],
      'http_req_failed{scenario:payment_idempotency}': ['rate<0.01'],
    };
  }

  if (profile === 'smoke') {
    return {
      http_req_failed: ['rate<0.01'],
      http_req_duration: ['p(95)<3000', 'p(99)<5000'],
      'http_req_failed{scenario:payment_idempotency}': ['rate<0.01'],
    };
  }

  return {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<9000', 'p(99)<11000'],
    'http_req_failed{scenario:payment_idempotency}': ['rate<0.01'],
  };
}

function profileScenario(profile) {
  if (profile === 'smoke') {
    return {
      executor: 'constant-vus',
      vus: Number(__ENV.PAYMENT_VUS || 1),
      duration: __ENV.PAYMENT_DURATION || '15s',
    };
  }

  return {
    executor: 'constant-vus',
    vus: Number(__ENV.PAYMENT_VUS || 50),
    duration: __ENV.PAYMENT_DURATION || '2m',
  };
}

export const options = {
  scenarios: {
    payment_write_load: profileScenario(loadProfile),
  },
  thresholds: profileThresholds(loadProfile),
};

export function setup() {
  console.log(`Payment load profile=${loadProfile}`);
  if (loadProfile === 'realistic') {
    console.log('Realistic profile expects PAYMENT_SIM_MAX_DELAY_MS near 8000ms; thresholds: p95<9000ms p99<11000ms.');
  }
  if (loadProfile === 'performance') {
    console.log('Performance profile expects reduced simulator delay, e.g. PAYMENT_SIM_MIN_DELAY_MS=50 and PAYMENT_SIM_MAX_DELAY_MS=500.');
  }
}

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
  recordStatus(res.status);
  checkStatus(name, [...allowed, 429])(res);
  if ([200, 201, 202, 409].includes(res.status)) {
    checkJsonResponse(name)(res);
  }
  return res;
}

function recordStatus(status) {
  if (status === 200) status200.add(1);
  else if (status === 201) status201.add(1);
  else if (status === 202) status202.add(1);
  else if (status === 409) status409.add(1);
  else if (status === 429) status429.add(1);
  else if (status >= 500 && status <= 599) status5xx.add(1);
  else statusOther.add(1);
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
