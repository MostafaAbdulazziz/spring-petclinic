FROM eclipse-temurin:17-jre-alpine  
EXPOSE 8080
ARG JAR_FILE=target/*.jar
ENV APP_DIR=/app
WORKDIR ${APP_DIR}
COPY ${JAR_FILE} app.jar
RUN apk update && apk add --no-cache curl \
    && rm -rf /var/cache/apk/*
ENTRYPOINT ["java", \
  "-Dspring.autoconfigure.exclude=org.springframework.boot.actuate.autoconfigure.metrics.SystemMetricsAutoConfiguration", \
  "-jar", "/app/app.jar"]


