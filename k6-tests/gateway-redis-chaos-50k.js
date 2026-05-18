import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const RATE = Number.parseInt(__ENV.RATE || '167', 10);
const DURATION = __ENV.DURATION || '5m';
const PRE_ALLOCATED_VUS = Number.parseInt(__ENV.PRE_ALLOCATED_VUS || '200', 10);
const MAX_VUS = Number.parseInt(__ENV.MAX_VUS || '500', 10);
const FAKE_PATIENT_ID =
  __ENV.FAKE_PATIENT_ID || '00000000-0000-0000-0000-000000000000';

const redisErrorPatterns = [
  'RedisConnectionFailureException',
  'LettuceConnectionException',
  'Unable to connect to Redis',
  'Redis command timed out',
  'No server is available to handle this request',
];

const gateway503 = new Counter('gateway_503');
const redisErrorBody = new Counter('redis_error_body');
const failOpenResponses = new Counter('fail_open_responses');
const normalRateLimitResponses = new Counter('normal_rate_limit_responses');
const businessResponses = new Counter('business_responses');

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 400, 404));

export const options = {
  scenarios: {
    gateway_redis_chaos_50k: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: PRE_ALLOCATED_VUS,
      maxVUs: MAX_VUS,
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    gateway_503: ['count==0'],
    redis_error_body: ['count==0'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

function rateLimitRemaining(headers) {
  return (
    headers['X-Ratelimit-Remaining'] ||
    headers['X-RateLimit-Remaining'] ||
    headers['x-ratelimit-remaining']
  );
}

function containsRedisError(body) {
  return redisErrorPatterns.some((pattern) => body.includes(pattern));
}

export default function () {
  const res = http.get(`${BASE_URL}/api/patients/${FAKE_PATIENT_ID}`, {
    headers: {
      Accept: 'application/json',
      'X-Client-Id': `k6-vu-${__VU}`,
    },
  });

  const body = res.body || '';
  const remaining = rateLimitRemaining(res.headers);
  const hasRedisErrorBody = containsRedisError(body);
  const hasRateLimitHeader = remaining !== undefined && remaining !== null;

  if (res.status === 503) {
    gateway503.add(1);
  }

  if (res.status === 400 || res.status === 404) {
    businessResponses.add(1);
  }

  if (hasRedisErrorBody) {
    redisErrorBody.add(1);
  }

  if (String(remaining) === '-1') {
    failOpenResponses.add(1);
  } else if (hasRateLimitHeader) {
    normalRateLimitResponses.add(1);
  }

  check(res, {
    'gateway no devuelve 503': (r) => r.status !== 503,
    'llega al upstream como respuesta de negocio': (r) =>
      r.status === 400 || r.status === 404,
    'no expone error Redis': () => !hasRedisErrorBody,
    'tiene header de rate limit': () => hasRateLimitHeader,
  });
}
