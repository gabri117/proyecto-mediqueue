import http from 'k6/http';
import { check, fail } from 'k6';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';
import { handleSummary } from '../../lib/summary.js';

export { handleSummary };

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const DATA_FILE = __ENV.DATA_FILE || __ENV.DATASET || '../data/appointments-50000.json';
const TOTAL_APPOINTMENTS = Number(__ENV.TOTAL_APPOINTMENTS || 50000);
const VUS = Number(__ENV.VUS || 200);
const MAX_DURATION = __ENV.MAX_DURATION || '10m';
const RUN_ID = __ENV.RUN_ID || String(Date.now());
const CLIENT_MODE = (__ENV.CLIENT_MODE || 'per-vu').toLowerCase();

const appointmentAttempts = new Counter('appointment_attempts');
const appointmentsCreated = new Counter('appointments_created');
const appointmentsConflict = new Counter('appointments_conflict');
const appointmentsValidationError = new Counter('appointments_validation_error');
const appointmentsRateLimited = new Counter('appointments_rate_limited');
const appointmentsServerError = new Counter('appointments_server_error');
const appointmentsUnexpected = new Counter('appointments_unexpected');

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 599 }));

const appointments = new SharedArray('appointments dataset', () => {
  const parsed = readJsonFile(DATA_FILE);
  return Array.isArray(parsed) ? parsed : parsed.appointments;
});

export const options = {
  scenarios: {
    appointment_fixed_total: {
      executor: 'shared-iterations',
      vus: VUS,
      iterations: TOTAL_APPOINTMENTS,
      maxDuration: MAX_DURATION,
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    appointments_server_error: ['count==0'],
    appointments_unexpected: ['count==0'],
  },
};

export function setup() {
  if (!['per-vu', 'single', 'per-iteration'].includes(CLIENT_MODE)) {
    fail(`CLIENT_MODE invalido: ${CLIENT_MODE}. Usa per-vu, single o per-iteration.`);
  }

  if (!appointments || appointments.length < TOTAL_APPOINTMENTS) {
    fail(`DATA_FILE=${DATA_FILE} no tiene suficientes citas. TOTAL_APPOINTMENTS=${TOTAL_APPOINTMENTS}, dataset.length=${appointments ? appointments.length : 0}.`);
  }
}

export default function () {
  const index = exec.scenario.iterationInTest;
  const body = normalizeAppointment(appointments[index]);
  const res = http.post(`${BASE_URL}/api/appointments`, JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-Client-Id': clientId(index),
      'X-Idempotency-Key': `appointment-fixed-${RUN_ID}-${index}`,
    },
    tags: {
      block: '2',
      service: 'appointment-service',
      endpoint: '/api/appointments',
      name: 'appointment fixed total create',
    },
  });

  classify(res);

  check(res, {
    'tiene respuesta HTTP valida': (r) => typeof r.status === 'number' && r.status > 0,
    'no 5xx': (r) => r.status < 500,
    'no RedisConnectionFailureException': (r) => !String(r.body || '').includes('RedisConnectionFailureException'),
    'status esperado para citas exitosas': (r) => [200, 201, 202].includes(r.status),
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
    notes: row.notes || 'Block 2 fixed-total appointment',
  };
}

function readJsonFile(path) {
  let content;
  try {
    content = open(path);
  } catch (e) {
    if (path.startsWith('/')) throw e;
    const filename = path.split('/').pop();
    const fallback = `../data/${filename}`;
    try {
      content = open(fallback);
    } catch (e2) {
      throw new Error(
        `Cannot open data file. Tried: "${path}" and "${fallback}". ` +
        `Pass DATA_FILE as absolute path: --env DATA_FILE=$(pwd)/${path}`
      );
    }
  }
  return JSON.parse(content.replace(/^\uFEFF/, '').replace(/^\u00EF\u00BB\u00BF/, ''));
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
