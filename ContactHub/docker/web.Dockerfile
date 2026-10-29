# The Flutter app's release web build, served by nginx under /app/, with
# /api/ proxied to the API service. Built by ../compose.yaml from the
# ContactHub/ folder, because scripts/make.sh and the version files live
# there; web.Dockerfile.dockerignore picks what it needs.
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
COPY contacthub_app/pubspec.yaml contacthub_app/pubspec.lock contacthub_app/
RUN cd contacthub_app && flutter pub get
COPY . .
# Served under /app/, as the dev server does. API_BASE_URL empty: the app
# calls /api/ on its own origin, which nginx proxies to the API.
RUN WEB_BASE_HREF=/app/ API_BASE_URL= bash scripts/make.sh web

FROM nginx:1.29-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/contacthub_app/build/web/ /usr/share/nginx/html/app/
EXPOSE 8080
