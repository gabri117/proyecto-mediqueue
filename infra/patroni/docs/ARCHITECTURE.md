# Arquitectura Patroni

## Diagrama textual

```text
Aplicaciones en modo Patroni
       |
       | escritura: 127.0.0.1:55432 / patroni-postgres-lb:5432
       v
patroni-postgres-lb (HAProxy)
       | usa HTTP checks contra Patroni REST
       | GET /primary para writer
       | GET /replica para reader
       |
       +--------------------+--------------------+
       |                    |                    |
       v                    v                    v
patroni-postgres-1    patroni-postgres-2    patroni-postgres-3
PostgreSQL + Patroni  PostgreSQL + Patroni  PostgreSQL + Patroni
REST :8008            REST :8008            REST :8008
       |                    |                    |
       +--------------------+--------------------+
                            |
                            v
              etcd-1 + etcd-2 + etcd-3
              DCS / consenso / leader lock
```

## Modo actual

El servicio `postgres` actual sigue siendo la base activa del proyecto. Los microservicios de MediQueue siguen apuntando a:

```text
DB_HOST=postgres-lb
DB_PORT=5432
```

El stack Patroni queda en paralelo al PostgreSQL simple. La activacion de microservicios se controla con `docker-compose.patroni-apps.yml`, que apunta los datasource hacia `patroni-postgres-lb` sin tocar codigo de negocio.

## Componentes

- etcd: almacena el estado compartido de Patroni y decide quien puede ser lider.
- Patroni: administra PostgreSQL, promocion de replicas y failover.
- PostgreSQL: tres nodos con replicacion streaming.
- HAProxy: punto unico de conexion. Usa la API REST de Patroni para enrutar escritura al primario y lecturas a replicas.

## Puertos

- Writer local: `55432 -> patroni-postgres-lb:5432`.
- Reader local: `55433 -> patroni-postgres-lb:5433`.
- HAProxy stats: `7000 -> patroni-postgres-lb:7000`.
- Patroni REST local: `18008`, `18009`, `18010`.
- etcd client local: `23791`, `23792`, `23793`.

## Seguridad

Los usuarios y passwords de ejemplo son solo para desarrollo local. En produccion se requiere:

- Secret manager o variables inyectadas por CI/CD.
- TLS entre clientes, HAProxy, Patroni y etcd.
- Restriccion de redes.
- Passwords unicas y rotadas.
- Backups probados con restore.
- Monitoreo y alertas de lag, leader changes y quorum etcd.
