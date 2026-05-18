import http from 'k6/http';
import { check, fail } from 'k6';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';
import { handleSummary } from '../../lib/summary.js';

export { handleSummary };

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const DATA_FILE = __ENV.DATA_FILE || __ENV.DATASET || '../data/appointments-50000.json';
const RATE_PER_MINUTE = Number(__ENV.RATE_PER_MINUTE || 50000);
const DURATION = __ENV.DURATION || '1m';
const PRE_ALLOCATED_VUS = Number(__ENV.PRE_ALLOCATED_VUS || 1000);
const MAX_VUS = Number(__ENV.MAX_VUS || 3000);
const TOTAL_LIMIT = __ENV.TOTAL_LIMIT === undefined || __ENV.TOTAL_LIMIT === ''
  ? null
  : Number(__ENV.TOTAL_LIMIT);
const RUN_ID = __ENV.RUN_ID || String(Date.now());
const CLIENT_MODE = (__ENV.CLIENT_MODE || 'per-vu').toLowerCase();

const appointmentAttempts = new Counter('appointment_attempts');
const appointmentsCreated = new Counter('appointments_created');
const appointmentsConflict = new Counter('appointments_conflict');
const appointmentsValidationError = new Counter('appointments_validation_error');
const appointmentsRateLimited = new Counter('appointments_rate_limited');
const appointmentsServerError = new Counter('appointments_server_error');
const appointmentsUnexpected = new Counter('appointments_unexpected');
const appointmentsDatasetExhausted = new Counter('appointments_dataset_exhausted');

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 599 }));

const appointments = new SharedArray('appointments dataset', () => {
  const parsed = JSON.parse(open(DATA_FILE));
  return Array.isArray(parsed) ? parsed : parsed.appointments;
});

export const options = {
  scenarios: {
    appointment_rpm: {
      executor: 'constant-arrival-rate',
      rate: RATE_PER_MINUTE,
      timeUnit: '1m',
      duration: DURATION,
      preAllocatedVUs: PRE_ALLOCATED_VUS,
      maxVUs: MAX_VUS,
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    appointments_server_error: ['count==0'],
    appointments_unexpected: ['count==0'],
    appointments_dataset_exhausted: ['count==0'],
  },
};

export function setup() {
  if (!['per-vu', 'single', 'per-iteration'].includes(CLIENT_MODE)) {
    fail(`CLIENT_MODE invalido: ${CLIENT_MODE}. Usa per-vu, single o per-iteration.`);
  }

  if (TOTAL_LIMIT !== null && (!Number.isFinite(TOTAL_LIMIT) || TOTAL_LIMIT < 1)) {
    fail(`TOTAL_LIMIT invalido: ${__ENV.TOTAL_LIMIT}. Debe ser un entero positivo.`);
  }

  if (!appointments || appointments.length === 0) {
    fail(`DATA_FILE=${DATA_FILE} no contiene citas.`);
  }
}

export default function () {
  const index = exec.scenario.iterationInTest;

  if (TOTAL_LIMIT !== null && index >= TOTAL_LIMIT) {
    appointmentsDatasetExhausted.add(1);
    check(null, { 'no dataset exhausted': () => false });
    return;
  }

  if (index >= appointments.length) {
    appointmentsDatasetExhausted.add(1);
    check(null, { 'no dataset exhausted': () => false });
    return;
  }

  const body = normalizeAppointment(appointments[index]);
  const res = http.post(`${BASE_URL}/api/appointments`, JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-Client-Id': clientId(index),
      'X-Idempotency-Key': `appointment-rpm-${RUN_ID}-${index}`,
    },
    tags: {
      block: '2',
      service: 'appointment-service',
      endpoint: '/api/appointments',
      name: 'appointment rpm create',
    },
  });

  classify(res);

  check(res, {
    'tiene respuesta HTTP valida': (r) => typeof r.status === 'number' && r.status > 0,
    'no 5xx': (r) => r.status < 500,
    'no RedisConnectionFailureException': (r) => !String(r.body || '').includes('RedisConnectionFailureException'),
    'no dataset exhausted': () => true,
  });
}

function normalizeAppointment(row) {
  return {
    patientId: row.patientId,
    dentistId: row.dentistId,
    slotId: row.slotId,
    appointmentDate: row.appointmentDate,
    startTime: normalizeTime(row.startTime),
    endTime: normalizeTime(row.endTime),
    amount: Number(row.amount),
    notes: row.notes || 'Block 2 rpm appointment',
  };
}

function normalizeTime(value) {
  if (!value) return value;
  const text = String(value);
  return text.length === 5 ? `${text}:00` : text;
}

function clientId(index) {
  if (CLIENT_MODE === 'single') return 'k6-appointment-single';
  if (CLIENT_MODE === 'per-iteration') return `k6-appointment-${index}`;
  return `k6-appointment-vu-${__VU}`;
}

function classify(res) {
  appointmentAttempts.add(1);

  if ([200, 201, 202].includes(res.status)) {
    appointmentsCreated.add(1);
  } else if (res.status === 409) {
    appointmentsConflict.add(1);
  } else if ([400, 422].includes(res.status)) {
    appointmentsValidationError.add(1);
  } else if (res.status === 429) {
    appointmentsRateLimited.add(1);
  } else if (res.status >= 500 && res.status <= 599) {
    appointmentsServerError.add(1);
  } else {
    appointmentsUnexpected.add(1);
  }
}
