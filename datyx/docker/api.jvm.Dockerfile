# The datyx API on the GraalVM JDK: Maven packages it in the build stage
# and the runtime stage carries the fast-jar. Built by ../compose.yaml from
# the datyx/ folder (see ../.dockerignore for what comes in). REVISION is
# the X.Y.Z version (scripts/build.sh image sets it).
FROM ghcr.io/graalvm/jdk-community:25 AS build
ARG REVISION=0.1.0-SNAPSHOT
# The configuration profile, built in (some settings, such as Flyway's
# locations, are fixed at build time) and run: prod unless compose.yaml
# says otherwise (DATYX_API_PROFILE, dev there).
ARG PROFILE=prod
WORKDIR /src
COPY datyx-api/mvnw datyx-api/pom.xml ./
COPY datyx-api/.mvn .mvn
# The dependencies first, so a source change doesn't fetch them again.
RUN ./mvnw -B -q -Drevision="$REVISION" dependency:go-offline || true
COPY datyx-api/src src
# More build-time settings for the package, none by default: the
# Kubernetes build (k8s/build.sh) adds Swagger UI to its dev-profile jar,
# which a packaged build leaves out (quarkus.swagger-ui.always-include).
ARG PACKAGE_ARGS=
RUN ./mvnw -B -q -DskipTests -Drevision="$REVISION" -Dquarkus.profile="$PROFILE" $PACKAGE_ARGS package

FROM ghcr.io/graalvm/jdk-community:25
ARG PROFILE=prod
ENV QUARKUS_PROFILE=$PROFILE
WORKDIR /app
COPY --from=build /src/target/quarkus-app/ /app/
# compose.yaml's healthcheck uses curl; XGBoost's native library
# (datyx.training) needs GCC's OpenMP runtime, libgomp.
RUN microdnf install -y curl libgomp && microdnf clean all
# DeepAR's libtorch (DJL's PyTorch engine, in the fast-jar for the
# platform built on) is extracted on first use to DJL's cache: somewhere
# the API's user can write.
ENV DJL_CACHE_DIR=/tmp/djl
USER 65534
EXPOSE 9900
CMD ["java", "-jar", "/app/quarkus-run.jar"]
