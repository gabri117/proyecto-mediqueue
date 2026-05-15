FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml ./pom.xml
COPY packages/shared-lib/pom.xml ./packages/shared-lib/pom.xml
COPY services/api-gateway/pom.xml ./services/api-gateway/pom.xml
COPY services/appointment-service/pom.xml ./services/appointment-service/pom.xml
COPY services/notification-service/pom.xml ./services/notification-service/pom.xml
COPY services/patient-service/pom.xml ./services/patient-service/pom.xml
COPY services/schedule-service/pom.xml ./services/schedule-service/pom.xml
COPY services/payment-service/pom.xml ./services/payment-service/pom.xml
COPY services/payment-service/src ./services/payment-service/src
RUN mvn -q -pl services/payment-service -DskipTests package

FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /workspace/services/payment-service/target/*.jar app.jar
USER app
EXPOSE 8084
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8084/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
