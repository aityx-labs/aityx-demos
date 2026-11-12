# Development environment

HealthHub's environment is PokerFace's, with its own names and ports and
more services: PostgreSQL, Kafka, Kafka's REST proxy and Flink;
[Mortgage Hub's spec](../../MortgageHub/specs/dev-environment.md)
explains the reasons behind each piece, and
[datyx](../../datyx/specs/) is where running a database from
process-compose through Docker Compose comes from.

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed, and is
  the same as Mortgage Hub's and Contact Hub's, so they share one Flutter
  (Dart 3.13.0) and one Nix store. Both packages require Dart SDK
  `^3.13.0`. PostgreSQL, Kafka and Flink are not devbox packages: they
  are Docker containers, so Docker must be running.
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
    `healthhub.people.moves`, `healthhub.admissions`,
    `healthhub.alarms` ([Occupancy alarms](occupancy-alarms.md)),
    `healthhub.test`, the API's live test's topic, and
    `healthhub.admissions.hourly`, the Flink job's, compacted
    (`cleanup.policy=compact,delete`): healthy once the broker answers
    and every topic exists. A `kafka` container made before
    `healthhub.admissions` was added keeps its old check until it is
    recreated (`docker compose up -d kafka`), and until then the API's
    admissions fail to publish (logged, retried); `kafka-topics.sh
    --create` in the container makes the topic by hand. The same goes for
    `healthhub.alarms`: a container made before it was added keeps
    retrying the alarm events until it is recreated or the topic made
    by hand (`docker exec healthhub-kafka-1 /opt/kafka/bin/kafka-topics.sh
    --bootstrap-server kafka:19092 --create --if-not-exists --topic
    healthhub.alarms`). The
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
    the proxy for 5 minutes (`KARAPACE_CONSUMER_IDLE_DISCONNECT_TIMEOUT`).
    It keeps two malloc arenas (`MALLOC_ARENA_MAX=2`), not eight per
    processor for its forty-odd threads (librdkafka's), whose fragments
    grew it until the local Kubernetes cluster killed it at its 384 MB
    limit after 18 hours. The API reaches Kafka only through it
    (`HEALTHHUB_KAFKA_REST_URL`, http://127.0.0.1:9805 on the host), so it
    needs no Kafka client library. Produce is `POST
    /topics/<topic>` with `application/vnd.kafka.json.v2+json`; a
    consumer is made with `POST /consumers/<group>`, subscribed, polled
    with `GET .../records` and deleted. The `base_uri` it answers is
    relative (`consumers/<group>/instances/<name>`);
  - Flink (`6-flink-jobmanager`, `7-flink-taskmanager` and
    `8-flink-sql`, `infra.sh up <service>` each): the `flink-jobmanager`,
    `flink-taskmanager` and `flink-sql` services, which run and keep
    running the job of [Admissions per hour](admissions-hourly.md), one
    image built from [flink/Dockerfile](../flink/Dockerfile) on the first
    start. The JobManager's web UI and REST API are on 127.0.0.1:9806
    (`HEALTHHUB_FLINK_PORT`; always 127.0.0.1, like Kafka: it runs any
    job it is sent), its readiness probe the container's health
    (`GET /overview`, up to 5 minutes for a first build); the TaskManager
    starts once it is ready; `flink-sql` once the TaskManager has started
    and the API and Kafka are ready, as the job writes the table the API
    makes, and is ready while the job is on the cluster. Their memory is
    768 MB and 1 GB, their JVMs sized for two processors and jemalloc
    for two arenas ([Admissions per hour](admissions-hourly.md));
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
    `AITYX_URL`, `DATYX_SERVICE_TOKEN`, `HEALTHHUB_AITYX_VIA_DATYX` and
    the database's host, port, name, user and password
    to the server only, with `HEALTHHUB_MODE`, `HEALTHHUB_KAFKA_REST_URL`
    and the simulation's settings. It doesn't wait for Kafka: in dev mode
    it retries the REST proxy until it answers. CORS allows the web app's
    origins (`ALLOWED_ORIGINS`);
  - the health monitor (`0-health-check`,
    [scripts/health-check.sh](../scripts/health-check.sh)), once the web
    app, the API, the REST proxy and the Flink job are ready. It first prints where to open the app,
    `http://localhost:9801/app/` and, in a codespace, the forwarded URL,
    and waits 5 s (`HEALTH_CHECK_DELAY`). Then every 15 s
    (`HEALTH_CHECK_INTERVAL`) one line with the time, 🌐 Web, 🔌 API
    (`/api/health`), 🐘 Postgres (the API's `"db"`), 🤖 aityx (✅ the
    API has a key to reach aityx with, its own or datyx's through datyx, ⚪ it doesn't), 📨 Kafka (the REST proxy's
    `GET /topics` on `HEALTHHUB_KAFKA_REST_PORT` answers 200) and 🌊
    Flink (the JobManager on `HEALTHHUB_FLINK_PORT` lists
    `healthhub-admissions-hourly` as `RUNNING`).
- The ports, 9801 to 9806, are HealthHub's, in the 98xx range after the
  datyx index's 9800: the other demos have 88xx and 89xx (Mortgage Hub
  8880/8881, Contact Hub 8890/8891, PokerFace 8910/8911, RoboRules
  8920/8921, Cellfie 8930/8931) and datyx 99xx (9900 to 9906), so all can
  run at once.
- **Settings** ([.env.example](../.env.example), read by
  [scripts/env.sh](../scripts/env.sh)): `AITYX_API_KEY`, `AITYX_URL`,
  `HEALTHHUB_TRIAGE` (`on`, or `off` for no triage),
  `HEALTHHUB_AITYX_VIA_DATYX` (`on` in dev mode, `off` in prod) and
  `DATYX_SERVICE_TOKEN` (a secret, datyx's too: the triage's calls go
  through datyx's aityx gateway; [Triage at the
  desk](triage.md#which-way-through-datyx-or-directly)),
  `OIDC_CLIENT_ID`, `OIDC_ISSUER`, `DATYX_API_URL` ([API](api.md)),
  `HEALTHHUB_BIND_HOST`, `FLUTTER_WEB_PORT`, `API_PORT`,
  `HEALTHHUB_DB_PORT`, `HEALTHHUB_DB_ADMIN_PASSWORD`,
  `HEALTHHUB_DB_PASSWORD`, `WEB_MODE`, `HEALTHHUB_KAFKA_PORT` (9804),
  `HEALTHHUB_KAFKA_REST_PORT` (9805), `HEALTHHUB_FLINK_PORT` (9806),
  `HEALTHHUB_KAFKA_REST_URL`
  (http://127.0.0.1:9805), `HEALTHHUB_MODE` (`dev`, which runs the
  people simulation; `prod` doesn't), `HEALTHHUB_SIM_PEOPLE` (80 per
  city), `HEALTHHUB_SIM_TURN_MS` (2500) and
  `HEALTHHUB_SIM_MINUTES_PER_TURN` (15, so a simulated hour takes 10 real
  seconds), `HEALTHHUB_HISTORY_DAYS` (90, the days of admissions history
  the API writes at start in dev mode; 0 for none: [The
  history](admissions-hourly.md#the-history)),
  `HEALTHHUB_SIM_HISTORY_DAYS` (365, the days of the people's visits the
  API simulates ahead and writes at start in dev mode, for datyx's
  models to train on from the first start; 0 for none, at most 730:
  [The simulated history](simulated-history.md)), `HEALTHHUB_ALARM_EVERY_MS`
  (5000, the least real milliseconds between two [occupancy
  alarm](occupancy-alarms.md) checks; 0 turns them off),
  `HEALTHHUB_ALARM_THRESHOLD` (0.9, the share of a care center's capacity
  whose reaching, observed or forecast, is an alarm; `85%` works too,
  above 0 and at most 2), every one but the key with a default. `.env` is
  git-ignored; one copied from an older `.env.example` keeps
  `HEALTHHUB_SIM_TURN_MS=1000` and `HEALTHHUB_SIM_MINUTES_PER_TURN=60`,
  the old pace, until they are removed.
- **The pace and datyx** ([The simulation](simulation.md#pace)): a
  simulated hour every 10 s, so datyx's DeepAR inference (about 7 s a
  call for 33 care centers) comes within a simulated hour and its 24
  hours ahead are 4 real minutes of warning. datyx trains
  `occupancy_hourly` in about 106 s (a fresh datyx queues it after
  `admissions_hourly`'s two DeepAR groups, so its first model comes some
  6 minutes after datyx starts) and retrains it every 15 minutes, its
  development catalogue's `retrain` (`15min`,
  `datyx-api/src/main/resources/devdata/healthhub-catalog.json`, set as
  the table's `timeSeriesRetrain` when it has none). The numbers come
  from datyx's `training_run` table (`started_at`, `finished_at`), read
  from its database.
- **aityx's triage** ([Triage at the desk](triage.md)):
  [scripts/model-test.sh](../scripts/model-test.sh) runs the triage
  decision on aityx at each rule and threshold, and
  [scripts/triage-cases.sh](../scripts/triage-cases.sh) triages every
  complaint template and writes
  [docs/aityx-triage-cases.md](../docs/aityx-triage-cases.md); both read
  the key like the API (the environment, else `.env`), never printing it.
  After changing `healthhub_api/data/triage/triage.json`, `dart run
  tool/generate_triage.dart` in `healthhub_api/` compiles it in.
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
  `kafka` first); `devbox run flink` the Flink job (`infra.sh up
  flink-sql`, which starts the JobManager, the TaskManager, Kafka and
  PostgreSQL first; the API must have made `admissions_hourly`).
- `dart run bin/history.dart [--days N] [--sim-days N] [--dry-run]` in
  `healthhub_api/` writes the two histories to the database
  `HEALTHHUB_DB_*` names without starting the API: the admissions per
  hour drawn from rates ([The history](admissions-hourly.md#the-history))
  and the simulated year of the people's visits
  ([The simulated history](simulated-history.md)). `--dry-run` writes
  nothing and prints what both would hold; it still reads the care
  centers from the database.
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
  and `kafka-rest` are Kafka and its REST proxy, and `flink-jobmanager`,
  `flink-taskmanager` and `flink-sql` Flink and its job, as above; `api`
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
  environment, else `.env`, and `flink-sql` `HEALTHHUB_DB_PASSWORD`;
  `web` gets none. All but `flink-taskmanager` have health checks (`api`
  runs `/app/bin/server healthcheck`).
- **Kubernetes** ([k8s/](../k8s)): `bash k8s/deploy.sh HealthHub` from
  the repository's root runs compose's services on the local kind
  cluster (`k8s/up.sh` makes it), in the datyx group's namespace,
  `datyx`, every name starting with `healthhub-`, beside the demos the
  usual ports serve: the app on http://localhost:19801/app/ and Flink's
  web UI on http://localhost:19806 (the usual ports plus 10000).
  [k8s/build.sh](../k8s/build.sh) builds the three images compose builds
  (the API, the web app, Flink) and pushes them to the cluster's
  registry; PostgreSQL and Kafka are StatefulSets with a volume each,
  Kafka's readiness probe makes the topics as compose's health check
  does ([k8s/kafka-topics.sh](../k8s/kafka-topics.sh)), and the web
  app's nginx proxies `/api/` to the `healthhub-api` Service
  ([k8s/nginx.conf](../k8s/nginx.conf), a copy of docker/nginx.conf with
  that upstream, as k8s/postgres-init.sh is of docker/postgres-init.sh:
  change both together). The API reaches datyx at
  http://datyx-api:9900; the aityx settings, datyx's service token and
  the OAuth client id come from the cluster's `demo-env` secret
  (`k8s/secrets.sh`). [k8s/verify.sh](../k8s/verify.sh) checks it from
  the host: the app, the API through the proxy, the moves through
  Kafka, the Flink job and its counts, a triage through datyx's
  gateway, and `/api/datyx/*` refusing without a sign-in. Google's
  sign-in needs http://localhost:19801 among the client's authorized
  origins.
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
  the health monitor's 📨 Kafka ✅, the API in dev mode moving 560 people
  through the topic and `/api/people` reading them back) and with `docker
  compose up kafka kafka-rest`; the whole Compose stack hasn't run with
  them. The host listener (9804) has only been checked to accept
  connections, not with a Kafka client.
- The Flink services have run with `docker compose up --no-deps` beside
  a running stack (the job running, the table and the topic filling, the
  submitter's restart and the JobManager's tested), not yet from
  process-compose or a whole `docker compose up`.
- A codespace builds HealthHub's web build itself, a minute or two,
  when the datyx image wasn't made from the current `HealthHub/`, or
  hasn't been pushed since `bash image/build-image.sh datyx` was added.
- No release, deploy or CI workflows.
