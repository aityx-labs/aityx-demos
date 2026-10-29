# The datyx API on the GraalVM JDK: Maven packages it in the build stage
# and the runtime stage carries the fast-jar. Built by ../compose.yaml from
# the datyx/ folder (see ../.dockerignore for what comes in). REVISION is
# the X.Y.Z version (scripts/build.sh image sets it).
FROM ghcr.io/graalvm/jdk-community:25 AS build
ARG REVISION=0.1.0-SNAPSHOT
WORKDIR /src
COPY datyx-api/mvnw datyx-api/pom.xml ./
COPY datyx-api/.mvn .mvn
# The dependencies first, so a source change doesn't fetch them again.
RUN ./mvnw -B -q -Drevision="$REVISION" dependency:go-offline || true
COPY datyx-api/src src
RUN ./mvnw -B -q -DskipTests -Drevision="$REVISION" package

FROM ghcr.io/graalvm/jdk-community:25
WORKDIR /app
COPY --from=build /src/target/quarkus-app/ /app/
# compose.yaml's healthcheck uses curl.
RUN microdnf install -y curl && microdnf clean all
USER 65534
EXPOSE 9900
CMD ["java", "-jar", "/app/quarkus-run.jar"]
