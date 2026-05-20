import http from 'k6/http';
import { check, fail } from 'k6';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';
import { handleSummary } from '../../lib/summary.js';

export { handleSummary };

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const DATA_FILE = __ENV.DATA_FILE || __ENV.DATASET || '../data/appointments.sample.json';
const TOTAL_ATTEMPTS = Number(__ENV.TOTAL_ATTEMPTS || __ENV.ITERATIONS || 1000);
const VUS = Number(__ENV.VUS || 500);
const RUN_ID = __ENV.RUN_ID || String(Date.now());
const SAME_SLOT_INDEX = Number(__ENV.SAME_SLOT_INDEX || 0);
const CLIENT_MODE = (__ENV.CLIENT_MODE || 'per-vu').toLowerCase();
const CLIENT_ID = __ENV.X_CLIENT_ID || __ENV.CLIENT_ID || 'k6-appointment-hostile';

const sameSlotSuccess = new Counter('same_slot_success');
const sameSlotConflict = new Counter('same_slot_conflict');
const sameSlotServerError = new Counter('same_slot_server_error');
const sameSlotUnexpected = new Counter('same_slot_unexpected');

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 599 }));

const appointments = new SharedArray('appointments dataset', () => {
  const parsed = readJsonFile(DATA_FILE);
  return Array.isArray(parsed) ? parsed : parsed.appointments;
});

export const options = {
  scenarios: {
    hostile_same_slot: {
      executor: 'shared-iterations',
      vus: VUS,
      iterations: TOTAL_ATTEMPTS,
      maxDuration: __ENV.MAX_DURATION || '5m',
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    same_slot_server_error: ['count==0'],
    same_slot_unexpected: ['count==0'],
  },
};

export function setup() {
  if (!['per-vu', 'single', 'per-iteration'].includes(CLIENT_MODE)) {
    fail(`CLIENT_MODE invalido: ${CLIENT_MODE}. Usa per-vu, single o per-iteration.`);
  }

  if (!appointments || appointments.length <= SAME_SLOT_INDEX) {
    fail(`DATA_FILE=${DATA_FILE} no contiene SAME_SLOT_INDEX=${SAME_SLOT_INDEX}. Filas disponibles=${appointments ? appointments.length : 0}.`);
  }
}

export default function () {
  const index = exec.scenario.iterationInTest;
  const baseRow = appointments[SAME_SLOT_INDEX];
  const patientRow = appointments[index % appointments.length] || baseRow;
  const body = sameSlotBody(baseRow, patientRow, index);

  const res = http.post(`${BASE_URL}/api/appointments`, JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-Client-Id': clientId(index),
      'X-Idempotency-Key': `appointment-hostile-same-slot-${RUN_ID}-${index}`,
    },
    tags: {
      block: '2',
      service: 'appointment-service',
      endpoint: '/api/appointments',
      name: 'appointment hostile same slot',
    },
  });

  classify(res);

  check(res, {
    'no 5xx': (r) => r.status < 500,
    'no RedisConnectionFailureException': (r) => !String(r.body || '').includes('RedisConnectionFailureException'),
    'respuesta esperada 201 o 409': (r) => r.status === 201 || r.status === 409,
  });
}

function sameSlotBody(baseRow, patientRow, index) {
  return {
    patientId: patientRow.patientId || baseRow.patientId,
    dentistId: baseRow.dentistId,
    slotId: baseRow.slotId,
    appointmentDate: baseRow.appointmentDate,
    startTime: normalizeTime(baseRow.startTime),
    endTime: normalizeTime(baseRow.endTime),
    amount: Number(baseRow.amount),
    notes: `Block 2 hostile same-slot attempt ${index}`,
  };
}

function readJsonFile(path) {
  return JSON.parse(open(path).replace(/^\uFEFF/, '').replace(/^\u00EF\u00BB\u00BF/, ''));
}

function normalizeTime(value) {
  if (!value) return value;
  const text = String(value);
  return text.length === 5 ? `${text}:00` : text;
}

function clientId(index) {
  if (CLIENT_MODE === 'single') return CLIENT_ID;
  if (CLIENT_MODE === 'per-iteration') return `k6-appointment-hostile-${index}`;
  return `k6-appointment-hostile-vu-${__VU}`;
}

function classify(res) {
  if ([200, 201, 202].includes(res.status)) {
    sameSlotSuccess.add(1);
  } else if (res.status === 409) {
    sameSlotConflict.add(1);
  } else if (res.status >= 500 && res.status <= 599) {
    sameSlotServerError.add(1);
  } else {
    sameSlotUnexpected.add(1);
  }
}
