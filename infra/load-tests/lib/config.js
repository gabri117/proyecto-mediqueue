export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export const DEFAULT_HEADERS = {
  Accept: 'application/json',
};

export function jsonHeaders(extra = {}) {
  return {
    ...DEFAULT_HEADERS,
    'Content-Type': 'application/json',
    ...extra,
  };
}

export function correlationId(prefix = 'k6') {
  const vu = typeof __VU === 'undefined' ? 'setup' : __VU;
  const iter = typeof __ITER === 'undefined' ? Date.now() : __ITER;
  return `${prefix}-${vu}-${iter}-${Date.now()}`;
}

export function url(path) {
  return `${BASE_URL}${path}`;
}
