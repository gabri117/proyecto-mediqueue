# AGENTS.md – mediqueue-appointment-service

Instrucciones críticas para agentes IA que trabajan en este proyecto. **Léan completamente antes de ejecutar cualquier código.**

## 📌 Descripción del Proyecto

**mediqueue-appointment-service** es un microservicio Spring Boot 3.5.14 para gestionar citas médicas en MediQueue.

- **Stack**: Java 21, Spring Boot 3, PostgreSQL, RabbitMQ, Redis, Flyway
- **Patrón**: Layered + Event-Driven con Outbox
- **Propósito**: Gestión escalable de citas con comunicación asíncrona

---

## 🛠️ Comandos Esenciales

```bash
# Compilar
mvn clean compile

# Tests (todos)
mvn test

# Test específico
mvn test -Dtest=NombreDelTest

# Ejecutar app
mvn spring-boot:run

# Empaquetar
mvn clean package
```

**IMPORTANTE**: NO ejecutar `mvn clean package` después de cambios. Convención del equipo.

---

## 📁 Estructura de Directorios

```
src/main/java/com/mediqueue/appointment/
├── config/              # Beans Spring, propiedades
├── controller/          # Endpoints REST
├── service/             # Lógica de negocio
├── repository/          # JPA repositories
├── domain/              # Entidades JPA
│   └── enums/           # Enums de entidades
├── dto/                 # Data Transfer Objects
├── events/              # Infraestructura de eventos
│   ├── published/       # Eventos emitidos (outbox-backed)
│   └── consumed/        # Eventos consumidos (RabbitMQ)
├── outbox/              # Patrón Outbox: almacenamiento transaccional de eventos
├── messaging/           # Productores/consumidores RabbitMQ
└── exception/           # Excepciones personalizadas y manejo global
```

---

## ⚙️ Stack Tecnológico

### Persistencia
- **JPA/Hibernate** + Spring Data JPA
- **PostgreSQL** (driver runtime)
- **Flyway** (migraciones automáticas)

### Messaging Asíncrono
- **RabbitMQ** vía Spring AMQP
- **Outbox Pattern**: BD → Async Relay → RabbitMQ
- **spring-rabbit-test**: broker embebido para tests

### Infraestructura
- **Redis**: caching, sesiones
- **Resilience4j**: circuit breakers
- **Prometheus + Micrometer**: métricas
- **Spring Actuator**: health, metrics endpoints

### Build
- **Maven 3** (mvnw incluido)
- **Lombok**: auto-genera getters, setters, constructores
  - **CRÍTICO**: IDE debe habilitar annotation processing
  - IntelliJ: Build → Compiler → Annotation Processors → Enable
- **Java 21**: records, sealed classes, pattern matching permitidos

---

## 🚨 Gotchas – Lee Esto Antes de Codificar

### 1. **Lombok Annotation Processing**
Sin esto, obtendrás "symbol cannot be found" en `@Getter`, `@Setter`, `@Builder`.

**Solución**:
- IntelliJ: Settings → Build, Execution, Deployment → Compiler → Annotation Processors → Enable
- VS Code + Extension Pack for Java: auto-habilitado generalmente

### 2. **Outbox Pattern – NO Envíes Eventos Directamente a RabbitMQ**
Los eventos deben almacenarse en BD primero. RabbitMQ los releva después.

```java
// ❌ INCORRECTO
rabbitTemplate.convertAndSend("appointment-exchange", "event", appointmentEvent);

// ✅ CORRECTO
outboxRepository.save(new OutboxEvent(appointmentEvent));
// El relay asíncrono se encargará de enviarlo a RabbitMQ
```

### 3. **Flyway Migraciones – Ubicación Exacta**
```
src/main/resources/db/migration/
├── V1__Initial_schema.sql
├── V2__Add_appointments_table.sql
└── ...
```
Nombre: `V{num}__{descripcion}.sql`. Auto-ejecutadas en startup; fallan rápido si hay conflictos.

### 4. **Spring Cloud 2025.0.2 – Versión Alta**
Revisar compatibilidad antes de agregar dependencias cloud nuevas.

### 5. **Ningún Build Después de Cambios**
Convención del equipo: NO ejecutar `mvn clean package`.

---

## 🧪 Testing

- **Framework**: JUnit 5 (spring-boot-starter-test)
- **Mocking**: Mockito
- **RabbitMQ**: spring-rabbit-test (embedded broker)
- **Estructura**: `src/test/java/com/mediqueue/appointment/` espeja `src/main/`

```bash
mvn test                          # Todos
mvn test -Dtest=AppointmentTest   # Específico
```

---

## 📐 Convenciones de Código

### Naming
- **DTOs**: `{Entity}DTO` (e.g., `AppointmentDTO`, `CreateAppointmentRequestDTO`)
- **Entities**: Nombres singulares del dominio (e.g., `Appointment`, `Patient`, `Slot`)
- **Services**: `{Entity}Service` (e.g., `AppointmentService`)
- **Repositories**: `{Entity}Repository` extiende `JpaRepository<Entity, ID>`

### Lombok Usage
```java
@Data
@Builder
@AllArgsConstructor
@NoArgsConstructor
public class Appointment {
    private UUID id;
    private String title;
    // getters, setters, constructors autogenerados
}
```

### Service Layer
- Single responsibility
- Composición sobre herencia
- Inyección de dependencias via constructor

### Repositories
```java
public interface AppointmentRepository extends JpaRepository<Appointment, UUID> {
    List<Appointment> findByPatientId(UUID patientId);
    
    @Query("SELECT a FROM Appointment a WHERE a.status = :status")
    List<Appointment> findByCustomStatus(@Param("status") String status);
}
```

---

## 📚 Documentación de Referencia

| Archivo | Propósito |
|---------|----------|
| [`docs/README.md`](../../docs/README.md) | Overview del proyecto |
| [`docs/architecture/`](../../docs/architecture/) | Decisiones arquitectónicas (ADRs) |
| [`docs/guides/`](../../docs/guides/) | Guías temáticas |
| [`.agents/docs/JAVA-GUIDE.md`](./JAVA-GUIDE.md) | Patrones Java específicos |
| [`.agents/docs/BACKEND-PATTERNS.md`](./BACKEND-PATTERNS.md) | Patrones backend |
| [`HELP.md`](../../HELP.md) | Referencias de Spring Boot |

---

## ✅ Checklist Antes de Codificar

- [ ] Lombok annotation processing habilitado en IDE
- [ ] Conoces la diferencia entre entities, DTOs, y domain events
- [ ] Entiendes el patrón Outbox (eventos en BD primero)
- [ ] Migraciones Flyway en ubicación correcta: `src/main/resources/db/migration/`
- [ ] No vas a ejecutar `mvn clean package` después de cambios
- [ ] Tests ejecutados: `mvn test`

---

## 🔧 Troubleshooting Rápido

| Problema | Solución |
|----------|----------|
| "symbol cannot be found" en @Getter/@Setter | Habilitar annotation processing (ver Gotcha #1) |
| Tests fallan con RabbitMQ | Usar spring-rabbit-test; broker embebido en tests |
| Migraciones no ejecutadas | Verificar `src/main/resources/db/migration/` naming (V{num}__) |
| Error de versión Spring Cloud | Revisar pom.xml; versión actual 2025.0.2 |

---

**Última actualización**: Mayo 2026  
**Versión**: 1.0  
**Audiencia**: Agentes IA, desarrolladores de backend
