# Builds the API. Every target delegates to scripts/build.sh, which
# documents the settings; the version is X.Y.Z from the version files and
# the build time (scripts/version.sh). The dashboard builds in its own
# folder, datyx-dashboard/.
#
#   make             jar (what the services serve with API_MODE=jar)
#   make jar         datyx-api/target/quarkus-app/quarkus-run.jar
#   make native      datyx-api/target/datyx-runner, by GraalVM native-image
#   make test        ./mvnw verify
#   make image       the Docker image (docker compose build api)
#   make clean       ./mvnw clean

# One build time for every target in a run, so they share a version.
ifndef BUILD_NUMBER
BUILD_NUMBER := $(shell date -u +%s)
endif

export BUILD_NUMBER VERSION_Z

.PHONY: all jar native test image clean

all:
	@bash scripts/build.sh all

jar native test image:
	@bash scripts/build.sh $@

clean:
	@cd datyx-api && ./mvnw -B -q clean
