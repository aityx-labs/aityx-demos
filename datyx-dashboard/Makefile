# Builds the dashboard. Every target delegates to scripts/build.sh or
# scripts/make.sh, which document the settings; the version is X.Y.Z from
# the version files and the build time (scripts/version.sh).
#
#   make             web and web_server (what the services serve)
#   make web         datyx_dashboard/build/web/ (scripts/make.sh)
#   make web_server  datyx_dashboard/build/web_server
#   make test        flutter analyze and flutter test
#   make image       the Docker image (docker compose build web)
#   make clean       flutter clean

# One build time for every target in a run, so they share a version.
ifndef BUILD_NUMBER
BUILD_NUMBER := $(shell date -u +%s)
endif

export BUILD_NUMBER VERSION_Z MODE API_BASE_URL WEB_BASE_HREF

.PHONY: all web web_server test image clean

all:
	@bash scripts/build.sh all

web web_server:
	@bash scripts/build.sh $@

test:
	@cd datyx_dashboard && flutter pub get >/dev/null && flutter analyze && flutter test

image:
	@docker compose -f compose.yaml build web

clean:
	@bash scripts/make.sh clean
