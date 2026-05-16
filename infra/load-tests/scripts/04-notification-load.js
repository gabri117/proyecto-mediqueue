import http from 'k6/http';
import { sleep } from 'k6';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkJsonResponse, checkStatus } from '../lib/checks.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

export const options = {
  scenarios: {
    notification_read_load: {
      executor: 'constant-vus',
      vus: Number(__ENV.NOTIFICATION_VUS || 50),
      duration: __ENV.NOTIFICATION_DURATION || '2m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000', 'p(99)<2000'],
  },
};

function choosePath() {
  const base = '/api/notifications?page=0&size=20';
  const variants = [
    base,
    '/api/notifications?status=SENT&page=0&size=20',
  ];

  if (__ENV.PATIENT_ID) {
    variants.push(`/api/notifications?patientId=${encodeURIComponent(__ENV.PATIENT_ID)}&page=0&size=20`);
    variants.push(`/api/notifications/patient/${encodeURIComponent(__ENV.PATIENT_ID)}?page=0&size=20`);
  }

  if (__ENV.APPOINTMENT_ID) {
    variants.push(`/api/notifications?appointmentId=${encodeURIComponent(__ENV.APPOINTMENT_ID)}&page=0&size=20`);
  }

  return variants[__ITER % variants.length];
}

export default function () {
  const path = choosePath();
  const res = http.get(url(path), {
    headers: jsonHeaders({ 'X-Correlation-Id': correlationId('notification') }),
    tags: { service: 'notification-service', endpoint: path.split('?')[0], name: 'query notifications' },
  });

  checkStatus('query notifications', [200])(res);
  checkJsonResponse('query notifications')(res);
  sleep(1);
}
