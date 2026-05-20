import http from 'k6/http';
import { check, fail } from 'k6';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const DATA_FILE = __ENV.DATA_FILE || __ENV.DATASET || '../data/appointments-50000.json';
const RATE_PER_MINUTE = Number(__ENV.RATE_PER_MINUTE || 50000);
const DURATION = __ENV.DURATION || '1m';
const PRE_ALLOCATED_VUS = Number(__ENV.PRE_ALLOCATED_VUS || 1000);
const MAX_VUS = Number(__ENV.MAX_VUS || 3000);
const TOTAL_LIMIT = __ENV.TOTAL_LIMIT === undefined || __ENV.TOTAL_LIMIT === ''
  ? null
  : Number(__ENV.TOTAL_LIMIT);
const DATA_OFFSET = Number(__ENV.DATA_OFFSET || 0);
const RUN_ID = __ENV.RUN_ID || String(Date.now());
const CLIENT_MODE = (__ENV.CLIENT_MODE || 'per-vu').toLowerCase();
const DEBUG_RESPONSES = String(__ENV.DEBUG_RESPONSES || 'false').toLowerCase() === 'true';
const DEBUG_RESPONSE_LIMIT = Number(__ENV.DEBUG_RESPONSE_LIMIT || 10);
const DEBUG_RESPONSE_EVERY = Number(__ENV.DEBUG_RESPONSE_EVERY || 0);
const HTTP_TIMEOUT = __ENV.HTTP_TIMEOUT || '60s';

const appointmentAttempts = new Counter('appointment_attempts');
const appointmentsCreated = new Counter('appointments_created');
const appointmentsConflict = new Counter('appointments_conflict');
const appointmentsValidationError = new Counter('appointments_validation_error');
const appointmentsRateLimited = new Counter('appointments_rate_limited');
const appointmentsServerError = new Counter('appointments_server_error');
const appointments503 = new Counter('appointments_503');
const appointments503JsonGateway = new Counter('appointments_503_json_gateway');
const appointments503HtmlHaproxy = new Counter('appointments_503_html_haproxy');
const appointmentsConnectionRefused = new Counter('appointments_connection_refused');
const appointmentsTimeout = new Counter('appointments_timeout');
const appointmentsUnexpected = new Counter('appointments_unexpected');
const appointmentsDatasetExhausted = new Counter('appointments_dataset_exhausted');
const appointmentsSkippedAfterLimit = new Counter('appointments_skipped_after_limit');

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 599 }));

const appointments = new SharedArray('appointments dataset', () => {
  const parsed = readJsonFile(DATA_FILE);
  return Array.isArray(parsed) ? parsed : parsed.appointments;
});

export const options = {
  scenarios: {
    appointment_rpm: {
      executor: 'constant-arrival-rate',
      rate: RATE_PER_MINUTE,
      timeUnit: '1m',
      duration: DURATION,
      preAllocatedVUs: PRE_ALLOCATED_VUS,
      maxVUs: MAX_VUS,
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    appointments_server_error: ['count==0'],
    appointments_timeout: ['count==0'],
    appointments_connection_refused: ['count==0'],
    appointments_unexpected: ['count==0'],
    appointments_dataset_exhausted: ['count==0'],
  },
};

export function setup() {
  if (!['per-vu', 'single', 'per-iteration'].includes(CLIENT_MODE)) {
    fail(`CLIENT_MODE invalido: ${CLIENT_MODE}. Usa per-vu, single o per-iteration.`);
  }

  if (TOTAL_LIMIT !== null && (!Number.isFinite(TOTAL_LIMIT) || TOTAL_LIMIT < 1)) {
    fail(`TOTAL_LIMIT invalido: ${__ENV.TOTAL_LIMIT}. Debe ser un entero positivo.`);
  }

  if (!Number.isFinite(DATA_OFFSET) || DATA_OFFSET < 0) {
    fail(`DATA_OFFSET invalido: ${__ENV.DATA_OFFSET}. Debe ser un entero mayor o igual a cero.`);
  }

  if (!appointments || appointments.length === 0) {
    fail(`DATA_FILE=${DATA_FILE} no contiene citas.`);
  }

  const required = DATA_OFFSET + (TOTAL_LIMIT !== null ? TOTAL_LIMIT : estimatedIterations());
  if (required > appointments.length) {
    fail(`Dataset insuficiente. Se requieren al menos ${required} registros desde DATA_OFFSET ${DATA_OFFSET}, pero el dataset tiene ${appointments.length}.`);
  }
}

export default function () {
  const index = exec.scenario.iterationInTest;
  const datasetIndex = DATA_OFFSET + index;

  if (TOTAL_LIMIT !== null && index >= TOTAL_LIMIT) {
    appointmentsSkippedAfterLimit.add(1);
    return;
  }

  if (datasetIndex >= appointments.length) {
    appointmentsDatasetExhausted.add(1);
    check(null, { 'no dataset exhausted': () => false });
    return;
  }

  const body = normalizeAppointment(appointments[datasetIndex]);
  const idempotencyKey = `appointment-rpm-${RUN_ID}-${index}`;
  const res = http.post(`${BASE_URL}/api/appointments`, JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-Client-Id': clientId(index),
      'X-Idempotency-Key': idempotencyKey,
    },
    tags: {
      block: '2',
      service: 'appointment-service',
      endpoint: '/api/appointments',
      name: 'appointment rpm create',
    },
    timeout: HTTP_TIMEOUT,
  });

  classify(res);
  debugErrorResponse(res, body, datasetIndex, idempotencyKey, index);

  check(res, {
    'tiene respuesta HTTP valida': (r) => typeof r.status === 'number' && r.status > 0,
    'no 5xx': (r) => r.status < 500,
    'no RedisConnectionFailureException': (r) => !String(r.body || '').includes('RedisConnectionFailureException'),
    'no dataset exhausted': () => true,
  });
}

function normalizeAppointment(row) {
  return {
    patientId: row.patientId,
    dentistId: row.dentistId,
    slotId: row.slotId,
    appointmentDate: row.appointmentDate,
    startTime: normalizeTime(row.startTime),
    endTime: normalizeTime(row.endTime),
    amount: Number(row.amount),
    notes: row.notes || 'Block 2 rpm appointment',
  };
}

function estimatedIterations() {
  // constant-arrival-rate can schedule one extra iteration at time boundaries.
  return Math.ceil(RATE_PER_MINUTE * durationToMinutes(DURATION)) + 1;
}

function durationToMinutes(value) {
  const match = String(value).trim().match(/^(\d+(?:\.\d+)?)(ms|s|m|h)$/);
  if (!match) return 1;
  const amount = Number(match[1]);
  const unit = match[2];
  if (unit === 'ms') return amount / 60000;
  if (unit === 's') return amount / 60;
  if (unit === 'm') return amount;
  return amount * 60;
}

function readJsonFile(path) {
  return JSON.parse(open(path).replace(/^\uFEFF/, '').replace(/^\u00EF\u00BB\u00BF/, ''));
}

function normalizeTime(value) {
  if (!value) return value;
  const text = String(value);
  return text.length === 5 ? `${text}:00` : text;
}

function clientId(index) {
  if (CLIENT_MODE === 'single') return 'k6-appointment-single';
  if (CLIENT_MODE === 'per-iteration') return `k6-appointment-${index}`;
  return `k6-appointment-vu-${__VU}`;
}

function classify(res) {
  appointmentAttempts.add(1);

  if ([200, 201, 202].includes(res.status)) {
    appointmentsCreated.add(1);
  } else if (res.status === 0) {
    if (isConnectionRefused(res)) {
      appointmentsConnectionRefused.add(1);
    } else {
      appointmentsTimeout.add(1);
    }
  } else if (res.status === 409) {
    appointmentsConflict.add(1);
  } else if ([400, 422].includes(res.status)) {
    appointmentsValidationError.add(1);
  } else if (res.status === 429) {
    appointmentsRateLimited.add(1);
  } else if (res.status >= 500 && res.status <= 599) {
    appointmentsServerError.add(1);
    if (res.status === 503) {
      appointments503.add(1);
      if (isHaproxyNoBackend(res)) {
        appointments503HtmlHaproxy.add(1);
      } else if (isJsonGatewayUnavailable(res)) {
        appointments503JsonGateway.add(1);
      }
    }
  } else {
    appointmentsUnexpected.add(1);
  }
}

function debugErrorResponse(res, body, datasetIndex, idempotencyKey, index) {
  if (!DEBUG_RESPONSES || [200, 201, 202].includes(res.status)) {
    return;
  }

  const shouldPrintEarlyError = index < DEBUG_RESPONSE_LIMIT;
  const shouldPrintSampledError = DEBUG_RESPONSE_EVERY > 0 && index % DEBUG_RESPONSE_EVERY === 0;
  if (!shouldPrintEarlyError && !shouldPrintSampledError) {
    return;
  }

  console.error(JSON.stringify({
    debug: 'appointment-rpm-error-response',
    status: res.status,
    error: truncate(String(res.error || ''), 1000),
    errorCode: res.error_code || '',
    contentType: headerValue(res, 'Content-Type'),
    body: truncate(String(res.body || ''), 2000),
    correlationId: headerValue(res, 'X-Correlation-Id'),
    datasetIndex,
    patientId: body.patientId,
    dentistId: body.dentistId,
    slotId: body.slotId,
    idempotencyKey,
  }));
}

function isConnectionRefused(res) {
  const text = `${res.error || ''} ${res.body || ''}`.toLowerCase();
  return text.includes('connection refused') ||
    text.includes('connectex') ||
    text.includes('actively refused') ||
    text.includes('dial tcp') ||
    text.includes('no connection could be made');
}

function isHaproxyNoBackend(res) {
  const body = String(res.body || '').toLowerCase();
  const contentType = headerValue(res, 'Content-Type').toLowerCase();
  return res.status === 503 &&
    (contentType.includes('text/html') || body.includes('<html')) &&
    (body.includes('no server is available') || body.includes('service unavailable'));
}

function isJsonGatewayUnavailable(res) {
  const body = String(res.body || '').trim();
  const contentType = headerValue(res, 'Content-Type').toLowerCase();
  return res.status === 503 &&
    (contentType.includes('application/json') || body.startsWith('{')) &&
    (body.includes('SERVICE_UNAVAILABLE') || body.toLowerCase().includes('gateway_fallback') || body.toLowerCase().includes('service unavailable'));
}

function headerValue(res, name) {
  return res.headers[name] || res.headers[name.toLowerCase()] || res.headers[name.toUpperCase()] || '';
}

function truncate(value, maxLength) {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
}

export function handleSummary(data) {
  const flat = buildFlatSummary(data);
  const text = [
    'MediQueue appointment-rpm summary',
    `base_url=${BASE_URL}`,
    `data_file=${DATA_FILE}`,
    `rate_per_minute=${RATE_PER_MINUTE}`,
    `duration=${DURATION}`,
    `total_limit=${TOTAL_LIMIT === null ? 'none' : TOTAL_LIMIT}`,
    `data_offset=${DATA_OFFSET}`,
    `client_mode=${CLIENT_MODE}`,
    `debug_responses=${DEBUG_RESPONSES}`,
    '',
    `appointment_attempts=${flat.appointment_attempts}`,
    `appointments_created=${flat.appointments_created}`,
    `appointments_conflict=${flat.appointments_conflict}`,
    `appointments_validation_error=${flat.appointments_validation_error}`,
    `appointments_rate_limited=${flat.appointments_rate_limited}`,
    `appointments_server_error=${flat.appointments_server_error}`,
    `appointments_503=${flat.appointments_503}`,
    `appointments_503_json_gateway=${flat.appointments_503_json_gateway}`,
    `appointments_503_html_haproxy=${flat.appointments_503_html_haproxy}`,
    `appointments_connection_refused=${flat.appointments_connection_refused}`,
    `appointments_timeout=${flat.appointments_timeout}`,
    `appointments_unexpected=${flat.appointments_unexpected}`,
    `appointments_dataset_exhausted=${flat.appointments_dataset_exhausted}`,
    `appointments_skipped_after_limit=${flat.appointments_skipped_after_limit}`,
    `dropped_iterations=${flat.dropped_iterations}`,
    `checks_rate=${flat.checks_rate}`,
    `http_reqs=${flat.http_reqs}`,
    `http_req_failed_rate=${flat.http_req_failed_rate}`,
    `http_req_duration_p95=${flat.http_req_duration_p95}`,
    `http_req_duration_p99=${flat.http_req_duration_p99}`,
    '',
    'PowerShell tip: en --summary-export los counters viven en metrics.<name>.values.count.',
  ].join('\n');

  const base = `${resultDir()}/appointment-rpm-${Date.now()}`;
  return {
    stdout: `${text}\n`,
    [`${base}.json`]: JSON.stringify(data, null, 2),
    [`${base}.flat.json`]: JSON.stringify(flat, null, 2),
    [`${base}.txt`]: `${text}\n`,
  };
}

function buildFlatSummary(data) {
  return {
    appointment_attempts: count(data, 'appointment_attempts'),
    appointments_created: count(data, 'appointments_created'),
    appointments_conflict: count(data, 'appointments_conflict'),
    appointments_validation_error: count(data, 'appointments_validation_error'),
    appointments_rate_limited: count(data, 'appointments_rate_limited'),
    appointments_server_error: count(data, 'appointments_server_error'),
    appointments_503: count(data, 'appointments_503'),
    appointments_503_json_gateway: count(data, 'appointments_503_json_gateway'),
    appointments_503_html_haproxy: count(data, 'appointments_503_html_haproxy'),
    appointments_connection_refused: count(data, 'appointments_connection_refused'),
    appointments_timeout: count(data, 'appointments_timeout'),
    appointments_unexpected: count(data, 'appointments_unexpected'),
    appointments_dataset_exhausted: count(data, 'appointments_dataset_exhausted'),
    appointments_skipped_after_limit: count(data, 'appointments_skipped_after_limit'),
    dropped_iterations: count(data, 'dropped_iterations'),
    checks_rate: value(data, 'checks', 'rate'),
    http_reqs: count(data, 'http_reqs'),
    http_req_failed_rate: value(data, 'http_req_failed', 'rate'),
    http_req_duration_p95: value(data, 'http_req_duration', 'p(95)'),
    http_req_duration_p99: value(data, 'http_req_duration', 'p(99)'),
  };
}

function count(data, name) {
  return value(data, name, 'count') || 0;
}

function value(data, name, key) {
  const metric = (data.metrics || {})[name] || {};
  const values = metric.values || {};
  return typeof values[key] === 'number' ? values[key] : 0;
}

function resultDir() {
  return __ENV.RESULTS_DIR || 'infra/load-tests/appointments/results';
}
