# mediqueue-appointment-service

Microservicio crítico para la gestión de citas médicas en la plataforma **MediQueue**. Maneja el ciclo de vida completo de las citas: creación con reserva temporal, confirmación contra pago, cancelación por fallo de pago, y expiración automática por TTL. Forma parte de una arquitectura de microservicios con comunicación asíncrona basada en eventos.

---

## ⚡ Quick Reference (Para Integración)

**Puerto**: `8083`

**Endpoints disponibles**:
- `POST /appointments` — Crea una cita. **Requiere header `X-Idempotency-Key`**
- `GET /appointments/{id}` — Obtiene una cita por UUID
- `GET /appointments?patientId={id}` — Lista citas de un paciente

**Setup inicial**:
```bash
cp .env.example .env   # Copiar configuración
# → Editar .env con tus credenciales
mvn spring-boot:run    # Iniciar
```

---

## Stack Tecnológico

| Componente | Tecnología | Versión |
|-----------|-----------|---------|
| Lenguaje | Java | 21 (LTS) |
| Framework | Spring Boot | 3.5.14 |
| Base de datos | PostgreSQL | 14+ |
| Mensajería | RabbitMQ | 3.x |
| Caché | Redis | 6.x+ (declarado, pendiente de integración) |
| Migraciones | Flyway | (incluido con Spring Boot) |
| Monitoreo | Micrometer + Prometheus | (declarado, pendiente de configuración) |
| Resiliencia | Resilience4j | (declarado, pendiente de integración) |
| Build | Maven | 3.9+ |
| Contenedor | Docker | Multi-stage (build + JRE Alpine) |

---

## Responsabilidades del Servicio

- **Gestión de citas**: CRUD del ciclo de vida completo de citas médicas
- **Reserva temporal con TTL**: Bloquea slots por tiempo limitado (hold) mientras se procesa el pago
- **Control de concurrencia**: Previene doble reserva del mismo slot mediante índice único parcial en BD
- **Idempotencia**: Protege contra duplicados por reintentos del cliente (cabecera `X-Idempotency-Key`)
- **Outbox Pattern**: Garantiza consistencia eventual entre BD y RabbitMQ (eventos en misma transacción)
- **Compensación**: Cancela citas automáticamente ante fallos de pago
- **Expiración automática**: Libera slots con hold vencido vía scheduler
- **Auditoría inmutable**: Historial de cambios en tabla append-only con triggers de bloqueo en BD

---

## Endpoints Disponibles

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/appointments` | Crea una cita con reserva temporal. Requiere `X-Idempotency-Key` en el header. Retorna `201 Created`. |
| `GET` | `/appointments/{id}` | Obtiene una cita por su UUID. Retorna `200 OK` o `404 Not Found`. |
| `GET` | `/appointments?patientId={uuid}` | Lista todas las citas de un paciente. Retorna `200 OK` con array. |

### Ejemplo de request (POST /appointments)

```json
{
  "patientId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "dentistId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "slotId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "appointmentDate": "2026-05-15",
  "startTime": "10:00:00",
  "endTime": "10:30:00",
  "notes": "Consulta de rutina"
}
```

Header requerido: `X-Idempotency-Key: uuid-del-cliente`

---

## Variables de Entorno Requeridas

| Variable | Descripción | Valor por defecto | Requerida |
|----------|-------------|-------------------|-----------|
| `DB_URL` | JDBC URL de PostgreSQL | — | ✅ Sí |
| `DB_USER` | Usuario de BD | — | ✅ Sí |
| `DB_PASSWORD` | Contraseña de BD | — | ✅ Sí |
| `RABBITMQ_HOST` | Host de RabbitMQ | — | ✅ Sí |
| `RABBITMQ_PORT` | Puerto de RabbitMQ | — | ✅ Sí |
| `RABBITMQ_USER` | Usuario de RabbitMQ | — | ✅ Sí |
| `RABBITMQ_PASS` | Contraseña de RabbitMQ | — | ✅ Sí |
| `REDIS_HOST` | Host de Redis | — | ❌ No (declarada sin uso) |
| `REDIS_PORT` | Puerto de Redis | — | ❌ No (declarada sin uso) |
| `APPOINTMENT_HOLD_TTL_MINUTES` | Minutos de validez del hold | `5` | ❌ No (default) |
| `HOLD_EXPIRATION_SCAN_SECONDS` | Intervalo de escaneo de expiración | `30` | ❌ No (default) |
| `OUTBOX_PUBLISH_INTERVAL_SECONDS` | Intervalo de publicación de outbox | `1` | ❌ No (default) |
| `OUTBOX_RETRY_INTERVAL_SECONDS` | Intervalo de reintento de eventos FAILED | `30` | ❌ No (default) |
| `IDEMPOTENCY_CLEANUP_INTERVAL_SECONDS` | Intervalo de limpieza de keys expiradas | `3600` | ❌ No (default) |
| `OUTBOX_CLEANUP_INTERVAL_SECONDS` | Intervalo de limpieza de outbox publicados | `86400` | ❌ No (default) |

---

## Guía Rápida para Integración

### Requisitos Previos
- Java 21+
- Maven 3.9+
- PostgreSQL 14+ corriendo
- RabbitMQ 3.x corriendo

### Configuración Rápida

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd mediqueue-appointment-service

# 2. Configurar variables de entorno
cp .env.example .env
# → Editar .env con tus credenciales

# 3. Iniciar la aplicación
mvn spring-boot:run
```

**El servicio corre en el puerto `8083`**

---

## Cómo Levantar el Servicio Localmente (Detallado)

### Pasos Completos

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd mediqueue-appointment-service

# 2. Crear la base de datos (si no existe)
createdb mediqueue_appointment

# 3. Configurar variables de entorno
#    Copiar .env.example a .env y completar valores
cp .env.example .env
#    Editar .env con tus credenciales locales

# 4. Compilar
mvn clean compile

# 5. Ejecutar tests
mvn test

# 6. Iniciar la aplicación
mvn spring-boot:run
```

La aplicación arrancará en `http://localhost:8083`.

### Con Docker

```bash
# Build de la imagen
docker build -t mediqueue-appointment-service .

# Ejecutar (requiere red docker con PostgreSQL y RabbitMQ)
docker run -p 8080:8080 \
  -e DB_URL=jdbc:postgresql://postgres:5432/mediqueue_appointment \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres \
  -e RABBITMQ_HOST=rabbitmq \
  -e RABBITMQ_PORT=5672 \
  -e RABBITMQ_USER=guest \
  -e RABBITMQ_PASS=guest \
  mediqueue-appointment-service
```

---

## Estructura de Paquetes

```
src/main/java/com/mediqueue/appointment/
├── config/           # Configuración Spring (RabbitMQ, beans)
├── controller/       # Endpoints REST (thin HTTP adapter)
├── service/          # Lógica de negocio
├── repository/       # Acceso a datos (Spring Data JPA)
├── domain/           # Entidades JPA + Enums de dominio
│   └── enums/        # AppointmentStatus, HoldStatus, IdempotencyStatus, OutboxStatus
├── dto/              # Data Transfer Objects (records Java)
├── events/           # Records de eventos (publicados y consumidos)
│   ├── published/    # Eventos que este servicio emite
│   └── consumed/     # Eventos que este servicio consume
├── messaging/        # RabbitMQ listeners (@RabbitListener)
├── outbox/           # Relay del patrón Outbox (@Scheduled)
└── exception/        # Manejador global + excepciones de dominio
```

---

## Patrones Implementados

### Outbox Pattern
Los eventos NO se envían directamente a RabbitMQ. Se guardan en la tabla `outbox_events` **dentro de la misma transacción** que el cambio de negocio. Un proceso asíncrono (`OutboxPublisher`) lee los eventos pendientes y los publica en el broker. Si el envío falla, el evento permanece en BD para reintento.

```
Transacción 1 (atómica):
  ├─ INSERT appointment
  ├─ INSERT appointment_hold
  ├─ INSERT appointment_audit
  └─ INSERT outbox_event (status=PENDING)

Transacción 2 (async scheduler cada 1s):
  ├─ SELECT outbox_event WHERE PENDING
  ├─ SEND to RabbitMQ
  └─ UPDATE status=PUBLISHED
```

### Idempotencia
El endpoint `POST /appointments` requiere la cabecera `X-Idempotency-Key`. Si se recibe una key repetida con estado `SUCCEEDED`, se retorna la respuesta cacheada sin reprocesar. Si está `PROCESSING`, se rechaza con `409 Conflict`. Esto protege contra duplicados por reintentos de red.

### StateMachine
`AppointmentStateMachine` valida las transiciones de estado permitidas:

```
PENDING_PAYMENT → CONFIRMED   (pago exitoso)
PENDING_PAYMENT → CANCELLED   (pago fallido / compensación)
PENDING_PAYMENT → EXPIRED     (hold TTL vencido)
```

Cualquier otra transición lanza `IllegalStateTransitionException`.

### HoldExpirationScheduler
Scheduler que cada N segundos (configurable via `HOLD_EXPIRATION_SCAN_SECONDS`) escanea `appointment_holds` con estado `ACTIVE` y `expires_at` vencido. Por cada hold expirado:

1. Marca el hold como `EXPIRED`
2. Marca la cita como `EXPIRED`
3. Registra auditoría
4. Guarda evento `appointment.expired` en outbox

Cada hold se procesa en su propia transacción para que un fallo no afecte a los demás.

---

## Eventos Publicados y Consumidos

### Eventos publicados (→ appointments-exchange)

| Evento | Routing Key | Cuándo se emite | Payload incluye |
|--------|-------------|-----------------|-----------------|
| `AppointmentHeldEvent` | `appointment.held` | Al crear cita con hold | appointmentId, patientId, dentistId, slotId, fechas, holdExpiresAt |
| `AppointmentConfirmedEvent` | `appointment.confirmed` | Al confirmar cita tras pago exitoso | appointmentId, patientId, dentistId, fecha, hora |
| `AppointmentCancelledEvent` | `appointment.cancelled` | Al cancelar cita por pago fallido | appointmentId, patientId, dentistId, fecha, hora |
| `AppointmentExpiredEvent` | `appointment.expired` | Al expirar hold por TTL | appointmentId, patientId, dentistId, fecha, hora |

### Eventos consumidos (← payments-exchange)

| Evento | Queue | Routing Key | Qué hace el servicio |
|--------|-------|-------------|---------------------|
| `PaymentSucceededEvent` | `payment.succeeded` | `payment.succeeded` | Confirma la cita (`PENDING_PAYMENT → CONFIRMED`), consume el hold |
| `PaymentFailedEvent` | `payment.failed` | `payment.failed` | Cancela la cita como compensación (`PENDING_PAYMENT → CANCELLED`), libera el hold |

---

## Licencia

Propietario — MediQueue Platform
