FROM eclipse-temurin:21-jdk-alpine@sha256:0000000000000000000000000000000000000000000000000000000000000000 AS build
FROM build AS test
FROM eclipse-temurin:21-jre-alpine
COPY --from=build /app.jar /app.jar
