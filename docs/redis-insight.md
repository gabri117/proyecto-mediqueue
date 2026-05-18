# RedisInsight para MediQueue

RedisInsight permite explorar graficamente keys, valores, TTL, tipos de dato y contenido del cache de Redis.

## Levantar RedisInsight

```powershell
docker compose up -d redis-insight
```

Abrir:

```text
http://localhost:5540
```

## Conexion a Redis

En RedisInsight agrega una conexion manual:

```text
Name: MediQueue Redis
Host: redis
Port: 6379
Username: default
Password: redis123
TLS: off
```

`Host: redis` funciona porque RedisInsight esta dentro de la misma red Docker Compose `mediqueue-net`.

## Patrones utiles

Busca estos patrones en el explorador de keys:

```text
patients::*
slots::*
*request*
*rate*
*k6*
```

Contexto:

- API Gateway usa Redis para rate limiting.
- appointment-service usa Spring Cache para validaciones de pacientes y slots.
- Las keys `patients::*` y `slots::*` pueden expirar rapido por TTL.

## Comandos complementarios

```powershell
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli --scan
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli INFO keyspace
docker compose exec -e REDISCLI_AUTH=redis123 redis redis-cli MONITOR
```

Usa `MONITOR` solo por unos segundos porque genera mucho ruido.

## Evidencias sugeridas

- Captura de RedisInsight conectado como `MediQueue Redis`.
- Captura de keys `patients::*` y `slots::*` despues de crear citas.
- Captura de TTL de una key de cache.
- Captura de `INFO keyspace` o DBSIZE.
- Captura de keys del rate limiter durante una prueba de carga.
