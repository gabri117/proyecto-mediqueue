# Runbook de alta disponibilidad Patroni

Este documento describe pruebas controladas para demostrar alta disponibilidad de PostgreSQL con Patroni, etcd y HAProxy en MediQueue.

Las pruebas no deben tocar tablas de negocio. La prueba de escritura usa solamente:

```text
health_check.ha_write_probe
```

No ejecutar `docker compose down -v` durante estas pruebas.

## Conceptos

### Switchover

Un switchover es un cambio planificado de lider. Se usa cuando el cluster esta sano y se quiere mover el rol primario a una replica conocida, por ejemplo antes de mantenimiento.

Caracteristicas:

- Es controlado.
- Requiere lider actual y replicas sanas.
- Debe tener menor riesgo que cortar el lider a la fuerza.
- Se ejecuta solo con confirmacion explicita.

### Failover

Un failover ocurre cuando el lider cae o deja de estar disponible. Patroni usa etcd para coordinar la eleccion y promover una replica.

Caracteristicas:

- Simula una falla real.
- Puede cortar conexiones activas.
- Requiere verificar que HAProxy redirige al nuevo lider.
- El nodo caido debe volver como replica o requerir reinit.

## Evidencia a capturar

Antes, durante y despues de cada prueba guardar:

- Salida de `patroni-status.ps1`.
- Salida de `patroni-healthcheck.ps1`.
- Lider anterior y nuevo lider.
- Salida de `patroni-db-connection-test.ps1`.
- Resultado de escritura en `health_check.ha_write_probe`.
- Captura de HAProxy stats: `http://127.0.0.1:7000/`.
- Logs relevantes:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml logs --tail=100 patroni-postgres-1 patroni-postgres-2 patroni-postgres-3 patroni-postgres-lb
```

## 1. Ver estado actual

```powershell
.\infra\patroni\scripts\patroni-status.ps1
```

Esperado:

```text
PATRONI_LEADER=<un nodo>
PATRONI_REPLICAS=2
PATRONI_MEMBER ... lag=<valor o unknown>
WRITER_ENDPOINT=127.0.0.1:55432
```

Health general:

```powershell
.\infra\patroni\scripts\patroni-healthcheck.ps1
```

Esperado:

```text
ETCD_HEALTH_OK=True
PATRONI_HAS_PRIMARY=True
PATRONI_REPLICA_COUNT=2
PATRONI_WRITER_OK=True
PATRONICTL_LIST_OK=True
PATRONI_HEALTH_STATUS=OK
```

Validar HAProxy DB-LB:

```powershell
.\infra\patroni\scripts\patroni-db-connection-test.ps1
```

Esperado:

```text
WRITER_PG_IS_IN_RECOVERY=f
READER_PG_IS_IN_RECOVERY=t
PATRONI_DB_CONNECTION_STATUS=OK
```

## 2. Switchover controlado

Primero ejecutar plan:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1
```

Plan con candidato:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1 -Candidate patroni-postgres-2
```

Ejecutar solo con `-Execute`:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1 -Candidate patroni-postgres-2 -Execute
```

Despues del switchover:

```powershell
.\infra\patroni\scripts\patroni-status.ps1
.\infra\patroni\scripts\patroni-healthcheck.ps1
.\infra\patroni\scripts\patroni-db-connection-test.ps1
```

Esperado:

```text
SWITCHOVER_NEW_LEADER=<candidato o replica promovida>
PATRONI_DB_CONNECTION_STATUS=OK
SWITCHOVER_STATUS=OK
```

## 3. Simular caida del lider

Primero plan:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1
```

Ejecutar prueba real:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1 -Execute
```

El script:

- Detecta el lider actual.
- Detiene temporalmente el contenedor lider.
- Espera promocion automatica de una replica.
- Valida que HAProxy writer responde contra el nuevo lider.
- Hace un `INSERT` en `health_check.ha_write_probe`.
- Reinicia el lider detenido.
- Verifica que el nodo detenido vuelve como replica.

Salida esperada:

```text
FAILOVER_TEST_CURRENT_LEADER=<lider anterior>
FAILOVER_TEST_NEW_LEADER=<nuevo lider>
PATRONI_DB_CONNECTION_STATUS=OK
FAILOVER_TEST_WRITE_PROBE_OK probe_id=<uuid>
FAILOVER_TEST_OLD_LEADER_RETURNED_AS_REPLICA ...
FAILOVER_TEST_STATUS=OK
```

Si se quiere dejar el lider detenido para inspeccion manual:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1 -Execute -SkipRestartStoppedLeader
```

Luego reiniciarlo manualmente:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml start patroni-postgres-1
docker compose -f docker-compose.yml -f docker-compose.patroni.yml start patroni-postgres-2
docker compose -f docker-compose.yml -f docker-compose.patroni.yml start patroni-postgres-3
```

## 4. Confirmar writer de HAProxy

Despues de switchover o failover:

```powershell
.\infra\patroni\scripts\patroni-db-connection-test.ps1
```

El writer debe responder:

```text
WRITER_PG_IS_IN_RECOVERY=f
```

Esto prueba que `patroni-postgres-lb:5432` apunta al lider nuevo.

## 5. Reinit de replica

Usar solo si una replica queda rota, atrasada o no vuelve correctamente.

Plan:

```powershell
.\infra\patroni\scripts\patroni-reinit-replica.ps1 -ReplicaName patroni-postgres-3
```

Ejecutar:

```powershell
.\infra\patroni\scripts\patroni-reinit-replica.ps1 -ReplicaName patroni-postgres-3 -Execute
```

El script se niega a reinitializar el lider actual.

## 6. Rollback operativo

Si una prueba deja el cluster en estado no saludable:

1. Ver estado:

```powershell
.\infra\patroni\scripts\patroni-status.ps1
```

2. Reiniciar cualquier nodo detenido:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml start patroni-postgres-1 patroni-postgres-2 patroni-postgres-3
```

3. Esperar salud:

```powershell
.\infra\patroni\scripts\patroni-healthcheck.ps1
```

4. Si una replica no vuelve, usar reinit con `-Execute`.

5. Para las aplicaciones, se puede volver al PostgreSQL simple:

```powershell
docker compose -f docker-compose.yml up -d --force-recreate patient-service schedule-service appointment-service payment-service notification-service api-gateway
```

## Riesgos

- Failover corta conexiones activas al lider detenido.
- En replicacion asincrona puede existir una pequena ventana de perdida si el lider cae antes de replicar WAL.
- `reinit` reconstruye datos locales de una replica; no debe aplicarse sobre el lider.
- No hacer estas pruebas durante load testing si el objetivo es medir rendimiento puro.
- No borrar volumenes ni ejecutar `down -v`.
