# Stage 1: build
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# Stage 2: runtime
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Usuario no-root por seguridad
RUN addgroup -S mediqueue && adduser -S mediqueue -G mediqueue
USER mediqueue

COPY --from=build /app/target/*.jar app.jar

# Actuator healthcheck
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8083/actuator/health || exit 1

EXPOSE 8083
ENTRYPOINT ["java", "-jar", "app.jar"]
