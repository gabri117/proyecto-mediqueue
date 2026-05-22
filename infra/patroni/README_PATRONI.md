# MediQueue PostgreSQL HA local con Patroni

Esta carpeta prepara una arquitectura paralela de PostgreSQL HA para desarrollo local. No reemplaza el servicio `postgres` actual y no conecta los microservicios a Patroni en esta fase.

## Servicios

- `etcd-1`, `etcd-2`, `etcd-3`: DCS para Patroni.
- `patroni-postgres-1`, `patroni-postgres-2`, `patroni-postgres-3`: nodos PostgreSQL administrados por Patroni.
- `patroni-postgres-lb`: HAProxy para entrada unica.

## etcd dentro de Patroni

Patroni usa etcd como Distributed Configuration Store. En ese almacenamiento guarda el estado del cluster, el lock del lider, la configuracion compartida y la informacion necesaria para decidir si un nodo puede promocionarse.

Se usan 3 nodos etcd para tener quorum. Con 3 nodos, el cluster puede tolerar la caida de 1 nodo y seguir tomando decisiones. Con 1 solo nodo no hay alta disponibilidad real del DCS, y sin DCS sano Patroni no debe promocionar lideres de forma segura.

Los puertos client de etcd se publican solo en `127.0.0.1` para desarrollo local:

- `etcd-1`: `127.0.0.1:23791`
- `etcd-2`: `127.0.0.1:23792`
- `etcd-3`: `127.0.0.1:23793`

Dentro de Docker, Patroni usa:

```text
etcd-1:2379,etcd-2:2379,etcd-3:2379
```

## Puertos locales

- Writer: `127.0.0.1:55432`, enruta siempre al lider.
- Reader: `127.0.0.1:55433`, enruta a replicas.
- HAProxy stats: `http://127.0.0.1:7000/`
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

Para levantar solo etcd y los nodos PostgreSQL administrados por Patroni, sin HAProxy ni microservicios:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml up -d etcd-1 etcd-2 etcd-3 patroni-postgres-1 patroni-postgres-2 patroni-postgres-3
```

## Levantar solo etcd

Para validar unicamente el DCS, sin levantar PostgreSQL Patroni:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml up -d etcd-1 etcd-2 etcd-3
```

Esto no modifica ni detiene el PostgreSQL principal.

## Validar configuracion sin levantar

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml config --quiet
```

## Validar etcd

Healthcheck completo:

```powershell
.\infra\patroni\scripts\etcd-healthcheck.ps1
```

Comando manual de endpoint health:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T etcd-1 etcdctl --endpoints=http://etcd-1:2379,http://etcd-2:2379,http://etcd-3:2379 endpoint health
```

Listar miembros:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml exec -T etcd-1 etcdctl --endpoints=http://etcd-1:2379,http://etcd-2:2379,http://etcd-3:2379 member list
```

## Estado y salud

```powershell
.\infra\patroni\scripts\patroni-status.ps1
.\infra\patroni\scripts\patroni-healthcheck.ps1
```

`patroni-status.ps1` muestra el lider actual, las replicas y el estado REST de cada nodo.

## Observabilidad

Prometheus y Grafana pueden monitorear Patroni, PostgreSQL HA, HAProxy y etcd con el dashboard:

```text
MediQueue Patroni Cluster Status
```

Levantar exporters junto al stack:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml up -d prometheus grafana patroni-postgres-lb patroni-postgres-exporter-1 patroni-postgres-exporter-2 patroni-postgres-exporter-3
```

Abrir targets:

```text
http://localhost:9090/targets
```

Detalle de metricas, queries y paneles:

```text
infra/patroni/docs/OBSERVABILITY.md
```

## Conectarse al lider

Cuando HAProxy este levantado, usar el writer. Todas las escrituras de aplicaciones deben ir por este puerto, porque HAProxy lo enruta al nodo lider actual:

```powershell
psql -h 127.0.0.1 -p 55432 -U postgres -d mediqueue
```

Con el usuario de aplicacion:

```powershell
psql -h 127.0.0.1 -p 55432 -U mediqueue -d mediqueue
```

Para lecturas de prueba contra replicas:

```powershell
psql -h 127.0.0.1 -p 55433 -U mediqueue -d mediqueue
```

## DBeaver

Conexion de escritura:

```text
Driver: PostgreSQL
Host: localhost
Port: 55432
Database: mediqueue
User: mediqueue
Password: mediqueue
```

Conexion de lectura opcional:

```text
Driver: PostgreSQL
Host: localhost
Port: 55433
Database: mediqueue
User: mediqueue
Password: mediqueue
```

Stats de HAProxy:

```text
http://localhost:7000/
```

Sin HAProxy, usar el script SQL check para detectar el lider por REST y ejecutar la consulta dentro del contenedor correcto:

```powershell
.\infra\patroni\scripts\patroni-sql-check.ps1
```

Para crear una tabla tecnica de salud en un schema no relacionado con negocio:

```powershell
.\infra\patroni\scripts\patroni-sql-check.ps1 -CreateHealthTable
```

## Validar HAProxy

Levantar HAProxy sobre el cluster Patroni:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml up -d patroni-postgres-lb
```

Validar puertos writer, reader y stats:

```powershell
.\infra\patroni\scripts\haproxy-db-healthcheck.ps1
```

Validar que writer apunta al primario y reader a replica:

```powershell
.\infra\patroni\scripts\patroni-db-connection-test.ps1
```

## Microservicios usando Patroni

El modo Patroni para aplicaciones se activa con un overlay separado:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml -f docker-compose.patroni-apps.yml up -d
```

En este modo, los microservicios usan:

```text
jdbc:postgresql://patroni-postgres-lb:5432/mediqueue
```

Cada servicio mantiene su schema:

```text
patient-service       -> schema patient
schedule-service      -> schema schedule
appointment-service   -> schema appointment
payment-service       -> schema payment
notification-service  -> schema notification
```

Actualmente MediQueue usa una base compartida `mediqueue` con schemas separados por microservicio. A futuro podria evaluarse una base separada por servicio, pero no se cambia en esta fase para no romper migraciones ni contratos existentes.

Antes de levantar apps contra Patroni, preparar schemas tecnicos para Flyway:

```powershell
.\infra\patroni\scripts\prepare-patroni-app-schemas.ps1
```

Este script crea los schemas de cada microservicio, habilita `uuid-ossp` en `public` para las migraciones que usan `public.uuid_generate_v4()` y elimina solamente tablas `flyway_schema_history` vacias que hayan quedado por un arranque fallido previo contra Patroni.

Validar que el overlay Patroni no apunte al PostgreSQL simple:

```powershell
.\infra\patroni\scripts\app-db-routing-check.ps1
```

Smoke test sin carga:

```powershell
.\infra\patroni\scripts\app-smoke-test-patroni.ps1
```

Preparar datos E2E rapidamente en Patroni por SQL, usando el writer `patroni-postgres-lb`:

```powershell
.\infra\load-tests\appointments\tools\prepare-appointment-load-data.ps1 `
  -BaseUrl http://localhost:8080 `
  -TotalPatients 100 `
  -TotalDentists 20 `
  -TotalSlots 50000 `
  -Amount 1500.00 `
  -Mode sql `
  -DatabaseTarget patroni
```

Este modo valida que el writer no este en recovery, revisa que existan las tablas de los schemas de aplicacion y solo inserta datos base en `patient.patients`, `schedule.dentists` y `schedule.dentist_slots`. Las citas reales siguen entrando por `POST /api/appointments` durante k6.

Validar el dataset generado contra Patroni:

```powershell
.\infra\load-tests\appointments\tools\validate-appointment-dataset.ps1 `
  -DataFile .\infra\load-tests\appointments\data\appointments-50000.json `
  -ExpectedCount 50000 `
  -Limit 20 `
  -DatabaseTarget patroni
```

Si hubo un arranque fallido previo por migraciones o configuracion, recrear solo contenedores de aplicacion:

```powershell
.\infra\patroni\scripts\app-smoke-test-patroni.ps1 -ForceRecreate
```

### Volver a modo PostgreSQL simple

Usar solo el compose principal:

```powershell
docker compose -f docker-compose.yml up -d
```

Si habia contenedores de apps creados con el overlay Patroni, recrearlos con el compose simple:

```powershell
docker compose -f docker-compose.yml up -d --force-recreate patient-service schedule-service appointment-service payment-service notification-service api-gateway
```

No es necesario borrar volumenes para alternar el routing.

### Validar con DBeaver

Modo Patroni writer:

```text
Host: localhost
Port: 55432
Database: mediqueue
User: mediqueue
Password: mediqueue
```

Modo PostgreSQL simple actual:

```text
Host: localhost
Port: 55461
Database: mediqueue
User: mediqueue
Password: mediqueue
```

### Validar con Postman

Con Patroni apps levantado:

```text
GET http://localhost:8080/actuator/health
GET http://localhost:8080/api/patients
GET http://localhost:8080/api/schedules
```

No ejecutar pruebas de carga para esta validacion; solo smoke tests.

## Validar replicacion

Ver lider y replicas:

```powershell
.\infra\patroni\scripts\patroni-status.ps1
```

El estado esperado es 1 nodo con rol `primary` o `master`, y 2 nodos con rol `replica`.

## Migrar datos desde PostgreSQL simple

El procedimiento seguro esta documentado en:

```text
infra/patroni/docs/MIGRATION_RUNBOOK.md
```

Plan sin restaurar:

```powershell
.\infra\patroni\scripts\migrate-single-postgres-to-patroni.ps1 -PlanOnly -UseLatestDump
```

Restaurar en Patroni requiere `-Execute`. Si se recrea la base destino, tambien requiere `-ConfirmRecreateDestination`.

Ver logs:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml logs -f patroni-postgres-1 patroni-postgres-2 patroni-postgres-3
```

## Replicacion asincrona vs sincrona

Este stack local usa replicacion asincrona inicialmente. Es mejor para rendimiento y menor latencia, que es lo mas conveniente para pruebas locales y cargas altas.

Tradeoff:

- Asincrona: mejor rendimiento, pero puede perderse una pequena cantidad de transacciones si el primario cae antes de que una replica reciba todos los WAL.
- Sincrona: reduce o evita perdida de datos confirmados, pero agrega latencia porque el primario espera confirmacion de replica.

La replicacion sincrona queda como opcion futura para ambientes donde el RPO sea mas estricto que la latencia.

## Switchover controlado

Dry run:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1
```

Ejecutar:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1 -Candidate patroni-postgres-2 -Execute
```

## Failover test

Dry run:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1
```

Ejecutar prueba simulando caida real del primario con `docker compose kill`:

```powershell
.\infra\patroni\scripts\patroni-failover-test.ps1 -Execute
```

La prueba espera la promocion de una replica, reintenta el writer de HAProxy hasta que `pg_is_in_recovery=false`, inserta una fila en `health_check.ha_write_probe` y espera que el nodo caido vuelva como replica.

`docker compose stop` representa una parada manual y no dispara la politica `restart`. Para simular crash se usa `docker compose kill`. Si el proceso no vuelve solo, el script ejecuta `docker compose up -d <oldLeader>` para recuperar el nodo.

El lider anterior no debe recuperar liderazgo automaticamente. Si se quiere devolver liderazgo al nodo original, hacerlo despues con un switchover controlado:

```powershell
.\infra\patroni\scripts\patroni-switchover.ps1 -Candidate patroni-postgres-2 -Execute
```

Validar recuperacion completa:

```powershell
.\infra\patroni\scripts\patroni-cluster-recovery-check.ps1
```

## Limpieza

Para limpiar datos de pruebas E2E en Patroni sin borrar schemas, Flyway, extensiones, usuarios ni configuracion del cluster, usar primero dry-run:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-runtime-data.ps1 `
  -DatabaseTarget patroni
```

El dry-run valida que `patroni-postgres-lb` apunte a un writer con `pg_is_in_recovery=false`, muestra conteos actuales y enseña el `TRUNCATE ... CASCADE` que se ejecutaria.

Ejecutar limpieza real solo con confirmacion explicita:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-runtime-data.ps1 `
  -DatabaseTarget patroni `
  -ConfirmClean
```

Para dejar tambien RabbitMQ sin mensajes acumulados de pruebas:

```powershell
.\infra\load-tests\appointments\tools\clean-appointment-runtime-data.ps1 `
  -DatabaseTarget patroni `
  -PurgeRabbitMqQueues `
  -ConfirmClean
```

Esta limpieza elimina datos runtime/base de prueba en `notification`, `payment`, `appointment`, `schedule` y `patient`, pero no elimina estructura, historiales Flyway, schemas, usuarios, extensiones, volumenes ni configuracion Patroni. Usarla solo entre corridas E2E controladas.

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

## Perfil Patroni E2E para pruebas

Para pruebas E2E de appointments con Patroni usar el overlay dedicado:

```powershell
docker compose -f docker-compose.yml -f docker-compose.patroni.yml -f docker-compose.patroni-apps.yml -f docker-compose.patroni-e2e.yml up -d --build `
  --scale api-gateway=2 `
  --scale appointment-service=3 `
  --scale patient-service=2 `
  --scale schedule-service=2 `
  --scale payment-service=3 `
  --scale notification-service=2
```

Este perfil no cambia reglas de negocio. Ajusta presupuesto de recursos:

- `appointment-service`: pool Hikari 40 por replica y limite local `APPOINTMENT_CREATE_MAX_CONCURRENT=48`.
- `appointment-service`: precarga pacientes activos y slots disponibles una vez por replica para evitar una consulta PostgreSQL/Redis por cada cita durante pruebas preparadas.
- `appointment-service`: outbox activo, pero con batch/intervalo moderado; confirmaciones de pago limitadas a 1 consumidor por replica.
- `payment-service`: 3 replicas con pool 12 y consumidores RabbitMQ `4-8`, para no inundar appointment-service con confirmaciones durante el minuto de prueba.
- `api-gateway`: rate limit opcionalmente deshabilitado para que la prueba mida backend, no Redis.

Con 3 appointment-service, 3 payment-service y 2 replicas del resto, el consumo esperado queda alrededor de 200-220 conexiones, dejando margen frente a `max_connections=300`.
