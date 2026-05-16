# Plan de Reglas de Negocio para Creacion de Citas

## 1. Objetivo

Definir el plan de implementacion para reforzar las reglas de negocio de
creacion de citas en `appointment-service`.

La regla principal es que una cita solo puede aceptarse dentro del horario
laboral de 12 horas:

```text
08:00 a 20:00
```

Con exclusion del horario habitual de almuerzo:

```text
13:00 a 14:00
```

Ademas, el servicio debe validar que la solicitud sea coherente con el slot real
registrado en `schedule-service`, que no se creen citas en fechas u horas
invalidas, y que ante cualquier rechazo no se genere estado parcial en base de
datos ni eventos de dominio.

Este documento solo describe el plan. No aplica cambios de codigo ni de
infraestructura.

## 2. Estado Actual

Actualmente `AppointmentService.createAppointment` realiza estas acciones antes
de crear una cita:

- Valida que el paciente exista usando `PatientClient`.
- Valida que el slot exista usando `ScheduleClient.validateSlotExists`.
- Aplica idempotencia con `idempotency_keys`.
- Verifica que no exista un hold activo para el mismo `slotId`.
- Crea la cita en estado `PENDING_PAYMENT`.
- Crea un hold temporal.
- Registra auditoria.
- Publica un evento en outbox.

Limitaciones detectadas:

- `ScheduleClient.validateSlotExists` solo verifica que `/slots/{id}` responda,
  pero no lee el detalle del slot.
- `appointment-service` no valida que la cita este dentro de `08:00-20:00`.
- `appointment-service` no bloquea el horario de almuerzo `13:00-14:00`.
- No se valida explicitamente que `endTime` sea posterior a `startTime`.
- No se valida que la fecha no sea pasada.
- No se valida que una cita para el dia actual tenga una hora futura.
- No se valida que el slot remoto este en estado `AVAILABLE`.
- No se valida que el request coincida exactamente con el slot real:
  `slotId`, `dentistId`, fecha, hora de inicio y hora de fin.

## 3. Reglas de Negocio Objetivo

Las reglas deben ejecutarse antes de crear:

- Idempotency key.
- Appointment.
- Appointment hold.
- Appointment audit.
- Outbox event.

Esto evita registros parciales cuando la solicitud no cumple las reglas.

### 3.1 Horario laboral

Una cita es valida solo si todo el rango horario esta dentro de la jornada:

```text
Inicio permitido: 08:00
Fin maximo:       20:00
```

Ejemplos:

| Inicio | Fin   | Resultado |
|--------|-------|-----------|
| 08:00  | 08:30 | Valido    |
| 07:30  | 08:00 | Rechazado |
| 19:30  | 20:00 | Valido    |
| 19:30  | 20:30 | Rechazado |

### 3.2 Almuerzo

No se aceptan citas que se solapen con:

```text
13:00 a 14:00
```

El solapamiento debe rechazarse aunque la cita empiece antes o termine despues.

Ejemplos:

| Inicio | Fin   | Resultado |
|--------|-------|-----------|
| 12:00  | 13:00 | Valido    |
| 12:30  | 13:30 | Rechazado |
| 13:00  | 13:30 | Rechazado |
| 13:30  | 14:00 | Rechazado |
| 13:30  | 14:30 | Rechazado |
| 14:00  | 14:30 | Valido    |

La condicion tecnica recomendada para detectar solapamiento es:

```java
startTime.isBefore(lunchEnd) && endTime.isAfter(lunchStart)
```

### 3.3 Fecha y hora futura

Reglas:

- No aceptar citas en fechas pasadas.
- Si la cita es para la fecha actual, `startTime` debe ser posterior a la hora
  actual.
- No aceptar citas con `endTime <= startTime`.

Esta validacion debe usar `Clock` inyectable para que las pruebas sean
deterministicas.

### 3.4 Disponibilidad del slot

`appointment-service` debe leer el detalle del slot desde `schedule-service` y
aceptarlo solo si:

```text
status == AVAILABLE
```

Estados como `HELD`, `BOOKED` o `BLOCKED` deben rechazarse.

### 3.5 Coherencia con schedule-service

Aunque el request incluya `dentistId`, `appointmentDate`, `startTime` y
`endTime`, esos datos no deben aceptarse como fuente absoluta.

El slot real de `schedule-service` debe coincidir exactamente con la solicitud:

- `request.slotId == slot.slotId`
- `request.dentistId == slot.dentistId`
- `request.appointmentDate == slot.slotDate`
- `request.startTime == slot.startTime`
- `request.endTime == slot.endTime`

Si algun campo no coincide, la cita debe rechazarse.

## 4. Configuracion Recomendada

Los horarios deben ser configurables por properties/env, con valores por defecto
que representen la regla actual.

Agregar en `services/appointment-service/src/main/resources/application.properties`:

```properties
mediqueue.appointment.working-day-start=${APPOINTMENT_WORKING_DAY_START:08:00}
mediqueue.appointment.working-day-end=${APPOINTMENT_WORKING_DAY_END:20:00}
mediqueue.appointment.lunch-start=${APPOINTMENT_LUNCH_START:13:00}
mediqueue.appointment.lunch-end=${APPOINTMENT_LUNCH_END:14:00}
```

Ventajas:

- Permite cambiar horarios sin recompilar.
- Facilita ambientes distintos, por ejemplo pruebas, demo o produccion.
- Mantiene defaults alineados con la regla de negocio actual.

## 5. Cambios Tecnicos Propuestos

### 5.1 DTO para leer slots desde appointment-service

Crear un DTO cliente en `appointment-service` compatible con
`DentistSlotResponse` de `schedule-service`.

Nombre sugerido:

```text
ScheduleSlotResponse
```

Campos:

```java
UUID slotId;
UUID dentistId;
LocalDate slotDate;
LocalTime startTime;
LocalTime endTime;
String status;
LocalDateTime createdAt;
LocalDateTime updatedAt;
```

Este DTO debe vivir en el paquete cliente de `appointment-service`, por ejemplo:

```text
com.mediqueue.appointment.client
```

### 5.2 Cambios en ScheduleClient

Actualmente el cliente solo expone:

```java
void validateSlotExists(UUID slotId)
```

Debe agregarse un metodo que retorne el detalle del slot:

```java
ScheduleSlotResponse getSlot(UUID slotId)
```

Comportamiento requerido:

- Hacer `GET /slots/{id}` contra `schedule-service`.
- Mapear el body a `ScheduleSlotResponse`.
- Mantener el circuit breaker `schedule-service`.
- En errores 4xx o 5xx, lanzar `ServiceValidationException`.
- En fallback del circuit breaker, lanzar `ServiceValidationException`.

`validateSlotExists(UUID slotId)` puede conservarse por compatibilidad interna,
pero debe delegar en `getSlot(slotId)` para evitar dos comportamientos
distintos.

### 5.3 Nuevo componente AppointmentBusinessRules

Crear un componente dedicado para centralizar las reglas:

```text
AppointmentBusinessRules
```

Responsabilidad:

- Validar horarios.
- Validar almuerzo.
- Validar fecha y hora futura.
- Validar disponibilidad del slot.
- Validar coherencia entre request y slot remoto.

Metodo publico recomendado:

```java
void validateForCreation(AppointmentRequest request, ScheduleSlotResponse slot)
```

Dependencias recomendadas:

- Horario laboral configurable.
- Horario de almuerzo configurable.
- `Clock` para pruebas.

Errores:

- Las violaciones de negocio deben lanzar `BusinessException`.
- Los mensajes deben ser claros para diagnostico y pruebas.

Mensajes sugeridos:

```text
La cita no puede programarse en una fecha pasada
La cita debe iniciar en un horario futuro
La hora de fin debe ser posterior a la hora de inicio
La cita debe estar dentro del horario laboral de 08:00 a 20:00
No se aceptan citas durante el horario de almuerzo de 13:00 a 14:00
Slot no disponible: el horario no esta disponible
La cita solicitada no coincide con el slot registrado en agenda
```

### 5.4 Cambios en AppointmentService

El flujo de `createAppointment` debe quedar asi:

1. Validar que el paciente exista con `PatientClient`.
2. Obtener el detalle del slot con `ScheduleClient.getSlot`.
3. Ejecutar `AppointmentBusinessRules.validateForCreation`.
4. Buscar idempotency key existente.
5. Crear idempotency key en estado `PROCESSING`.
6. Validar que no exista hold activo para el `slotId`.
7. Crear appointment.
8. Crear hold.
9. Registrar auditoria.
10. Guardar evento outbox.
11. Marcar idempotency key como `SUCCEEDED`.
12. Retornar response.

La validacion debe ocurrir antes de crear la idempotency key. Si la solicitud es
invalida, no debe quedar rastro transaccional asociado a una operacion que nunca
debio iniciar.

## 6. Manejo de Errores

### 6.1 BusinessException

Usar `BusinessException` para violaciones de reglas internas de creacion de
citas:

- Fuera del horario laboral.
- Solapamiento con almuerzo.
- Fecha pasada.
- Hora invalida.
- Slot no disponible.
- Diferencia entre request y slot remoto.

Respuesta HTTP actual esperada:

```text
409 CONFLICT
code: BUSINESS_RULE_VIOLATION
```

### 6.2 ServiceValidationException

Usar `ServiceValidationException` cuando no sea posible validar el slot contra
`schedule-service`:

- Slot inexistente.
- Error 4xx/5xx desde schedule.
- Circuit breaker abierto.
- Timeout o falla de comunicacion.

Respuesta HTTP actual esperada:

```text
422 UNPROCESSABLE_ENTITY
code: SERVICE_VALIDATION_FAILED
```

## 7. Casos de Validacion

### 7.1 Casos validos

| Caso | Request | Slot remoto | Resultado |
|------|---------|-------------|-----------|
| Inicio de jornada | 08:00-08:30 | AVAILABLE y coincide | Aceptado |
| Antes de almuerzo | 12:00-13:00 | AVAILABLE y coincide | Aceptado |
| Despues de almuerzo | 14:00-14:30 | AVAILABLE y coincide | Aceptado |
| Fin de jornada | 19:30-20:00 | AVAILABLE y coincide | Aceptado |

### 7.2 Casos invalidos por horario

| Caso | Request | Motivo |
|------|---------|--------|
| Antes de jornada | 07:30-08:00 | Inicia antes de 08:00 |
| Despues de jornada | 19:30-20:30 | Termina despues de 20:00 |
| Inicio en almuerzo | 13:00-13:30 | Solapa almuerzo |
| Cruza almuerzo | 12:30-13:30 | Solapa almuerzo |
| Termina en almuerzo | 13:30-14:00 | Solapa almuerzo |
| Sale de almuerzo | 13:30-14:30 | Solapa almuerzo |

### 7.3 Casos invalidos por fecha y duracion

| Caso | Motivo |
|------|--------|
| Fecha pasada | `appointmentDate` menor que hoy |
| Hoy con hora pasada | `appointmentDate` igual a hoy y `startTime` ya paso |
| Duracion cero | `endTime == startTime` |
| Horario invertido | `endTime < startTime` |

### 7.4 Casos invalidos por slot

| Caso | Motivo |
|------|--------|
| Slot `HELD` | Ya esta reservado temporalmente |
| Slot `BOOKED` | Ya esta ocupado |
| Slot `BLOCKED` | No disponible para agenda |
| `dentistId` distinto | Request no coincide con agenda |
| Fecha distinta | Request no coincide con agenda |
| Hora inicio distinta | Request no coincide con agenda |
| Hora fin distinta | Request no coincide con agenda |

### 7.5 Garantia de no persistencia

Para todos los rechazos anteriores se debe verificar que no se creen:

- Filas en `idempotency_keys`.
- Filas en `appointments`.
- Filas en `appointment_holds`.
- Filas en `appointment_audit`.
- Filas en `outbox_events`.

## 8. Plan de Pruebas

### 8.1 Tests unitarios de AppointmentBusinessRules

Crear tests con `Clock` fijo para cubrir:

- Cita valida dentro de jornada.
- Inicio antes de `08:00`.
- Fin despues de `20:00`.
- Solapamiento con almuerzo en los bordes.
- Fecha pasada.
- Hoy con hora pasada.
- `endTime <= startTime`.
- Slot con estado distinto de `AVAILABLE`.
- Slot con datos distintos al request.

El uso de `Clock` fijo evita pruebas fragiles por depender de la hora real del
sistema.

### 8.2 Tests de AppointmentService

Crear o ampliar tests con mocks para:

- Confirmar que `patientClient.validatePatientExists` se ejecuta.
- Confirmar que `scheduleClient.getSlot` se ejecuta.
- Confirmar que `appointmentBusinessRules.validateForCreation` se ejecuta antes
  de cualquier persistencia.
- Confirmar que, si las reglas fallan, no se invocan repositorios `save`.
- Confirmar que, si todo es valido, el flujo existente de idempotencia, hold,
  auditoria y outbox sigue funcionando.

### 8.3 Comandos recomendados

Desde la raiz del monorepo:

```bash
mvn -pl services/appointment-service test
```

Si el modulo requiere compilar dependencias del parent:

```bash
mvn -pl services/appointment-service -am test
```

## 9. Criterios de Aceptacion

La implementacion estara lista cuando:

- `appointment-service` rechace citas fuera de `08:00-20:00`.
- `appointment-service` rechace citas que solapen `13:00-14:00`.
- Los horarios sean configurables por properties/env.
- Se rechacen fechas pasadas y horas ya pasadas para el dia actual.
- Se rechace cualquier request con `endTime <= startTime`.
- Se lea el detalle real del slot desde `schedule-service`.
- Solo se acepten slots `AVAILABLE`.
- El request de cita coincida exactamente con el slot remoto.
- Los rechazos de reglas de negocio respondan como `BUSINESS_RULE_VIOLATION`.
- Las fallas de validacion remota respondan como `SERVICE_VALIDATION_FAILED`.
- Ante rechazos, no se creen registros ni eventos.
- Los tests unitarios y de servicio cubran los casos principales.

## 10. Supuestos

- No se bloquearan fines de semana en esta intervencion. Si `schedule-service`
  expone un slot `AVAILABLE`, se aceptara siempre que cumpla horario laboral,
  almuerzo y coherencia de slot.
- `schedule-service` sera la fuente del detalle real del slot.
- `appointment-service` seguira siendo responsable de la transaccion de cita,
  hold, auditoria e idempotencia.
- El formato de hora configurable usara `HH:mm`.
- El timezone usado para validar "hoy" y "hora actual" sera el timezone del
  runtime de la aplicacion, salvo que se defina una politica posterior.

