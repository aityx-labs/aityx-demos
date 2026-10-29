# The API (bin/server.dart), compiled to a native executable. Built by
# ../compose.yaml; see the README's "Run it with Docker Compose".
FROM dart:3.13.0 AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY . .
RUN dart pub get --offline \
    && mkdir -p /out/bin \
    && dart compile exe bin/server.dart -o /out/bin/server \
    && cp -r models /out/models

# /runtime/ holds what an AOT executable needs (libc, CA certificates for
# aityx's https). The server reads ../models/river.json relative to
# itself, hence /app/bin and /app/models.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/ /app/
USER 65534:65534
EXPOSE 8941
ENTRYPOINT ["/app/bin/server"]
