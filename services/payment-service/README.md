# MediQueue Payment Service

Microservicio de pagos simulados de MediQueue. En la Fase 1 de DB unificada usa la base logica `mediqueue`, el schema `payment`, Flyway por schema y el endpoint interno `postgres-lb:5432`.

No implementa Patroni ni failover real de PostgreSQL todavia. La alta disponibilidad local actual se limita a replicas del servicio detras de `payment-lb`, con PostgreSQL y RabbitMQ compartidos.

## Base de datos

URL JDBC interna:

```text
jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment,public
```

Configuracion esperada:

```yaml
spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment,public}
  flyway:
    schemas: payment
    default-schema: payment
    create-schemas: false
  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        default_schema: payment
```

`currentSchema=payment,public` hace que tablas, tipos e indices no calificados se creen o consulten en `payment`, y que funciones como `uuid_generate_v4()` se resuelvan desde `public`, donde infraestructura instala `uuid-ossp`.

## Objetos esperados

Flyway debe crear en `payment`:

- `flyway_schema_history`
- `payments`
- `payment_idempotency`
- `payment_events_outbox`
- enums `payment_status`, `idempotency_status`, `outbox_publication_status`
- indice parcial unico `uq_payments_appointment_approved`

No debe haber tablas de negocio de payment en `public`, ni foreign keys hacia `appointment` o `patient`.

## Variables

| Variable | Default |
| --- | --- |
| `DB_URL` | `jdbc:postgresql://postgres-lb:5432/mediqueue?currentSchema=payment,public` |
| `DB_USER` | `mediqueue` |
| `DB_PASSWORD` | `mediqueue` |
| `SPRING_FLYWAY_SCHEMAS` | `payment` |
| `SPRING_FLYWAY_DEFAULT_SCHEMA` | `payment` |
| `SPRING_FLYWAY_CREATE_SCHEMAS` | `false` |
| `SPRING_JPA_PROPERTIES_HIBERNATE_DEFAULT_SCHEMA` | `payment` |
| `RABBITMQ_HOST` | `localhost` |
| `RABBITMQ_PORT` | `5672` |
| `RABBITMQ_USER` | `mediqueue` |
| `RABBITMQ_PASS` | `rabbit123` |
| `PAYMENT_TIMEOUT_SECONDS` | `10` |
| `IDEMPOTENCY_KEY_TTL_HOURS` | `24` |
| `PAYMENT_SIM_MIN_DELAY_MS` | `1000` |
| `PAYMENT_SIM_MAX_DELAY_MS` | `8000` |
| `PAYMENT_SIM_APPROVAL_RATE` | `0.80` |
| `OUTBOX_PUBLISH_INTERVAL_SECONDS` | `1` |
| `OUTBOX_BATCH_SIZE` | `50` |

## Endpoints

```text
POST /payments
GET  /payments/{id}
GET  /payments?page=0&size=20
GET  /payments?status=APPROVED&page=0&size=20
GET  /payments?appointmentId={uuid}&page=0&size=20
GET  /payments?appointmentId={uuid}&status=APPROVED&page=0&size=20
GET  /actuator/health
GET  /actuator/prometheus
```

Por el balanceador local:

```text
http://127.0.0.1:8083
```

Ejemplos:

```bash
curl -i "http://127.0.0.1:8083/payments?page=0&size=20"
curl -i "http://127.0.0.1:8083/payments?status=APPROVED&page=0&size=20"
curl -i "http://127.0.0.1:8083/payments?appointmentId=11111111-1111-1111-1111-111111111111&page=0&size=20"
```

Crear pago manual:

```bash
curl -i -X POST http://127.0.0.1:8083/payments \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: manual-payment-001" \
  -d '{
    "appointmentId": "11111111-1111-1111-1111-111111111111",
    "patientId": "22222222-2222-2222-2222-222222222222",
    "amount": 150.00,
    "currency": "GTQ"
  }'
```

## Idempotencia

Toda solicitud manual requiere `X-Idempotency-Key`.

- Misma key y mismo body: devuelve el pago ya asociado, sin crear otro.
- Misma key y body diferente: devuelve `409 Conflict`.
- Eventos `AppointmentHeld`: usan la key derivada `appointment-held:{appointmentId}`.

El indice parcial `uq_payments_appointment_approved` evita mas de un pago `APPROVED` para el mismo `appointment_id`, incluso con varias replicas.

## Outbox y RabbitMQ

`PaymentService` inserta eventos en `payment.payment_events_outbox` dentro de la misma transaccion que resuelve el pago. `PaymentOutboxPublisher` toma eventos `PENDING` con:

```sql
SELECT *
FROM payment_events_outbox
WHERE publication_status = 'PENDING'
ORDER BY created_at
LIMIT :limit
FOR UPDATE SKIP LOCKED;
```

Con `currentSchema=payment,public`, esa query nativa resuelve `payment_events_outbox` dentro del schema `payment`.

Eventos publicados:

- `PAYMENT_SUCCEEDED` -> routing key `payment.succeeded`
- `PAYMENT_FAILED` -> routing key `payment.failed`

Validar colas y DLQ:

```bash
docker exec mediqueue-rabbitmq rabbitmqctl list_queues name messages consumers
```

`notification.payment.queue` debe consumir mensajes de pago y las DLQ no deberian acumular mensajes.

## Validaciones SQL

Con DBeaver:

```text
Host: 127.0.0.1
Port: 55461
Database: mediqueue
User: mediqueue
Password: mediqueue
sslmode: disable
```

Historial Flyway:

```sql
SELECT installed_rank, description, success
FROM payment.flyway_schema_history
ORDER BY installed_rank;
```

Indices:

```sql
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'payment'
ORDER BY tablename, indexname;
```

Conteo por estado:

```sql
SELECT payment_status, COUNT(*)
FROM payment.payments
GROUP BY payment_status;
```

Duplicados aprobados:

```sql
SELECT appointment_id, COUNT(*)
FROM payment.payments
WHERE payment_status = 'APPROVED'
GROUP BY appointment_id
HAVING COUNT(*) > 1;
```

Tablas de payment fuera de `public`:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('payment', 'public')
ORDER BY table_schema, table_name;
```

## Ejecutar tests

Desde la raiz del monorepo:

```bash
./mvnw -pl services/payment-service test
```

En Windows:

```powershell
.\mvnw.cmd -pl services/payment-service test
```

Los tests cubren creacion de pago, idempotencia, conflicto por body distinto, proteccion contra doble `APPROVED`, eventos outbox y publishers concurrentes.

## Escalar a 3 replicas

Desde la raiz del monorepo:

```bash
docker compose up -d --scale payment-service=3 payment-service payment-lb
```

Verificar:

```bash
docker compose ps payment-service payment-lb
curl -s http://127.0.0.1:8083/actuator/health
curl -s http://127.0.0.1:8083/actuator/prometheus
```

El health debe reportar `status: UP`, `db: UP` y `rabbit: UP`. En Prometheus deben aparecer 3 targets UP de `payment-service` y el target de `payment-lb` UP cuando el stack de observabilidad este levantado.

## Pendientes hacia HA real

- No avanzar a Patroni en Fase 1.
- Implementar Patroni/etcd o PostgreSQL administrado en una fase posterior.
- Probar failover real de PostgreSQL cuando exista cluster.
- Mantener RabbitMQ y notification validados para confirmar consumo de `payment.succeeded` y `payment.failed`.
