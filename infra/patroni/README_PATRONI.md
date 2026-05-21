# MediQueue PostgreSQL HA local con Patroni

Esta carpeta prepara una arquitectura paralela de PostgreSQL HA para desarrollo local. No reemplaza el servicio `postgres` actual y no conecta los microservicios a Patroni en esta fase.

## Servicios

- `etcd-1`, `etcd-2`, `etcd-3`: DCS para Patroni.
- `patroni-postgres-1`, `patroni-postgres-2`, `patroni-postgres-3`: nodos PostgreSQL administrados por Patroni.
- `patroni-postgres-lb`: HAProxy para entrada unica.

## Puertos locales

- Writer: `127.0.0.1:55432`, enruta siempre al lider.
- Reader: `127.0.0.1:55433`, enruta a replicas.
- HAProxy stats: `http://127.0.0.1:57000/`
- Patroni REST:
  - nodo 1: `http://127.0.0.1:18008/`
  - nodo 2: `http://127.0.0.1:18009/`
  - nodo 3: `http://127.0.0.1:18010/`

## Variables de ejemplo

Copiar `infra/patroni/.env.patroni.example` si se quieren exportar valores manualmente. Las passwords incluidas son solo para desarrollo local.

```powershell
$env:POSTGRES_APP_USER="mediqueue"
$env:POSTGRES_APP_PASSWORD="mediqueue"
$env:POSTGRES_APP_DB="mediqueue"
$env:PATRONI_SUPERUSER_USERNAME="postgres"
$env:PATRONI_SUPERUSER_PASSWORD="postgres"
$env:PATRONI_REPLICATION_USERNAME="replicator"
$env:PATRONI_REPLICATION_PASSWORD="replicator"
```

No usar estas passwords en produccion.

## Levantar el stack

Desde la raiz del proyecto:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml up -d
```

Esto levanta el stack Patroni junto al compose actual. En esta fase, los microservicios siguen usando `postgres-lb` del PostgreSQL actual porque sus variables continuan apuntando a `DB_HOST=postgres-lb` y `DB_PORT=5432`.

## Validar configuracion sin levantar

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml config --quiet
```

## Estado y salud

```powershell
.\infra\patroni\scripts\patroni-status.ps1
.\infra\patroni\scripts\patroni-healthcheck.ps1
```

## Switchover controlado

Dry run:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1
```

Ejecutar:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1 -Candidate patroni-postgres-2 -ConfirmSwitchover
```

## Failover test

Dry run:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1
```

Ejecutar prueba deteniendo temporalmente el primario:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1 -Execute -RestartStoppedPrimary
```

## Limpieza

Dry run:

```powershell
.\infra\patroni\scripts\patroni-clean-test-data.ps1
```

Eliminar contenedores del stack Patroni:

```powershell
.\infra\patroni\scripts\patroni-clean-test-data.ps1 -ConfirmDelete
```

Eliminar tambien volumenes de prueba Patroni:

```powershell
.\infra\patroni\scripts\patroni-clean-test-data.ps1 -ConfirmDelete -IncludeVolumes
```

La limpieza no debe usarse sobre datos importantes y no toca el volumen `postgres-data` del PostgreSQL principal.
