# --- Build stage -------------------------------------------------------
# Note: the repo's mvnw wrapper ships without its .mvn/wrapper properties,
# so the build stage uses the Maven image directly rather than the wrapper.
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app

COPY pom.xml .
RUN mvn -B dependency:go-offline

COPY src src
RUN mvn -B clean package -DskipTests

# --- Runtime stage -------------------------------------------------------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

RUN addgroup -S craftista && adduser -S craftista -G craftista

COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080
USER craftista

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
