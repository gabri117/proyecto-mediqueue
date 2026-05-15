import http from 'k6/http';
import { sleep } from 'k6';
import { Counter, Rate } from 'k6/metrics';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkStatus } from '../lib/checks.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 429));

const gatewayStatus429 = new Counter('gateway_rate_limit_status_429');
const gatewayStatus5xx = new Counter('gateway_rate_limit_status_5xx');
const gatewayStatusOther = new Counter('gateway_rate_limit_status_other');
const gatewayRateLimited = new Rate('gateway_rate_limit_429_rate');
const gatewayBackendError = new Rate('gateway_rate_limit_5xx_rate');

export const options = {
  scenarios: {
    gateway_rate_limit: {
      executor: 'constant-vus',
      vus: Number(__ENV.RATE_LIMIT_VUS || 40),
      duration: __ENV.RATE_LIMIT_DURATION || '30s',
    },
  },
  thresholds: {
    gateway_rate_limit_5xx_rate: ['rate==0'],
    gateway_rate_limit_429_rate: ['rate>0'],
    http_req_duration: ['p(95)<3000'],
  },
};

export function setup() {
  console.log('Gateway rate-limit test: HTTP 429 is expected and reported; HTTP 5xx is not accepted.');
}

export default function () {
  const res = http.get(url('/api/payments?page=0&size=5'), {
    headers: jsonHeaders({ 'X-Correlation-Id': correlationId('gateway-rate-limit') }),
    tags: { service: 'api-gateway', endpoint: '/api/payments', name: 'gateway rate limit payments' },
  });

  if (res.status === 429) {
    gatewayStatus429.add(1);
    gatewayRateLimited.add(true);
    gatewayBackendError.add(false);
  } else if (res.status >= 500 && res.status <= 599) {
    gatewayStatus5xx.add(1);
    gatewayRateLimited.add(false);
    gatewayBackendError.add(true);
  } else if (res.status < 200 || res.status > 399) {
    gatewayStatusOther.add(1);
    gatewayRateLimited.add(false);
    gatewayBackendError.add(false);
  } else {
    gatewayRateLimited.add(false);
    gatewayBackendError.add(false);
  }

  checkStatus('gateway rate limit accepts success or 429', [200, 429])(res);
  sleep(1);
}
