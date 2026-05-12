# AGENTS.md – mediqueue-appointment-service

**Documento de Referencia Rápida**

Instrucciones completas disponibles en: [`.agents/docs/AGENTS.md`](./.agents/docs/AGENTS.md)

---

## 🎯 Lo Esencial

**Stack**: Java 21 • Spring Boot 3.5.14 • PostgreSQL • RabbitMQ • Redis • Flyway

**Comandos**:
```bash
mvn clean compile      # Compilar
mvn test              # Tests
mvn spring-boot:run   # Ejecutar
```

**NO** ejecutar `mvn clean package` después de cambios.

---

## 📁 Estructura

```
src/main/java/com/mediqueue/appointment/
├── config/           # Configuración Spring
├── controller/       # Endpoints REST
├── service/          # Lógica de negocio
├── repository/       # JPA
├── domain/           # Entidades JPA
├── dto/              # Data Transfer Objects
├── events/           # Event infrastructure
├── outbox/           # Patrón Outbox
├── messaging/        # RabbitMQ
└── exception/        # Manejo de errores
```

---

## ⚠️ 3 Cosas Críticas

1. **Habilitar Lombok Annotation Processing en IDE**
   - Sin esto: "symbol cannot be found" en @Getter, @Setter
   - IntelliJ: Build → Compiler → Annotation Processors → Enable

2. **Outbox Pattern: BD Primero, Luego RabbitMQ**
   - Eventos NO se envían directamente al broker
   - Guardar en DB primero; relay asíncrono los envía

3. **Flyway Migraciones**: `src/main/resources/db/migration/V{num}__{desc}.sql`

---

## 📚 Documentación

| Recurso | Ubicación |
|---------|-----------|
| Guía Completa de Agentes | [`.agents/docs/AGENTS.md`](./.agents/docs/AGENTS.md) |
| Overview del Proyecto | [`docs/README.md`](./docs/README.md) |
| Decisiones Arquitectónicas | [`docs/architecture/`](./docs/architecture/) |
| Guías Temáticas | [`docs/guides/`](./docs/guides/) |
| Patrones Java | [`.agents/docs/JAVA-GUIDE.md`](./.agents/docs/JAVA-GUIDE.md) |
| Patrones Backend | [`.agents/docs/BACKEND-PATTERNS.md`](./.agents/docs/BACKEND-PATTERNS.md) |

---

**Para agentes IA**: Leer `.agents/docs/AGENTS.md` completamente antes de codificar.

**Última actualización**: Mayo 2026
