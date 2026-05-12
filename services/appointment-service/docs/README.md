# MediQueue Appointment Service

Microservicio escalable y basado en eventos para la gestión de citas médicas en la plataforma MediQueue.

## 📋 Descripción General

**mediqueue-appointment-service** es un servicio backend que implementa la lógica de negocio para la gestión de citas médicas en un sistema de salud. Está diseñado como parte de una arquitectura de microservicios con comunicación asíncrona mediante RabbitMQ.

### Propósito
- Gestionar el ciclo de vida completo de citas médicas
- Eventos síncronos entre citas y otros servicios
- Patrón Outbox para garantizar consistencia eventual
- Resiliencia mediante circuit breakers (Resilience4j)
- Monitoreo con métricas Prometheus

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────┐
│   REST API Controllers                      │
│   (appointments, scheduling, etc.)          │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│   Business Logic (Services)                 │
│   (rules, validations, events)              │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│   Data Access (Repositories)                │
│   (JPA, Entities, Queries)                  │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│   Persistence Layer                         │
│   PostgreSQL + Flyway Migrations            │
└─────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│   Event-Driven (Outbox Pattern)             │
│   ├─ Publish events (to outbox table)       │
│   ├─ Async relay to RabbitMQ                │
│   └─ Consume events from broker             │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│   Infrastructure                            │
│   ├─ Redis (caching, sessions)              │
│   ├─ Resilience4j (circuit breakers)        │
│   └─ Prometheus (metrics)                   │
└──────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Requisitos
- Java 21+
- Maven 3.9+
- PostgreSQL 14+
- RabbitMQ (para eventos)
- Redis (opcional, para caching)

### Comandos Básicos

```bash
# Compilar
mvn clean compile

# Ejecutar tests
mvn test

# Ejecutar aplicación
mvn spring-boot:run

# Empaquetar
mvn clean package
```

Más detalles: [AGENTS.md](../AGENTS.md)

## 📁 Estructura del Proyecto

```
mediqueue-appointment-service/
├── docs/                          # Documentación para desarrolladores
│   ├── README.md                  # Este archivo
│   ├── architecture/              # Decisiones arquitectónicas (ADRs)
│   └── guides/                    # Guías temáticas
├── .agents/                       # Instrucciones para agentes IA
│   ├── AGENTS.md                  # Configuración global de agentes
│   └── docs/                      # Documentación específica para agentes
├── src/
│   ├── main/java/com/mediqueue/appointment/
│   │   ├── config/                # Configuración Spring
│   │   ├── controller/            # Endpoints REST
│   │   ├── service/               # Lógica de negocio
│   │   ├── repository/            # Acceso a datos (JPA)
│   │   ├── domain/                # Entidades JPA
│   │   ├── dto/                   # Data Transfer Objects
│   │   ├── events/                # Infraestructura de eventos
│   │   ├── outbox/                # Patrón Outbox
│   │   ├── messaging/             # RabbitMQ producers/consumers
│   │   └── exception/             # Manejo de excepciones
│   └── test/                      # Tests unitarios e integración
├── pom.xml                        # Configuración Maven
└── AGENTS.md                      # Instrucciones para agentes (raíz del proyecto)
```

## 🔧 Stack Tecnológico

| Componente | Tecnología | Versión |
|-----------|-----------|---------|
| Lenguaje | Java | 21 |
| Framework | Spring Boot | 3.5.14 |
| BD | PostgreSQL | 14+ |
| Messaging | RabbitMQ | 3.x |
| Caché | Redis | 6.x+ |
| Migraciones | Flyway | Latest |
| Monitoreo | Prometheus + Micrometer | Latest |
| Resiliencia | Resilience4j | Latest |

## 📚 Documentación

- **[AGENTS.md](../AGENTS.md)** - Instrucciones específicas para agentes IA
- **[docs/architecture/](./architecture/)** - Decisiones arquitectónicas (ADRs)
- **[docs/guides/](./guides/)** - Guías temáticas (Java, Testing, etc.)
- **[.agents/docs/](../.agents/docs/)** - Documentación de agentes

## 🧪 Testing

- **Framework**: JUnit 5
- **Mocking**: Mockito
- **RabbitMQ Testing**: spring-rabbit-test (embedded broker)
- **Estructura**: Mirrors `src/main/` structure

Ejecutar tests:
```bash
mvn test                           # Todos los tests
mvn test -Dtest=YourTestClass      # Test específico
```

## 🔐 Convenciones de Código

- **Lombok**: Usar `@Data`, `@Builder`, `@AllArgsConstructor`
- **DTOs**: Nombrar `{Entity}DTO` (e.g., `AppointmentDTO`)
- **Entidades**: Nombres singulares que representen el concepto del dominio
- **Services**: Single responsibility principle
- **Repositories**: Extender `JpaRepository<Entity, ID>`

Más detalles: [AGENTS.md](../AGENTS.md) → Sección "Code Style & Conventions"

## ⚠️ Gotchas Importantes

1. **Lombok**: Habilitar annotation processing en IDE
2. **Outbox Pattern**: Eventos NO se envían directamente a RabbitMQ
3. **Flyway**: Migraciones en `src/main/resources/db/migration/`
4. **Spring Cloud**: Versión 2025.0.2 (revisar compatibilidad al agregar deps)

Detalles: [AGENTS.md](../AGENTS.md) → Sección "Common Gotchas"

## 🤝 Contribuir

Antes de hacer cambios:
1. Lee [AGENTS.md](../AGENTS.md) para convenciones
2. Consulta [docs/guides/](./guides/) para patrones específicos
3. Ejecuta tests: `mvn test`
4. No empaques (no ejecutes `mvn clean package`)

## 📞 Soporte

- **Bugs**: Reportar en GitHub Issues
- **Preguntas**: Consulta primero la documentación en `docs/` y `.agents/docs/`
- **Skills de IA**: Verificar `.agents/skills/` para herramientas especializadas

---

**Última actualización**: Mayo 2026  
**Mantenedor**: MediQueue Team
