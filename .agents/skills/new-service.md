# Skill: Agregar un Nuevo Microservicio

## Checklist

### 1. Crear la carpeta del servicio

```
services/{nombre-servicio}/
├── pom.xml
└── src/
    ├── main/
    │   ├── java/com/mediqueue/{paquete}/
    │   │   └── Application.java
    │   └── resources/
    │       ├── application.properties
    │       └── db/migration/     (si usa Flyway)
    └── test/java/com/mediqueue/{paquete}/
```

### 2. Crear el pom.xml del servicio

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>com.mediqueue.platform</groupId>
        <artifactId>mediqueue-platform</artifactId>
        <version>1.0.0-SNAPSHOT</version>
        <relativePath>../../pom.xml</relativePath>
    </parent>

    <groupId>com.mediqueue</groupId>
    <artifactId>mediqueue-{nombre}-service</artifactId>
    <name>mediqueue-{nombre}-service</name>

    <dependencies>
        <!-- Agregar dependencias específicas del servicio -->
        <!-- NO declarar <version> para deps gestionadas por el padre -->
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

### 3. Registrar el módulo en el POM padre

Agregar en `pom.xml` (raíz) dentro de `<modules>`:

```xml
<module>services/{nombre-servicio}</module>
```

### 4. Crear base de datos

Agregar en `infra/docker/init-dbs.sql`:

```sql
CREATE DATABASE mediqueue_{nombre};
GRANT ALL PRIVILEGES ON DATABASE mediqueue_{nombre} TO mediqueue;
```

### 5. Crear Dockerfile

Copiar uno existente de `infra/docker/` y reemplazar el nombre del servicio.

El patrón es siempre:
- Copiar TODOS los pom.xml de módulos
- Copiar solo shared-lib + el nuevo servicio como fuente
- Compilar con `-pl services/{nombre-servicio} -am`

### 6. Agregar al docker-compose.yml

```yaml
  {nombre-service}:
    build:
      context: .
      dockerfile: infra/docker/{nombre-service}.Dockerfile
    container_name: mediqueue-{nombre-service}
    restart: unless-stopped
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/mediqueue_{nombre}
      SPRING_DATASOURCE_USERNAME: ${DB_USERNAME:-mediqueue}
      SPRING_DATASOURCE_PASSWORD: ${DB_PASSWORD:-mediqueue}
      SPRING_PROFILES_ACTIVE: docker
    ports:
      - "{puerto-externo}:8080"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - mediqueue-net
```

### 7. Actualizar TODOS los Dockerfiles existentes

Agregar una línea `COPY` para el pom.xml del nuevo módulo en CADA Dockerfile existente:

```dockerfile
COPY services/{nombre-servicio}/pom.xml services/{nombre-servicio}/pom.xml
```

Esto es necesario porque Maven necesita resolver el reactor completo.

### 8. Verificar

```bash
mvn clean install -DskipTests
docker compose up --build {nombre-service}
```

## Puertos usados

Los puertos externos actuales son: 8080-8085. El próximo disponible es **8086**.
