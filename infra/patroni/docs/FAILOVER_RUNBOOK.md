# Runbook de failover Patroni

## Validar estado

```powershell
.\infra\patroni\scripts\patroni-status.ps1
.\infra\patroni\scripts\patroni-healthcheck.ps1
```

Estado esperado:

```text
PATRONI_HAS_PRIMARY=True
PATRONI_WRITER_TCP_OK=True
PATRONI_HEALTH_STATUS=OK
```

## Switchover controlado

Usar switchover cuando el cluster esta sano y se quiere mover el lider sin simular una caida.

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1 -Candidate patroni-postgres-2 -ConfirmSwitchover
```

Despues:

```powershell
.\infra\patroni\scripts\patroni-healthcheck.ps1
```

## Failover de prueba

Primero dry run:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1
```

Ejecutar prueba:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1 -Execute -RestartStoppedPrimary
```

El script detiene temporalmente el primario detectado, espera promocion y puede reiniciar el nodo detenido si se pasa `-RestartStoppedPrimary`.

## Reinit de replica

Usar solo si una replica quedo inconsistente y se acepta reconstruir sus datos locales desde el lider.

Dry run:

```powershell
.\infra\patroni\scripts\patroni-reinit-replica.ps1 -ReplicaName patroni-postgres-3
```

Ejecutar:

```powershell
.\infra\patroni\scripts\patroni-reinit-replica.ps1 -ReplicaName patroni-postgres-3 -ConfirmReinit
```

## Reglas de seguridad operativa

- No ejecutar `docker compose down -v` sobre el proyecto completo.
- No borrar `postgres-data`.
- No activar microservicios contra Patroni sin migracion y prueba de restore.
- No probar failover durante cargas criticas si el objetivo es medir rendimiento.
- Revisar logs de Patroni, HAProxy y PostgreSQL antes de repetir una prueba.
