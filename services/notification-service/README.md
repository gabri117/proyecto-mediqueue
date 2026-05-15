# notification-service

Servicio consumidor de eventos para MediQueue Resilient.

Este servicio registra notificaciones simuladas a partir de eventos publicados en RabbitMQ. En esta fase sigue siendo un consumidor puro:

- No expone `POST /notifications`.
- No expone `PUT`, `PATCH` ni `DELETE`.
- No usa Redis.
- No implementa Outbox.
- No envia email/SMS real todavia; el envio es simulado y queda auditado en PostgreSQL.

## Eventos consumidos

### Citas

Exchange: `appointments-exchange`

Cola: `notification.appointment.queue`

Routing keys consumidas:

- `appointment.confirmed`
- `appointment.cancelled`
- `appointment.expired`

Payload esperado:

```json
{
  "eventId": "c157d70e-9085-4c2d-850e-27c215596bdf",
  "eventType": "APPOINTMENT_CONFIRMED",
  "occurredAt": "2026-05-15T17:09:02Z",
  "patientEmail": "patient@example.test",
  "payload": {
    "appointmentId": "bd91d0ed-0bb7-4285-b174-84527d971594",
    "patientId": "48cec0ad-7dd1-46c9-9124-26830c103a40",
    "dentistId": "d7d0c2f8-1529-49a6-90aa-0a8f630bb736",
    "slotId": "23363b15-09fd-406b-8d3c-a7efaf71ac80",
    "appointmentDate": "2026-05-16",
    "startTime": "09:00:00",
    "endTime": "09:30:00",
    "amount": 125.50
  }
}
```

El consumidor tambien acepta algunos campos en la raiz del evento para mantener compatibilidad, pero los publishers actuales usan `payload` anidado.

### Pagos

Exchange: `payments-exchange`

Cola: `notification.payment.queue`

Routing keys consumidas:

- `payment.succeeded`
- `payment.failed`

## Deduplicacion

La tabla `notifications` tiene columnas de trazabilidad del evento origen:

- `source_event_id`
- `source_event_type`
- `source_service`
- `event_key`
- `routing_key`
- `attempt_count`

`event_key` tiene un indice unico parcial. Si llega `eventId`, ese valor se usa como `event_key`. Si no llega, se construye una llave deterministica con `eventType`, `appointmentId`, `paymentId`, `patientId` y `channel`.

Un duplicado se confirma con ACK y no crea otra fila. Si dos replicas futuras compiten por insertar el mismo evento, el indice unico evita duplicados y la violacion de integridad se trata como duplicado.

## Consultas

Via API Gateway:

```bash
curl "http://localhost:8080/api/notifications?page=0&size=20"
curl "http://localhost:8080/api/notifications?patientId=<uuid>&page=0&size=20"
curl "http://localhost:8080/api/notifications?appointmentId=<uuid>&page=0&size=20"
curl "http://localhost:8080/api/notifications?status=SENT&page=0&size=20"
curl "http://localhost:8080/api/notifications?patientId=<uuid>&status=FAILED&page=0&size=20"
curl "http://localhost:8080/api/notifications/<notificationId>"
curl "http://localhost:8080/api/notifications/patient/<patientId>?page=0&size=20"
```

Las respuestas paginadas usan `PagedResponse<T>`, ordenadas por `createdAt DESC`. El parametro `size` tiene maximo 100.

## Validacion RabbitMQ

Ver colas y consumidores:

```bash
docker exec mediqueue-rabbitmq rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
```

Publicar un evento sintetico desde PowerShell:

```powershell
$eventId = [guid]::NewGuid().ToString()
$appointmentId = [guid]::NewGuid().ToString()
$patientId = [guid]::NewGuid().ToString()

$payloadObject = [ordered]@{
  eventId = $eventId
  eventType = 'APPOINTMENT_CONFIRMED'
  occurredAt = (Get-Date).ToUniversalTime().ToString('o')
  patientEmail = "patient-$patientId@mediqueue.test"
  payload = [ordered]@{
    appointmentId = $appointmentId
    patientId = $patientId
    dentistId = [guid]::NewGuid().ToString()
    slotId = [guid]::NewGuid().ToString()
    appointmentDate = (Get-Date).AddDays(1).ToString('yyyy-MM-dd')
    startTime = '09:00:00'
    endTime = '09:30:00'
    amount = 125.50
  }
}

$messageJson = $payloadObject | ConvertTo-Json -Depth 8 -Compress
$publishBody = @{
  properties = @{ content_type = 'application/json'; delivery_mode = 2 }
  routing_key = 'appointment.confirmed'
  payload = $messageJson
  payload_encoding = 'string'
} | ConvertTo-Json -Depth 10 -Compress

$securePass = ConvertTo-SecureString 'rabbit123' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('mediqueue', $securePass)

Invoke-RestMethod -Method Post `
  -Uri 'http://localhost:15672/api/exchanges/%2F/appointments-exchange/publish' `
  -Credential $cred `
  -ContentType 'application/json' `
  -Body $publishBody
```

Para validar duplicados, ejecutar el mismo publish dos veces con el mismo `eventId` y consultar:

```bash
curl "http://localhost:8080/api/notifications?appointmentId=<appointmentId>&page=0&size=20"
docker exec mediqueue-postgres psql -U mediqueue -d mediqueue_notifications -c "SELECT event_key, COUNT(*) FROM notifications WHERE event_key = '<eventId>' GROUP BY event_key;"
```

El resultado esperado es una sola fila.

## Logs utiles

```bash
docker compose logs --tail=200 notification-service
docker compose logs --tail=200 rabbitmq
```

En una publicacion duplicada exitosa deben verse entradas similares a:

- `appointment_event_processed ... result=CREATED_SENT`
- `notification_duplicate ...`
- `appointment_event_processed ... result=DUPLICATE`

No deben aparecer `PRECONDITION_FAILED`, `NOT_FOUND` ni `ERROR`.

## Tests

```bash
docker run --rm -v "${PWD}:/workspace" -w /workspace maven:3.9-eclipse-temurin-21 mvn -pl services/notification-service -am test -q
```

## Escalabilidad pendiente

No se implemento HA de `notification-service` en esta fase. Para escalarlo despues:

- Quitar `container_name: mediqueue-notification-service`.
- Quitar el mapeo externo `ports: "8082:8080"`.
- Usar `expose: "8080"` para replicas internas.
- Opcionalmente agregar `notification-lb`.
- Apuntar el gateway a `notification-lb`.

RabbitMQ ya permite competir consumidores en la misma cola y la deduplicacion por `event_key` protege contra redeliveries y carreras entre replicas.
