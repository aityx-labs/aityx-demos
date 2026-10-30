# The datyx API as a native executable: GraalVM native-image builds it in
# the build stage (minutes, and give Docker 6 GB or more) and a minimal
# image runs it. Built by ../compose.yaml with
# DATYX_API_DOCKERFILE=docker/api.native.Dockerfile.
FROM ghcr.io/graalvm/native-image-community:25 AS build
ARG REVISION=0.1.0-SNAPSHOT
# The configuration profile, built in (some settings, such as Flyway's
# locations, are fixed at build time) and run: prod unless compose.yaml
# says otherwise (DATYX_API_PROFILE, dev there).
ARG PROFILE=prod
WORKDIR /src
COPY datyx-api/mvnw datyx-api/pom.xml ./
COPY datyx-api/.mvn .mvn
RUN ./mvnw -B -q -Drevision="$REVISION" dependency:go-offline || true
COPY datyx-api/src src
RUN ./mvnw -B -q -DskipTests -Drevision="$REVISION" -Dquarkus.profile="$PROFILE" -Dnative package

FROM quay.io/quarkus/ubi9-quarkus-micro-image:2.0
ARG PROFILE=prod
ENV QUARKUS_PROFILE=$PROFILE
WORKDIR /app
COPY --from=build --chown=1001:root /src/target/datyx-runner /app/datyx
USER 1001
EXPOSE 9900
CMD ["/app/datyx"]
