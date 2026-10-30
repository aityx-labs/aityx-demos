# Builds the web app. Every target delegates to scripts/make.sh, which
# documents the settings, e.g. `make web MODE=debug`.
#
#   make           the web app (RoboRules is web only)
#   make web       roborules_app/build/web/
#   make clean     flutter clean

# One build time for every target in a run, so they share a version (see
# scripts/version.sh).
ifndef BUILD_NUMBER
BUILD_NUMBER := $(shell date -u +%s)
endif

export MODE WEB_BASE_HREF BUILD_NUMBER VERSION_Z

.PHONY: all web clean

all web clean:
	@bash scripts/make.sh $@
