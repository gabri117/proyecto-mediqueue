# MediQueue Platform

Monorepo multi-module Maven para la plataforma MediQueue.

## Estructura

```
mediqueue-platform/
├── pom.xml                          # POM padre (reactor)
├── docker-compose.yml               # Stack local completo
├── .env.example                     # Variables de entorno
├── services/
│   ├── api-gateway/                 # Spring Cloud Gateway + Resilience4j
│   ├── appointment-service/         # Gestión de citas
│   ├── notification-service/        # Consumidor de eventos / notificaciones
│   ├── payment-service/             # Procesamiento de pagos
│   ├── patient-service/             # Gestión de pacientes
│   └── schedule-service/            # Agenda de dentistas
├── packages/
│   └── shared-lib/                  # DTOs y utilidades compartidas
├── infra/
│   ├── docker/                      # Dockerfiles + init-dbs.sql
│   ├── grafana/                     # Dashboards y provisioning Grafana
│   ├── prometheus/                  # Configuración Prometheus
│   ├── rabbitmq/                    # Definiciones y plugins RabbitMQ
│   ├── load-tests/                  # Escenarios avanzados de carga (K6)
│   └── scripts/                     # Scripts de utilidad
├── tests/
│   └── load-test.js                 # Prueba de carga principal (K6)
├── docs/
│   └── MediQueue.postman_collection.json  # Colección Postman E2E
└── README.md
```

## Requisitos

- Java 21
- Maven 3.9+
- Docker & Docker Compose
- [K6](https://k6.io/docs/getting-started/installation/) (para pruebas de carga)

## Inicio rápido

```bash
# 1. Copiar variables de entorno
cp .env.example .env

# 2. Compilar todo el monorepo
mvn clean install -DskipTests

# 3. Levantar con Docker Compose
docker compose up --build

# 4. Verificar servicios
curl http://localhost:8080/actuator/health   # API Gateway
curl http://localhost:8081/actuator/health   # Appointment
curl http://localhost:8082/actuator/health   # Notification
curl http://localhost:8083/actuator/health   # Payment
curl http://localhost:8084/actuator/health   # Patient
curl http://localhost:8085/actuator/health   # Schedule
```

## Compilar un servicio individual

```bash
mvn -pl services/appointment-service -am clean package -DskipTests
```

## Puertos

| Servicio             | Puerto externo | Puerto interno | Descripción                       |
|----------------------|----------------|----------------|-----------------------------------|
| api-gateway          | 8080           | 8080           | Punto de entrada principal        |
| appointment-service  | 8081           | 8080           | Gestión de citas                  |
| notification-service | 8082           | 8080           | Notificaciones / eventos          |
| payment-service      | 8083           | 8080           | Procesamiento de pagos            |
| patient-service      | 8084           | 8080           | Gestión de pacientes              |
| schedule-service     | 8085           | 8080           | Agenda de dentistas               |
| PostgreSQL           | 5432           | 5432           | Base de datos principal           |
| Redis                | 6379           | 6379           | Caché y rate limiting             |
| RabbitMQ             | 5672           | 5672           | Mensajería asíncrona              |
| RabbitMQ Management  | 15672          | 15672          | UI de administración              |
| Prometheus           | 9090           | 9090           | Recolección de métricas           |
| Grafana              | 3000           | 3000           | Dashboards de observabilidad      |

## Observabilidad (Prometheus + Grafana)

Al ejecutar `docker compose up`, Prometheus y Grafana se levantan automáticamente.

- **Prometheus:** [http://localhost:9090](http://localhost:9090)
- **Grafana:** [http://localhost:3000](http://localhost:3000) (usuario: `admin`, contraseña: `admin`)

Grafana se auto-provisiona con:
- **Datasource:** Prometheus (configurado automáticamente)
- **Dashboard:** "MediQueue Resilient - Dashboard Principal" con paneles de:
  - Requests por segundo por servicio
  - Tasa de error 5xx
  - Latencia p50/p95/p99
  - Mensajes en colas RabbitMQ
  - Uso de heap JVM y CPU
  - Réplicas activas por servicio
  - Conexiones JDBC (HikariCP)

## Colección Postman (Flujo E2E)

La colección se encuentra en `docs/MediQueue.postman_collection.json`.

### Importar en Postman

1. Abrir Postman → Import → Seleccionar archivo `docs/MediQueue.postman_collection.json`
2. La colección incluye variables de entorno que se capturan automáticamente entre pasos

### Flujo E2E

Ejecutar las peticiones **en orden** (usar "Run Collection"):

| # | Petición                     | Método | Endpoint                                           |
|---|------------------------------|--------|-----------------------------------------------------|
| 0 | Health Check                 | GET    | `/actuator/health`                                  |
| 1 | Crear Paciente               | POST   | `/api/patients`                                     |
| 2 | Crear Dentista               | POST   | `/api/dentists`                                     |
| 3 | Crear Slot                   | POST   | `/api/slots`                                |
| 4 | Crear Cita (idempotencia)    | POST   | `/api/appointments` + `X-Idempotency-Key`           |
| 5 | Consultar Pago               | GET    | `/api/payments?appointmentId={{appointmentId}}`      |
| 6 | Consultar Cita               | GET    | `/api/appointments/{{appointmentId}}`                |
| 7 | Notificaciones del Paciente  | GET    | `/api/notifications/patient/{{patientId}}`           |
| 8 | Test Idempotencia (retry)    | POST   | `/api/appointments` (misma key → 200/409)            |

## Pruebas de carga (K6)

### Test principal (raíz)

```bash
# Ejecución básica
k6 run tests/load-test.js

# Con URL personalizada del gateway
k6 run --env GATEWAY_URL=http://localhost:8080 tests/load-test.js

# Para 50,000 peticiones (requerimiento de la rúbrica)
k6 run --iterations 50000 --vus 100 tests/load-test.js
```

### Escenarios avanzados (infra/)

```bash
# Escenario A: Consulta de slots bajo carga
k6 run infra/load-tests/scenario-a-slots.js

# Escenario B: Concurrencia sobre operación crítica
k6 run infra/load-tests/scenario-b-concurrency.js

# Escenario C: Flujo completo + falla inducida
k6 run infra/load-tests/scenario-c-full-flow.js
```

Los resultados se guardan automáticamente en JSON en `tests/results/` o `infra/load-tests/results/`.

## Variables de entorno

Copiar `.env.example` a `.env` y ajustar según sea necesario. Las variables más importantes:

| Variable             | Default      | Descripción                          |
|----------------------|--------------|--------------------------------------|
| `DB_USERNAME`        | `mediqueue`  | Usuario PostgreSQL                   |
| `DB_PASSWORD`        | `mediqueue`  | Contraseña PostgreSQL                |
| `REDIS_PASSWORD`     | `redis123`   | Contraseña Redis                     |
| `RABBITMQ_USER`      | `mediqueue`  | Usuario RabbitMQ                     |
| `RABBITMQ_PASSWORD`  | `rabbit123`  | Contraseña RabbitMQ                  |
| `GRAFANA_USER`       | `admin`      | Usuario Grafana                      |
| `GRAFANA_PASSWORD`   | `admin`      | Contraseña Grafana                   |

## Stack tecnológico

- **Spring Boot** 3.5.14
- **Spring Cloud** 2025.0.2
- **Java** 21
- **PostgreSQL** 16
- **Redis** 7
- **RabbitMQ** 3.13
- **Flyway** (migraciones)
- **Resilience4j** (circuit breakers)
- **Micrometer + Prometheus + Grafana** (observabilidad)
- **K6** (pruebas de carga)

