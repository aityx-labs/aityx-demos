# The aityx index as one container: the server (bin/server.dart, compiled
# to a native executable), the index page (www/) and the six aityx demos'
# release web builds, each made by the demo's own scripts/build.sh, as
# ./build-all.sh makes them on a laptop (base href /demos/<slug>/, no
# CDN). Built from the root of the repository (k8s/build.sh), because the
# apps depend on packages/aityx_web by path; its ignore file,
# aityx-index.Dockerfile.dockerignore, lets in only what the builds need,
# never the root .env.
#
# The image keeps the repository's layout under /app/: bin/server.dart
# finds www/ and the demos from its own path (www/ beside bin/, the demos
# in the folders beside Index/), so it runs here unchanged. The aityx key
# and URL come from the environment at run time, never into the image.
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
COPY packages/aityx_web/ packages/aityx_web/
# The six web builds one after another, never at once: one dart2js takes
# a gigabyte or two. Each layer keeps the pub cache, so the apps after the
# first fetch little; a change to one app rebuilds it and those after it.
COPY Cellfie/ Cellfie/
RUN bash Cellfie/scripts/build.sh
COPY ContactHub/ ContactHub/
RUN bash ContactHub/scripts/build.sh
COPY MortgageHub/ MortgageHub/
RUN bash MortgageHub/scripts/build.sh
COPY PokerFace/ PokerFace/
RUN bash PokerFace/scripts/build.sh
COPY RiverRace/ RiverRace/
RUN bash RiverRace/scripts/build.sh
COPY RoboRules/ RoboRules/
RUN bash RoboRules/scripts/build.sh

# The server, and /out/ laid out as the repository is: Index/ with the
# executable, www/ and group.id.txt, and for each demo what the server
# finds it by (its group.id.txt and its app's pubspec.yaml) and its build,
# without the build's own records (.aityx-services, .last_build_id), as
# scripts/stage-static.sh leaves them out.
COPY Index/ Index/
RUN mkdir -p /out/Index/bin \
    && dart compile exe Index/bin/server.dart -o /out/Index/bin/server \
    && cp -R Index/www Index/group.id.txt /out/Index/ \
    && for folder in Cellfie ContactHub MortgageHub PokerFace RiverRace RoboRules; do \
         app="$folder/$(echo "$folder" | tr '[:upper:]' '[:lower:]')_app"; \
         mkdir -p "/out/$app/build" \
         && cp "$folder/group.id.txt" "/out/$folder/" \
         && cp "$app/pubspec.yaml" "/out/$app/" \
         && cp -R "$app/build/web" "/out/$app/build/web" \
         || exit 1; \
       done \
    && find /out -type f -name '.*' -delete

# /runtime/ of Dart's image holds what an AOT executable needs (libc, CA
# certificates for aityx's https).
FROM dart:3.13.0 AS runtime

FROM scratch
COPY --from=runtime /runtime/ /
COPY --from=build /out/ /app/
# Every interface, in a container; the port is published by whoever runs
# it (k8s/service.yaml: on this machine's loopback only).
ENV INDEX_PORT=8800 INDEX_BIND_HOST=0.0.0.0
USER 65534:65534
EXPOSE 8800
ENTRYPOINT ["/app/Index/bin/server"]
