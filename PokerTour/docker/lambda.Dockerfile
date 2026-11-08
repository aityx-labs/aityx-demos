# The Lambda functions' code: bin/lambda.dart compiled to a Linux
# executable named bootstrap (a custom runtime on provided.al2023), with
# the models beside it, as the zip Lambda gets. The official Dart image
# builds it for the functions' architecture (arm64 by default; deploy.sh
# passes --platform). Nothing runs from this image: deploy.sh builds it
# with --output, which writes the last stage's files to a folder, and
# zips them. The build context is the PokerTour folder, whose
# .dockerignore keeps the builds, .env, the data and every credential
# (.secrets/, client_secret*.json) out.
FROM dart:3.13.0 AS build
WORKDIR /src
COPY poker_core/ poker_core/
COPY aws_lite/ aws_lite/
COPY pokertour_api/ pokertour_api/
RUN cd pokertour_api && dart pub get \
    && mkdir -p /out && dart compile exe bin/lambda.dart -o /out/bootstrap
COPY pokertour_app/assets/models/ /out/models/

FROM scratch AS export
COPY --from=build /out/ /
