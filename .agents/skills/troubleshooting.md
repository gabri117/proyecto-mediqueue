# Skill: Troubleshooting

## Errores comunes y soluciones

### 1. "Could not find artifact com.mediqueue.platform:mediqueue-platform"

**Causa**: El POM padre no está instalado en el repositorio local de Maven.

**Solución**:
```bash
# Instalar el padre primero
mvn -N install
# Luego compilar el servicio
mvn -pl services/{servicio} -am clean package -DskipTests
```

### 2. "Could not find module services/xxx"

**Causa**: Un `<module>` declarado en el POM padre no existe en disco.

**Solución**: Verificar que la carpeta del módulo existe y tiene un `pom.xml`:
```bash
ls services/
```

### 3. Docker build falla con "COPY failed: file not found"

**Causa**: El build context no es la raíz del proyecto.

**Solución**: Los Dockerfiles están en `infra/docker/` pero el build context debe ser `.` (raíz). Verificar en `docker-compose.yml`:
```yaml
build:
  context: .                                    # ← raíz del proyecto
  dockerfile: infra/docker/{servicio}.Dockerfile # ← ruta al Dockerfile
```

### 4. Servicio no conecta a PostgreSQL en Docker

**Causa**: Las variables de entorno no coinciden con lo que el `application.properties` del servicio espera.

**Servicios y sus variables**:
- `appointment`, `patient`, `payment` usan `DB_URL`, `DB_USER`, `DB_PASSWORD`
- `schedule` usa `SCHEDULE_DB_URL`, `DB_USER`, `DB_PASSWORD`
- `notification` tiene URL hardcoded en docker profile, se overridea con `SPRING_DATASOURCE_URL`

**Solución**: Verificar que el `docker-compose.yml` pasa la variable correcta. En caso de duda, pasar AMBAS:
```yaml
environment:
  SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/{db_name}
  DB_URL: jdbc:postgresql://postgres:5432/{db_name}
```

### 5. "No qualifying bean of type ... RedisConnectionFactory"

**Causa**: El `appointment-service` excluye Redis autoconfiguration en su `application.properties`:
```
spring.autoconfigure.exclude=...RedisAutoConfiguration,RedisRepositoriesAutoConfiguration
```

**Solución**: No es un error. Es intencional. El servicio maneja Redis manualmente.

### 6. Flyway falla en el primer arranque

**Causa**: La base de datos existe pero no tiene las tablas esperadas para `validate`.

**Solución**: Verificar que `init-dbs.sql` se ejecutó correctamente:
```bash
docker compose exec postgres psql -U mediqueue -l
```
Si la DB no aparece, borrar el volumen y recrear:
```bash
docker compose down -v
docker compose up --build
```

### 7. Maven descarga dependencias lento en Docker

**Solución**: Agregar un volumen para caché de Maven en `docker-compose.yml`:
```yaml
volumes:
  - maven-cache:/root/.m2
```
O usar `mvn dependency:go-offline` como paso separado en el Dockerfile.

### 8. Conflicto de puertos

**Puertos asignados**:
| Puerto | Servicio |
|--------|----------|
| 8080 | api-gateway |
| 8081 | appointment-service |
| 8082 | notification-service |
| 8083 | payment-service |
| 8084 | patient-service |
| 8085 | schedule-service |
| 5432 | PostgreSQL |
| 6379 | Redis |

Si hay conflicto con un servicio local, cambiar solo el puerto **externo** en `docker-compose.yml`.

### 9. "payment.service" artifactId con punto

El `artifactId` de payment-service es `payment.service` (con punto, no guion). Esto viene del proyecto original. Cambiar el artifactId requiere también:
- Renombrar el JAR generado
- Actualizar cualquier referencia en CI/CD
- Actualizar el `dependencyManagement` del padre si lo referencia

**Recomendación**: No cambiar a menos que sea absolutamente necesario.
