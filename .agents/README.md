# .agents/ — AI Agent Skills

Guías de contexto para agentes AI que trabajen en este monorepo.

## Skills disponibles

| Skill | Descripción |
|-------|-------------|
| [build.md](skills/build.md) | Cómo compilar el monorepo (Maven multi-module) |
| [docker.md](skills/docker.md) | Cómo levantar el stack completo con Docker Compose |
| [new-service.md](skills/new-service.md) | Pasos para agregar un nuevo microservicio al monorepo |
| [security.md](skills/security.md) | Reglas de seguridad, secretos y prevención de fugas de credenciales |
| [troubleshooting.md](skills/troubleshooting.md) | Errores comunes y sus soluciones |

## Convenciones del proyecto

- **Spring Boot**: 3.5.14
- **Java**: 21
- **Spring Cloud**: 2025.0.2
- **Empaquetado**: Maven multi-module con POM padre en la raíz
- **Restricción**: NUNCA modificar `src/` sin aprobación explícita
- **Restricción**: NUNCA modificar `application.properties` / `application.yml` existentes
