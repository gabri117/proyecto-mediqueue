import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const FAKE_PATIENT_ID = '00000000-0000-0000-0000-000000000000';

const gateway503 = new Counter('gateway_503');
const redisErrorBody = new Counter('redis_error_body');
const failOpenResponses = new Counter('fail_open_responses');
const normalRateLimitResponses = new Counter('normal_rate_limit_responses');

export const options = {
  scenarios: {
    gateway_redis_chaos_small: {
      executor: 'ramping-vus',
      stages: [
        { duration: '30s', target: 5 },
        { duration: '45s', target: 15 },
        { duration: '60s', target: 15 },
        { duration: '30s', target: 0 },
      ],
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    gateway_503: ['count==0'],
    redis_error_body: ['count==0'],
  },
};

export default function () {
  const clientId = `k6-vu-${__VU}`;

  const params = {
    headers: {
      'X-Client-Id': clientId,
      'Accept': 'application/json',
    },
  };

  const res = http.get(`${BASE_URL}/api/patients/${FAKE_PATIENT_ID}`, params);

  const body = res.body || '';
  const remaining = res.headers['X-Ratelimit-Remaining'] ||
                    res.headers['X-RateLimit-Remaining'] ||
                    res.headers['x-ratelimit-remaining'];

  if (res.status === 503) {
    gateway503.add(1);
  }

  if (
    body.includes('RedisConnectionFailureException') ||
    body.includes('LettuceConnectionException') ||
    body.includes('Unable to connect to Redis') ||
    body.includes('No server is available to handle this request')
  ) {
    redisErrorBody.add(1);
  }

  if (String(remaining) === '-1') {
    failOpenResponses.add(1);
  } else if (remaining !== undefined && remaining !== null) {
    normalRateLimitResponses.add(1);
  }

  check(res, {
    'gateway no devuelve 503': (r) => r.status !== 503,
    'llega al upstream patient-service': (r) => [400, 404].includes(r.status),
    'no expone error Redis': (r) =>
      !body.includes('RedisConnectionFailureException') &&
      !body.includes('LettuceConnectionException') &&
      !body.includes('Unable to connect to Redis') &&
      !body.includes('No server is available to handle this request'),
    'tiene header de rate limit': () => remaining !== undefined && remaining !== null,
  });

  sleep(0.2);
}