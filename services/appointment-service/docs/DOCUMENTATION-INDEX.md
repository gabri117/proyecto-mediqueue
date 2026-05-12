# Documentation Index – mediqueue-appointment-service

Índice centralizado para navegar la documentación del proyecto.

---

## 🗺️ Mapa de Documentación

### Para Agentes IA 🤖

| Archivo | Propósito | Audience |
|---------|-----------|----------|
| [**AGENTS.md**](./AGENTS.md) (raíz) | Quick reference - instrucciones críticas | Agentes + Devs |
| [**.agents/docs/AGENTS.md**](./.agents/docs/AGENTS.md) | Guía completa para agentes | Agentes |
| [**.agents/docs/JAVA-GUIDE.md**](./.agents/docs/JAVA-GUIDE.md) | Patrones y estándares Java 21 | Agentes + Devs |
| [**.agents/docs/BACKEND-PATTERNS.md**](./.agents/docs/BACKEND-PATTERNS.md) | Arquitectura, Outbox, Events, etc. | Agentes + Devs |

### Para Desarrolladores 👨‍💻

| Archivo | Propósito | Audience |
|---------|-----------|----------|
| [**docs/GETTING-STARTED.md**](./docs/GETTING-STARTED.md) | Guía de bienvenida, primeros pasos | Nuevos Devs |
| [**docs/README.md**](./docs/README.md) | Overview del proyecto, stack, quick start | Todos |
| [**docs/architecture/**](./docs/architecture/) | Decisiones arquitectónicas (ADRs) | Arquitectos, Leads |
| [**docs/guides/**](./docs/guides/) | Guías temáticas (Testing, CI/CD, etc.) | Devs específicos |
| [**HELP.md**](./HELP.md) | Referencias de Spring Boot (auto-generated) | Devs |

---

## 📖 Cómo Navegar

### Caso 1: Acabo de Llegar al Proyecto (NUEVO DEVELOPER)

1. Lee [**docs/GETTING-STARTED.md**](./docs/GETTING-STARTED.md) (10 min) - Bienvenida y primeros pasos
2. Lee [**docs/README.md**](./docs/README.md) (5 min) - Overview
3. Lee [**AGENTS.md**](./AGENTS.md) (raíz, 3 min) - Comandos críticos
4. Examina la estructura en `src/main/java/com/mediqueue/appointment/`

### Caso 2: Soy Agente IA y Necesito Codificar

1. Lee [**.agents/docs/AGENTS.md**](./.agents/docs/AGENTS.md) (10 min) - Completo
2. Consulta [**.agents/docs/JAVA-GUIDE.md**](./.agents/docs/JAVA-GUIDE.md) - Patrones Java
3. Consulta [**.agents/docs/BACKEND-PATTERNS.md**](./.agents/docs/BACKEND-PATTERNS.md) - Arquitectura

### Caso 3: Necesito Entender Cómo Funcionan los Eventos

→ [**.agents/docs/BACKEND-PATTERNS.md**](./.agents/docs/BACKEND-PATTERNS.md) → Secciones "Patrón Outbox" y "Event-Driven Design"

### Caso 4: Necesito Saber Comandos Maven

→ [**AGENTS.md**](./AGENTS.md) (raíz) → Sección "Comandos Esenciales"

### Caso 5: Tengo un Error en Lombok

→ [**.agents/docs/AGENTS.md**](./.agents/docs/AGENTS.md) → Sección "Gotchas" → #1

### Caso 6: Necesito Escribir Tests

→ **docs/guides/** (cuando esté disponible)

---

## 📋 Estructura de Carpetas

```
mediqueue-appointment-service/
│
├── AGENTS.md (raíz)           ← Quick reference para todos
│
├── docs/                      ← Documentación para devs
│   ├── README.md              ← Overview del proyecto
│   ├── architecture/          ← ADRs (Architectural Decision Records)
│   │   └── (vacío ahora, agregar según necesidad)
│   └── guides/                ← Guías temáticas
│       └── (Testing, CI/CD, etc.)
│
├── .agents/docs/              ← Documentación para agentes
│   ├── AGENTS.md              ← Guía completa de agentes
│   ├── JAVA-GUIDE.md          ← Patrones Java 21 + Spring Boot
│   └── BACKEND-PATTERNS.md    ← Outbox, Events, Transacciones, etc.
│
├── .agents/skills/            ← Skills customizados del proyecto
│   ├── java-coding-standards/
│   ├── java-docs/
│   ├── java-springboot/
│   └── security-privacy/
│
├── HELP.md                    ← Referencias Spring Boot (auto-generated)
└── pom.xml                    ← Configuración Maven
```

---

## 🔍 Búsqueda Rápida

### Por Tema

| Tema | Ubicación |
|------|-----------|
| **Java Coding Standards** | [.agents/docs/JAVA-GUIDE.md](./.agents/docs/JAVA-GUIDE.md) |
| **Outbox Pattern** | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#patrón-outbox) |
| **Event-Driven Design** | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#event-driven-design) |
| **RabbitMQ Config** | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#rabbitmq-configuration) |
| **Transacciones JPA** | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#transacciones-y-consistency) |
| **Redis Caching** | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#caching-con-redis) |
| **Circuit Breakers** | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#circuit-breakers-resilience4j) |
| **Lombok Usage** | [.agents/docs/JAVA-GUIDE.md](./.agents/docs/JAVA-GUIDE.md#lombok-usage) |
| **Naming Conventions** | [.agents/docs/JAVA-GUIDE.md](./.agents/docs/JAVA-GUIDE.md#convenciones-de-nombrado) |
| **Maven Commands** | [AGENTS.md](./AGENTS.md#-comandos-esenciales) |

### Por Problema

| Problema | Solución |
|----------|----------|
| "symbol cannot be found" en @Getter/@Setter | [AGENTS.md](./AGENTS.md#-3-cosas-críticas) → Gotcha #1 |
| ¿Cómo envío eventos a RabbitMQ? | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#patrón-outbox) |
| ¿Dónde pongo las migraciones Flyway? | [AGENTS.md](./AGENTS.md#-3-cosas-críticas) → Gotcha #3 |
| ¿Cómo creo un servicio? | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#arquitectura-layered) |
| ¿Cuáles son las convenciones de naming? | [.agents/docs/JAVA-GUIDE.md](./.agents/docs/JAVA-GUIDE.md#convenciones-de-nombrado) |
| ¿Cómo valido entrada en DTOs? | [.agents/docs/BACKEND-PATTERNS.md](./.agents/docs/BACKEND-PATTERNS.md#dtos-y-mapping) |

---

## 📝 Metadata de Documentación

| Archivo | Última Actualización | Versión | Audiencia |
|---------|--------------------|---------|---------| 
| docs/GETTING-STARTED.md | Mayo 2026 | 1.0 | Nuevos Devs |
| docs/README.md | Mayo 2026 | 1.0 | Todos |
| AGENTS.md (raíz) | Mayo 2026 | 1.0 | Todos |
| .agents/docs/AGENTS.md | Mayo 2026 | 1.0 | Agentes |
| .agents/docs/JAVA-GUIDE.md | Mayo 2026 | 1.0 | Agentes + Devs |
| .agents/docs/BACKEND-PATTERNS.md | Mayo 2026 | 1.0 | Agentes + Devs |

---

## 🔄 Flujo de Referencia Típico

```
Agente IA o Developer
        ↓
        └─→ "¿Por dónde empiezo?" → docs/README.md
        ├─→ "¿Qué comandos?" → AGENTS.md (raíz)
        ├─→ "¿Cómo codifico?" → .agents/docs/JAVA-GUIDE.md
        ├─→ "¿Cómo es la arquitectura?" → .agents/docs/BACKEND-PATTERNS.md
        └─→ "¿Dónde está X?" → Usa tabla "Búsqueda Rápida" arriba
```

---

## ✅ Checklist de Documentación

- [x] `docs/GETTING-STARTED.md` - Guía de bienvenida para nuevos devs
- [x] `docs/README.md` - Overview y quick start
- [x] `AGENTS.md` (raíz) - Quick reference
- [x] `.agents/docs/AGENTS.md` - Guía completa para agentes
- [x] `.agents/docs/JAVA-GUIDE.md` - Patrones Java
- [x] `.agents/docs/BACKEND-PATTERNS.md` - Arquitectura backend
- [x] `docs/architecture/` - ADRs con ejemplo (ADR-001)
- [ ] `docs/guides/` - Guías temáticas (Testing, CI/CD, etc. - agregar según necesidad)

---

## 📞 Contribuir a la Documentación

Si agregas nueva documentación:

1. Crea el archivo en la carpeta apropiada (`docs/`, `.agents/docs/`, etc.)
2. Agrega metadata: "Última actualización", "Versión", "Audiencia"
3. Actualiza este índice en la tabla correspondiente
4. Asegúrate de que los links sean relativos y funcionen

---

**Última actualización**: Mayo 2026  
**Mantenedor**: MediQueue Team
