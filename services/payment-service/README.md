# MediQueue Payment Service

Microservicio backend de pagos simulados para MediQueue Resilient. Procesa pagos manuales para pruebas y eventos `AppointmentHeld`, protege idempotencia con PostgreSQL y publica resultados mediante patron Outbox.

## Variables de Entorno

| Variable | Default |
| --- | --- |
| `DB_URL` | `jdbc:postgresql://localhost:5436/mediqueue_payment` |
| `DB_USER` | `postgres` |
| `DB_PASSWORD` | `postgres` |
| `RABBITMQ_HOST` | `localhost` |
| `RABBITMQ_PORT` | `5672` |
| `RABBITMQ_USER` | `guest` |
| `RABBITMQ_PASS` | `guest` |
| `PAYMENT_TIMEOUT_SECONDS` | `10` |
| `IDEMPOTENCY_KEY_TTL_HOURS` | `24` |
| `PAYMENT_SIM_MIN_DELAY_MS` | `1000` |
| `PAYMENT_SIM_MAX_DELAY_MS` | `8000` |
| `PAYMENT_SIM_APPROVAL_RATE` | `0.80` |
| `OUTBOX_PUBLISH_INTERVAL_SECONDS` | `1` |
| `OUTBOX_BATCH_SIZE` | `50` |

## Endpoints

- `POST /payments`
- `GET /payments/{id}`
- `GET /payments?appointmentId={appointmentId}`
- `GET /payments?page=0&size=20`
- `GET /payments?status=APPROVED&page=0&size=20`
- `GET /actuator/health`
- `GET /actuator/prometheus`

## Consultar pagos registrados

Directo al payment-service:

```text
GET http://localhost:8084/payments
GET http://localhost:8084/payments?page=0&size=20
GET http://localhost:8084/payments?status=APPROVED&page=0&size=20
GET http://localhost:8084/payments?appointmentId=11111111-1111-1111-1111-111111111111&page=0&size=20
GET http://localhost:8084/payments?appointmentId=11111111-1111-1111-1111-111111111111&status=APPROVED&page=0&size=20
```

Por API Gateway:

```text
GET http://localhost:8080/api/payments
GET http://localhost:8080/api/payments?page=0&size=20
GET http://localhost:8080/api/payments?status=APPROVED&page=0&size=20
GET http://localhost:8080/api/payments?appointmentId=11111111-1111-1111-1111-111111111111&page=0&size=20
GET http://localhost:8080/api/payments?appointmentId=11111111-1111-1111-1111-111111111111&status=APPROVED&page=0&size=20
```

Este endpoint es solo lectura. No existen `PUT`, `PATCH` ni `DELETE` para pagos. Los pagos se crean por `POST /payments` para pruebas manuales o por eventos `AppointmentHeld`. Los cambios de estado ocurren por logica interna del servicio, no por actualizacion manual desde la API.

## Ejecucion local 100% con Docker

No necesitas tener JDK 17 instalado en Windows si usas Docker. El build se ejecuta dentro de la imagen `maven:3.9-eclipse-temurin-17`, y el runtime usa `eclipse-temurin:17-jre-alpine`.

Levantar todo:

```bash
docker compose -f docker-compose.local.yml up --build
```

Levantar en segundo plano:

```bash
docker compose -f docker-compose.local.yml up -d --build
```

Ver logs del payment-service:

```bash
docker logs -f mediqueue-payment-service
```

Apagar todo sin borrar volumenes:

```bash
docker compose -f docker-compose.local.yml down
```

Apagar todo borrando volumenes:

```bash
docker compose -f docker-compose.local.yml down -v
```

Probar health:

```http
GET http://localhost:8084/actuator/health
```

RabbitMQ Management:

```text
URL: http://localhost:15672
user: guest
pass: guest
```

Conexion en DBeaver:

```text
Host: localhost
Puerto: 5436
Database: mediqueue_payment
Usuario: postgres
Contrasena: postgres
```

El SQL `src/main/resources/db/migration/V1__payment_service_init.sql` no se ejecuta manualmente en DBeaver. Flyway lo ejecuta automaticamente cuando arranca `payment-service`.

## Verificacion en DBeaver

Consulta el historial de Flyway:

```sql
SELECT *
FROM flyway_schema_history;
```

Consulta las tablas creadas:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

Consulta los indices de `payments`:

```sql
SELECT tablename, indexname
FROM pg_indexes
WHERE tablename = 'payments';
```

Deberian aparecer:

- `flyway_schema_history`
- `payments`
- `payment_idempotency`
- `payment_events_outbox`
- indice `uq_payments_appointment_approved`

## Prueba rapida con Postman

Request:

```text
POST http://localhost:8084/payments
```

Headers:

```text
Content-Type: application/json
X-Idempotency-Key: test-payment-001
```

Body:

```json
{
  "appointmentId": "11111111-1111-1111-1111-111111111111",
  "patientId": "22222222-2222-2222-2222-222222222222",
  "amount": 150.00,
  "currency": "GTQ"
}
```

Luego consulta por appointment:

```text
GET http://localhost:8084/payments?appointmentId=11111111-1111-1111-1111-111111111111
```

El resultado puede ser `APPROVED`, `REJECTED` o `TIMEOUT` porque el pago es simulado.

## Prueba de idempotencia

Si repites el mismo `POST /payments` con el mismo `X-Idempotency-Key` y el mismo body, el servicio no debe crear otro pago; debe devolver el pago asociado a esa key.

Si repites el mismo `X-Idempotency-Key` con un body diferente, el servicio debe devolver `409 Conflict`.

## Prueba del Outbox

Consulta los eventos:

```sql
SELECT *
FROM payment_events_outbox
ORDER BY created_at DESC;
```

Si RabbitMQ esta arriba, los eventos deberian pasar a `PUBLISHED`. Si RabbitMQ esta apagado, los eventos quedan `PENDING`. Al levantar RabbitMQ nuevamente, `PaymentOutboxPublisher` debe publicarlos.

## Ejemplos curl

Crear un pago manual:

```bash
curl -i -X POST http://localhost:8084/payments \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: postman-key-001" \
  -d '{
    "appointmentId": "11111111-1111-1111-1111-111111111111",
    "patientId": "22222222-2222-2222-2222-222222222222",
    "amount": 150.00,
    "currency": "GTQ"
  }'
```

Consultar por `paymentId`:

```bash
curl -i http://localhost:8084/payments/33333333-3333-3333-3333-333333333333
```

Consultar por `appointmentId`:

```bash
curl -i "http://localhost:8084/payments?appointmentId=11111111-1111-1111-1111-111111111111"
```

## Idempotencia

Toda solicitud manual requiere `X-Idempotency-Key`. Si la misma key llega con el mismo body, el servicio devuelve el mismo pago. Si la misma key llega con un body distinto, responde `409 Conflict`. Los eventos `AppointmentHeld` usan la key derivada `appointment-held:{appointmentId}`.

## Outbox

`PaymentService` no publica directo a RabbitMQ. En la misma transaccion donde resuelve el pago inserta un evento en `payment_events_outbox`. `PaymentOutboxPublisher` lee eventos `PENDING` con `FOR UPDATE SKIP LOCKED`, publica en `payments-exchange` y marca como `PUBLISHED`. Si RabbitMQ falla, el evento queda `PENDING` para reintento.

## Correr con Maven

Requiere JDK 17 local. Si no quieres instalarlo, usa la seccion "Ejecucion local 100% con Docker".

```bash
./mvnw spring-boot:run
```

En Windows:

```powershell
.\mvnw.cmd spring-boot:run
```

## Correr con Docker sin Compose

Este modo requiere que PostgreSQL y RabbitMQ ya esten levantados.

```bash
docker build -t mediqueue-payment-service .
docker run --rm -p 8084:8084 \
  -e DB_URL=jdbc:postgresql://host.docker.internal:5436/mediqueue_payment \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres \
  -e RABBITMQ_HOST=host.docker.internal \
  mediqueue-payment-service
```

## Alta disponibilidad local con replicas

`docker-compose.local.yml` es el modo simple para una sola instancia de `payment-service`.
`docker-compose.ha.yml` levanta varias replicas de `payment-service` detras de HAProxy.

En modo HA, `payment-service` no publica puertos directamente. HAProxy expone
`localhost:8084` y reparte trafico hacia las replicas disponibles usando
`/actuator/health` como healthcheck. PostgreSQL y RabbitMQ son compartidos por
todas las replicas.

La seguridad funcional se mantiene en componentes compartidos:

- La idempotencia vive en PostgreSQL, en `payment_idempotency`, y evita duplicados entre replicas.
- El indice parcial unico `uq_payments_appointment_approved` evita dos pagos `APPROVED` para el mismo `appointmentId`.
- El Outbox usa `FOR UPDATE SKIP LOCKED` para que varias replicas no publiquen el mismo evento pendiente.

Levantar 3 replicas:

```bash
docker compose -f docker-compose.ha.yml up -d --build --scale payment-service=3
```

Ver contenedores:

```bash
docker compose -f docker-compose.ha.yml ps
```

Ver logs de las replicas:

```bash
docker compose -f docker-compose.ha.yml logs -f payment-service
```

Ver logs de HAProxy:

```bash
docker logs -f mediqueue-payment-lb
```

Health por balanceador:

```http
GET http://localhost:8084/actuator/health
```

Consultar pagos por balanceador:

```http
GET http://localhost:8084/payments?page=0&size=20
```

Crear pago por balanceador:

```text
POST http://localhost:8084/payments
```

Headers:

```text
Content-Type: application/json
X-Idempotency-Key: ha-payment-001
```

Body:

```json
{
  "appointmentId": "11111111-1111-1111-1111-111111111111",
  "patientId": "22222222-2222-2222-2222-222222222222",
  "amount": 150.00,
  "currency": "GTQ"
}
```

Matar una replica:

```bash
docker ps --filter "name=payment-service"
docker kill <container_id>
```

Verificar continuidad:

```http
GET http://localhost:8084/actuator/health
GET http://localhost:8084/payments?page=0&size=20
```

Escalar a 5 replicas:

```bash
docker compose -f docker-compose.ha.yml up -d --scale payment-service=5
```

Apagar:

```bash
docker compose -f docker-compose.ha.yml down
```

Apagar borrando datos:

```bash
docker compose -f docker-compose.ha.yml down -v
```

## Uso desde api-gateway

Si `api-gateway` usa:

```text
PAYMENT_SERVICE_URL=http://host.docker.internal:8084
```

no hay que cambiarlo. En modo HA, `localhost:8084` lo atiende HAProxy, no una
sola instancia de `payment-service`.

## Nota sobre nube o VM

Docker Compose local simula replicas en una sola maquina, pero no es alta
disponibilidad real entre maquinas. Para replicas en VM o nube se necesita:

- Load balancer externo.
- PostgreSQL compartido/administrado o cluster.
- RabbitMQ compartido/administrado o cluster.
- Red privada, VPC o VPN.
- Firewall configurado.
- No exponer publicamente PostgreSQL ni RabbitMQ.
