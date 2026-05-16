import http from 'k6/http';
import { fail } from 'k6';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkJsonResponse, checkStatus } from '../lib/checks.js';
import { uuidv4 } from '../lib/ids.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 409, 422));

export const options = {
  scenarios: {
    hostile_same_slot: {
      executor: 'shared-iterations',
      vus: Number(__ENV.HOSTILE_VUS || 500),
      iterations: Number(__ENV.HOSTILE_ITERATIONS || 500),
      maxDuration: __ENV.HOSTILE_MAX_DURATION || '5m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<3000', 'p(99)<6000'],
  },
};

export function setup() {
  const missing = ['PATIENT_ID', 'DENTIST_ID', 'SLOT_ID'].filter((key) => !__ENV[key]);
  if (missing.length > 0) {
    fail(`Faltan variables requeridas para prueba hostil: ${missing.join(', ')}`);
  }
}

export default function () {
  const body = {
    patientId: __ENV.PATIENT_ID,
    dentistId: __ENV.DENTIST_ID,
    slotId: __ENV.SLOT_ID,
    appointmentDate: __ENV.DATE || new Date(Date.now() + 86400000).toISOString().slice(0, 10),
    startTime: __ENV.START_TIME || '09:00:00',
    endTime: __ENV.END_TIME || '09:30:00',
    notes: `hostile same slot ${__VU}-${__ITER}`,
  };

  const res = http.post(url('/api/appointments'), JSON.stringify(body), {
    headers: jsonHeaders({
      'X-Idempotency-Key': `appointment-hostile-${uuidv4()}`,
      'X-Correlation-Id': correlationId('appointment-hostile'),
    }),
    tags: { service: 'appointment-service', endpoint: '/api/appointments', name: 'hostile create appointment' },
  });

  checkStatus('hostile create appointment', [200, 201, 202, 409, 422])(res);
  if ([200, 201, 202, 409, 422].includes(res.status)) {
    checkJsonResponse('hostile create appointment')(res);
  }
}
