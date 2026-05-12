FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
COPY packages/shared-lib/pom.xml packages/shared-lib/pom.xml
COPY services/api-gateway/pom.xml services/api-gateway/pom.xml
COPY services/appointment-service/pom.xml services/appointment-service/pom.xml
COPY services/notification-service/pom.xml services/notification-service/pom.xml
COPY services/payment-service/pom.xml services/payment-service/pom.xml
COPY services/patient-service/pom.xml services/patient-service/pom.xml
COPY services/schedule-service/pom.xml services/schedule-service/pom.xml
COPY packages/shared-lib packages/shared-lib
COPY services/patient-service services/patient-service
RUN mvn -B -pl services/patient-service -am package -DskipTests

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S mediqueue && adduser -S mediqueue -G mediqueue
COPY --from=build /workspace/services/patient-service/target/*.jar app.jar
USER mediqueue
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
