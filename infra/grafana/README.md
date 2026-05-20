# Dashboards de Observabilidad — MediQueue

Este directorio contiene todos los dashboards de Grafana del proyecto MediQueue, provisioned automáticamente desde `dashboards/`. Grafana los carga cada 30 segundos sin necesidad de reiniciar el contenedor.

Para verlos: accedé a **http://localhost:3000** (usuario: `admin`, contraseña: `admin`) con el stack levantado (`docker-compose up`).

---

## Mapa de dashboards

### 1. Panel de Control Principal
**Archivo:** `mediqueue-dashboard.json`

Dashboard central del equipo. Muestra el estado general de todos los microservicios en tiempo real: tráfico HTTP, latencia, errores, estado de los circuit breakers de Resilience4j y actividad de RabbitMQ. Es el punto de partida para cualquier revisión del sistema.

---

### 2. Vista Ejecutiva
**Archivo:** `mediqueue-executive-overview.json`

Pensado para una mirada rápida de alto nivel. En una sola pantalla se ve:
- Si cada uno de los 6 servicios está activo o caído (verde/rojo)
- Cuántas solicitudes por segundo está procesando el sistema
- La latencia p95 global (el peor 5% de los tiempos de respuesta)
- La distribución de respuestas HTTP (2xx éxito, 4xx cliente, 5xx error)
- El uso de memoria heap de la JVM y la actividad de RabbitMQ

Ideal para mostrar durante la presentación como pantalla de introducción.

---

### 3. Escenarios de Prueba A / B / C
**Archivo:** `mediqueue-checkpoint-scenarios.json`

Documenta los tres escenarios de carga que el proyecto debe demostrar:

- **Escenario A — Carga de Lectura:** mide el rendimiento de las consultas GET al patient-service y schedule-service. Muestra solicitudes por segundo, latencia media y distribución de respuestas.
- **Escenario B — Concurrencia:** enfocado en el appointment-service bajo carga simultánea. Muestra saturación del servicio, errores bajo presión y el pie chart de distribución de respuestas.
- **Escenario C — Flujo Completo E2E:** cubre el flujo de pago → notificación. Muestra el rendimiento del payment-service, la latencia del proceso completo y los mensajes publicados en RabbitMQ.

Usar este dashboard durante la demostración de los checkpoints de la materia.

---

### 4. Resiliencia y Estabilidad
**Archivo:** `mediqueue-resilience-stability.json`

Muestra los mecanismos de resiliencia implementados en el proyecto:

- **Circuit Breakers (State Timeline):** visualización en línea de tiempo del estado de los circuit breakers de Resilience4j — `CERRADO` (operación normal), `MEDIO ABIERTO` (recuperando), `ABIERTO` (fallo activo, rechazando llamadas). El appointment-service protege las llamadas a patient-service y schedule-service.
- **Rate Limiting con Redis:** estado del Redis que respalda el FailOpenRedisRateLimiter del API Gateway. Si Redis cae, el sistema sigue operando (fail-open).
- **Reintentos (notification-service):** cantidad de reintentos automáticos ejecutados por Resilience4j Retry.
- **Mensajería RabbitMQ:** mensajes publicados, consumidos y en cola.

Este dashboard es el más importante para demostrar los patrones de resiliencia del sistema.

---

### 5. SLA y Disponibilidad
**Archivo:** `mediqueue-sla-disponibilidad.json`

Calcula y muestra el SLA (Service Level Agreement) de las últimas 24 horas para cada servicio usando el tiempo que estuvo disponible (`up` metric de Prometheus). Incluye:

- Porcentaje de disponibilidad por servicio (target: 99.5%)
- Ranking comparativo de disponibilidad entre servicios
- Historial de disponibilidad en el tiempo
- Tasa de éxito global (solicitudes exitosas vs. total)
- Contador de errores consumidos del error budget
- Cantidad de réplicas activas por servicio

---

### 6. Rendimiento BD y JVM
**Archivo:** `mediqueue-rendimiento-bd.json`

Métricas internas de cada microservicio Java:

- **HikariCP (pool de conexiones a PostgreSQL):** conexiones activas, inactivas, en espera y saturación del pool. Un pool saturado al 80%+ indica cuellos de botella en la base de datos.
- **Memoria JVM:** heap usado vs. máximo por servicio. Si el heap se llena, el Garbage Collector se dispara continuamente y degrada la latencia.
- **Garbage Collector:** tiempo total de GC y frecuencia de pausas Young GC vs. Full GC. El Full GC detiene completamente la aplicación (stop-the-world).
- **Hilos JVM:** hilos activos y bloqueados por servicio. Muchos hilos bloqueados simultáneamente puede indicar deadlocks.
- **CPU por proceso:** carga de CPU de cada proceso Java individual.
- **Uptime:** tiempo en servicio de cada proceso — detecta reinicios recientes por crashes.

---

### 7. Gateway y Redis — Prueba de Caos (50K solicitudes)
**Archivo:** `mediqueue-gateway-redis-chaos-50k.json`

Dashboard del equipo para la prueba de caos con 50.000 solicitudes. Muestra cómo se comporta el API Gateway y el rate limiter basado en Redis bajo carga extrema, incluyendo qué pasa cuando Redis se cae durante la prueba (modo fail-open).

---

### 8. Resumen de Pruebas de Carga
**Archivo:** `mediqueue-load-testing-overview.json`

Dashboard del equipo para visualizar los resultados de las pruebas de carga generadas con k6. Muestra solicitudes por segundo por servicio, latencia, tasa de error y duración total de la prueba.

---

## Tecnologías detrás de los dashboards

| Herramienta | Rol |
|---|---|
| **Prometheus** | Recolecta métricas de todos los servicios cada 15s vía `/actuator/prometheus` |
| **Micrometer** | Expone las métricas de Spring Boot en formato Prometheus |
| **Resilience4j** | Expone métricas de circuit breakers, retries y rate limiters |
| **HikariCP** | Expone métricas del pool de conexiones a PostgreSQL |
| **Redis Exporter** | Expone métricas de Redis (memoria, hit rate, comandos/s) |
| **RabbitMQ** | Expone métricas de mensajería vía plugin Prometheus en puerto 15692 |
| **Grafana 11** | Visualiza todo lo anterior mediante dashboards JSON provisioned |

## Cómo generar datos para ver los paneles

Si los paneles aparecen en blanco ("No data"), es porque no hay tráfico activo. Ejecutar este comando genera carga para poblar los gráficos:

```bash
while true; do
  curl -s http://localhost:8080/api/patients > /dev/null
  curl -s http://localhost:8080/api/appointments > /dev/null
  curl -s http://localhost:8080/api/schedules > /dev/null
  sleep 0.5
done
```
