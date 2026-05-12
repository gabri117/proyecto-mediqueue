# Skill: Build del Monorepo

## Stack

- **Maven** 3.9+ (multi-module reactor)
- **Java** 21 (Temurin)
- **Spring Boot** 3.5.14
- **Spring Cloud** 2025.0.2

## Estructura de módulos

```
pom.xml (padre — com.mediqueue.platform:mediqueue-platform)
├── packages/shared-lib          → com.mediqueue.platform:shared-lib
├── services/api-gateway         → com.mediqueue:mediqueue-api-gateway
├── services/appointment-service → com.mediqueue:mediqueue-appointment-service
├── services/notification-service → com.mediqueue:mediqueue-notification-service
├── services/payment-service     → com.mediqueue:payment.service
├── services/patient-service     → com.mediqueue:mediqueue-patient-service
└── services/schedule-service    → com.mediqueue:mediqueue-schedule-service
```

> **Nota**: `payment-service` tiene artifactId `payment.service` (con punto) por herencia del proyecto original. NO cambiar sin refactor completo.

## Comandos

```bash
# Compilar TODO el monorepo
mvn clean install -DskipTests

# Compilar un servicio específico y sus dependencias
mvn -pl services/appointment-service -am clean package -DskipTests

# Compilar solo shared-lib
mvn -pl packages/shared-lib clean install -DskipTests

# Ejecutar tests de un servicio
mvn -pl services/patient-service test
```

## Gestión de versiones centralizada

El POM padre centraliza estas versiones vía `<properties>` y `<dependencyManagement>`:

| Propiedad | Valor | Uso |
|-----------|-------|-----|
| `java.version` | 21 | Compilador Java |
| `spring-cloud.version` | 2025.0.2 | BOM de Spring Cloud |
| `resilience4j.version` | 2.2.0 | Circuit breakers (notification-service) |

Lombok, Flyway, PostgreSQL driver y demás vienen gestionados por el BOM de `spring-boot-starter-parent`.

## Reglas

- Los servicios **NO declaran** `<version>` propia (heredan del padre).
- Los servicios **NO declaran** `<dependencyManagement>` para Spring Cloud (heredan del padre).
- Los servicios apuntan al padre con `<relativePath>../../pom.xml</relativePath>`.
- `shared-lib` se compila PRIMERO (aparece primero en `<modules>`).
