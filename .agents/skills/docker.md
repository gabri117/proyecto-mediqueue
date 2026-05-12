# Skill: Docker Compose

## Archivos relevantes

| Archivo | Propósito |
|---------|-----------|
| `docker-compose.yml` (raíz) | Stack local de desarrollo |
| `infra/docker-compose.yml` | Stack de staging/prod con DBs separadas, RabbitMQ, Prometheus, Grafana |
| `infra/docker/init-dbs.sql` | Crea las 5 bases de datos en el postgres único |
| `infra/docker/*.Dockerfile` | Dockerfiles multi-stage por servicio |
| `.env.example` (raíz) | Variables de entorno para el compose de desarrollo |
| `infra/.env.example` | Variables de entorno para el compose de staging/prod |

## Levantar el stack de desarrollo

```bash
# 1. Crear .env desde el ejemplo
cp .env.example .env

# 2. Levantar todo (build + start)
docker compose up --build

# 3. Solo infraestructura (postgres + redis)
docker compose up postgres redis

# 4. Rebuild de un servicio específico
docker compose up --build appointment-service
```

## Puertos

| Servicio | Puerto externo | Puerto interno |
|----------|---------------|----------------|
| api-gateway | 8080 | 8080 |
| appointment-service | 8081 | 8080 |
| notification-service | 8082 | 8080 |
| payment-service | 8083 | 8080 |
| patient-service | 8084 | 8080 |
| schedule-service | 8085 | 8080 |
| PostgreSQL | 5432 | 5432 |
| Redis | 6379 | 6379 |

## Bases de datos (postgres único)

El script `infra/docker/init-dbs.sql` crea:

- `mediqueue_appointments`
- `mediqueue_notifications`
- `mediqueue_payments`
- `mediqueue_patients`
- `mediqueue_schedules`

Todas propiedad del usuario `mediqueue` (definido por `DB_USERNAME` en `.env`).

## Variables de entorno críticas

> **IMPORTANTE**: Cada servicio usa nombres DIFERENTES para las mismas variables en sus `application.properties`. El `docker-compose.yml` pasa AMBAS variantes para compatibilidad:

| Servicio | Variable URL de BD |
|----------|-------------------|
| appointment, patient, payment | `DB_URL` |
| schedule | `SCHEDULE_DB_URL` |
| notification | `${DB_URL}` en dev, `postgres:5432/mediqueue_notifications` en profile docker |

Además se pasan `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` como override de Spring Boot.

## Dockerfiles

Todos los Dockerfiles son multi-stage y siguen el mismo patrón:

1. Copian TODOS los `pom.xml` de módulos (necesario para resolución del reactor Maven)
2. Copian solo `packages/shared-lib` + el servicio específico como fuente
3. Compilan con `mvn -B -pl services/{nombre} -am package -DskipTests`
4. Runtime: `eclipse-temurin:21-jre-alpine` con usuario no-root `mediqueue`

Los Dockerfiles están en `infra/docker/{nombre-servicio}.Dockerfile`.

El build context siempre es la **raíz del proyecto** (`.`), no la carpeta del servicio.
