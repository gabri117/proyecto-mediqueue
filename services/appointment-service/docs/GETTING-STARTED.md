# 🚀 BIENVENIDO a mediqueue-appointment-service

Guía de orientación rápida para nuevos desarrolladores.

---

## ⏱️ Primeros 5 Minutos

```bash
# 1. Clonar repo (ya hecho)
git clone <repo-url>
cd mediqueue-appointment-service

# 2. Instalar dependencias y compilar
mvn clean compile

# 3. Ejecutar tests
mvn test

# 4. Lanzar la app
mvn spring-boot:run
```

---

## 📖 Documentación Esencial (Lee en Este Orden)

### Minuto 5-10: Overview del Proyecto
→ [`docs/README.md`](./docs/README.md)

### Minuto 10-15: Comandos y Configuración Rápida
→ [`AGENTS.md`](./AGENTS.md) (raíz - 2 páginas)

### Minuto 15-30: Estructura del Código
Lee la estructura en `src/main/java/com/mediqueue/appointment/`:
- `domain/` = Entidades JPA (modelos de datos)
- `service/` = Lógica de negocio
- `controller/` = Endpoints REST
- `repository/` = Acceso a datos
- `dto/` = Modelos para API REST
- `events/` = Publicación/consumo de eventos
- `outbox/` = Almacenamiento transaccional de eventos

---

## 🔥 3 Cosas Críticas (NO las olvides)

### 1. Habilitar Lombok en tu IDE
**Problema**: Verás errores "symbol cannot be found" en `@Getter`, `@Setter`

**Solución**:
- **IntelliJ**: Build → Compiler → Annotation Processors → Enable Annotation Processing
- **VS Code**: Instalar "Extension Pack for Java" (auto-habilitado)

### 2. Patrón Outbox: NO Envíes Eventos Directamente a RabbitMQ
**Incorrecto**:
```java
rabbitTemplate.convertAndSend("event", appointment);  // ❌ MAL
```

**Correcto**:
```java
outboxRepository.save(new OutboxEvent(appointment));  // ✅ BIEN
// El relay asíncrono los envía a RabbitMQ después
```

### 3. Migraciones Flyway en Ubicación Exacta
```
src/main/resources/db/migration/
├── V1__Initial_schema.sql
├── V2__Add_appointments_table.sql
```

Nombre: `V{numero}__{descripcion}.sql`

---

## 📚 Documentación Completa

| Necesito... | Leer... |
|-----------|---------|
| Overview del proyecto | [`docs/README.md`](./docs/README.md) |
| Comandos Maven | [`AGENTS.md`](./AGENTS.md) |
| Guía Java 21 + Spring Boot | [`.agents/docs/JAVA-GUIDE.md`](./.agents/docs/JAVA-GUIDE.md) |
| Arquitectura, Outbox, Events | [`.agents/docs/BACKEND-PATTERNS.md`](./.agents/docs/BACKEND-PATTERNS.md) |
| Decisiones arquitectónicas | [`docs/architecture/`](./docs/architecture/) |
| Índice centralizado | [`docs/DOCUMENTATION-INDEX.md`](./docs/DOCUMENTATION-INDEX.md) |

---

## 💻 Tu Primer Feature

### Paso 1: Entiende la Solicitud
Lee la especificación y la data model.

### Paso 2: Implementa la Entidad
```java
// src/main/java/com/mediqueue/appointment/domain/Appointment.java
@Entity
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class Appointment {
    @Id
    private UUID id;
    private String title;
    private LocalDateTime scheduledAt;
    // ...
}
```

### Paso 3: Crea el Repository
```java
// src/main/java/com/mediqueue/appointment/repository/AppointmentRepository.java
public interface AppointmentRepository extends JpaRepository<Appointment, UUID> {
    List<Appointment> findByPatientId(UUID patientId);
}
```

### Paso 4: Implementa el Service
```java
// src/main/java/com/mediqueue/appointment/service/AppointmentService.java
@Service
@Transactional
public class AppointmentService {
    private final AppointmentRepository repository;
    private final OutboxEventRepository outboxRepository;
    
    public Appointment createAppointment(CreateAppointmentRequestDTO request) {
        // Validar
        // Crear entidad
        // Guardar en BD
        // Emitir evento (via outbox)
        // Retornar
    }
}
```

### Paso 5: Crea el Controller
```java
// src/main/java/com/mediqueue/appointment/controller/AppointmentController.java
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

### Paso 6: Escribe Tests
```bash
mvn test
```

### Paso 7: Ejecuta la App
```bash
mvn spring-boot:run
```

### Paso 8: NO empaques
Convención del equipo: NO ejecutes `mvn clean package` después de cambios.

---

## ❓ FAQ Rápido

### P: ¿Cómo ejecuto UN test específico?
```bash
mvn test -Dtest=AppointmentServiceTest
```

### P: ¿Dónde pongo validaciones?
- **DTOs**: Anotaciones `@Valid`, `@NotNull`, `@Size`, etc.
- **Service**: Lógica de negocio compleja (reglas de dominio)

### P: ¿Cómo manejo errores?
Crea excepciones personalizadas:
```java
public class AppointmentNotFoundException extends RuntimeException {
    public AppointmentNotFoundException(UUID id) {
        super("Appointment with id " + id + " not found");
    }
}
```

### P: ¿Cómo cacheo datos?
Usa anotaciones de Spring:
```java
@Cacheable(value = "appointments", key = "#id")
public Optional<Appointment> findById(UUID id) {
    return repository.findById(id);
}
```

### P: ¿Qué versión de Java?
Java 21 – puedes usar records, sealed classes, pattern matching, etc.

### P: ¿Qué es el Outbox Pattern?
Leer: [`.agents/docs/BACKEND-PATTERNS.md`](./.agents/docs/BACKEND-PATTERNS.md#patrón-outbox)

---

## 🆘 Troubleshooting

| Problema | Solución |
|----------|----------|
| "symbol cannot be found" @Getter/@Setter | [Habilitar Lombok](#1-habilitar-lombok-en-tu-ide) |
| Tests fallan con RabbitMQ | Usar `spring-rabbit-test` (ya incluido) |
| La app no inicia | Verificar PostgreSQL, Redis, RabbitMQ están corriendo |
| Migraciones no ejecutadas | Revisar `src/main/resources/db/migration/` naming |
| "Could not resolve placeholder in string" | Verificar `application.yml` o `application-dev.yml` |

---

## 📞 Contacto

- **Documentación**: Ver [`docs/DOCUMENTATION-INDEX.md`](./docs/DOCUMENTATION-INDEX.md)
- **Skills IA**: Ver [`.agents/`](./.agents/)
- **Bugs/Issues**: GitHub Issues
- **Team**: [Tu team chat/Slack]

---

**Bienvenido al equipo! 🎉**

Cualquier duda, consulta la documentación o pregunta a un senior.

**Última actualización**: Mayo 2026
