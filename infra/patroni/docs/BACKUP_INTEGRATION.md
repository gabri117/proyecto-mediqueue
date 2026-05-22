# Integracion Patroni con backups

La implementacion de backups en `infra/backups/` soporta dos modos:

```powershell
$BackupMode = "single"
$BackupMode = "patroni"
```

El modo por defecto sigue siendo `single`, por lo que el PostgreSQL actual no se rompe.

## Modo single

Usa el PostgreSQL simple actual:

```text
postgres -> mediqueue-postgres
postgres-lb -> 127.0.0.1:55461
```

Scripts principales:

```powershell
.\infra\backups\scripts\backup-base.ps1
.\infra\backups\scripts\backup-pgdump.ps1
.\infra\backups\scripts\verify-backups.ps1
.\infra\backups\scripts\run-daily-backup-pipeline.ps1
```

## Modo patroni

Usa el writer de HAProxy:

```text
patroni-postgres-lb:5432
localhost:55432
```

`backup-pgdump.ps1` valida antes de generar el dump:

```sql
SELECT pg_is_in_recovery();
```

Si el writer devuelve `true`, el script falla porque no debe hacer dump desde una replica cuando se espera el primario.

`backup-base.ps1` detecta nodos con Patroni REST API y prefiere una replica sana para reducir carga sobre el lider. Si no hay replica sana, puede usar el lider en ambiente local y deja advertencia en log.

## Configuracion local

Archivo local:

```text
infra/backups/config/backup.local.ps1
```

Ejemplo:

```powershell
$BackupMode = "patroni"
$PatroniWriterHost = "localhost"
$PatroniWriterPort = 55432
$PatroniDockerServicePrefix = "patroni-postgres"
$PatroniScope = "mediqueue-postgres-ha"
$PatroniBackupNode = ""
```

Si `$PatroniBackupNode` queda vacio, el backup base prefiere una replica sana.

## WAL archive

Los nodos Patroni montan:

```text
./infra/backups/wal-archive -> /var/lib/postgresql/wal-archive
```

El WAL de Patroni se separa en:

```text
infra/backups/wal-archive/patroni
```

Esto evita mezclar WAL del PostgreSQL simple con WAL del cluster Patroni durante verificaciones.

## Recomendacion

- `pg_dump`: usar writer de HAProxy.
- Backup fisico/base: preferir replica sana.
- PITR: requiere WAL consistente del cluster y pruebas de restore.
- No mezclar backups `single` y `patroni` para una restauracion PITR.

## Riesgos pendientes

- Las credenciales actuales son de desarrollo local.
- En produccion se necesita usuario dedicado para backups, cifrado y gestion de secretos.
- El archivado WAL debe validarse con restore PITR real antes de considerarlo completo.
- La retencion debe dimensionarse para el volumen de escritura real.
