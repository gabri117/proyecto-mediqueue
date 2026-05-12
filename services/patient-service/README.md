# MediQueue Patient Service

Microservicio de gestión de pacientes para el sistema MediQueue, desarrollado con Spring Boot 3.5.14, PostgreSQL y Flyway.

---

# Tecnologías Utilizadas

* Java 21
* Spring Boot 3.5.14
* Spring Data JPA
* PostgreSQL
* Flyway Migration
* Maven
* Docker PostgreSQL
* Lombok
* Validation
* Postman

---

# Arquitectura del Proyecto

```text
com.mediqueue.patient

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

## Gestión de Pacientes

* Crear pacientes
* Buscar paciente por ID
* Buscar paciente por email
* Desactivar paciente
* Reactivar paciente

---

# Base de Datos

## Tabla principal

```text
patients
```

## Características

* UUID como llave primaria
* ENUM PostgreSQL para estado
* Constraints UNIQUE
* Timestamps automáticos
* Trigger para updated_at
* Índices para optimización

---

# Endpoints REST

## Crear paciente

```http
POST /patients
```

### Request

```json
{
  "firstName": "Riquelme",
  "lastName": "Gomez",
  "email": "riquelme@gmail.com",
  "phone": "55555555",
  "documentNumber": "123456789"
}
```

### Response

```json
{
  "patientId": "uuid",
  "firstName": "Riquelme",
  "lastName": "Gomez",
  "email": "riquelme@gmail.com",
  "phone": "55555555",
  "documentNumber": "123456789",
  "status": "ACTIVE",
  "createdAt": "2026-05-06T11:06:06",
  "updatedAt": "2026-05-06T11:06:06"
}
```

---

## Buscar paciente por ID

```http
GET /patients/{id}
```

---

## Buscar paciente por email

```http
GET /patients?email=correo@gmail.com
```

---

## Desactivar paciente

```http
PATCH /patients/{id}/deactivate
```

---

## Reactivar paciente

```http
PATCH /patients/{id}/activate
```

---

# Validaciones

El sistema incluye validaciones automáticas:

* First name requerido
* Last name requerido
* Email requerido
* Formato de email válido
* Document number requerido
* Email único
* Document number único

---

# Manejo Global de Errores

## Respuestas implementadas

| Código HTTP | Descripción           |
| ----------- | --------------------- |
| 400         | Validation Error      |
| 404         | Patient Not Found     |
| 409         | Conflict              |
| 500         | Internal Server Error |

---

# Configuración del Proyecto

## Puerto

```properties
server.port=8081
```

## Base de Datos PostgreSQL

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/mediqueue_patient
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
V1__patient_service_init.sql
```

---

# Pruebas

Las pruebas de endpoints fueron realizadas utilizando Postman.

Pruebas realizadas:

* Creación de pacientes
* Consulta por ID
* Consulta por email
* Desactivación
* Reactivación
* Validación de duplicados
* Validación de campos obligatorios

---

Proyecto MediQueue - Universidad Mariano Gálvez
