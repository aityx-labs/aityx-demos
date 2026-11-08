# The app, under devbox (`devbox run make <target>`) or with Node on the
# PATH.
#
#   make build   tatyx_app/dist/ (base /tatyx/), only what changed
#   make serve   build, then the server on http://localhost:9710/tatyx/
#   make dev     Vite's dev server on http://localhost:9711/tatyx/, with
#                /api/ and /aityx/ proxied to the server on 9710
#   make test    the app's tests and type check, and the shared package's
#   make clean   the build and the packages

.PHONY: build serve dev test clean

build:
	@bash scripts/build.sh

serve:
	@bash scripts/serve.sh

dev:
	@cd tatyx_app && npm install --no-audit --no-fund && npm run dev

test:
	@cd tatyx_app && npm install --no-audit --no-fund && npm test && npm run typecheck
	@cd ../packages/aityx_js && npm install --no-audit --no-fund && npm test && npm run typecheck

clean:
	@rm -rf tatyx_app/dist tatyx_app/node_modules
