# Observabilidad Patroni/PostgreSQL HA

Esta capa agrega monitoreo minimo para el cluster local de Patroni sin tocar dashboards de load testing.

## Componentes

- `patroni-rest`: Prometheus intenta scrapear `/metrics` de cada REST API de Patroni.
- `patroni-postgres-exporter`: un `postgres_exporter` por nodo PostgreSQL Patroni.
- `patroni-haproxy`: HAProxy expone metricas Prometheus en `http://patroni-postgres-lb:7000/metrics`.
- `patroni-etcd`: Prometheus lee `/metrics` de `etcd-1`, `etcd-2`, `etcd-3`.
- Grafana carga el dashboard `MediQueue Patroni Cluster Status`.

## Servicios nuevos

```text
patroni-postgres-exporter-1 -> patroni-postgres-1:5432
patroni-postgres-exporter-2 -> patroni-postgres-2:5432
patroni-postgres-exporter-3 -> patroni-postgres-3:5432
```

No publican puertos al host; solo Prometheus los consulta dentro de `mediqueue-net`.

## Dashboard

Archivo:

```text
infra/grafana/dashboards/mediqueue-patroni-cluster-status.json
```

Paneles incluidos:

- Current Leader Count.
- Replica Count.
- Max Replica Lag.
- HAProxy Metrics.
- Replication Lag By Node.
- Leader Changes Evidence.
- etcd Up/Down.
- HAProxy Backend Up/Down.

## Queries principales

Lider actual:

```promql
sum(pg_patroni_role_is_primary{job="patroni-postgres-exporter"})
```

Replicas:

```promql
sum(pg_patroni_role_is_replica{job="patroni-postgres-exporter"})
```

Lag maximo de replicas en bytes:

```promql
max(pg_patroni_replay_lag_lsn_bytes{job="patroni-postgres-exporter"})
```

Evidencia de failover o switchover:

```promql
changes(pg_patroni_role_is_primary{job="patroni-postgres-exporter"}[15m])
```

HAProxy disponible:

```promql
up{job="patroni-haproxy"}
```

Backends de HAProxy:

```promql
haproxy_backend_up{job="patroni-haproxy"}
```

etcd disponible:

```promql
up{job="patroni-etcd"}
```

## Validar targets

Levantar Patroni con observabilidad:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml up -d prometheus grafana patroni-postgres-lb patroni-postgres-exporter-1 patroni-postgres-exporter-2 patroni-postgres-exporter-3
```

Abrir:

```text
http://localhost:9090/targets
http://localhost:3000
```

Targets esperados:

```text
patroni-rest
patroni-postgres-exporter
patroni-haproxy
patroni-etcd
```

## Notas

- `postgres_exporter` usa credenciales de desarrollo del superuser de Patroni. En produccion se debe crear un usuario dedicado con permisos de monitoreo.
- El dashboard es intencionalmente pequeno para evidenciar alta disponibilidad sin mezclar resultados de load testing.
- Si Patroni REST no expone `/metrics` en la imagen usada, el target `patroni-rest` aparecera down, pero los paneles principales siguen usando `postgres_exporter`, HAProxy y etcd.
