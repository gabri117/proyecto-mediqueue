# Integracion con backups

## Estado actual

La implementacion de backups en `infra/backups/` se conserva sin cambios en esta fase. El PostgreSQL principal actual sigue siendo el origen de datos activo.

El stack Patroni se crea en paralelo, por lo que no se debe asumir que los backups actuales cubren Patroni hasta completar una fase de activacion.

## Cuando Patroni sea activado

Los backups deben apuntar al endpoint writer:

```text
host: patroni-postgres-lb
port: 5432
```

O desde el host:

```text
127.0.0.1:55432
```

Para `pg_basebackup`, se debe conectar contra el lider o contra el endpoint writer. Para `pg_dump`, tambien conviene usar writer mientras no exista una politica clara de backups desde replicas.

## WAL archive

Los nodos Patroni montan `./infra/backups/wal-archive` en:

```text
/var/lib/postgresql/wal-archive
```

Esto mantiene una ruta local coherente con el esquema actual, pero antes de produccion hay que revisar:

- Retencion de WAL.
- Colisiones entre clusters.
- Permisos de escritura.
- Restauracion a punto en el tiempo.
- Separacion entre backups del PostgreSQL actual y del cluster Patroni.

## Pendientes antes de migrar microservicios

- Crear o migrar la base `mediqueue` en Patroni.
- Restaurar datos desde backup validado.
- Ejecutar migraciones Flyway contra Patroni.
- Probar restore en ambiente aislado.
- Actualizar variables `DB_HOST` y `DB_PORT` solo despues de validar.
- Monitorear lag de replicas y failover durante pruebas funcionales.
