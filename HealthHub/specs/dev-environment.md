# Development environment

HealthHub's environment is PokerFace's, with its own names and ports and
three more services, PostgreSQL, Kafka and Kafka's REST proxy;
[Mortgage Hub's spec](../../MortgageHub/specs/dev-environment.md)
explains the reasons behind each piece, and
[datyx](../../datyx/specs/) is where running a database from
process-compose through Docker Compose comes from.

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed, and is
  the same as Mortgage Hub's and Contact Hub's, so they share one Flutter
  (Dart 3.13.0) and one Nix store. Both packages require Dart SDK
  `^3.13.0`. PostgreSQL and Kafka are not devbox packages: they are
  Docker containers, so Docker must be running.
- `devbox services up` ([process-compose.yaml](../process-compose.yaml)),
  run in this folder, starts:
  - PostgreSQL (`1-postgres`, via
    [scripts/infra.sh](../scripts/infra.sh) `up postgres`): the `postgres`
    service of [compose.yaml](../compose.yaml), `docker compose up`
    attached so its log is the process's, published on
    127.0.0.1:9803 (`HEALTHHUB_DB_PORT`, `HEALTHHUB_BIND_HOST`). Its
    readiness probe is the container's health check (`infra.sh healthy
    postgres`), up to 3 minutes for a first pull; its shutdown is `docker
    compose stop postgres`, which keeps the data. See
    [Database](database.md);
  - Kafka (`4-kafka`, `infra.sh up kafka`): the `kafka` service, Apache
    Kafka 4.3 (`apache/kafka:4.3.2`), one node in KRaft mode (broker and
    controller in one process, no ZooKeeper), with two listeners:
    `kafka:19092` for the compose network and one published on
    127.0.0.1:9804 (`HEALTHHUB_KAFKA_PORT`; always 127.0.0.1, whatever
    `HEALTHHUB_BIND_HOST` says, since the broker has no authentication) and
    advertised as `localhost:9804`, for a Kafka client on the host. Its
    data is in the `kafka-data` volume, a day of retention, a 512 MB heap
    at most. Its Docker health check runs `kafka-topics.sh --create
    --if-not-exists` (with a 64 MB heap of its own) for
    `healthhub.people.moves`, `healthhub.admissions` and
    `healthhub.test`, the API's live test's topic: healthy once the broker
    answers and every topic exists. A `kafka` container made before
    `healthhub.admissions` was added keeps its old check until it is
    recreated (`docker compose up -d kafka`), and until then the API's
    admissions fail to publish (logged, retried); `kafka-topics.sh
    --create` in the container makes the topic by hand. The
    check makes the topics because the REST proxy answers 404 to a record
    for a topic that doesn't exist, instead of letting the broker create
    it (the broker's auto-creation, on, serves only Kafka clients).
    Readiness probe and shutdown as PostgreSQL's;
  - Kafka's REST proxy (`5-kafka-rest`, `infra.sh up kafka-rest`, once
    Kafka is healthy): the `kafka-rest` service, Karapace's REST proxy
    (`ghcr.io/aiven-open/karapace:6.2.4`, Apache 2.0, compatible with
    Confluent's REST Proxy v2), run as `python3 -m
    karapace.kafka_rest_apis` without Karapace's schema registry, since
    the records are plain JSON. It listens on 8082 inside, published on
    127.0.0.1:9805 (`HEALTHHUB_KAFKA_REST_PORT`; always 127.0.0.1, like
    Kafka); its health check is `GET /topics`. Consumers left behind by
    an API killed before it could delete them go once nobody has called
    the proxy for 5 minutes (`KARAPACE_CONSUMER_IDLE_DISCONNECT_TIMEOUT`). The API reaches Kafka only through it
    (`HEALTHHUB_KAFKA_REST_URL`, http://127.0.0.1:9805 on the host), so it
    needs no Kafka client library. Produce is `POST
    /topics/<topic>` with `application/vnd.kafka.json.v2+json`; a
    consumer is made with `POST /consumers/<group>`, subscribed, polled
    with `GET .../records` and deleted. The `base_uri` it answers is
    relative (`consumers/<group>/instances/<name>`);
  - the web app (`2-flutter-web`, via
    [scripts/flutter-web.sh](../scripts/flutter-web.sh)) on
    http://localhost:9801/app/ (`FLUTTER_WEB_PORT`), bound to 127.0.0.1
    (`HEALTHHUB_BIND_HOST`), with an HTTP readiness probe of up to 15
    minutes. In release mode, the default (`WEB_MODE`), it is the app's
    release build served by
    [healthhub_api/bin/web_server.dart](../healthhub_api/bin/web_server.dart)
    ([lib/web_server.dart](../healthhub_api/lib/web_server.dart), the
    same as PokerFace's) compiled to a native executable,
    `healthhub_api/build/web_server`: `/app/` from
    `healthhub_app/build/web/` (`WEB_ROOT`), `/api/` and the bare `/`
    proxied to the API on 127.0.0.1:`API_PORT`. With `WEB_MODE=debug` it
    is Flutter's dev server instead, with hot reload, which proxies
    `/api/` itself (`web_dev_config.yaml`, generated, git-ignored). On
    stop, its shutdown command kills whatever listens on the port;
  - the API (`3-api`, via [scripts/api.sh](../scripts/api.sh)) on
    http://localhost:9802 (`API_PORT`), `bin/server.dart` compiled to a
    native executable, `healthhub_api/build/server`, once PostgreSQL is
    healthy, with a readiness probe on `/api/health`. The script loads
    the settings through [scripts/env.sh](../scripts/env.sh) (the
    environment, else `.env`, else defaults) and exports `AITYX_API_KEY`,
    `AITYX_URL` and the database's host, port, name, user and password
    to the server only, with `HEALTHHUB_MODE`, `HEALTHHUB_KAFKA_REST_URL`
    and the simulation's settings. It doesn't wait for Kafka: in dev mode
    it retries the REST proxy until it answers. CORS allows the web app's
    origins (`ALLOWED_ORIGINS`);
  - the health monitor (`0-health-check`,
    [scripts/health-check.sh](../scripts/health-check.sh)), once the web
    app, the API and the REST proxy are ready. It first prints where to open the app,
    `http://localhost:9801/app/` and, in a codespace, the forwarded URL,
    and waits 5 s (`HEALTH_CHECK_DELAY`). Then every 15 s
    (`HEALTH_CHECK_INTERVAL`) one line with the time, 🌐 Web, 🔌 API
    (`/api/health`), 🐘 Postgres (the API's `"db"`), 🤖 aityx (✅ the
    API has its key, ⚪ it doesn't) and 📨 Kafka (the REST proxy's
    `GET /topics` on `HEALTHHUB_KAFKA_REST_PORT` answers 200).
- The ports, 9801 to 9805, are HealthHub's, in the 98xx range after the
  datyx index's 9800: the other demos have 88xx and 89xx (Mortgage Hub
  8880/8881, Contact Hub 8890/8891, PokerFace 8910/8911, RoboRules
  8920/8921, Cellfie 8930/8931) and datyx 99xx (9900 to 9906), so all can
  run at once.
- **Settings** ([.env.example](../.env.example), read by
  [scripts/env.sh](../scripts/env.sh)): `AITYX_API_KEY`, `AITYX_URL`,
  `OIDC_CLIENT_ID`, `OIDC_ISSUER`, `DATYX_API_URL` ([API](api.md)),
  `HEALTHHUB_BIND_HOST`, `FLUTTER_WEB_PORT`, `API_PORT`,
  `HEALTHHUB_DB_PORT`, `HEALTHHUB_DB_ADMIN_PASSWORD`,
  `HEALTHHUB_DB_PASSWORD`, `WEB_MODE`, `HEALTHHUB_KAFKA_PORT` (9804),
  `HEALTHHUB_KAFKA_REST_PORT` (9805), `HEALTHHUB_KAFKA_REST_URL`
  (http://127.0.0.1:9805), `HEALTHHUB_MODE` (`dev`, which runs the
  people simulation; `prod` doesn't), `HEALTHHUB_SIM_PEOPLE` (10 per
  city), `HEALTHHUB_SIM_TURN_MS` (1000) and
  `HEALTHHUB_SIM_MINUTES_PER_TURN` (60, so a real second is a simulated
  hour), every one but the key with a
  default. `.env` is git-ignored.
- **Builds for the services**: [scripts/build.sh](../scripts/build.sh)
  (`devbox run build`; targets `web`, `web_server`, `api`, `all`) is
  PokerFace's: it builds only what is missing or older than its sources,
  the web build with `WEB_BASE_HREF=/app/` and an empty `API_BASE_URL`
  (recorded in `build/web/.aityx-services`), the two executables with
  `dart compile exe`, one Flutter web build at a time across the
  repository's demos through a lock in the system's temp folder.
  `build/` is git-ignored.
- `devbox run web` runs only the web app, in debug mode (hot reload)
  unless `WEB_MODE=release`; `devbox run api` only the API (it needs the
  database); `devbox run db` only the database; `devbox run kafka` only
  Kafka and its REST proxy (`infra.sh up kafka-rest`, which starts
  `kafka` first).
- The web app calls the API at `API_BASE_URL` (a dart-define). The
  services leave it empty, in both modes: the app calls `/api/` on its own
  origin, which the web server (or the dev server) proxies to the API.
  `scripts/make.sh` passes `API_BASE_URL`, or `http://localhost:9802`.
- **Version**: `X.Y.Z`, X and Y from `version.X.txt` and `version.Y.txt`
  (0.1 today), Z the build time as `YYYYMMDDHHMM` UTC; the build number is
  the same time in Unix seconds
  ([scripts/version.sh](../scripts/version.sh)). It reaches the app as the
  `HEALTHHUB_VERSION` dart-define, shown at the bottom of the screen.
- **Coordinates**: the group ID `datyx` from `group.id.txt` (HealthHub
  belongs to the datyx group, with the datyx API and dashboard; the
  other demos are the aityx group) and the artifact ID `healthhub` from
  `artifact.id.txt`; with the version, `datyx:healthhub:X.Y.Z`.
- **Builds**: the [Makefile](../Makefile) runs
  [scripts/make.sh](../scripts/make.sh): `web`, `android`, `ios` (macOS),
  `linux` (Linux), `all` (what the host can build) and `clean`, with
  `MODE`, `IOS_CODESIGN` and `WEB_BASE_HREF`.
- **Docker Compose** ([compose.yaml](../compose.yaml)): `docker compose up`
  runs the whole demo with Docker alone on http://localhost:9801/app/,
  published on 127.0.0.1 unless `HEALTHHUB_BIND_HOST` says otherwise.
  `postgres` is the database, with its init script and volume; `kafka`
  and `kafka-rest` are Kafka and its REST proxy, as above; `api`
  ([healthhub_api/Dockerfile](../healthhub_api/Dockerfile)) is the server
  compiled with `dart compile exe`, run from `scratch` as user 65534 and
  not published, started once `postgres` is healthy, with the database's
  host set to the service's name, `HEALTHHUB_KAFKA_REST_URL` to
  http://kafka-rest:8082 and the mode and simulation settings from the
  environment (it doesn't wait for Kafka); `web`
  ([docker/web.Dockerfile](../docker/web.Dockerfile)) builds the release
  web app with the Flutter devbox.lock pins and serves it with nginx under
  `/app/`, redirecting `/` and proxying `/api/` to `api`
  ([docker/nginx.conf](../docker/nginx.conf)). Compose passes `api`
  `AITYX_API_KEY`, `AITYX_URL` and `HEALTHHUB_DB_PASSWORD` from the
  environment, else `.env`; `web` gets none. All five have health checks
  (`api` runs `/app/bin/server healthcheck`).
- **Dev container**: the datyx group's
  ([.devcontainer/datyx/](../../.devcontainer/datyx)), named **datyx
  demos**, which HealthHub shares with the datyx API (`datyx/`) and the
  datyx dashboard (`datyx-dashboard/`); the aityx group has its own, and
  there is no per-demo one. It runs the group's published image
  (`docker.io/aletyxcode/samples-and-demos-datyx`, built from
  [image/Containerfile](../../image/Containerfile) by
  `bash image/build-image.sh datyx`: Flutter 3.47.0, GraalVM,
  process-compose, the datyx API's Maven dependencies and the release web
  builds of the dashboard and HealthHub) on a 4-core, 16 GB machine (the largest the organization allows),
  plus the `docker-in-docker` feature, since the databases are
  containers. The scripts are the ones in
  [.devcontainer/](../../.devcontainer), which both groups share;
  `DEMOS_GROUP=datyx` makes them, and the root `start-all.sh`,
  `stop-all.sh` and `build-all.sh`, act on the folders whose
  `group.id.txt` says `datyx`. `on-create.sh` restores the group's web
  builds from the image; `update-content.sh` runs `build-all.sh` for
  what changed since; `post-create.sh` reports whether `AITYX_API_KEY`
  arrived (never its value); `post-start.sh` starts the index page and
  then the group detached with `start-all.sh` on every start, which logs
  when each demo answers; `public-port.sh` makes the web ports public,
  9801 among them (again on attach). Everything goes to `startup.log` at
  the root of the repository (see
  [startup-log.sh](../../.devcontainer/startup-log.sh)), git-ignored,
  which holds no secrets. The container sets
  `HEALTHHUB_BIND_HOST=0.0.0.0` with the index's and the datyx API's,
  forwards 9801 with the index's 9800 and the dashboard's 9906 (HealthHub's
  API, database and Kafka stay inside), and adds the Dart and Flutter
  extensions.
- **Codespaces secret**: the group's `devcontainer.json` declares `AITYX_API_KEY`,
  the same secret as Mortgage Hub's and Contact Hub's; `AITYX_URL` is
  optional. A local dev container uses `.env`.
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) and the
  repository README have an **Open in GitHub Codespaces** badge with
  `devcontainer_path=.devcontainer/datyx/devcontainer.json` and
  `machine=standardLinux32gb`, the same link as the datyx group's.

## Known limitations

- The datyx dev container hasn't been started yet, and of the Docker Compose
  services only `postgres` and `api` have (the API's image built and
  run against the database); the `web` image hasn't been built. The
  devbox services have run end to end (PostgreSQL, the API and the app,
  with `/api/hello` answering from the database).
- `kafka` and `kafka-rest` have run from process-compose (both ready,
  the health monitor's 📨 Kafka ✅, the API in dev mode moving 70 people
  through the topic and `/api/people` reading them back) and with `docker
  compose up kafka kafka-rest`; the whole Compose stack hasn't run with
  them. The host listener (9804) has only been checked to accept
  connections, not with a Kafka client.
- A codespace builds HealthHub's web build itself, a minute or two,
  when the datyx image wasn't made from the current `HealthHub/`, or
  hasn't been pushed since `bash image/build-image.sh datyx` was added.
- No release, deploy or CI workflows.
