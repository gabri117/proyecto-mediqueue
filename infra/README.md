# mediqueue-infra

Repositorio de infraestructura del sistema **MediQueue Resilient**.  
Contiene el Docker Compose maestro, configuraciones de Prometheus/Grafana, scripts de k6 y demo de caos.

## Estructura

```
mediqueue-infra/
├── docker-compose.yml          # Orquestación completa (5 PG + Redis + RabbitMQ + 7 servicios + obs)
├── .env                        # Variables de entorno (NO commitear)
├── .env.example                # Plantilla de variables
├── rabbitmq/
│   ├── rabbitmq.conf           # Config base de RabbitMQ
│   └── definitions.json        # Exchanges, queues y bindings predefinidos
├── prometheus/
│   └── prometheus.yml          # Scrape targets de todos los servicios
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/        # Prometheus como datasource automático
│   │   └── dashboards/         # Provisioning automático de dashboards
│   └── dashboards/
│       └── mediqueue-dashboard.json   # Dashboard principal
├── load-tests/
│   ├── scenario-a-slots.js     # 50k GET /slots en 3 min (200 VUs)
│   ├── scenario-b-concurrency.js  # 1000 VUs mismo slot (prueba de locks)
│   ├── scenario-c-full-flow.js    # Flujo completo bajo carga + falla inducida
│   └── results/                # Resultados de k6 (gitignored)
├── chaos/
│   └── chaos.sh                # Script interactivo de demo de caos (5 actos)
└── scripts/
    ├── seed-data.sh            # Crea 50 pacientes, 10 dentistas y ~200 slots
    └── check-system.sh         # Verificación rápida de health de todos los servicios
```

## Puertos

| Servicio              | Puerto externo | Puerto interno |
| --------------------- | -------------- | -------------- |
| api-gateway-1         | 8080           | 8080           |
| api-gateway-2         | 8090           | 8080           |
| patient-service       | 8081           | 8081           |
| schedule-service      | 8082           | 8082           |
| appointment-service-1 | 8083           | 8083           |
| appointment-service-2 | 8093           | 8083           |
| payment-service-1     | 8084           | 8084           |
| payment-service-2     | 8094           | 8084           |
| notification-service  | 8085           | 8085           |
| patient-db (PG)       | 5432           | 5432           |
| schedule-db (PG)      | 5433           | 5432           |
| appointment-db (PG)   | 5434           | 5432           |
| payment-db (PG)       | 5435           | 5432           |
| notification-db (PG)  | 5436           | 5432           |
| Redis                 | 6379           | 6379           |
| RabbitMQ AMQP         | 5672           | 5672           |
| RabbitMQ Management   | 15672          | 15672          |
| Prometheus            | 9090           | 9090           |
| Grafana               | 3000           | 3000           |

## Inicio rápido

### Prerrequisitos

- Docker Desktop con al menos 8GB de RAM asignados
- Docker Compose v2+
- k6 (opcional, para pruebas de carga): `brew install k6`

### 1. Clonar y configurar

```bash
git clone https://github.com/<org>/mediqueue-infra.git
cd mediqueue-infra
cp .env.example .env
# Editar .env con los valores reales (o dejar los defaults para desarrollo)
```

### 2. Levantar solo la infraestructura base (sin microservicios)

Útil para que cada miembro del equipo levante los servicios en modo local:

```bash
docker compose up -d patient-db schedule-db appointment-db payment-db notification-db redis rabbitmq prometheus grafana
```

### 3. Levantar todo el sistema (imágenes de ghcr.io)

```bash
docker compose pull   # Descarga imágenes publicadas por cada equipo
docker compose up -d
```

### 4. Verificar estado

```bash
bash scripts/check-system.sh
docker compose ps
```

### 5. Cargar datos de prueba

```bash
bash scripts/seed-data.sh
```

### 6. Abrir dashboards

- Grafana: http://localhost:3000 (admin / admin123)
- RabbitMQ Management: http://localhost:15672 (mediqueue / rabbit123)
- Prometheus: http://localhost:9090

## Pruebas de carga (k6)

```bash
# Escenario A — 50k GET /slots (200 VUs, ~3 min)
k6 run load-tests/scenario-a-slots.js

# Escenario B — 1000 VUs mismo slot (prueba de locks)
k6 run -e SLOT_ID=1 load-tests/scenario-b-concurrency.js

# Escenario C — Flujo completo (100 VUs, 5 min)
k6 run load-tests/scenario-c-full-flow.js
```

## Demo de caos

```bash
bash chaos/chaos.sh
```

El script guía la demo en 5 actos:

1. **Flujo normal** — crear cita y ver la saga completa
2. **Carga sostenida** — k6 escenario A en vivo en Grafana
3. **Concurrencia hostil** — 1000 VUs al mismo slot, 1 gana
4. **Caos en vivo** — matar réplicas, reiniciar Redis, escalar
5. **Verificación de consistencia** — consultas directas a BD

## Comandos útiles

```bash
# Ver logs de un servicio específico
docker compose logs -f appointment-service-1

# Ver estado de todas las colas RabbitMQ
docker exec rabbitmq rabbitmqctl list_queues name messages consumers

# Consultar BD de appointment directamente
docker exec appointment-db psql -U mediqueue -d appointment_db -c "SELECT * FROM appointments LIMIT 10;"

# Reiniciar solo un servicio
docker compose restart notification-service

# Escalar appointment-service a 3 réplicas (requiere ajuste de puertos)
docker compose up -d --scale appointment-service-1=1 --scale appointment-service-2=1

# Detener todo y limpiar volúmenes (⚠️ borra todos los datos)
docker compose down -v
```

## Responsables

| Orden | Repo                           | Persona        |
| ----- | ------------------------------ | -------------- |
| 1     | mediqueue-infra                | Domingo Rubén  |
| 2     | mediqueue-patient-service      | Riquelme Gómez |
| 3     | mediqueue-schedule-service     | Riquelme Gómez |
| 4     | mediqueue-appointment-service  | José Morales   |
| 5     | mediqueue-payment-service      | Melbyn Xutuc   |
| 6     | mediqueue-notification-service | Domingo Rubén  |
| 7     | mediqueue-api-gateway          | Melbyn Xutuc   |
