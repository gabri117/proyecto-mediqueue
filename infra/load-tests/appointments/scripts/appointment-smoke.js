import http from 'k6/http';
import { check, fail } from 'k6';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';
import { handleSummary } from '../../lib/summary.js';

export { handleSummary };

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const DATA_FILE = __ENV.DATA_FILE || __ENV.DATASET || '../data/appointments.sample.json';
const TOTAL_APPOINTMENTS = Number(__ENV.TOTAL_APPOINTMENTS || 10);
const VUS = Number(__ENV.VUS || 5);
const RUN_ID = __ENV.RUN_ID || String(Date.now());

const appointmentAttempts = new Counter('appointment_attempts');
const appointmentsCreated = new Counter('appointments_created');
const appointmentsConflict = new Counter('appointments_conflict');
const appointmentsValidationError = new Counter('appointments_validation_error');
const appointmentsRateLimited = new Counter('appointments_rate_limited');
const appointmentsServerError = new Counter('appointments_server_error');
const appointmentsUnexpected = new Counter('appointments_unexpected');

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 599 }));

const appointments = new SharedArray('appointments dataset', () => {
  const parsed = JSON.parse(open(DATA_FILE));
  return Array.isArray(parsed) ? parsed : parsed.appointments;
});

export const options = {
  scenarios: {
    appointment_smoke: {
      executor: 'shared-iterations',
      vus: VUS,
      iterations: TOTAL_APPOINTMENTS,
      maxDuration: __ENV.MAX_DURATION || '2m',
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    appointments_server_error: ['count==0'],
    appointments_unexpected: ['count==0'],
  },
};

export function setup() {
  if (!appointments || appointments.length < TOTAL_APPOINTMENTS) {
    fail(`DATA_FILE=${DATA_FILE} no tiene suficientes citas. Requiere ${TOTAL_APPOINTMENTS}, contiene ${appointments ? appointments.length : 0}. Genera primero el dataset.`);
  }
}

export default function () {
  const index = exec.scenario.iterationInTest;
  const body = normalizeAppointment(appointments[index]);
  const res = http.post(`${BASE_URL}/api/appointments`, JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-Client-Id': `k6-appointment-smoke-${__VU}`,
      'X-Idempotency-Key': `appointment-smoke-${RUN_ID}-${index}`,
    },
    tags: {
      block: '2',
      service: 'appointment-service',
      endpoint: '/api/appointments',
      name: 'appointment smoke create',
    },
  });

  classify(res);

  check(res, {
    'tiene respuesta HTTP valida': (r) => typeof r.status === 'number' && r.status > 0,
    'no 5xx': (r) => r.status < 500,
    'no RedisConnectionFailureException': (r) => !String(r.body || '').includes('RedisConnectionFailureException'),
    'status esperado para smoke limpio': (r) => [200, 201, 202].includes(r.status),
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
    notes: row.notes || 'Block 2 appointment smoke',
  };
}

function normalizeTime(value) {
  if (!value) return value;
  const text = String(value);
  return text.length === 5 ? `${text}:00` : text;
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
