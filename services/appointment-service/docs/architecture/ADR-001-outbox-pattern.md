# ADR-001: Usar Patrón Outbox para Consistencia Eventual en Eventos

**Status**: Accepted  
**Date**: 2026-05-06  
**Participants**: Architecture Team, Backend Team

---

## Context

En un sistema distribuido de microservicios, mediqueue-appointment-service necesita:
1. Persistir cambios en la BD (PostgreSQL)
2. Notificar otros servicios de eventos importantes (vía RabbitMQ)

**El problema**: Si ambas operaciones no son atómicas, podemos quedarnos inconsistentes:
- ✗ Guardar en BD pero fallar al enviar evento → otros servicios no se enteran
- ✗ Enviar evento pero fallar al guardar en BD → evento enviado sin persistencia

En distribución, esta inconsistencia es costosa (duplicados, discrepancias de datos, etc).

---

## Decision

Implementar el **Patrón Outbox** para garantizar consistencia eventual:

1. **Persistencia Transaccional**: Guardar evento en tabla `outbox_events` como PARTE de la misma transacción que el cambio
2. **Relay Asíncrono**: Un process de fondo (scheduler) lee la tabla `outbox_events` y envía a RabbitMQ
3. **Marcado de Publicados**: Una vez enviado exitosamente, marcar `published = true`

### Implementación

```
Transacción 1 (atómica):
  ├─ INSERT Appointment
  └─ INSERT OutboxEvent (published=false)
  
Transacción 2 (async scheduler):
  ├─ SELECT OutboxEvent WHERE published=false
  ├─ SEND to RabbitMQ
  └─ UPDATE OutboxEvent SET published=true
```

---

## Rationale

### Por Qué Outbox

1. **Garantía Transaccional**: Si la transacción falla, TODO se rollback (tanto entidad como evento)
2. **Resiliencia a Fallos de RabbitMQ**: Si el broker no está disponible, el relay reintenta después
3. **Auditoría Completa**: Todos los eventos quedan guardados en BD (histórico)
4. **Operacionalmente Simple**: No requiere infraestructura adicional compleja (CDC, event sourcing, etc.)

### Tradeoff

- **Latencia**: Evento no se envía inmediatamente; hay un delay de hasta `scheduler.interval` (típicamente 1 segundo)
- **Costo de Almacenamiento**: Tabla adicional de outbox
- **Complejidad**: Necesita relay process; más código para mantener

Aceptables porque:
- Latencia de 1 segundo es acceptable para este dominio
- Almacenamiento es minimal (eventos son pequeños)
- Relay es relativamente simple

---

## Consequences

### Positivas ✅

1. **Consistency Guaranteed**: No hay gap entre persistencia y publicación
2. **Resilient**: Broker down no causa datos pérdidos; relay reintenta
3. **Auditable**: Todos los eventos quedan en BD
4. **Simple**: No requiere CDC, event sourcing, o infraestructura compleja

### Negativas ⚠️

1. **Latencia**: Evento se envía con delay (< 1 segundo típicamente)
2. **Complejidad**: Código adicional para relay process
3. **Almacenamiento**: Tabla outbox crece indefinidamente (requiere cleanup periódico)

### Mitigaciones

- **Para latencia**: Usar short polling interval (1-5 segundos)
- **Para almacenamiento**: Crear política de archivado (purgar outbox_events > 30 días)

---

## Alternatives Considered

### 1. Enviar Evento Directamente a RabbitMQ en Transacción

```java
@Transactional
public void createAppointment(...) {
    appointment = repository.save(appointment);
    rabbitTemplate.convertAndSend("event", event);  // Directo, sin outbox
}
```

**Problema**: Si RabbitMQ falla después de `save()`, la transacción se rollback y pierden datos.

**Rechazo**: ✗ No es resiliente a fallos del broker

### 2. Change Data Capture (CDC) – Debezium

Usar herramienta como Debezium para:
- Monitorear WAL (Write-Ahead Log) de PostgreSQL
- Capturar cambios automáticamente
- Publicar a Kafka/RabbitMQ

**Ventaja**: Desacoplamiento total entre app y messaging

**Problema**: Complejidad operacional; requiere Debezium, Kafka/Redis coordinador, etc.

**Rechazo**: ✗ Overkill para este proyecto

### 3. Event Sourcing

Guardar TODO como eventos; estado derivado de eventos.

**Ventaja**: Auditoría perfecta; viajes temporales; replay

**Problema**: Arquitectura radicalmente diferente; requiere refactor completo

**Rechazo**: ✗ Scope fuera de las necesidades actuales

### 4. Saga Pattern (Distributed Transaction)

Usar sagas (coreografía o orquestación) para manejar transacciones distribuidas.

**Ventaja**: Manejo fino de fallos y compensaciones

**Problema**: Complejidad; requiere coordinar múltiples servicios

**Rechazo**: ✗ Outbox es suficiente para consistencia eventual

---

## Related Decisions

- **ADR-002** (Futuro): RabbitMQ Configuration y Bindings
- **ADR-003** (Futuro): Database Schema y Migrations Strategy

---

## Implementation Details

### Tabla Outbox

```sql
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(255) NOT NULL,
    payload TEXT NOT NULL,  -- JSON serializado
    published BOOLEAN DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    published_at TIMESTAMP
);

CREATE INDEX idx_outbox_published ON outbox_events(published, created_at);
```

### Service

```java
@Service
@Transactional
public class AppointmentService {
    
    public Appointment createAppointment(CreateAppointmentRequestDTO request) {
        // 1. Guardar entidad
        Appointment appointment = repository.save(new Appointment(request));
        
        // 2. Guardar evento (PARTE de la misma transacción)
        OutboxEvent event = OutboxEvent.builder()
            .eventType("AppointmentCreatedEvent")
            .payload(jsonSerialize(new AppointmentCreatedEvent(appointment)))
            .published(false)
            .build();
        outboxRepository.save(event);
        
        return appointment;  // Ambos persisten o ninguno (atomicidad)
    }
}
```

### Relay (Scheduler)

```java
@Component
public class OutboxRelay {
    
    @Scheduled(fixedRate = 1000)  // Cada 1 segundo
    public void relay() {
        List<OutboxEvent> unpublished = outboxRepository.findByPublishedFalse();
        
        for (OutboxEvent event : unpublished) {
            try {
                rabbitTemplate.convertAndSend("appointment-exchange", event.getEventType(), event.getPayload());
                event.setPublished(true);
                event.setPublishedAt(LocalDateTime.now());
                outboxRepository.save(event);
            } catch (Exception e) {
                log.error("Failed to publish event: {}", event.getId(), e);
                // Reintenta en el siguiente ciclo
            }
        }
    }
}
```

---

## References

- [Transactional Outbox Pattern - Chris Richardson](https://microservices.io/patterns/data/transactional-outbox.html)
- [Saga Pattern for Distributed Transactions](https://microservices.io/patterns/data/saga.html)
- [Spring Data JPA + RabbitMQ Integration](https://spring.io/projects/spring-amqp)
- [PostgreSQL WAL y CDC](https://www.postgresql.org/docs/14/wal-intro.html)

---

**Última actualización**: Mayo 2026  
**Versión**: 1.0  
**Aprobado por**: Architecture Team
