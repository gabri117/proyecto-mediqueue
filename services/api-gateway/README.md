# mediqueue-api-gateway

API Gateway reactivo para MediQueue Resilient. Este servicio es el punto unico de entrada HTTP y se encarga de enrutar solicitudes hacia los microservicios internos, aplicar rate limiting con Redis, propagar `X-Correlation-Id` y exponer health checks y metricas para Prometheus.

El gateway no tiene base de datos, no ejecuta SQL, no usa JPA/Flyway/PostgreSQL/RabbitMQ y no contiene reglas de negocio de pacientes, horarios, citas, pagos ni notificaciones.

## Dependencias

- Spring Cloud Gateway Server WebFlux: enrutamiento reactivo.
- Spring Cloud LoadBalancer: soporte para balanceo cuando se usen URIs `lb://` o replicas registradas.
- Spring Data Redis Reactive: backend del `RequestRateLimiter`.
- Spring Boot Actuator: health, metrics y endpoint del gateway.
- Micrometer Prometheus: scrape de metricas para Prometheus/Grafana.
- Spring Cloud CircuitBreaker Reactor Resilience4j: circuit breaker y fallback 503 para fallas de servicios.
- Spring Boot Validation: soporte de validacion de propiedades si se agregan configuraciones tipadas.

Se removieron dependencias que no pertenecen al gateway: Spring AI Redis Vector Store y Spring Boot Admin Client. No se agregaron JPA, PostgreSQL, Flyway ni RabbitMQ.

## Rutas

| Entrada gateway | Servicio destino | Path reenviado |
| --- | --- | --- |
| `/api/patients/**` | patient-service | `/patients/**` |
| `/api/dentists/**` | schedule-service | `/dentists/**` |
| `/api/dentist-slots/**` | schedule-service | `/dentist-slots/**` |
| `/api/appointments/**` | appointment-service | `/appointments/**` |
| `/api/payments/**` | payment-service | `/payments/**` |
| `/api/notifications/**` | notification-service | `/notifications/**` |

El query string se conserva. Headers como `Content-Type`, `X-Idempotency-Key`, `X-Correlation-Id` y `X-Client-Id` no se eliminan.

## Variables de entorno

| Variable | Default |
| --- | --- |
| `SERVER_PORT` | `8080` |
| `REDIS_HOST` | `localhost` |
| `REDIS_PORT` | `6379` |
| `PATIENT_SERVICE_URL` | `http://localhost:8081` |
| `SCHEDULE_SERVICE_URL` | `http://localhost:8082` |
| `APPOINTMENT_SERVICE_URL` | `http://localhost:8083` |
| `PAYMENT_SERVICE_URL` | `http://localhost:8084` |
| `NOTIFICATION_SERVICE_URL` | `http://localhost:8085` |
| `RATE_LIMIT_PATIENT_REPLENISH` | `50` |
| `RATE_LIMIT_PATIENT_BURST` | `100` |
| `RATE_LIMIT_SCHEDULE_REPLENISH` | `200` |
| `RATE_LIMIT_SCHEDULE_BURST` | `400` |
| `RATE_LIMIT_APPOINTMENT_REPLENISH` | `50` |
| `RATE_LIMIT_APPOINTMENT_BURST` | `100` |
| `RATE_LIMIT_PAYMENT_REPLENISH` | `30` |
| `RATE_LIMIT_PAYMENT_BURST` | `60` |
| `RATE_LIMIT_NOTIFICATION_REPLENISH` | `50` |
| `RATE_LIMIT_NOTIFICATION_BURST` | `100` |

## Docker local

Levantar gateway + Redis:

```bash
docker compose -f docker-compose.local.yml up -d --build
```

Ver estado:

```bash
docker compose -f docker-compose.local.yml ps
docker logs -f mediqueue-api-gateway
```

Apagar:

```bash
docker compose -f docker-compose.local.yml down
```

Apagar y borrar volumen Redis:

```bash
docker compose -f docker-compose.local.yml down -v
```

Este compose usa `host.docker.internal` para enrutar hacia microservicios levantados en Windows o en otros compose. Si se usa un compose maestro con todos los servicios en la misma red Docker, cambia las URLs a nombres de servicio, por ejemplo `PAYMENT_SERVICE_URL=http://payment-service:8084`.

No necesitas JDK 17 local si usas Docker; el build se hace dentro de `maven:3.9-eclipse-temurin-17`.

## Pruebas con Postman

Health:

```http
GET http://localhost:8080/actuator/health
```

Info del gateway:

```http
GET http://localhost:8080/gateway/info
```

Consulta hacia payment-service:

```http
GET http://localhost:8080/api/payments?appointmentId=11111111-1111-1111-1111-111111111111
X-Client-Id: test-client-1
```

Pago con idempotencia:

```http
POST http://localhost:8080/api/payments
Content-Type: application/json
X-Idempotency-Key: gateway-payment-001
X-Client-Id: test-client-1

{
  "appointmentId": "11111111-1111-1111-1111-111111111111",
  "patientId": "22222222-2222-2222-2222-222222222222",
  "amount": 150.00,
  "currency": "GTQ"
}
```

Para probar payment-service, primero levanta `mediqueue-payment-service` en el puerto `8084`, luego levanta este gateway y ejecuta el `POST` anterior.

## Rate limiting

El rate limiting usa primero `X-Client-Id` como clave. Si no existe, usa la IP remota, y si no hay IP usa `anonymous`. Muchas solicitudes rapidas con el mismo `X-Client-Id` pueden devolver `429 Too Many Requests`.

## Circuit breaker y errores

Los circuit breakers estan configurados por ruta con fallback interno `/fallback/{service}`. Si un microservicio esta caido, responde `503`:

```json
{
  "code": "SERVICE_UNAVAILABLE",
  "message": "payment-service is temporarily unavailable",
  "timestamp": "2026-05-08T18:00:00Z"
}
```

Errores de negocio devueltos por los microservicios, como `400`, `404`, `409` o `422`, se preservan con su status y body.

## Actuator y Prometheus

Endpoints expuestos:

- `/actuator/health`
- `/actuator/metrics`
- `/actuator/prometheus`
- `/actuator/gateway`

## Desarrollo

Compilar y probar:

```bash
./mvnw test
```

Construir imagen:

```bash
docker compose -f docker-compose.local.yml build
```
