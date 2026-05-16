import http from 'k6/http';
import { fail, sleep } from 'k6';
import { correlationId, jsonHeaders, url } from '../lib/config.js';
import { checkJsonResponse, checkStatus } from '../lib/checks.js';
import { randomInt, uuidv4 } from '../lib/ids.js';
import { handleSummary } from '../lib/summary.js';

export { handleSummary };

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 409, 422));

export const options = {
  vus: Number(__ENV.E2E_VUS || 1),
  iterations: Number(__ENV.E2E_ITERATIONS || 1),
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<3000', 'p(99)<6000'],
  },
};

function post(path, body, headers, name, service, allowed = [200, 201, 202]) {
  const res = http.post(url(path), JSON.stringify(body), {
    headers: jsonHeaders({ 'X-Correlation-Id': correlationId('e2e'), ...headers }),
    tags: { service, endpoint: path, name },
  });
  checkStatus(name, allowed)(res);
  if (allowed.includes(res.status)) {
    checkJsonResponse(name)(res);
  }
  return res;
}

export function setup() {
  if ((__ENV.ALLOW_E2E || 'false').toLowerCase() !== 'true') {
    fail('06-e2e-flow.js esta deshabilitado por defecto. Ejecuta con ALLOW_E2E=true solo cuando AppointmentHeld.amount este corregido.');
  }
}

export default function () {
  const id = uuidv4();
  const date = __ENV.DATE || new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  const startTime = __ENV.START_TIME || '10:00:00';
  const endTime = __ENV.END_TIME || '10:30:00';

  const patientRes = post('/api/patients', {
    firstName: 'E2E',
    lastName: 'Patient',
    email: `e2e.patient.${id}@mediqueue.local`,
    phone: `502${randomInt(10000000, 99999999)}`,
    documentNumber: `E2E-${id}`,
  }, {}, 'e2e create patient', 'patient-service', [201]);
  const patient = patientRes.json();

  const dentistId = __ENV.DENTIST_ID || createDentist(id).dentistId;
  const slotId = __ENV.SLOT_ID || createSlot(dentistId, date, startTime, endTime).slotId;

  const appointmentRes = post('/api/appointments', {
    patientId: patient.patientId,
    dentistId,
    slotId,
    appointmentDate: date,
    startTime,
    endTime,
    notes: 'k6 e2e flow',
  }, { 'X-Idempotency-Key': `e2e-appointment-${id}` }, 'e2e create appointment', 'appointment-service', [201, 409, 422]);

  if (appointmentRes.status !== 201) {
    fail(`No se pudo crear cita E2E: status=${appointmentRes.status}`);
  }

  const appointment = appointmentRes.json();
  const paymentRes = post('/api/payments', {
    appointmentId: appointment.appointmentId,
    patientId: patient.patientId,
    amount: Number(__ENV.PAYMENT_AMOUNT || 150),
    currency: 'GTQ',
  }, { 'X-Idempotency-Key': `e2e-payment-${id}` }, 'e2e create payment', 'payment-service', [200, 201, 202, 409]);

  if ([200, 201, 202].includes(paymentRes.status)) {
    sleep(Number(__ENV.NOTIFICATION_WAIT_SECONDS || 3));
    const notificationRes = http.get(url(`/api/notifications?appointmentId=${appointment.appointmentId}&page=0&size=20`), {
      headers: jsonHeaders({ 'X-Correlation-Id': correlationId('e2e-notification') }),
      tags: { service: 'notification-service', endpoint: '/api/notifications', name: 'e2e query notification' },
    });
    checkStatus('e2e query notification', [200])(notificationRes);
    checkJsonResponse('e2e query notification')(notificationRes);
  }
}

function createDentist(id) {
  const res = post('/api/dentists', {
    firstName: 'E2E',
    lastName: 'Dentist',
    specialty: 'General',
    email: `e2e.dentist.${id}@mediqueue.local`,
    licenseNumber: `LIC-${id}`,
  }, {}, 'e2e create dentist', 'schedule-service', [201]);
  return res.json();
}

function createSlot(dentistId, date, startTime, endTime) {
  const res = post('/api/slots', {
    dentistId,
    slotDate: date,
    startTime,
    endTime,
  }, {}, 'e2e create slot', 'schedule-service', [201]);
  return res.json();
}
