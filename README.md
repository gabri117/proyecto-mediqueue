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
│   ├── grafana/                     # Dashboards Grafana
│   ├── prometheus/                  # Configuración Prometheus
│   ├── rabbitmq/                    # Definiciones RabbitMQ
│   └── scripts/                     # Scripts de utilidad
└── docs/
```

## Requisitos

- Java 21
- Maven 3.9+
- Docker & Docker Compose

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

| Servicio             | Puerto externo | Puerto interno |
|----------------------|----------------|----------------|
| api-gateway          | 8080           | 8080           |
| appointment-service  | 8081           | 8080           |
| notification-service | 8082           | 8080           |
| payment-service      | 8083           | 8080           |
| patient-service      | 8084           | 8080           |
| schedule-service     | 8085           | 8080           |
| PostgreSQL           | 5432           | 5432           |
| Redis                | 6379           | 6379           |

## Stack tecnológico

- **Spring Boot** 3.5.14
- **Spring Cloud** 2025.0.2
- **Java** 21
- **PostgreSQL** 16
- **Redis** 7
- **RabbitMQ** 3.12
- **Flyway** (migraciones)
- **Resilience4j** (circuit breakers)
- **Micrometer + Prometheus + Grafana** (observabilidad)
