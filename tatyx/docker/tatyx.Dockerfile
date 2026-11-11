# tatyx as one container: the server (tatyx_server/server.mjs, plain Node
# with no packages) with the app's release build under /tatyx/, the
# leaderboard's runner it imports, and the strategies an empty tour starts
# with. Built by k8s/build.sh from the tatyx/ folder, with the
# repository's shared packages as a second context named `packages` (by
# hand, `docker build -f docker/tatyx.Dockerfile --build-context
# packages=../packages .`): the app depends on ../../packages/aityx_js by
# path. tatyx.Dockerfile.dockerignore lets in only the app's sources, the
# server and the strategies: never the .env, the builds, or data/ (the
# tour and the session secret of a laptop's server). The keys and the
# sign-in settings come from the environment at run time, never into the
# image.
FROM node:22-alpine AS build

WORKDIR /src
# The shared package by path, as the lock file has it: its sources only,
# it has no dependencies of its own to install.
COPY --from=packages aityx_js/package.json aityx_js/tsconfig.json packages/aityx_js/
COPY --from=packages aityx_js/src/ packages/aityx_js/src/
COPY tatyx_app/package.json tatyx_app/package-lock.json tatyx/tatyx_app/
RUN cd tatyx/tatyx_app && npm ci --no-audit --no-fund
COPY tatyx_app/ tatyx/tatyx_app/
# What scripts/build.sh builds: the type check, the app under /tatyx/
# (dist/) and the leaderboard's runner (dist-runner/runner.mjs).
RUN cd tatyx/tatyx_app && npm run build

FROM node:22-alpine

WORKDIR /app
# Owned by root and only read: the server writes to TATYX_DATA_DIR alone.
# Its tests stay out; it needs no packages, so there is no node_modules.
COPY tatyx_server/*.mjs tatyx_server/
COPY strategies/ strategies/
COPY --from=build /src/tatyx/tatyx_app/dist/ tatyx_app/dist/
COPY --from=build /src/tatyx/tatyx_app/dist-runner/ tatyx_app/dist-runner/

# Every interface, so a Service reaches it; the port is the usual one.
# The tour's files go to /data, a volume on Kubernetes.
ENV NODE_ENV=production \
    TATYX_PORT=9710 \
    TATYX_BIND_HOST=0.0.0.0 \
    WEB_ROOT=/app/tatyx_app/dist \
    TATYX_DATA_DIR=/data
EXPOSE 9710
# The node user of the image (uid 1000), not root.
USER node
CMD ["node", "tatyx_server/server.mjs"]
