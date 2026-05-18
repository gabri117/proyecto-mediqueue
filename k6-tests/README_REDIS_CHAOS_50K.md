# MediQueue Redis Chaos 50k

## Objetivo

Validar que el API Gateway mantiene el servicio durante una caida temporal de Redis bajo una carga aproximada de 50,000 peticiones. Redis se usa para rate limiting; cuando Redis cae, el gateway debe operar en modo fail-open y no debe responder 503 por esa dependencia.

## Endpoint de prueba

La prueba usa:

```text
GET /api/patients/00000000-0000-0000-0000-000000000000
```

Ese paciente no existe, por eso una respuesta 404 o 400 es correcta: confirma que la peticion atraveso el gateway y llego al flujo de negocio. Un 503 es incorrecto para esta prueba porque indicaria que el gateway o el upstream no pudo manejar la peticion; si ocurre durante la caida de Redis, rompe la expectativa del fail-open.

Cada VU envia este header para tener su propio bucket:

```text
X-Client-Id: k6-vu-<id>
```

## Preparar infraestructura

```powershell
docker compose up -d --build
docker compose ps
docker compose exec redis redis-cli -a redis123 PING
curl.exe -i http://localhost:8080/actuator/health
curl.exe -i http://localhost:8080/api/patients/00000000-0000-0000-0000-000000000000 -H "X-Client-Id: manual-check"
```

Revisa los targets en:

```text
http://localhost:9090/targets
```

Deben aparecer UP al menos `api-gateway` y `redis-exporter`.

## Ejecutar solo con Redis encendido

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
k6 run -o experimental-prometheus-rw .\k6-tests\gateway-redis-chaos-50k.js --summary-export .\k6-tests\gateway-redis-chaos-50k-summary.json
```

Valores por defecto:

```text
RATE=167 req/s
DURATION=5m
PRE_ALLOCATED_VUS=200
MAX_VUS=500
BASE_URL=http://localhost:8080
FAKE_PATIENT_ID=00000000-0000-0000-0000-000000000000
```

Con esos valores se generan cerca de 50,100 peticiones.

## Ejecutar con caos Redis

Terminal 1:

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
k6 run -o experimental-prometheus-rw .\k6-tests\gateway-redis-chaos-50k.js --summary-export .\k6-tests\gateway-redis-chaos-50k-summary.json
```

Terminal 2, inmediatamente despues de arrancar k6:

```powershell
.\k6-tests\redis-chaos-control.ps1
```

El script de caos:

- Enciende Redis y valida `PING`.
- Espera 90 segundos.
- Apaga Redis durante 120 segundos.
- Enciende Redis de nuevo y valida `PING PONG`.

Puedes ajustar tiempos:

```powershell
.\k6-tests\redis-chaos-control.ps1 -RedisOffAfterSeconds 60 -RedisDownSeconds 90
```

## Metricas k6 en Prometheus

Prometheus esta configurado para recibir remote write con:

```text
--web.enable-remote-write-receiver
```

k6 envia metricas con:

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
k6 run -o experimental-prometheus-rw .\k6-tests\gateway-redis-chaos-50k.js
```

Usa `K6_PROMETHEUS_RW_TREND_STATS` para que k6 envie percentiles como series normales. Esto evita errores 500 en Prometheus cuando no esta habilitada la ingesta de native histograms. El dashboard usa esta query para p95:

```promql
max(k6_http_req_duration_p95) or vector(0)
```

No uses esta variable salvo que Prometheus haya sido arrancado con soporte de native histograms:

```powershell
$env:K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM="true"
```

Sin ese soporte, Prometheus responde 500 a `/api/v1/write` con el error `native histograms are disabled`.

Metricas clave:

- `k6_gateway_503_total`
- `k6_redis_error_body_total`
- `k6_fail_open_responses_total`
- `k6_normal_rate_limit_responses_total`
- `k6_business_responses_total`

Consultas rapidas en Prometheus:

```promql
redis_up
max(redis_memory_used_bytes) or vector(0)
sum(rate(redis_commands_processed_total[1m])) or vector(0)
k6_gateway_503_total
k6_fail_open_responses_total
k6_redis_error_body_total
```

## Dashboard Grafana

El dashboard esta en:

```text
infra/grafana/dashboards/mediqueue-gateway-redis-chaos-50k.json
```

Grafana ya provisiona los dashboards desde `/var/lib/grafana/dashboards`, montado desde `infra/grafana/dashboards`. Si Grafana ya esta corriendo, espera unos segundos o reinicia el contenedor:

```powershell
docker compose restart grafana
```

Tambien puedes importarlo manualmente en Grafana usando el JSON y seleccionando el datasource `Prometheus`.

Para presentar la corrida, selecciona `Last 15 minutes` o el rango exacto de la prueba. Los totales stat de k6 usan `increase(...[$__range])`, asi que el rango de tiempo define que corrida estas mostrando.

El dashboard usa `job="api-gateway-lb"` para los paneles del Gateway. No se suman `api-gateway` y `api-gateway-lb` porque ambos representan el mismo request visto en dos puntos de scrape; sumarlos duplicaria el RPS. Si k6 genera cerca de 167 req/s, el panel Gateway RPS debe acercarse a ese valor, no a 334 req/s.

Redis Memory usa:

```promql
max(redis_memory_used_bytes) or vector(0)
```

Esto muestra un solo valor global y evita que `or vector(0)` agregue una segunda serie `0 B` cuando Redis ya esta reportando memoria real.

Los contadores stat de k6 usan `increase(...[$__range])`, por ejemplo:

```promql
sum(increase(k6_fail_open_responses_total[$__range])) or vector(0)
sum(increase(k6_gateway_503_total[$__range])) or vector(0)
sum(increase(k6_redis_error_body_total[$__range])) or vector(0)
```

Asi el dashboard muestra el total de la corrida dentro del rango seleccionado, sin arrastrar valores acumulados de pruebas anteriores.

## Resultados esperados

En k6:

- Aproximadamente 50,000 requests.
- `gateway_503 = 0`.
- `redis_error_body = 0`.
- `fail_open_responses > 0`.
- `normal_rate_limit_responses > 0`.
- `checks > 95%`.

En Grafana:

- `redis_up` debe verse como `1 -> 0 -> 1`.
- `fail_open_responses > 0` confirma que el fail-open se activo mientras Redis estuvo apagado.
- `normal_rate_limit_responses > 0` confirma que el rate limit normal funciono con Redis encendido.
- `gateway_503 = 0` confirma que el gateway no fallo por Redis.
- `redis_error_body = 0` confirma que no se expusieron errores de Redis al cliente.
- `Gateway 5xx Rate = 0` o muy cercano a 0 indica resiliencia del gateway durante la caida.
- El RPS del gateway debe mantenerse estable.
- La latencia p95 puede subir durante la caida, pero el sistema no debe caer.
- `redis_commands_processed_total` cambia al apagar y restaurar Redis.

## Capturas recomendadas

Guarda capturas de:

- Grafana con Redis Availability mostrando `1 -> 0 -> 1`.
- k6 Fail-Open Responses aumentando.
- Gateway 5xx Rate en 0 o casi 0.
- k6 Gateway 503 Total en 0.
- Latencia p95 durante la ventana de Redis OFF.
- Resumen final de k6.

## Troubleshooting

### k6 no reconocido

Instala k6 localmente o ejecuta con Docker. Para Windows, verifica que `k6.exe` este en el `PATH`.

### Prometheus no recibe k6

Verifica:

```powershell
$env:K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write"
$env:K6_PROMETHEUS_RW_TREND_STATS="p(95),p(99),avg,min,max"
```

Confirma que Prometheus esta en `http://localhost:9090` y que el servicio incluye `--web.enable-remote-write-receiver`.
Si los paneles de k6 p95 aparecen en cero, confirma que la ejecucion nueva se hizo con `K6_PROMETHEUS_RW_TREND_STATS` incluyendo `p(95)`.

### redis-exporter DOWN

Revisa:

```powershell
docker compose ps redis redis-exporter
docker compose logs --tail=100 redis-exporter
docker compose exec redis redis-cli -a redis123 PING
```

Si Redis esta apagado durante el caos, el exporter debe seguir respondiendo y `redis_up` debe pasar a 0.
Si `http://localhost:9121/metrics` muestra `redis_up` pero Prometheus no tiene el target `redis-exporter`, reinicia Prometheus para recargar `infra/prometheus/prometheus.yml`:

```powershell
docker compose restart prometheus
```

### Dashboard sin datos

Confirma el datasource `Prometheus`, el rango de tiempo del dashboard y que k6 se ejecuto con remote write. Revisa tambien `http://localhost:9090/targets`.

### 503 por upstream real y no por Redis

Revisa:

```powershell
docker compose ps patient-service api-gateway api-gateway-lb
docker compose logs --tail=200 api-gateway
```

Si `patient-service` esta caido o no saludable, el 503 puede venir del upstream real. La prueba de Redis espera que el upstream pueda responder 400 o 404.
