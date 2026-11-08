# Poker Tour as one container: the server (pokertour_api/bin/server.dart,
# compiled to a native executable) with the app's release web build and
# the models inside it. Built by compose.yaml from this folder, with the
# repository's shared packages as a second context named `packages`
# (compose.yaml's additional_contexts; by hand, `docker build
# --build-context packages=../packages .`): the app depends on
# ../../packages/aityx_web by path. .dockerignore keeps the builds, the
# .env and the leaderboard's data out. The aityx key and the sign-in
# settings come from the environment at run time, never into the image.
FROM ubuntu:24.04 AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# The Flutter devbox.lock pins, as in the dev container's Containerfile:
# on x64 the release archive, checked against its published SHA-256; on
# arm64, which has no Linux archive, the release tag from git.
ARG FLUTTER_VERSION=3.47.0
ARG FLUTTER_SHA256_AMD64=26cd99d3d94b1367e6b50535a18aeef0282c10a535bbe3ec493534dcdab75296
RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in \
         amd64) \
           curl -fsSL -o /tmp/flutter.tar.xz \
             "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
           && echo "${FLUTTER_SHA256_AMD64}  /tmp/flutter.tar.xz" | sha256sum -c - \
           && mkdir /opt/flutter \
           && tar -xJf /tmp/flutter.tar.xz -C /opt/flutter --strip-components=1 \
           && rm /tmp/flutter.tar.xz ;; \
         arm64) \
           git clone --depth 1 --branch "$FLUTTER_VERSION" \
             https://github.com/flutter/flutter.git /opt/flutter ;; \
         *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
       esac \
    && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --no-cli-animations \
    && flutter --disable-analytics \
    && flutter precache --web

WORKDIR /src
COPY --from=packages aityx_web/ packages/aityx_web/
COPY . PokerTour/
# Served under /app/, calling /api/ on its own origin.
RUN cd PokerTour && WEB_BASE_HREF=/app/ bash scripts/make.sh web
RUN cd PokerTour/pokertour_api && dart pub get && mkdir -p /out/bin \
    && dart compile exe bin/server.dart -o /out/bin/server

# /runtime/ of Dart's image holds what an AOT executable needs (libc, CA
# certificates for aityx's and Google's https).
FROM dart:3.13.0 AS runtime

FROM scratch
COPY --from=runtime /runtime/ /
COPY --from=build /out/ /app/
COPY --from=build /src/PokerTour/pokertour_app/build/web/ /app/web/
COPY --from=build /src/PokerTour/pokertour_app/assets/models/ /app/models/
ENV WEB_ROOT=/app/web POKERTOUR_MODELS=/app/models \
    API_PORT=9810 POKERTOUR_BIND_HOST=0.0.0.0
USER 65534:65534
EXPOSE 9810
ENTRYPOINT ["/app/bin/server"]
