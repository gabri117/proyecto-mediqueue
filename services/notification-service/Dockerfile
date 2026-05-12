FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

RUN addgroup -S mediqueue && adduser -S mediqueue -G mediqueue

COPY target/mediqueue-notification-service-*.jar app.jar

RUN chown mediqueue:mediqueue app.jar

USER mediqueue

EXPOSE 8080

ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]
