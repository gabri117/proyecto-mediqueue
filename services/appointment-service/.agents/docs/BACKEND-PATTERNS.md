# BACKEND-PATTERNS.md – Patrones y Arquitectura Backend

Patrones arquitectónicos, de persistencia, y de messaging para mediqueue-appointment-service.

---

## 📚 Contenido

1. [Arquitectura Layered](#arquitectura-layered)
2. [Patrón Outbox](#patrón-outbox)
3. [Event-Driven Design](#event-driven-design)
4. [Transacciones y Consistency](#transacciones-y-consistency)
5. [Caching con Redis](#caching-con-redis)
6. [Circuit Breakers (Resilience4j)](#circuit-breakers-resilience4j)
7. [DTOs y Mapping](#dtos-y-mapping)
8. [Repository Queries](#repository-queries)

---

## Arquitectura Layered

### Responsabilidades por Capa

```
┌──────────────────────────────────────────────┐
│ Controller (REST)                            │
│ - Recibir solicitudes HTTP                   │
│ - Validar entrada (anotaciones @Valid)       │
│ - Mapear DTOs ↔ Domain                       │
│ - Retornar respuestas HTTP                   │
└──────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────┐
│ Service (Business Logic)                     │
│ - Orquestar operaciones de negocio           │
│ - Aplicar reglas del dominio                 │
│ - Manejar transacciones                      │
│ - Emitir eventos de dominio                  │
│ - Gestionar consistencia eventual            │
└──────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────┐
│ Repository (Data Access)                     │
│ - Persistencia (JPA/Hibernate)               │
│ - Queries de lectura                         │
│ - Abstracción de BD                          │
└──────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────┐
│ Entity (Domain Model)                        │
│ - Lógica específica del dominio              │
│ - Invariantes                                │
│ - Relaciones con otras entidades             │
└──────────────────────────────────────────────┘
```

### Flujo Típico de Solicitud

```java
// 1. REQUEST llega al Controller
@PostMapping
public ResponseEntity<AppointmentDTO> create(
    @Valid @RequestBody CreateAppointmentRequestDTO request
) {
    // 2. Controller valida y mapea DTO → Domain
    Appointment appointment = service.createAppointment(request);
    
    // 3. Service ejecuta lógica de negocio
    // - Aplica reglas
    // - Emite eventos
    // - Maneja transacciones
    
    // 4. Repository persiste a BD
    // 5. Service emite evento de dominio (outbox)
    
    // 6. Controller mapea Domain → DTO
    return ResponseEntity.ok(map(appointment));
}
```

---

## Patrón Outbox

### ¿Por Qué Outbox?

En sistemas distribuidos, necesitamos **consistencia eventual**:
- Guardar cambio en BD
- Publicar evento en message broker
- Si fallamos a mitad camino, nos quedamos inconsistentes

**Solución**: Almacenar evento en BD como parte de la transacción.

### Implementación

```java
// 1. Entidad Outbox en BD
@Entity
@Table(name = "outbox_events")
@Data
@Builder
public class OutboxEvent {
    @Id
    private UUID id;
    private String eventType;      // e.g., "AppointmentCreatedEvent"
    private String payload;         // JSON serializado
    private LocalDateTime createdAt;
    private boolean published;      // False hasta que se envíe
}

// 2. Repository
public interface OutboxEventRepository extends JpaRepository<OutboxEvent, UUID> {
    List<OutboxEvent> findByPublishedFalse();
}

// 3. Service: Guardar evento en BD (transaccional)
@Service
@Transactional
public class AppointmentService {
    private final AppointmentRepository appointmentRepository;
    private final OutboxEventRepository outboxRepository;
    
    public Appointment createAppointment(CreateAppointmentRequestDTO request) {
        // Crear y guardar entidad
        Appointment appointment = Appointment.builder()
            .title(request.title())
            .status(AppointmentStatus.PENDING)
            .build();
        appointmentRepository.save(appointment);
        
        // CRÍTICO: Guardar evento en BD como PARTE de la transacción
        OutboxEvent event = OutboxEvent.builder()
            .id(UUID.randomUUID())
            .eventType("AppointmentCreatedEvent")
            .payload(jsonSerialize(new AppointmentCreatedEvent(appointment)))
            .createdAt(LocalDateTime.now())
            .published(false)
            .build();
        outboxRepository.save(event);
        
        // Transacción se confirma o rollback TODO JUNTO
        return appointment;
    }
}

// 4. Relay Asíncrono (ejecutado por scheduler)
@Component
public class OutboxRelay {
    private final OutboxEventRepository outboxRepository;
    private final RabbitTemplate rabbitTemplate;
    
    @Scheduled(fixedRate = 1000)  // Cada 1 segundo
    public void relay() {
        List<OutboxEvent> unpublished = outboxRepository.findByPublishedFalse();
        
        for (OutboxEvent event : unpublished) {
            try {
                // Enviar a RabbitMQ
                rabbitTemplate.convertAndSend(
                    "appointment-exchange",
                    event.getEventType(),
                    event.getPayload()
                );
                
                // Marcar como publicado
                event.setPublished(true);
                outboxRepository.save(event);
            } catch (Exception e) {
                log.error("Failed to publish event: {}", event.getId(), e);
                // El relay reintentará más tarde
            }
        }
    }
}
```

---

## Event-Driven Design

### Tipos de Eventos

```java
// 1. Events Publicados (Outbox)
@Data
@Builder
public class AppointmentCreatedEvent {
    private UUID appointmentId;
    private UUID patientId;
    private LocalDateTime scheduledAt;
    private LocalDateTime timestamp;
}

// 2. Events Consumidos (RabbitMQ)
@RabbitListener(queues = "patient-queue")
public void handlePatientCreatedEvent(PatientCreatedEvent event) {
    // Reaccionar a evento del dominio
    log.info("New patient created: {}", event.getPatientId());
}
```

### Convención de Nombrado

- `{Entity}CreatedEvent`
- `{Entity}UpdatedEvent`
- `{Entity}DeletedEvent`
- `{Entity}CancelledEvent`

### RabbitMQ Configuration

```java
@Configuration
public class RabbitMQConfig {
    
    // Exchanges
    public static final String APPOINTMENT_EXCHANGE = "appointment-exchange";
    
    // Queues
    public static final String APPOINTMENT_CREATED_QUEUE = "appointment-created-queue";
    
    // Routing Keys
    public static final String APPOINTMENT_CREATED_KEY = "appointment.created";
    
    @Bean
    public DirectExchange appointmentExchange() {
        return new DirectExchange(APPOINTMENT_EXCHANGE, true, false);
    }
    
    @Bean
    public Queue appointmentCreatedQueue() {
        return new Queue(APPOINTMENT_CREATED_QUEUE, true);
    }
    
    @Bean
    public Binding appointmentCreatedBinding() {
        return BindingBuilder.bind(appointmentCreatedQueue())
            .to(appointmentExchange())
            .with(APPOINTMENT_CREATED_KEY);
    }
}
```

---

## Transacciones y Consistency

### Transaccional por Default en Services

```java
@Service
@Transactional  // ✅ CORRECTO: Por defecto, todas las transacciones persisten
public class AppointmentService {
    
    public Appointment createAppointment(CreateAppointmentRequestDTO request) {
        // Todo aquí está en una transacción
        // Si algo falla, TODO se rollback
    }
    
    @Transactional(readOnly = true)  // ✅ Optimización para queries
    public Optional<Appointment> findById(UUID id) {
        return repository.findById(id);
    }
}
```

### Rollback en Excepciones

```java
@Service
@Transactional
public class AppointmentService {
    
    public Appointment createAppointment(CreateAppointmentRequestDTO request) {
        Appointment appointment = new Appointment(request);
        repository.save(appointment);
        
        // ✅ CORRECTO: Excepción personalizada causa rollback
        if (isConflictingSlot(appointment)) {
            throw new AppointmentConflictException("Slot already booked");
        }
        
        return appointment;
    }
    
    // ❌ INCORRECTO: RuntimeException dentro de try-catch evita rollback
    public void problematicMethod() {
        try {
            repository.save(appointment);
        } catch (RuntimeException e) {
            // Transacción NO se rollback si la excepto está capturada
            log.error("Error", e);
        }
    }
}
```

### Propagación Transaccional

```java
@Service
@Transactional
public class AppointmentService {
    private final PatientService patientService;
    
    public Appointment createAppointment(UUID patientId, CreateAppointmentRequestDTO request) {
        // 1. Verificar que paciente existe (lee de BD)
        Patient patient = patientService.getPatient(patientId);
        
        // 2. Crear cita
        Appointment appointment = new Appointment(request);
        repository.save(appointment);
        
        // 3. Llamar a otro service
        patientService.addAppointment(patientId, appointment);
        
        // TODO está en la MISMA transacción
        // Si patientService falla, TODO se rollback
        
        return appointment;
    }
}

@Service
public class PatientService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void addAppointment(UUID patientId, Appointment appointment) {
        // Esta es una NUEVA transacción, independiente
        // Si falla, NO afecta la transacción de AppointmentService
    }
}
```

---

## Caching con Redis

### Cache Configuration

```java
@Configuration
@EnableCaching
public class CacheConfig {
    
    @Bean
    public CacheManager cacheManager(LettuceConnectionFactory connectionFactory) {
        return new RedisCacheManager.create(connectionFactory);
    }
}
```

### Uso de Cache

```java
@Service
public class AppointmentService {
    
    // ✅ CORRECTO: Cachear lecturas frecuentes
    @Cacheable(value = "appointments", key = "#id")
    public Optional<Appointment> findById(UUID id) {
        return repository.findById(id);
    }
    
    // ✅ CORRECTO: Invalidar cache en updates
    @CacheEvict(value = "appointments", key = "#appointment.id")
    public Appointment updateAppointment(Appointment appointment) {
        return repository.save(appointment);
    }
    
    // ✅ CORRECTO: Limpiar todo el cache
    @CacheEvict(value = "appointments", allEntries = true)
    public void clearCache() { }
}
```

### TTL y Eviction Policy

```java
@Configuration
public class RedisConfig {
    
    @Bean
    public RedisCacheManagerBuilderCustomizer redisCacheManagerBuilderCustomizer() {
        return builder -> builder
            .withCacheConfiguration("appointments",
                RedisCacheConfiguration.defaultCacheConfig()
                    .entryTtl(Duration.ofHours(1))
                    .prefixCacheNameWith("mediqueue:")
            );
    }
}
```

---

## Circuit Breakers (Resilience4j)

### Configuration

```yaml
# application.yml
resilience4j:
  circuitbreaker:
    instances:
      appointmentService:
        registerHealthIndicator: true
        slidingWindowSize: 10
        failureRateThreshold: 50.0
        waitDurationInOpenState: 5000
        permittedNumberOfCallsInHalfOpenState: 3
        automaticTransitionFromOpenToHalfOpenEnabled: true
```

### Usage

```java
@Service
public class AppointmentService {
    
    // ✅ CORRECTO: Circuit breaker en operaciones remotas
    @CircuitBreaker(name = "appointmentService", fallbackMethod = "fallbackGetAppointment")
    public Appointment getAppointmentFromRemote(UUID id) {
        return restTemplate.getForObject("https://api.example.com/appointments/" + id, Appointment.class);
    }
    
    private Appointment fallbackGetAppointment(UUID id, Exception e) {
        log.warn("Circuit breaker opened for appointment: {}", id);
        throw new AppointmentServiceUnavailableException("Service temporarily unavailable", e);
    }
}
```

---

## DTOs y Mapping

### Estructura de DTOs

```java
// Request DTO
public record CreateAppointmentRequestDTO(
    @NotNull(message = "Title cannot be null")
    @Size(min = 5, max = 255)
    String title,
    
    @NotNull
    @Future(message = "Scheduled date must be in the future")
    LocalDateTime scheduledAt,
    
    @NotNull
    UUID patientId
) {}

// Response DTO
public record AppointmentDTO(
    UUID id,
    String title,
    LocalDateTime scheduledAt,
    AppointmentStatus status,
    LocalDateTime createdAt
) {}
```

### Mapping (Entity ↔ DTO)

```java
@Component
public class AppointmentMapper {
    
    public AppointmentDTO toDTO(Appointment entity) {
        return new AppointmentDTO(
            entity.getId(),
            entity.getTitle(),
            entity.getScheduledAt(),
            entity.getStatus(),
            entity.getCreatedAt()
        );
    }
    
    public Appointment toEntity(CreateAppointmentRequestDTO dto) {
        return Appointment.builder()
            .title(dto.title())
            .scheduledAt(dto.scheduledAt())
            .status(AppointmentStatus.PENDING)
            .build();
    }
}
```

---

## Repository Queries

### Query Naming Convention

```java
public interface AppointmentRepository extends JpaRepository<Appointment, UUID> {
    
    // Método query derivado (simple)
    List<Appointment> findByPatientId(UUID patientId);
    List<Appointment> findByStatus(AppointmentStatus status);
    Optional<Appointment> findByIdAndPatientId(UUID id, UUID patientId);
    
    // Query personalizada (compleja)
    @Query("SELECT a FROM Appointment a " +
           "WHERE a.patient.id = :patientId " +
           "AND a.status = :status " +
           "AND a.scheduledAt BETWEEN :startDate AND :endDate")
    List<Appointment> findAppointmentsByPatientAndDateRange(
        @Param("patientId") UUID patientId,
        @Param("status") AppointmentStatus status,
        @Param("startDate") LocalDateTime startDate,
        @Param("endDate") LocalDateTime endDate
    );
    
    // Native SQL cuando sea necesario
    @Query(value = "SELECT * FROM appointments WHERE status = :status LIMIT :limit", 
           nativeQuery = true)
    List<Appointment> findByStatusNative(@Param("status") String status, @Param("limit") int limit);
}
```

### Pagination

```java
@Service
public class AppointmentService {
    private final AppointmentRepository repository;
    
    public Page<AppointmentDTO> getAppointmentsPage(UUID patientId, int page, int size) {
        PageRequest pageRequest = PageRequest.of(page, size, Sort.by("scheduledAt").descending());
        Page<Appointment> result = repository.findByPatientId(patientId, pageRequest);
        return result.map(this::toDTO);
    }
}

// Controller
@GetMapping
public ResponseEntity<Page<AppointmentDTO>> list(
    @RequestParam UUID patientId,
    @RequestParam(defaultValue = "0") int page,
    @RequestParam(defaultValue = "10") int size
) {
    return ResponseEntity.ok(appointmentService.getAppointmentsPage(patientId, page, size));
}
```

---

## Checkpoints de Revisión

- [ ] Capas separadas (Controller → Service → Repository → Entity)
- [ ] Service usa `@Transactional` correctamente
- [ ] Eventos guardados en outbox (parte de transacción)
- [ ] RabbitMQ bindings correctamente configurados
- [ ] DTOs validan entrada con anotaciones `@Valid`
- [ ] Queries JPA optimizadas (no N+1)
- [ ] Cache invalidado en updates
- [ ] Circuit breakers en operaciones remotas

---

**Última actualización**: Mayo 2026  
**Versión**: 1.0
