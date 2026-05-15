import { check } from 'k6';

export function checkStatus(name, allowedStatuses) {
  return (res) => check(res, {
    [`${name}: status in ${allowedStatuses.join(',')}`]: (r) => allowedStatuses.includes(r.status),
  });
}

export function checkJsonResponse(name = 'json response') {
  return (res) => check(res, {
    [`${name}: content-type json`]: (r) => (r.headers['Content-Type'] || '').includes('application/json'),
    [`${name}: body parses`]: (r) => {
      try {
        r.json();
        return true;
      } catch (error) {
        return false;
      }
    },
  });
}

export function checkDurationLessThan(ms) {
  return (res) => check(res, {
    [`duration < ${ms}ms`]: (r) => r.timings.duration < ms,
  });
}
