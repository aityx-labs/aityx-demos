# Requests

The history of requests that shaped datyx, newest first.

## 2026-11-10: every profile has HealthHub's data, and its addresses come from the environment

Asked: pass the ports as environment variables, so the same build works
locally and on Kubernetes, and fix the issues the cluster's deploy had
left open.

Found: with Google sign-in on, a user's profile was empty (no data
source, catalogue nor model), because the development data reached only
the profiles there when the Flyway migration ran, so the cluster ran with
sign-in off. HealthHub's addresses were written into that migration
(`localhost:9803`, `localhost:9804`), which on the cluster took two port
forwarders in the API's pod, and `/api/health` reported OpenMetadata at
the address the API calls, a Service name a browser can't open, which
took a third. The container also stood at its 1536 MiB memory limit
while DeepAR trained.

Changed:

- The development data (`DevData`) takes HealthHub's addresses from
  `DATYX_HEALTHHUB_DB_HOST`, `DATYX_HEALTHHUB_DB_PORT`,
  `DATYX_HEALTHHUB_DB_PASSWORD` and `DATYX_HEALTHHUB_KAFKA` (a laptop's
  ports by default), and a profile made later, at someone's first
  sign-in, is made with HealthHub's two sources too (`ProfileMaker`), so
  every profile has them, as [data-sources.md](data-sources.md) says.
- The dev catalogue syncs and curates a new profile's sources at its next
  half-minute tick instead of the next pass, up to 10 minutes later, and
  the trainer picks them up from there: a user sees their sources at
  once, the catalogue and the models within minutes. A Kafka that didn't
  answer (HealthHub's still starting on a new cluster, which left the
  topics out of the catalogue for 10 minutes) is tried again every half
  minute for 5 minutes. A pass that fails on something unexpected no
  longer has its sources taken for new profiles half a minute later.
- `DATYX_OPENMETADATA_PUBLIC_URL` is the address `/api/health` reports
  for OpenMetadata, the dashboard's links (the address the API calls when
  unset); Docker Compose sets it to this host's port.
- On the cluster (`k8s/api.yaml`): sign-in back on, with the root `.env`'s
  client; HealthHub and OpenMetadata at their Services, the three
  forwarders gone; 2 GiB of memory. `k8s/verify.sh` checks HealthHub's
  sources in every profile, HealthHub reached at the API's addresses,
  and its topics catalogued.
- `DevDataProfileTest`: a first sign-in's profile has the two sources at
  the configured addresses, each person their own.

[data-sources.md](data-sources.md), [profiles.md](profiles.md),
[curation.md](curation.md), [api.md](api.md),
[dev-environment.md](dev-environment.md), README, `.env.example`,
`compose.yaml`, the scripts.

## 2026-11-10: on the cluster, datyx's data in reach and a first deploy that passes

Asked: kill every demo and the cluster, start the cluster again with
only the Kubernetes demos, and make sure they all deploy correctly.

Found, on the new cluster: `bash k8s/deploy.sh` exited 1 on datyx's
training check, which gave up a minute after the catalogue's first
table, 7 s before the first run was queued (the curation tags the
groups a minute or more after the first table, and the trainer looks
once a minute). Signed in on the dashboard, nothing showed: the cluster
turned sign-in on, a Google user's profile is made after the dev data's
seed (which reaches only the profiles there at start, and the dev
profile empties the database at every start), so HealthHub's sources,
their catalogue and models were the Local profile's alone, out of
anyone's reach, and HealthHub's forecasts found no data source. The
Health tab's OpenMetadata links named the Service (`openmetadata:8585`),
which no browser resolves. The API's container exited once at each new
cluster's start, PostgreSQL not yet listening.

Changed, in `k8s/` only: `api.yaml` gives the API no `OIDC_CLIENT_ID`
(sign-in off, as a local run without a `datyx/.env`), calls OpenMetadata
at `http://localhost:19902` through a third port forwarder beside the
API, and waits for PostgreSQL in an init container. `verify.sh` awaits
the catalogue's first table (6 minutes at most, with HealthHub's
database answering), its indexing and the first training run (5 minutes
after the catalogue), reads the caller's data sources through the API,
and checks that the address the API reports for OpenMetadata opens from
this host. Nothing in `datyx-api/` changed: seeding the dev data into a
profile when it is made, which sign-in on with dev data needs, is still
to do. [dev-environment.md](dev-environment.md).

## 2026-11-09: datyx on the local Kubernetes cluster

Asked: run every demo on a local Kubernetes cluster (kind), datyx among
them, up and working, beside the demos running locally.

Changed: `k8s/` (the manifests, `build.sh`, `verify.sh`) runs
PostgreSQL, Elasticsearch, OpenMetadata and the API in the cluster's
`datyx` namespace ([dev-environment.md](dev-environment.md));
`docker/kustomization.yaml` makes the PostgreSQL init script a
ConfigMap; `docker/api.jvm.Dockerfile` takes `PACKAGE_ARGS`, more
build-time settings, empty by default (Compose builds as before), which
the cluster's build uses to put Swagger UI in its dev-profile jar.
Nothing in `datyx-api/` changed: the cluster reaches HealthHub at the
dev data's laptop addresses through port forwarders beside the API, and
sets the host names the API answers in its environment.

## 2026-11-01: HealthHub's occupancy alarms and forecasts curated

Asked (a review of HealthHub's occupancy alarms merged with the data
quality work): HealthHub's API now makes `occupancy_alarm` and
`occupancy_forecast` and publishes `healthhub.alarms`, but the curation
document and its test fixture left them out, so they were synced with
their schema's checks only, while the document said it curated every
table.

Changed: `devdata/healthhub-catalog.json` curates both tables (22 and 9
checks: an alarm's kind follows its levels, each level reaches the
threshold by its own measure, its hour and peak are the forecast's, its
capacity is its kind's, its care center is one of the run's, its
occupancy no more than the view counts; a forecast's lead, quantiles
and care center; information: the actual alarms, the settled hours
observed outside the band), the topic `healthhub.alarms` (every field,
nested ones too), two glossary terms (Occupancy Alarm, Occupancy
Forecast), the `occupancy-alarms` pipeline of HealthHub's API and its
lineage from `occupancy_hourly` and `care_centers`. The fixture has both
tables as `lib/db.dart` makes them, with correct rows; new defects in
`HealthHubChecksTest`; `CurationTest` holds the document and the
fixture to every `CREATE TABLE` and `CREATE VIEW` of HealthHub's
`lib/db.dart`, so the next table HealthHub adds fails it until it is
curated. `curation.md`.

## 2026-11-01: HealthHub's occupancy model retrained every 15 minutes

Asked (HealthHub's request): make sure the occupancy forecast is
retrained in time for the live simulation.

Changed: the development catalogue (`devdata/healthhub-catalog.json`)
sets `occupancy_hourly`'s `timeSeriesRetrain` to `15min` (it was the
default, `1D`). Measured on the development machine: a DeepAR run of
the group takes 106 s (30 epochs of 50 batches; `admissions_hourly`'s
first, 182 s), so a run every 15 minutes keeps the trainer, one run at a
time, free most of the time; a failed run (too little data at a fresh
start) is tried again after 15 minutes rather than an hour.
HealthHub's simulation runs a simulated hour every 10 s, so 15 minutes
is 90 simulated hours of new data. `curation.md`.

## 2026-11-01: an aityx gateway, its account, and where calls will be personalized

Asked: in the datyx dashboard, an aityx tab showing the requests routed
to aityx, and in the future personalize them (the dashboard's tab and
HealthHub's routing are theirs).

Changed: new package `datyx.aityx`. `POST /api/aityx/v1/systemone` is a
gateway to aityx's `/v1/systemone`: the body (1 MB at most) goes through
the personalization hook (`AityxPersonalizer`, today `NoPersonalization`,
which changes nothing) to aityx with datyx's key (`AITYX_API_KEY`, never
logged, stored or answered), and aityx's status, body and
`X-aityx-Mode` come back as they were; no key is a 503. A signed-in
user calls it as on the rest of `/api`; a service presents
`X-Datyx-Service-Token` (`DATYX_SERVICE_TOKEN`, compared in constant
time) instead, through a security policy of its own for
`/api/aityx/v1/*` (`AityxGatewayPolicy`). Every call is recorded
(`aityx_call`, `V9__aityx_calls.sql`): caller, purpose
(`X-Datyx-Purpose`), model, decision, questions, status, mode, latency,
input tokens and their cost ($0.042 per million), the request and the
answer (64 KB each), the latest 2,000 per profile; a service's calls
are the services' bucket, every profile's to see in dev mode only
(`DATYX_AITYX_SHARE_SERVICE_CALLS`; empty, the profile decides, so
Docker Compose's prod image shares nothing; `AityxShareConfigTest`). `GET /api/aityx` answers the account
(totals, the last 24 hours, by purpose, model and decision, the latest
50 calls, whether personalization is active), `GET /api/aityx/calls/{id}`
one call with its request and answer, `GET /api/aityx/v1/status` whether
datyx has a key (for HealthHub, which counts on aityx only when one of
them has). Settings in `scripts/env.sh`
(also from the root `.env`), `scripts/api.sh`, `compose.yaml` and
`.env.example`. Tests (`AityxGatewayTest`, `AityxAuthTest`,
`AityxNoKeyTest`, aityx a local stub); new `aityx.md`, `api.md`,
`auth.md`, `dev-environment.md`, README.

## 2026-11-01: Data quality across HealthHub's data, set in OpenMetadata at every start

Asked: cover data quality on our data; on initialization, update or set
OpenMetadata.

Changed: `Quality` runs more of OpenMetadata 2.0.7's test definitions,
each with SQL aggregates on the read-only connection:
`columnValuesToBeNotInSet`, `columnValuesToNotMatchRegex`,
`columnValuesMissingCount`, `columnValueLengthsToBeBetween`, a number
column's min, max, mean, median, standard deviation and sum,
`tableRowCountToEqual`, `tableColumnCountToEqual` and `...ToBeBetween`,
`tableColumnNameToExist`, `tableColumnToMatchSet`, and custom SQL
(`tableCustomSQLQuery`, `ROWS` or `COUNT`, an operator and a threshold)
from a curation document too: one read-only `SELECT`, checked when the
document is read (no semicolon, comment, write, lock or session word,
nor a function reaching beyond the query) and run in a read-only
transaction with the statement timeout. A check's parameters are
checked against its definition; a check has a `key` telling apart
those of one test. A test case is written only when new or changed,
and a curation removes the ones datyx made that it no longer checks
(those with its mark). HealthHub's document now has 137 checks over its nine
tables and views (keys, not-nulls, ranges, sets, formats, lengths, the
shape the time series read, and consistency across columns and tables:
hourly counts against the admissions, triage against admissions and
templates, references to care centers and conditions, views against
their sources); the composite key's check is now
`tableCustomSQLQuery_primary_key`. `DevCatalog`, at every start then
every 10 minutes, sets every check in OpenMetadata, runs it and logs
one line (checks set, passed, failed). The curation puts in the domain
and the data product only the assets not in them yet: adding all again
went over the call's 5 s once the database service held its test cases
(22 s), so a pass never finished. A sync answers `testsCreated` and
`testsUpdated`. Run against the live stack: 217 checks, 215 passing;
the two failures are the data's (`admissions_hourly` counting 104 hours
of admissions the `admissions` table hasn't; two care centers' websites
that aren't web addresses). Tests (`QualityTest`, `QualityChecksTest`,
`HealthHubChecksTest`); `catalog.md`, `curation.md`.

After review: datyx marks the test cases it sets with a tag,
`Datyx.Managed` (a `Datyx` classification), and removes only marked
ones, so someone's test case named like datyx's (OpenMetadata's console
names them `{column}_{test}_{random}`) is never deleted; the ones set
before get the mark at the next pass. A check that can't run (an error,
past the timeout) fails with the error and the others still run, on a
connection opened again when the error broke it; a profile that can't
be read is skipped; queries time out at 50 s, under the connection's
60 s socket timeout. A min, max or mean of no values is `Aborted`, not
a failure, and the first pass at a start waits up to 5 minutes for the
tables that should have rows to have them. Custom SQL can't call a
guarded function by a quoted name (`"pg_sleep"(1)`) nor use Unicode
escapes, while a quoted name may now hold `$`, `;` or `--`, so the
composite-key check works for any column names. `admissions_hourly`'s
count check fails only on hours Flink counted beyond the admissions
table (the feed lost them), since HealthHub's spec allows Flink to count
fewer (a restart recounting the topic, the retention's edge, a database
down); the hours counted short are information
(`tableCustomSQLQuery_hours_counted_short`). A triage call's `millis`
may reach 180 s, its client's three timeouts.

## 2026-11-01: the inference account hour by hour, by model, with latency

Asked (of the dashboard): the Inference view should be a dashboard, not
so repeated, more like the time series of inferences and statistics; its
charts need what the API didn't answer.

Changed: `GET /api/inference` takes `?hours=` (24 by default, up to the
window's 168), and answers `hours`; each hour of `perHour` now also has
its series `scored`, `p50Millis` and `p95Millis` (null without a call),
and `byModel`, each model's (a group's algorithm) calls, failures and
series in it; `models` has a model per group's algorithm (its latest
run, its calls those that algorithm answered), as `byModel`, and
`models` and `calls` name their `algorithm`. The hours are bucketed
once over the window's calls. Tests; `inference.md`, README.

## 2026-11-01: DeepAR trains its groups, on being switched on or retrained

Asked: as for XGBoost, when a DeepAR group of tags is enabled or
retrained, train it; then HealthHub can show its admissions per hour
with DeepAR's forecast of the hours after, in the care center view
(HealthHub's and the dashboard's changes are theirs).

Changed: the trainer trains DeepAR groups as it trains XGBoost's (never
trained, switched on, `timeSeriesRetrain`, on request): `DeepArData` lays
each series out step by step, `DeepArTrainer` trains DJL 0.39's DeepAR on
its PyTorch engine (libtorch 2.7.1, CPU, bundled by a Maven profile per
platform), a negative binomial for counts, a Student's t otherwise, the
last horizon held out for its test (MAE of the median, RMSE, naive and
mean baselines, the 80% band's coverage), the network's parameters kept
with the run. DJL can't sample either distribution on PyTorch, so datyx
draws the paths in Java (`Distributions`). A group without a horizon
forecasts 24 steps. Inference on a DeepAR model answers each series'
forecast step by step, the mean and the 10th, 50th and 90th percentiles
(`DeepArInference`); `GET /api/training` lists DeepAR groups with the
horizon they forecast, and a manual run of one is accepted. TableReader
feeds either (`Rows`). The JVM image sets `DJL_CACHE_DIR`. On
HealthHub's `admissions_hourly` a run takes about 45 s, a third better
than the naive forecast per hour. Tests; `training.md`, `inference.md`,
`catalog.md`, `api.md`, README.

Merged with the groups switched on through OpenMetadata (a group with
several algorithms, one run each): every algorithm of a ready group is
queued on schedule, a run trains with its own algorithm, `GET
/api/training` answers one model per group and algorithm, and inference
answers with XGBoost's model when a group has both, unless the request
names an `algorithm`.
## 2026-11-01: HealthHub at top quality in OpenMetadata, described and in context

Asked: check HealthHub's data classification and quality indexing in
OpenMetadata, add the OpenMetadata calls needed after the data
initialization, reset what needs it; the console should show everything
at top quality, described and in context.

Changed: every database sync now profiles each table and runs the
checks its schema implies (`Quality`: no nulls where `NOT NULL`, no
duplicate keys), with SQL aggregates, writing the profile and each check
as a test case with its result; the answer gains `tests`, `failed` and
`failing`. A sync keeps what a PUT would clear: data products, domains,
the certification, the database's and schemas' descriptions. New
`Curation`: a document's owners, domain, data product, glossary, tiers,
descriptions, checks, TimeSeries roles, pipelines and lineage written to
OpenMetadata, a data contract per table validated by datyx, and the
certification each table and topic earns. In development, `DevCatalog`
waits for HealthHub's data initialization (its tables described, which
HealthHub's API now does), then syncs and curates HealthHub's sources
with `devdata/healthhub-catalog.json`, every 10 minutes, and runs Data
Insights. Reset: HealthHub's services in OpenMetadata, three scratch
services and a stray Kafka topic were deleted and everything rebuilt by
datyx. Result: 18 assets 100% described, owned and tiered, 113 tests
passing, 12 assets Gold, 8 contracts kept. Tests (`QualityTest`,
`CurationTest`, `CatalogResourceTest`); `catalog.md`, new
`curation.md`, `data-sources.md`, `api.md`, README.

## 2026-11-01: a PII classification for every column and JSON field, by the GDPR

Asked: make sure the catalogue has a PII classification for every data
column and JSON property, in OpenMetadata if possible, following the
GDPR's definitions and standards for data classification.

Changed: every sync (`POST /api/datasources/{id}/catalog`) tags every
column, and every field of a topic's records (nested ones too), with
OpenMetadata's own `PII` classification (`None`, `NonSensitive`,
`Sensitive`), and those holding personal data with its `PersonalData`
(`Personal`, `SpecialCategory`), from names alone (`Pii`): personal only
in a record about a person; special category for Art. 9 and Art. 10
data and the facts of a health care record (Recital 35); direct and
quasi-identifiers, keys (pseudonymous, Recital 26) and other facts as
personal. Each tag is `Automated` with its GDPR reason; a person's own
tags win. Written by a JSON Patch after the PUT (a PUT merges tags, and
both classifications are mutually exclusive); the sync answers how many
columns or fields hold `personal` and `special` data. Tests
(`PiiTest`); `catalog.md`, `api.md`, README.
## 2026-11-01: switching a group on is an event datyx captures, and it trains all its algorithms

Asked: the trigger for training is enabling the tag group; make sure the
API captures that event, and train every algorithm associated with the
group. (The dashboard shows the algorithms and the events, in its
folder.)

Changed: a group may carry several algorithm tags (`TimeSeries.care.XGBoost`
and `TimeSeries.care.DeepAR`); specs say `algorithms` (XGBoost first;
`["DeepAR"]` when none) beside `algorithm`, and `PUT .../timeseries`
takes `algorithms`. Runs are per algorithm (latest run, one at a time,
schedule), inference and `GET /api/training` use XGBoost's. OpenMetadata
tells datyx: at start datyx makes the event subscription
`datyx-catalog-events` (Notification, tables, `entityUpdated`, a Webhook
to `POST /api/catalog/openmetadata-events` at
`datyx.openmetadata.callback-url`, `host.docker.internal` in development),
authenticated by OpenMetadata's `X-OM-Signature` (HMAC-SHA256 of the raw
body, base64) with a secret datyx sets (`DATYX_OPENMETADATA_WEBHOOK_SECRET`,
else a random one per start), checked in constant time; the path is
outside sign-in, the rest stays secured. Each switch of a group's
Disabled tag is a `GroupEvent` (`group_event`, V8: on or off, via the
webhook, datyx's switch or the minute's check, the table's version, who,
when, the runs it queued); a switch on queues one `ENABLED` run per
algorithm of the group at once, deduplicated across the three ways (one
locked decision and a unique index on a group's and algorithm's queued or
running run). `GET /api/catalog/events` lists them; runs carry `eventId`.
Manual training takes an `algorithm` (DeepAR refused: no trainer yet).
Reviewed adversarially (security, triggers, regressions); five findings
fixed with tests (non-canonical service names, a late switch-off, a
version OpenMetadata reused, a removed group's Disabled tag read as a
switch on). Tests (75); `catalog.md`, `training.md`, `api.md`, `auth.md`,
`dev-environment.md`.

## 2026-11-01: groups switched off by a tag, and switching one on trains it

Asked: on the Catalog's view of a table's tag groups, let a group be
disabled; HealthHub's chronic admissions group disabled by default; when
a group is enabled, that event triggers its training, whatever its
algorithm; the tagging as the trigger, viewable in OpenMetadata. (The
switch on the Catalog and Training tabs is the dashboard's change.)

Changed: a group is switched off by a tag on its table,
`TimeSeries.{group}.Disabled` (`TimeSeries.Disabled` for the default
group), made with the group's roles and algorithms; `Disabled` can't
name a group. Specs say `enabled`. `PUT /api/datasources/{id}/timeseries/enabled`
adds or removes the tag. The trainer never trains a group switched off
(nor on request, a 409), and queues an `ENABLED` run of any group
switched on: seen off at its last look, or, from OpenMetadata's version
history of the table (GET /tables/{id}/versions), its tag removed after
its latest run; the run's `trigger_note` (V7) names the change (table
version, who, when). A switch on through datyx is checked at once, and a
switch off is noted at once, as OpenMetadata merges one user's quick
changes into one version. Runs go to the group's algorithm: XGBoost
trains, DeepAR fails saying datyx has no DeepAR trainer yet. HealthHub's
`chronic` group of `admissions_hourly` is switched off in development's
OpenMetadata. Tests; `catalog.md`, `training.md`.

## 2026-11-01: inference on the trained models, and its account

Asked: an Inference panel on the dashboard, to account for inference
calls and their statistics. (The panel is the dashboard's change.)

Changed: `POST /api/datasources/{id}/inference` scores series named by
their key, or all those still observed, with a group's latest model:
`Inference` reads only those series and their cohort's end from the
source, builds their features as training did, and predicts with the
model loaded from the run (kept, the latest 8). Training runs now keep
the group as trained, its categories' codes and the features with the
model (`Dataset` codes by them when given, and gives every series'
features at its end; `TableReader` reads series by key). Each call is
kept in `inference_call` (V6); `GET /api/inference` answers the last 7
days' account: totals, latency percentiles, per model, per hour, the
latest calls. Secured like the rest. Tests; `inference.md`,
`training.md`, `api.md`, README.

## 2026-11-01: XGBoost trained by a component started with the API

Asked: in a separate component, started with the API, train XGBoost
(XGBoost4J) on the groups tagged for it; let the user set how often a
model is retrained, in OpenMetadata if possible; train at start when
there's no training yet, and retrain by the setting; show the training's
activity and results in a view of its own in the navigation.

Changed: `datyx.training`: `Training`, a bean started with the API,
checks every minute (Quarkus Scheduler) the groups tagged
`TimeSeries.*XGBoost` and ready in each source's catalogue, queues the
never-trained and those whose table's new `timeSeriesRetrain` (a span or
never, 1D when not set: in OpenMetadata) has passed, and trains them one
at a time on its own thread: `TableReader` reads the group's columns
from the source, `Dataset` builds the examples (cutoffs, windows of the
past, the Target summed over the horizon as the label, split by time),
`XgbTrainer` trains XGBoost4J 3.4 and measures it against the naive and
mean baselines, with SHAP weights and the highest scores. Runs are kept
in `training_run` (V5) with the model; interrupted ones are failed at
start. `GET /api/training`, `GET /api/training/runs/{id}`,
`POST`/`PUT /api/datasources/{id}/training` (train now, how often). The
spec answers `retrain`, and checks it. The JVM image installs `libgomp`;
macOS needs Homebrew's `libomp`. Tests; `training.md`, `catalog.md`,
`api.md`, `dev-environment.md`, README.

## 2026-11-01: Kafka clusters as data sources, in the catalogue

Asked: add Kafka to the data sources, connect the dev profile to
HealthHub's Kafka as it is to HealthHub's database, and show it in the
dashboard's Catalog, in a section of its own.

Changed: a fourth type, `kafka`: bootstrap servers, security protocol
and SASL mechanism, user and password, encrypted like the other
details, the password never answered back (`V4__kafka_sources.sql`
widens the type's check). `POST .../catalog` on a Kafka source reads its
topics with Kafka's client (`StreamReader`): partitions, replication,
cleanup and retention, and the fields of the latest JSON records, and
writes them to OpenMetadata as a `Kafka` messaging service and its
topics, keeping what people added there; `GET .../catalog` answers the
topics; deleting the source removes them. The dev data seeds HealthHub
Kafka (`localhost:9804`) in every profile next to HealthHub
(`R__HealthHub_data_source` version 2). Tests; `data-sources.md`,
`catalog.md`, `api.md`, `dev-environment.md`, README.

## 2026-11-01: XGBoost groups, scoring each patient's care in the next 30 days

Asked: score each patient's hospital care in the next 30 days with
XGBoost, the horizon a parameter; nothing hard-coded: tag a group with
the XGBoost algorithm in the tag schema, explicitly for now, so a
component to come finds the groups tagged XGBoost and trains them; for
now, the tagging right in OpenMetadata and clear in the catalogue.

Changed: a group's algorithm is a tag on the table, `TimeSeries.XGBoost`
(default group) or `TimeSeries.{group}.XGBoost`, `TimeSeries.DeepAR`
likewise, none being DeepAR as before; made with the vocabulary and with
each group. The table property `timeSeriesHorizon` (a pandas offset,
shared by the groups), required for XGBoost. The spec answers the
group's `algorithm` and `horizon`, with two algorithms or XGBoost
without a horizon as problems; groups come from the table's algorithm
tags too; an algorithm's name can't be a group's. `PUT .../timeseries`
takes `algorithm` and `horizon`, replacing only the group's algorithm
tag; `GET .../timeseries?algorithm=XGBoost` answers that algorithm's
groups; `GET .../catalog` answers a table's own tags. The role
descriptions say what each becomes to XGBoost. In development,
HealthHub's new `patient_days` view (its own change) is tagged as the
`care` group: XGBoost, the hours of care over 30 days per run and
person. Tests; `catalog.md`, README.

## 2026-11-01: groups of time series tags in one table

Asked: tag separate groups in the same table, to train on it more than
once with partly the same columns: in `admissions_hourly`, one series
forecasting `admissions`, one `acute_admissions` and one
`chronic_admissions`, all with the same timestamp.

Changed: a group of roles is tagged under the group's own tag of the
TimeSeries classification (`TimeSeries.acute.Target`, a child of
`TimeSeries.acute`), the existing tags being the `default` group's;
`GET .../timeseries` answers one series per table and group (a new
`group` field), each checked on its own; `PUT .../timeseries` takes a
`group` and replaces only that group's tags, making the group's tags in
OpenMetadata when missing; a role's name, or a name with other than
letters, digits, `_` and `-`, is a 400. The frequency and missing rows
stay the table's, shared by its groups. A column's tags are compared
without regard to order, so setting a group again doesn't patch what
didn't change. Tests; `catalog.md`, README.

## 2026-10-31: HealthHub's data in OpenMetadata, as time series

Asked: make sure OpenMetadata can find HealthHub's data, as a step
towards training a DeepAR model (GraalPy, in the API) on the number of
admissions per hour; keep it decoupled, so datyx understands HealthHub's
model as it would a customer's, without HealthHub changing, by indexing
it and by tags on the timestamp, the target and the other fields DeepAR
takes, picked by hand for now and suggested by a tool later.
(HealthHub's hourly aggregation, a Flink job, is HealthHub's change, in
its folder.)

Changed: the catalogue (`datyx.catalog`): `POST /api/datasources/{id}/catalog`
reads a PostgreSQL source's tables through JDBC metadata and writes them
to OpenMetadata as the service `datyx-ds-{id}` (no credentials), keeping
what people added there; `GET` answers them back; deleting a source
removes its service. The `TimeSeries` classification (Timestamp, Target,
SeriesKey, StaticCategorical, StaticReal, KnownCovariate, PastCovariate,
each with its DeepAR field) and the table properties `timeSeriesFrequency`
and `timeSeriesMissing`, made in OpenMetadata by datyx;
`GET /api/datasources/{id}/timeseries` reads the tagged tables as series
with their problems, `PUT` sets a table's roles. `OpenMetadataSession`
signs in (a bot token, or the stack's admin by default:
`DATYX_OPENMETADATA_*`), the client gained the calls and a lenient JSON
reader; tests; `catalog.md`, the API, data sources and dev environment
specs, README, `.env.example`, `compose.yaml`, `scripts/`.

## 2026-10-30: the health with the profile; hello, greetings and status gone

Asked: a health check as the Quarkus SmallRye Health guide describes, with
an attribute stating the execution mode or profile, injected by Quarkus;
dev mode in local, process-compose and Docker Compose development; remove
the greeting and hello resources, and the status resource, the greetings'
table out of the migrations; reset the database to zero in dev mode.

Changed: `ModeHealthCheck`, a liveness check named `datyx` in
`/api/health`, always UP with the version, the profile (`quarkus.profile`),
the launch mode (the injected `LaunchMode`), `jvm` or `native` and the
start time. `GreetingResource`, `Greeting`, `HelloResource` and
`StatusResource` are gone, with their tests (`HealthTest` covers the
health); the greetings' table is out of the migrations altogether (V1 is
now `V1__data_sources.sql`), and the dev profile starts from an empty
database (`%dev.quarkus.flyway.clean-at-start=true`). The health
monitor checks the API on `/api/health/live`, and the dashboard reads
`/api/health` (its own spec says how). `API_MODE=dev` (`quarkus:dev`) was
already the default for `devbox services up`; Docker Compose now builds and
runs the API with the `dev` profile (`DATYX_API_PROFILE`, the Dockerfiles'
`PROFILE` argument, `prod` when built without compose), so the dev data
loads there too: Flyway's locations are fixed at build time.

## 2026-10-29: the index on 9800, HealthHub's database on 9803

Asked: make the datyx index the first port of the group (9800).

Changed: the index (datyx-index/) moves from 9907 to 9800 and HealthHub
up one, to 9801 to 9803; the dev data source for HealthHub's PostgreSQL
(`R__HealthHub_data_source`), its test and the API spec now say port 9803.

## 2026-10-29: OpenMetadata in the API's health check

Asked: remove the OpenMetadata card from the datyx index, and cover
OpenMetadata in the datyx API's health check, on the API's card.

Changed: `OpenMetadataHealthCheck`, a readiness check in `/api/health`
beside the database's, through `OpenMetadataClient` (off in the test
profile); the index's OpenMetadata card is gone and the API card says its
health check covers PostgreSQL and OpenMetadata, with OpenMetadata's UI
and sign-in; the API spec.

## 2026-10-29: Flyway locations by profile, dev data for HealthHub

Asked: Flyway on the datyx API with different folders for the Quarkus
dev runtime and the regular (prod) runtime, so migrations and data can
differ between them; in dev, a data source pointing at HealthHub's
database.

Changed: `quarkus.flyway.locations` is `db/migration` and dev mode adds
`db/devdata`; `db.devdata.R__HealthHub_data_source`, a repeatable Java
migration seeding HealthHub's PostgreSQL as the HealthHub data source of
every profile (the local one made when missing), encrypted through the
new `AccessCodec`, which the resource uses too; `DevDataTest`; the API,
data sources, dev-environment specs.

## 2026-10-29: profiles, and encryption at rest

Asked: profiles on the API and the dashboard, as the other apps have:
when someone signs in with an identity such as an email, create a profile
for it if there is none, else load it; a profile can have more than one
identity, so it isn't bound to one email, and may be shared later; for
now the basic creation, and with each profile an encryption key that
encrypts the sensitive data, such as data source usernames, passwords
and locations.

Changed: the `Profile` and `ProfileIdentity` entities, `Profiles`
resolving the caller's profile by the token's issuer and subject and
making one on the first call (`ProfileMaker`), `Crypto` (AES-256-GCM: a
master key from `DATYX_MASTER_KEY` wrapping a key per profile, a
development key in dev and test modes, required otherwise),
`GET /api/profile`, `profileId` in `GET /api/me`, `profiles` in the
status; data sources owned by a profile, listed, read and removed within
it, their access details one encrypted document (`access`) in place of
the clear columns, and the name unique per profile
(`V2__profiles_and_encrypted_access.sql`, which drops the pre-profile
rows); `DATYX_MASTER_KEY` in `.env.example`, the scripts and
`compose.yaml`; `ProfileTest`, `CryptoTest`, the auth-off test; the
`profiles.md` spec, and the data sources, auth, API and dev-environment
specs. The dashboard gained a Profile tab
([../../datyx-dashboard/specs/dashboard.md](../../datyx-dashboard/specs/dashboard.md)).

## 2026-10-29: the API starts without a .env

Asked: spin up a codespace for each demo group. In the datyx one the API
never answered: "Failed to load config value ... datyx.oidc.issuer".

Changed: scripts/env.sh exported `OIDC_ISSUER` empty when neither the
environment nor `.env` set it, which overrode the Google default in
application.properties with nothing. It now defaults to
`https://accounts.google.com` too, so a fresh checkout (a codespace has
no `.env`) starts the API, with authentication still off until
`OIDC_CLIENT_ID` is set.

## 2026-10-29: the dev containers by demo group

Asked: separate the dev containers, images and Codespaces configurations
by demo group.

Changed: nothing in this folder. The API now runs in a codespace, in the
datyx group's dev container, **datyx demos**
(`.devcontainer/datyx/devcontainer.json` at the repository root), on the
group's image `docker.io/aletyxcode/samples-and-demos-datyx` (`bash
image/build-image.sh datyx`: GraalVM, Flutter and the API's Maven
dependencies), which starts it with the dashboard, HealthHub and the
index page. There was no per-demo dev container for it to replace; the
per-demo ones of the other folders were removed.

## 2026-10-28: data sources, and OpenID Connect with Google

Asked: the first entity, data sources, which users add and remove:
databases, S3 or filesystem for now, each with its access details; OIDC
authentication on the API, the dashboard and HealthHub, with the user's
identity propagated through, from HealthHub to the datyx API seamlessly;
Google sign-in set up, with `datyx` and `healthhub` as the Google ids.

Changed: the `DataSource` entity and `/api/datasources` (list, get, add,
remove; [data-sources.md](data-sources.md)), counted in `/api/status`;
Quarkus OIDC as a bearer-token service with Google as the issuer,
`/api/auth/config` and `/api/me`, `CurrentUser`, and
`AuthConfigSourceFactory`, which turns authentication on when
`OIDC_CLIENT_ID` is set and accepts `OIDC_EXTRA_AUDIENCES` (HealthHub's
client) too ([auth.md](auth.md)); the settings in `.env.example`,
`scripts/env.sh`, `scripts/api.sh` and `compose.yaml`; the tests point
OpenMetadata at a closed port; `DataSourceResourceTest`, `AuthOffTest`,
`AuthOnTest` (the OIDC test server as the issuer). The dashboard and
HealthHub changed in their own folders.

## 2026-10-28: API only; the dashboard in its own folder

Asked: create `datyx-dashboard`, a Flutter app like the other demos',
accessing the datyx API; the `datyx` module becomes API only, the
dashboard a separate app that invokes it.

Changed: `datyx-dash/` moved to `../datyx-dashboard/datyx_dashboard/`,
with its own devbox, process-compose, Docker Compose, scripts, id and
version files and specs ([../../datyx-dashboard/specs/](../../datyx-dashboard/specs/)).
Here: the `5-dash` process, the `dash` compose service, `scripts/dash.sh`,
`scripts/make.sh`, `docker/dash.Dockerfile`, `docker/nginx.conf`, the web
targets of `build.sh` and the Makefile, Flutter in `devbox.json`, and
`FLUTTER_WEB_PORT`, `DATYX_DASH_PORT` and `WEB_MODE` are gone; the health
monitor starts after the API and checks API, Postgres, OpenMetadata and
Search; the API's port is published by `compose.yaml` so the dashboard's
container reaches it; README, CLAUDE.md (data and logic here, views in the
dashboard's folder), AGENTS.md and these specs. The repository's
`start-all.sh` waits for datyx on the API's `/api/health`, since it has
no web port.

## 2026-10-28: the dashboard, datyx-dash

Asked: a separate module, `datyx-dash`, a Flutter dashboard (like every
demo's app) that invokes the API; from now on, data and logic go in the
API and views in the dashboard, recorded in the project's CLAUDE.md.

Changed: the Quarkus project moved into `datyx-api/`; `datyx-dash/`, a
Flutter web app with status cards, a hello call, the greetings on record
and a panel of every API call, served under `/app/` on 9906 by a small
Dart web server (release) or Flutter's dev server (debug), both proxying
`/api/` to the API; the API gained `GET /api/status` (database,
OpenMetadata, greetings count) and `GET`/`POST /api/greetings` on the
`Greeting` entity, with an OpenMetadata REST client; `scripts/api.sh`
(was `app.sh`, `API_MODE`), `scripts/dash.sh`, `scripts/make.sh`,
`build.sh` with the web targets, the `5-dash` process, the `api` and
`dash` compose services with their Dockerfiles and nginx; `DATYX_PORT`
became `DATYX_API_PORT`, `DATYX_DASH_PORT` added; Flutter in devbox; the
module convention in CLAUDE.md; README and specs.

## 2026-10-28: start datyx

Asked: a new `datyx` folder for the system, following the demos' patterns
(devbox, process-compose, Docker Compose, the id and version files), with
group and artifact id both `datyx`; a Quarkus app on GraalVM, a PostgreSQL
database and an OpenMetadata server, on port 9900 for the app and 99xx for
the rest; start it up. Then: keep the app a simple hello-world REST API, no
pages, with the usual components (health, Hibernate ORM with Panache).

Changed: the folder, as a git repository, with `devbox.json` (GraalVM CE,
Maven), `process-compose.yaml`, `compose.yaml`, the scripts, the
Dockerfiles, PostgreSQL's init script, the Quarkus project (`GET
/api/hello`, the `Greeting` entity, health, OpenAPI, tests), the Makefile,
the id and version files, README, AGENTS.md, CLAUDE.md and these specs.

## 2026-11-01: HealthHub's occupancy per hour, a DeepAR series

Asked (HealthHub's request): the care center view plots its occupancy
and its DeepAR forecast.

Changed: the development catalogue (`devdata/healthhub-catalog.json`)
curates HealthHub's new view `occupancy_hourly`: tier 2, the glossary
term *Hourly Occupancy*, its columns' terms, checks (the run id's shape,
at least one person a row), the lineage from `admissions` and
`medical_conditions`, and its TimeSeries roles, group `default`
(Target `occupancy`, SeriesKey `run_id` and `hospital_id`, hourly,
missing zero), trained by DeepAR. `catalog.md`, `training.md`,
`curation.md`.

