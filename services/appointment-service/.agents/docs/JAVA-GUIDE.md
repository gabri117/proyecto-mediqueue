# JAVA-GUIDE.md – Patrones y Estándares Java

Guía específica para desarrollar en Java 21 con Spring Boot 3.5.14 en mediqueue-appointment-service.

---

## 📚 Contenido

1. [Convenciones de Nombrado](#convenciones-de-nombrado)
2. [Lombok Usage](#lombok-usage)
3. [Inmovilidad y Optional](#inmovilidad-y-optional)
4. [Streams y Functional](#streams-y-functional)
5. [Manejo de Excepciones](#manejo-de-excepciones)
6. [Genéricos](#genéricos)
7. [Estructuras de Proyecto](#estructuras-de-proyecto)

---

## Convenciones de Nombrado

### Clases

| Tipo | Patrón | Ejemplo |
|------|--------|---------|
| Entidad JPA | Singular, representa dominio | `Appointment`, `Patient`, `Slot` |
| DTO | `{Entity}DTO` o `{Entity}RequestDTO` | `AppointmentDTO`, `CreateAppointmentRequestDTO` |
| Service | `{Entity}Service` | `AppointmentService`, `PatientService` |
| Repository | `{Entity}Repository` | `AppointmentRepository` |
| Controller | `{Entity}Controller` | `AppointmentController` |
| Exception | `{Concept}Exception` | `AppointmentNotFoundException`, `InvalidSlotException` |
| Config | Descriptivo + `Config` | `DatabaseConfig`, `RabbitMQConfig` |
| Event | `{Event}Event` o `{Event}PublishedEvent` | `AppointmentCreatedEvent`, `AppointmentCancelledEvent` |

### Variables y Métodos

- **Snake_case**: NUNCA. Usar camelCase.
- **Getters/Setters**: Deixar para Lombok (no escribir manualmente).
- **Métodos Booleanos**: Comenzar con `is` o `has`.

```java
// ✅ CORRECTO
private boolean isActive;
public boolean hasAppointments() { ... }

// ❌ INCORRECTO
private boolean active;
private boolean check_if_valid;
```

---

## Lombok Usage

### Recomendado

```java
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class Appointment {
    private UUID id;
    private String title;
    private LocalDateTime scheduledAt;
    private AppointmentStatus status;
}
```

### Cuándo NO Usar Lombok

1. **Clases con validación compleja en constructor**:
   ```java
   public class Appointment {
       private UUID id;
       private LocalDateTime scheduledAt;
       
       public Appointment(UUID id, LocalDateTime scheduledAt) {
           this.id = Objects.requireNonNull(id, "id cannot be null");
           if (scheduledAt.isBefore(LocalDateTime.now())) {
               throw new InvalidScheduleException("Cannot schedule in the past");
           }
           this.scheduledAt = scheduledAt;
       }
   }
   ```

2. **Entidades con relaciones complejas**: Usar `@Data` solo con `@EqualsAndHashCode(exclude = {...})`

### EqualsAndHashCode con Relaciones

```java
@Data
@Entity
@EqualsAndHashCode(exclude = "patient")  // Evitar loops infinitos
public class Appointment {
    @Id
    private UUID id;
    
    @ManyToOne
    private Patient patient;
}
```

---

## Inmovilidad y Optional

### Usar Records para DTOs (Java 21)

```java
public record AppointmentDTO(
    UUID id,
    String title,
    LocalDateTime scheduledAt,
    AppointmentStatus status
) {}
```

### Inmutabilidad en Entidades

```java
@Data
@Builder
@Entity
public class Appointment {
    @Id
    private final UUID id = UUID.randomUUID();
    
    // Setter será generado por Lombok, pero considera usar @Setter(AccessLevel.NONE)
    // si quieres inmutabilidad real
    private String title;
}
```

### Optional Usage

```java
// ✅ CORRECTO: Usar Optional para retornos
public Optional<Appointment> findById(UUID id) {
    return repository.findById(id);
}

// ✅ CORRECTO: Encadenar
appointment.ifPresent(a -> System.out.println(a.getTitle()));
appointment.orElseThrow(() -> new AppointmentNotFoundException(id));

// ❌ INCORRECTO: Nunca usar Optional en parámetros
public void process(Optional<Appointment> appointment) { }  // MAL

// ❌ INCORRECTO: get() sin is Present
Appointment a = appointment.get();  // Puede lanzar NoSuchElementException
```

### Manejo de null en Collections

```java
// ✅ CORRECTO
List<Appointment> appointments = appointmentRepository.findAll();
appointments.stream()
    .filter(Objects::nonNull)
    .forEach(this::process);

// ✅ CORRECTO: Retornar colección vacía, no null
public List<Appointment> getAppointments(UUID patientId) {
    return repository.findByPatientId(patientId);  // Retorna List.of() si no hay
}
```

---

## Streams y Functional

### Streams en Lugar de Bucles Tradicionales

```java
// ❌ INCORRECTO: Loop tradicional
List<String> titles = new ArrayList<>();
for (Appointment a : appointments) {
    if (a.getStatus() == AppointmentStatus.CONFIRMED) {
        titles.add(a.getTitle());
    }
}

// ✅ CORRECTO: Stream
List<String> titles = appointments.stream()
    .filter(a -> a.getStatus() == AppointmentStatus.CONFIRMED)
    .map(Appointment::getTitle)
    .toList();
```

### Evitar Streams Anidados Profundos

```java
// ❌ INCORRECTO: Muy anidado
patients.stream()
    .flatMap(p -> p.getAppointments().stream())
    .filter(a -> a.getStatus() == CONFIRMED)
    .map(Appointment::getTitle)
    .collect(Collectors.groupingBy(...))
    .values()
    .stream()
    .map(...)
    .forEach(...);

// ✅ CORRECTO: Dividir en pasos claros
List<Appointment> confirmedAppointments = patients.stream()
    .flatMap(p -> p.getAppointments().stream())
    .filter(a -> a.getStatus() == CONFIRMED)
    .toList();

// Luego procesar
confirmedAppointments.forEach(this::sendNotification);
```

### Usar Method References

```java
// ✅ CORRECTO
appointments.forEach(System.out::println);
appointments.stream().map(Appointment::getTitle).toList();

// ❌ INCORRECTO: Lambda innecesaria
appointments.forEach(a -> System.out.println(a));
```

---

## Manejo de Excepciones

### Excepciones Personalizadas

```java
// ✅ CORRECTO: Excepciones específicas del dominio
public class AppointmentNotFoundException extends RuntimeException {
    public AppointmentNotFoundException(UUID id) {
        super("Appointment with id " + id + " not found");
    }
}

public class InvalidScheduleException extends RuntimeException {
    public InvalidScheduleException(String message) {
        super(message);
    }
}
```

### No Silenciar Excepciones

```java
// ❌ INCORRECTO: Silenciar excepción
try {
    process();
} catch (Exception e) {
    // No hacer nada
}

// ✅ CORRECTO: Loguear o relanzar
try {
    process();
} catch (IOException e) {
    log.error("Failed to process appointment", e);
    throw new AppointmentProcessingException("Cannot process", e);
}
```

### Try-with-Resources

```java
// ✅ CORRECTO: Cierre automático de recursos
try (BufferedReader reader = new BufferedReader(new FileReader("data.txt"))) {
    String line = reader.readLine();
} catch (IOException e) {
    log.error("Failed to read file", e);
}
```

---

## Genéricos

### Usar Genéricos para Type Safety

```java
// ✅ CORRECTO: Genéricos con bounds
public <T extends Entity> void save(T entity) {
    repository.save(entity);
}

// ✅ CORRECTO: Wildcard cuando es read-only
public void processAppointments(List<? extends Appointment> appointments) {
    appointments.forEach(this::validate);
}

// ❌ INCORRECTO: Raw types
List appointments = new ArrayList();  // Sin tipo
```

### Evitar Type Erasure Issues

```java
// ❌ INCORRECTO: No puedes instanciar genéricos
public <T> T create(Class<T> clazz) {
    return new T();  // ERROR: No permitido
}

// ✅ CORRECTO: Usar reflexión o factory
public <T> T create(Class<T> clazz) {
    try {
        return clazz.getDeclaredConstructor().newInstance();
    } catch (Exception e) {
        throw new RuntimeException(e);
    }
}
```

---

## Estructuras de Proyecto

### Estructura Base por Dominio

```
src/main/java/com/mediqueue/appointment/
├── domain/
│   ├── Appointment.java
│   ├── Patient.java
│   └── enums/
│       ├── AppointmentStatus.java
│       └── AppointmentType.java
├── dto/
│   ├── AppointmentDTO.java
│   ├── CreateAppointmentRequestDTO.java
│   └── AppointmentResponseDTO.java
├── repository/
│   └── AppointmentRepository.java
├── service/
│   └── AppointmentService.java
├── controller/
│   └── AppointmentController.java
├── events/
│   ├── published/
│   │   └── AppointmentCreatedEvent.java
│   └── consumed/
│       └── PatientCreatedEventListener.java
├── exception/
│   ├── AppointmentNotFoundException.java
│   └── InvalidScheduleException.java
└── config/
    └── AppointmentConfig.java
```

### Separación de Concerns

**Service Layer**: Lógica de negocio, transacciones, orquestación

```java
@Service
@Transactional
public class AppointmentService {
    private final AppointmentRepository repository;
    private final OutboxEventRepository outboxRepository;
    
    public Appointment createAppointment(CreateAppointmentRequestDTO request) {
        Appointment appointment = Appointment.builder()
            .title(request.title())
            .scheduledAt(request.scheduledAt())
            .status(AppointmentStatus.PENDING)
            .build();
        
        repository.save(appointment);
        outboxRepository.save(new AppointmentCreatedEvent(appointment));
        return appointment;
    }
}
```

**Controller Layer**: Validación de entrada, conversión DTO, HTTP

```java
@RestController
@RequestMapping("/api/appointments")
public class AppointmentController {
    private final AppointmentService service;
    
    @PostMapping
    public ResponseEntity<AppointmentDTO> create(@Valid @RequestBody CreateAppointmentRequestDTO request) {
        Appointment appointment = service.createAppointment(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(map(appointment));
    }
}
```

---

## Javadoc y Comentarios

### Documentar Contratos Públicos

```java
/**
 * Crea una nueva cita médica.
 *
 * @param request Datos de la cita (no null)
 * @return La cita creada
 * @throws AppointmentConflictException si existe solapamiento de horarios
 * @throws InvalidScheduleException si la fecha es en el pasado
 */
public Appointment createAppointment(CreateAppointmentRequestDTO request) {
    // ...
}
```

### Evitar Comentarios Obvios

```java
// ❌ INCORRECTO: Comentario que repite el código
int count = 0;  // Inicializar contador

// ✅ CORRECTO: Comentario que explica el por qué
// Usamos contador para rastrear reintentos en case de fallos de conexión
int retryCount = 0;
```

---

## Checkpoints de Revisión

- [ ] Convenciones de nombrado seguidas (Entity, DTO, Service, Repository)
- [ ] Lombok habilitado; no hay getters/setters manuales innecesarios
- [ ] Immutabilidad donde sea posible (records para DTOs)
- [ ] Manejo correcto de Optional (no `get()` sin check)
- [ ] Streams en lugar de loops tradicionales
- [ ] Excepciones personalizadas para casos de error del dominio
- [ ] Genéricos con type safety (sin raw types)
- [ ] Javadoc en métodos públicos

---

**Última actualización**: Mayo 2026  
**Versión**: 1.0
