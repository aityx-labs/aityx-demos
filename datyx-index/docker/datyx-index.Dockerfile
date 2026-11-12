# The datyx index as one small container: bin/server.dart compiled to a
# native executable, with www/ (the page) beside it, as the server looks
# for it: /app/bin/server serves /app/www/. Built from this folder (the
# demo's, datyx-index/) by k8s/build.sh; datyx-index.Dockerfile.dockerignore
# lets in only bin/ and www/. The server has no folders beside it here,
# so INDEX_DEMOS says which demos /api/demos lists, and its *_PORT
# settings where a browser reaches each one (see k8s/).
FROM dart:3.13.0 AS build
WORKDIR /src
COPY bin/ bin/
RUN mkdir -p /out/bin && dart compile exe bin/server.dart -o /out/bin/server

# /runtime/ of Dart's image holds what an AOT executable needs (libc, CA
# certificates); nothing else, so no shell.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/bin/server /app/bin/server
COPY www/ /app/www/
ENV INDEX_PORT=9800 INDEX_BIND_HOST=0.0.0.0
USER 65534:65534
EXPOSE 9800
ENTRYPOINT ["/app/bin/server"]
