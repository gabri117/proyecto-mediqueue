---
name: postgresql-hibernate-migration
description: 'Guía de resolución de problemas de compilación, mapeo de enums nativos de PostgreSQL, configuración de Docker Compose, volúmenes, dependencias de Maven y healthchecks.'
---

# PostgreSQL & Hibernate Migration Skill Guide

Esta guía documenta los aprendizajes, resoluciones de conflictos y estándares técnicos establecidos en el proyecto `mediqueue-appointment-service` para el manejo de contenedores, mapeo de enums, configuración de base de datos y dependencias críticas. Está diseñada para que tanto tú (agente IA) como otros desarrolladores puedan solventar rápidamente problemas similares de integración entre PostgreSQL, Flyway y Spring Boot Hibernate.

---

## 1. Configuración de Contenedores y Red local (Docker Compose)

Para levantar el servicio de citas junto con sus dependencias de manera local y aislada, se utiliza un archivo `docker-compose.yml` en la raíz del proyecto.

### Arquitectura de Servicios:
- **`postgres-appointment`**: PostgreSQL 16 (Alpine). Expuesto en puerto `5435` local para evitar colisiones con otras instancias de PostgreSQL en el puerto por defecto `5432`.
- **`rabbitmq`**: RabbitMQ 3.12 con consola de administración (`management`). Expone el puerto AMQP `5672` y la interfaz web en `15672`.
- **`appointment-service`**: La aplicación Spring Boot construida dinámicamente mediante el `Dockerfile`.

### Bloque de Docker Compose Clave:
```yaml
version: '3.8'

services:
  postgres-appointment:
    image: postgres:16-alpine
    container_name: mediqueue-postgres-appointment
    environment:
      POSTGRES_DB: mediqueue_appointment
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5435:5432"
    volumes:
      - postgres_appointment_data:/var/lib/postgresql/data
    networks:
      - mediqueue-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d mediqueue_appointment"]
      interval: 10s
      timeout: 5s
      retries: 5

  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    container_name: mediqueue-rabbitmq
    ports:
      - "5672:5672"
      - "15672:15672"
    networks:
      - mediqueue-network
    healthcheck:
      test: ["CMD-SHELL", "rabbitmq-diagnostics ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  appointment-service:
    build: .
    container_name: mediqueue-appointment-service
    ports:
      - "8083:8083"
    environment:
      - SPRING_DATASOURCE_URL=jdbc:postgresql://postgres-appointment:5432/mediqueue_appointment
      - SPRING_DATASOURCE_USERNAME=postgres
      - SPRING_DATASOURCE_PASSWORD=postgres
      - SPRING_RABBITMQ_HOST=rabbitmq
      - SPRING_RABBITMQ_PORT=5672
      - SPRING_RABBITMQ_USERNAME=guest
      - SPRING_RABBITMQ_PASSWORD=guest
    depends_on:
      postgres-appointment:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    networks:
      - mediqueue-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8083/actuator/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  mediqueue-network:
    name: mediqueue-network

volumes:
  postgres_appointment_data:
```

> [!IMPORTANT]
> - El `appointment-service` utiliza un `depends_on` con la condición `service_healthy`. Esto garantiza que la aplicación Spring Boot no intente arrancar hasta que PostgreSQL y RabbitMQ estén completamente listos para recibir conexiones.
> - El healthcheck de `appointment-service` depende de **Actuator** (`/actuator/health`). Si esta dependencia es removida, el healthcheck fallará constantemente y el contenedor reportará un estado `unhealthy`.

---

## 2. El Conflicto de PostgreSQL Custom Enums vs. Hibernate

### El Problema Root Cause
PostgreSQL soporta enums nativos en base de datos mediante comandos DDL del tipo:
```sql
CREATE TYPE appointment_status AS ENUM ('PENDING_PAYMENT', 'CONFIRMED', 'CANCELLED', 'EXPIRED');
```
Sin embargo, cuando Hibernate genera las sentencias de consulta (JPQL / HQL) para comparar campos de enums, intenta realizar un binding estándar de strings (`character varying`). PostgreSQL rechaza tajantemente esta comparación sin un casteo explícito, arrojando errores como:
```
ERROR: operator does not exist: outbox_publication_status = character varying
```
Si intentas solventar esto usando implementaciones JPA de `AttributeConverter<Enum, PGobject>` (para envolver el enum en un objeto nativo de Postgres), Hibernate 6+ puede arrojar problemas secundarios mapeando los tipos de parámetros de consulta como `bytea`, resultando en:
```
ERROR: operator does not exist: outbox_publication_status = bytea
```

### La Solución Más Simple y Robusta: `VARCHAR(30)`
La mejor práctica en entornos empresariales de alto rendimiento para evitar la fricción entre Hibernate y los enums nativos de PostgreSQL es **usar tipos de datos estándar en la base de datos (`VARCHAR`) y mapear en Java a través de anotaciones nativas de JPA**. Esto simplifica las consultas y asegura portabilidad absoluta.

#### 1. Modificación en la Migración Flyway (`V1__appointment_service_init.sql`):
Se eliminan todos los bloques `CREATE TYPE ... AS ENUM` y se definen las columnas de las tablas directamente como `VARCHAR(30)` con sus correspondientes valores predeterminados de tipo string:

```sql
-- TABLA: appointments
appointment_status  VARCHAR(30) NOT NULL DEFAULT 'PENDING_PAYMENT'

-- TABLA: appointment_holds
hold_status     VARCHAR(30) NOT NULL DEFAULT 'ACTIVE'

-- TABLA: appointment_audit
previous_status   VARCHAR(30),
new_status        VARCHAR(30) NOT NULL

-- TABLA: idempotency_keys
status              VARCHAR(30) NOT NULL DEFAULT 'PROCESSING'

-- TABLA: outbox_events
publication_status  VARCHAR(30) NOT NULL DEFAULT 'PENDING'
```

#### 2. Mapeo Limpio en las Entidades Java de Spring Boot:
En cada una de las entidades JPA, se utiliza la anotación `@Enumerated(EnumType.STRING)` para que Hibernate guarde el enum de Java como un simple `String` de manera automática y transparente.

```java
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Column;

// Ejemplo en la clase Appointment:
@Enumerated(EnumType.STRING)
@Column(name = "appointment_status", nullable = false)
private AppointmentStatus appointmentStatus = AppointmentStatus.PENDING_PAYMENT;
```

> [!TIP]
> Al migrar de un Enum Nativo o un Converter personalizado hacia `@Enumerated(EnumType.STRING)`, recuerda:
> - Eliminar cualquier anotación `@Convert(converter = ...)` en los campos.
> - Eliminar las clases conversoras redundantes (por ejemplo, `*Converter.java`) para mantener el código limpio.
> - Asegurar que el campo `@Column` no tenga configuraciones explícitas de `columnDefinition` que referencien tipos de datos obsoletos.

---

## 3. Manejo de Dependencias Críticas en `pom.xml`

### PostgreSQL Runtime vs. Compile Scope
Cuando creas un proyecto de Spring Boot desde el Initializr, por defecto se configura la dependencia del driver de base de datos de PostgreSQL con un ámbito `runtime`:
```xml
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>
```
Esto es excelente si solo interactúas con la base de datos a través de la abstracción de JDBC y JPA. No obstante, **si por alguna razón tu código Java necesita importar de manera explícita clases pertenecientes al driver de PostgreSQL** (por ejemplo, `org.postgresql.util.PGobject` para conversores), el compilador de Java fallará con el error:
```
The import org.postgresql cannot be resolved
```
**Resolución:** Remueve la etiqueta `<scope>runtime</scope>` para permitir que el driver esté disponible bajo el scope de compilación por defecto (`compile`).

### Actuator & Monitoreo
Para habilitar los healthchecks requeridos por Docker Compose y asegurar un ciclo de vida sano en microservicios, el `pom.xml` debe contener las dependencias de monitoreo de Spring Boot:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
    <scope>runtime</scope>
</dependency>
```

---

## 4. Resetear y Regenerar Entornos Locales

Cuando se modifica la migración base de Flyway (`V1__...sql`), es **MANDATORIO** purgar los volúmenes asociados para asegurar que la base de datos se reconstruya desde cero con el nuevo DDL. De lo contrario, PostgreSQL intentará reutilizar los volúmenes antiguos y Flyway fallará por discrepancias de firmas en los scripts (`Migration checksum mismatch`).

### Flujo de Comandos de Rescate:
1. **Detener y purgar volúmenes**:
   ```bash
   docker compose down -v
   ```
   *(La bandera `-v` elimina de forma segura el volumen local `postgres_appointment_data` mapeado para la base de datos).*

2. **Reconstruir imágenes y levantar de forma asíncrona**:
   ```bash
   docker compose up --build -d
   ```
   *(La bandera `--build` fuerza a Docker a compilar de nuevo el JAR localmente usando el Dockerfile y a registrar el nuevo compilado de dependencias).*

3. **Verificar que el arranque y la migración Flyway sean exitosos**:
   ```bash
   docker compose ps
   docker compose logs appointment-service -f
   ```
