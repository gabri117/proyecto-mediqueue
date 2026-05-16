import http from 'k6/http';
import { group, sleep } from 'k6';
import { BASE_URL, correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkDurationLessThan, checkJsonResponse, checkStatus } from '../lib/checks.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

export const options = {
  vus: Number(__ENV.SMOKE_VUS || 1),
  iterations: Number(__ENV.SMOKE_ITERATIONS || 5),
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
  },
};

function get(path, name, tags) {
  const res = http.get(url(path), {
    headers: jsonHeaders({ 'X-Correlation-Id': correlationId('smoke') }),
    tags: { service: tags.service, endpoint: path, name },
  });
  checkStatus(name, [200])(res);
  checkDurationLessThan(1000)(res);
  return res;
}

export default function () {
  group('ecosystem smoke', () => {
    get('/actuator/health', 'gateway health', { service: 'api-gateway' });
    checkJsonResponse('gateway health')(get('/actuator/health', 'gateway health json', { service: 'api-gateway' }));

    checkJsonResponse('payments page')(
      get('/api/payments?page=0&size=5', 'payments page', { service: 'payment-service' }),
    );

    checkJsonResponse('notifications page')(
      get('/api/notifications?page=0&size=5', 'notifications page', { service: 'notification-service' }),
    );

    checkJsonResponse('available slots')(
      get('/api/slots/available', 'available slots', { service: 'schedule-service' }),
    );
  });

  sleep(1);
}

export function setup() {
  console.log(`Smoke BASE_URL=${BASE_URL}`);
  console.log('Paciente y citas no tienen endpoint de listado seguro; se omiten en smoke salvo pruebas con IDs.');
}
