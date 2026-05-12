# MediQueue Schedule Service

Microservicio de gestión de odontólogos y disponibilidad de horarios para el sistema MediQueue, desarrollado con Spring Boot 3.5.14, PostgreSQL y Flyway.

---

# Tecnologías Utilizadas

* Java 17
* Spring Boot 3.5.14
* Spring Data JPA
* PostgreSQL
* Flyway Migration
* Maven
* Docker PostgreSQL
* Lombok
* Validation
* Hibernate 6
* Postman
* DBeaver

---

# Arquitectura del Proyecto

```text
com.mediqueue.schedule

├── controller
├── service
├── repository
├── domain
│   └── enums
├── dto
├── exception
```

---

# Funcionalidades

## Gestión de Odontólogos

* Crear odontólogos
* Buscar odontólogo por ID
* Buscar odontólogo por email
* Desactivar odontólogo
* Reactivar odontólogo

---

## Gestión de Slots

* Crear slots de atención
* Buscar slot por ID
* Obtener slots por odontólogo
* Obtener slots disponibles
* Bloquear slots
* Reactivar slots

---

# Base de Datos

## Tablas principales

```text
dentists
dentist_working_hours
dentist_slots
```

## Características

* UUID como llave primaria
* ENUM PostgreSQL para estados
* Constraints UNIQUE
* Relaciones con Foreign Keys
* Timestamps automáticos
* Trigger para updated_at
* Índices para optimización
* Validación de horarios

---

# Estados Implementados

## Dentist Status

```text
ACTIVE
INACTIVE
```

## Slot Display Status

Estados soportados por el sistema:

- AVAILABLE
- HELD
- BOOKED
- BLOCKED

Actualmente implementados en schedule-service:

- AVAILABLE
- BLOCKED

---

# Endpoints REST

# Dentists

## Crear odontólogo

```http
POST /dentists
```

### Request

```json
{
  "firstName": "Carlos",
  "lastName": "Lopez",
  "licenseNumber": "OD-1001",
  "specialty": "ORTODONCIA",
  "email": "carlos@clinic.com"
}
```

### Response

```json
{
  "dentistId": "uuid",
  "firstName": "Carlos",
  "lastName": "Lopez",
  "specialty": "ORTODONCIA",
  "email": "carlos@clinic.com",
  "licenseNumber": "OD-1001",
  "status": "ACTIVE",
  "createdAt": "2026-05-08T15:44:17",
  "updatedAt": "2026-05-08T15:44:17"
}
```

---

## Buscar odontólogo por ID

```http
GET /dentists/{id}
```

---

## Buscar odontólogo por email

```http
GET /dentists?email=carlos@clinic.com
```

---

## Desactivar odontólogo

```http
PATCH /dentists/{id}/deactivate
```

---

## Reactivar odontólogo

```http
PATCH /dentists/{id}/activate
```

---

# Slots

## Crear slot

```http
POST /slots
```

### Request

```json
{
  "dentistId": "uuid",
  "slotDate": "2026-05-10",
  "startTime": "09:00",
  "endTime": "09:30"
}
```

### Response

```json
{
  "slotId": "uuid",
  "dentistId": "uuid",
  "slotDate": "2026-05-10",
  "startTime": "09:00",
  "endTime": "09:30",
  "status": "AVAILABLE",
  "createdAt": "2026-05-08T15:50:00",
  "updatedAt": "2026-05-08T15:50:00"
}
```

---

## Buscar slot por ID

```http
GET /slots/{id}
```

---

## Obtener slots por odontólogo

```http
GET /slots/dentist/{dentistId}
```

---

## Obtener slots disponibles

```http
GET /slots/available
```

---

## Desactivar slot

```http
PATCH /slots/{id}/deactivate
```

---

## Reactivar slot

```http
PATCH /slots/{id}/activate
```

---

# Validaciones

El sistema incluye validaciones automáticas:

## Dentists

* First name requerido
* Last name requerido
* License number requerido
* Email requerido
* Formato de email válido
* Email único
* License number único

## Slots

* Dentist ID requerido
* Fecha requerida
* Hora inicio requerida
* Hora fin requerida
* Restricción UNIQUE para slots repetidos
* Validación de horarios

---

# Manejo Global de Errores

## Respuestas implementadas

| Código HTTP | Descripción                |
| ----------- | -------------------------- |
| 400         | Validation Error           |
| 404         | Resource Not Found         |
| 409         | Conflict                   |
| 500         | Internal Server Error      |

---

# Configuración del Proyecto

## Puerto

```properties
server.port=8082
```

## Base de Datos PostgreSQL

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/mediqueue_schedule
spring.datasource.username=postgres
spring.datasource.password=TU_PASSWORD
```

---

# Ejecución del Proyecto

## Levantar PostgreSQL Docker

```bash
docker start mi-postgres
```

## Ejecutar Spring Boot

```bash
./mvnw spring-boot:run
```

---

# Migraciones Flyway

Las migraciones SQL se encuentran en:

```text
src/main/resources/db/migration
```

Archivo principal:

```text
V1__schedule_service_init.sql
```

---

# Pruebas

Las pruebas de endpoints fueron realizadas utilizando Postman.

Pruebas realizadas:

## Dentists 

* Creación de odontólogos
* Consulta por ID
* Consulta por email
* Desactivación
* Reactivación
* Validación de duplicados
* Validación de campos obligatorios

## Slots

* Creación de slots
* Consulta de slots disponibles
* Consulta por odontólogo
* Desactivación de slots
* Reactivación de slots
* Validación de ENUM PostgreSQL
* Validación de slots duplicados

---


Proyecto MediQueue - Universidad Mariano Gálvez