import http from 'k6/http';
import { sleep } from 'k6';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkJsonResponse, checkStatus } from '../lib/checks.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

export const options = {
  scenarios: {
    schedule_read_load: {
      executor: 'constant-vus',
      vus: Number(__ENV.SCHEDULE_VUS || 100),
      duration: __ENV.SCHEDULE_DURATION || '2m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000', 'p(99)<2000'],
  },
};

export function setup() {
  if (__ENV.DENTIST_ID) {
    return { dentistId: __ENV.DENTIST_ID };
  }

  const res = http.get(url('/api/slots/available'), {
    headers: jsonHeaders({ 'X-Correlation-Id': correlationId('schedule-setup') }),
    tags: { service: 'schedule-service', endpoint: '/api/slots/available', name: 'discover available slots' },
  });

  if (res.status === 200) {
    const slots = res.json();
    if (Array.isArray(slots) && slots.length > 0 && slots[0].dentistId) {
      return { dentistId: slots[0].dentistId };
    }
  }

  console.log('DENTIST_ID no fue provisto y /api/slots/available no devolvio dentistId; se usara /api/slots/available como carga de lectura.');
  return { dentistId: null };
}

export default function (data) {
  const date = __ENV.DATE;
  const path = data.dentistId
    ? `/api/slots/dentist/${data.dentistId}${date ? `?date=${encodeURIComponent(date)}` : ''}`
    : '/api/slots/available';

  const res = http.get(url(path), {
    headers: jsonHeaders({ 'X-Correlation-Id': correlationId('schedule') }),
    tags: { service: 'schedule-service', endpoint: data.dentistId ? '/api/slots/dentist/{dentistId}' : '/api/slots/available', name: 'schedule slots' },
  });

  checkStatus('schedule slots', [200])(res);
  checkJsonResponse('schedule slots')(res);
  sleep(1);
}
