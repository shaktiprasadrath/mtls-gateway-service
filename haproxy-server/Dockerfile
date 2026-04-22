FROM maven:3.9-eclipse-temurin-17-alpine AS build
WORKDIR /app

COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline

COPY src ./src
RUN mvn -q -DskipTests package

FROM gcr.io/distroless/java17-debian12:nonroot
WORKDIR /app

COPY --from=build --chown=nonroot:nonroot /app/target/*.jar app.jar

USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/bin/java", "-jar", "/app/app.jar"]
