import http from 'k6/http';
import { sleep } from 'k6';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkJsonResponse, checkStatus } from '../lib/checks.js';
import { randomInt, uuidv4 } from '../lib/ids.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

const duration = __ENV.PATIENT_DURATION || '1m';

export const options = {
  scenarios: {
    patient_write_load: {
      executor: 'constant-vus',
      vus: Number(__ENV.PATIENT_VUS || 20),
      duration,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000', 'p(99)<2000'],
  },
};

function uniquePatient() {
  const id = uuidv4();
  return {
    firstName: 'Load',
    lastName: `Patient ${__VU}-${__ITER}`,
    email: `load.patient.${id}@mediqueue.local`,
    phone: `502${randomInt(10000000, 99999999)}`,
    documentNumber: `K6-${id}`,
  };
}

export default function () {
  const payload = uniquePatient();
  const createRes = http.post(url('/api/patients'), JSON.stringify(payload), {
    headers: jsonHeaders({ 'X-Correlation-Id': correlationId('patient') }),
    tags: { service: 'patient-service', endpoint: '/api/patients', name: 'create patient' },
  });

  checkStatus('create patient', [201])(createRes);
  checkJsonResponse('create patient')(createRes);

  if (createRes.status === 201) {
    const lookupRes = http.get(url(`/api/patients?email=${encodeURIComponent(payload.email)}`), {
      headers: jsonHeaders({ 'X-Correlation-Id': correlationId('patient-get') }),
      tags: { service: 'patient-service', endpoint: '/api/patients?email', name: 'get patient by email' },
    });
    checkStatus('get patient by email', [200])(lookupRes);
  }

  sleep(1);
}
