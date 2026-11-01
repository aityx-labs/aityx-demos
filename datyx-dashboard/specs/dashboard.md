# The dashboard

The datyx dashboard is a Flutter web app in `datyx_dashboard/` (package
`datyx_dashboard`), in the aityx dark palette like every demo's app. It
invokes the datyx API ([../../datyx/specs/api.md](../../datyx/specs/api.md))
and shows what it answers, with the details of each call. It computes,
stores and decides nothing on its own: when a view needs data the API
doesn't have, the API gets it first.

## What it shows

One screen, `DashboardScreen`, with an app bar and six tabs under it
(a `TabBar`, as the demos' apps have), in the order of `DashboardTab`:
Data sources, Catalog, Training, Audit, Health, Profile. Data sources opens at
start, unless the page's address names another (see Kept across a
reload).

- The app bar: the title, the account corner (`UserMenu`: nothing while
  the API has authentication off; Google's own sign-in button while
  nobody is signed in; the user's picture, name, email and a sign-out
  button once someone is) and the refresh button, which asks the API
  again for the status, the data sources and the profile, as a timer
  does every 15 s.

- **Data sources** (`DataSourcesCard`): the list from
  `GET /api/datasources`, newest first, one row each with the kind's
  icon, the name and kind, where it points on one line
  (`engine://host:port/database as user`, `s3://bucket/prefix (region)
  at endpoint`, the path, or `kafka://servers (protocol, mechanism) as
  user`, the protocol left out when plain text), the description, when and by whom it was
  added, and a remove button, which confirms and then `DELETE`s. An Add
  button opens `AddDataSourceDialog`: the kind (Database, S3 bucket,
  Filesystem, Kafka), name and description, then the fields of that kind
  (engine and port, host, database, username and password; bucket,
  region and prefix, endpoint, access key id and secret access key; the
  path; or the bootstrap servers, the security protocol and SASL
  mechanism picked from the API's lists, and with a SASL protocol the
  username and password), the required ones checked before the `POST`; secrets go as
  typed, the rest trimmed. Errors the API answers show in a snack bar.
  With authentication on and nobody signed in, the card says to sign in
  and the list isn't asked. A line in red above the card when the API
  itself didn't answer.

- **Catalog** (`CatalogTab`): what datyx makes of the data in each
  source, as the catalogue (OpenMetadata) has it
  ([../../datyx/specs/catalog.md](../../datyx/specs/catalog.md)). Under
  an intro card, the sources come in sections, each with a title (an
  icon, its name and what its cards show) and room above it, and 16 px
  between cards: **Databases**, **Streams** (Kafka sources) and **Not
  read yet** (S3 and folder sources), a section only when it has a
  source. Each database source is a card (`SourceCatalog`) that loads
  `GET /api/datasources/{id}/catalog` and `.../timeseries`: "Not
  catalogued yet" before a first read; **Read schema** (then **Read
  again**) calls `POST .../catalog` and says how many tables and columns
  it read. Each table is a tile that opens on its columns: name (a key
  icon for the primary key), OpenMetadata's type, and its tags, a
  TimeSeries tag shown as its role and what it is to the algorithm that
  trains its group, DeepAR's field (`Target · target`) or its part in
  XGBoost's dataset (`Target · label: sum over the horizon`), with its
  group first when it isn't the default one (`acute: Target · target`).
  The table's own tags come first, *on the table*: a group's algorithm
  tag shown as `care: trained by XGBoost`. A table can hold several time
  series, one per group of tags, each read by the API on its own and
  trained by its own algorithm (DeepAR, or XGBoost). Each group has a
  color, on its tags and its box (a dot and the border): the
  default group first, then the others by name, take orange, blue and
  aqua (`groupPalette`, checked with the dataviz skill's validator to
  stay apart side by side on the dark surface, for color blindness too;
  no fourth hue does with these three), and any past the third a neutral
  gray. The status colors (green, amber, red) are never a group's. The
  name is always on the chip and the box, so the color is never alone. A tagged table has
  a badge, *time series: ready* or *needs work* for one group, *3 time
  series: all ready* (or how many are) for several; under its name, even
  closed, what trains each group, in the group's color (`care: XGBoost,
  30D ahead`, `acute: DeepAR`); and a box per group named by its
  algorithm (`DeepAR · acute`, `XGBoost · care`, the default's first)
  with what its tags give the algorithm (`item_id = run_id +
  hospital_id`; for XGBoost first what it scores, `scores stay_hours
  summed over the next 30D, per run_id + person_id`), `freq`, `horizon`
  (the trainer's choice for DeepAR when the table has none), a missing
  row as 0 or unknown, whether it is ready, the API's problems and
  **Edit**.
  **Tag for training** on an untagged table, **Add a group** on a tagged
  one, and **Edit** open `TimeSeriesDialog`: for a new group, its name
  (`default` for a table's first, else empty to type; a name the table
  has already is refused there, other names by the API), starting from
  the first group's roles but its Target; for a group, the API's
  reading of it. **Trained by** DeepAR or XGBoost, the group's (a new
  one's starts from the group it copies, else DeepAR), named in the
  title (`Tag public.patient_days for XGBoost: care`) and sent
  explicitly, so the table carries its tag. One row per role (Timestamp,
  Target, SeriesKey, StaticCategorical, StaticReal, KnownCovariate,
  PastCovariate, with what it is to the algorithm picked and what it
  means as a tooltip), each a chip per column, one column for Timestamp
  and Target and any number for the others; the table's frequency
  (typed, or 15min, 1h, 1D, 1W, 1MS), horizon (typed, or 24h, 7D, 30D,
  90D; *required* for XGBoost) and whether a missing row counts as 0 or
  is unknown, shared by its groups. **Save
  tags** sends `PUT .../timeseries` with the group, its algorithm and
  the horizon: a ready group closes
  the dialog and the card reloads; otherwise the dialog stays with the
  API's problems. **Remove group**, pressed twice, sends the group with
  no roles, which takes it off the table. The tab only shows what the API
  answers: which columns fit a role, and whether the table is ready,
  are the API's to say. Each Kafka source is a card (`StreamCatalog`)
  that loads `GET .../catalog`'s topics: "Not catalogued yet" before a
  first read; **Read topics** (then **Read again**) calls `POST
  .../catalog` and says how many topics and fields it read, and from how
  many topics with records. Each topic is a tile with its name, how many
  fields (or "no fields read") and its cleanup policies; it opens on its
  partitions, replication and retention (`1 partition · replication 1 ·
  kept 1 day`, and the size kept when limited), its description and
  tags, and its records' fields: name, OpenMetadata's type and tags, a
  record's own fields indented under it; a topic without fields says
  there was no JSON record to learn them from. S3 and folder sources are
  listed as not read yet; with authentication on and nobody signed in,
  the tab says to sign in. An error answer shows the API's own words
  (`{"error":...}`).

- **Training** (`TrainingTab`, `?tab=training`): the models datyx
  trains, from `GET /api/training`. A card says what datyx does (each
  group tagged for XGBoost trained at the API's start if it never was,
  then as often as its table's `timeSeriesRetrain` says, 1D when not
  set, and when asked), with a reload button; the sources whose
  catalogue couldn't be read in amber; none tagged yet, where to tag one.
  A card per model (`ModelCard`): `XGBoost · care`, its table and
  source, its latest run's status (`StatusChip`: an icon and the word,
  succeeded green, queued and running amber, failed red; *not ready*
  amber, with the API's problems), and what it scores (*Scores
  stay_hours summed over the next 30D, per run_id + person_id, from
  steps of 1D.*). **Retrain every**: the table's setting, typed or
  picked (1h, 6h, 1D, 1W, never; empty for the default) and **Save**d
  with `PUT /api/datasources/{id}/training`, which writes it to
  OpenMetadata, saying so; under it what applies and when the model is
  next due (*Next in 42 min, at ...*, *Due now*, *A run is running*, or
  never). **Train now** (`POST .../training`; off while a run is on or
  the group isn't ready). A failed latest run shows its error in red.
  From its latest success (`GET /api/training/runs/{id}`): which run,
  when, why and how long, and how many test examples; four stat tiles
  (`StatTile`: a large value, its label above and a note below): the
  mean error, the naive forecast's, *better than naive* as a percentage
  (with an arrow icon, green when better), and the actual average; the
  features that weighed most (`FeatureWeights`): a bar per feature, its
  share of the mean |SHAP| in the brand orange (one series, no legend;
  checked against the card's surface with the dataviz skill's
  validator), the name and the percentage in text beside it and a
  tooltip saying it; and the highest scores now (`TopScores`): a table of
  the 10 series still observed with the highest prediction, their key's
  values, the prediction and the last horizon's actual. Then
  **Activity**: every run of them all, newest first, with when it was
  queued, its status chip, the table and group, why (initial, schedule,
  manual), how long, its test MAE against the naive one and its
  examples, and a failure's error. While a run is queued or running the
  tab asks again every 3 s.
- **Audit** (`CallsPanel`): every call made, newest first, up to 100,
  under the title *API calls* and on a tab labelled *Audit*, neither
  with a count (the refresh every 15 s soon fills it to 100): method,
  path with its query, status (or
  pending, or error), time of day and duration; expanded, the request and
  the response bodies pretty-printed. A button clears it. The calls are
  kept across a reload of the page.

- **Health** (`HealthTab`): cards from `GET /api/health`'s checks: API
  (the `datyx` check: name and version, its profile, launch mode and
  `jvm` or `native`, as `dev profile, development, jvm`, uptime, started
  at), PostgreSQL (ok, or the error), OpenMetadata (version and URL, or
  the error), Sign-in (off, with no `OIDC_CLIENT_ID` on the API; on and
  nobody signed in; or the issuer, whom the API sees and their profile
  id, from `GET /api/me`), and Dashboard: this build's version, when built by the scripts
  (`dash 0.1.202610291200`; a bare `flutter run` or a test has none), and
  how often it asks the API. A green dot when the part is ok, red
  otherwise, and the same red line when the API didn't answer. Three
  cards end with a link, opened in a new tab (`noopener`): the API's, its
  health check (`/api/health` where the app calls the API: its own
  origin, or `API_BASE_URL`); OpenMetadata's, the URL its check reports
  (the API's view of it, so behind Docker Compose it may be a name only
  the API resolves); the Dashboard's, this page without its query.

- **Profile** (`ProfileTab`): the caller's profile from
  `GET /api/profile`, which the API makes the first time an identity
  signs in: its name, id, since when and how many data sources it owns,
  a line saying their access details are encrypted with a key of the
  profile's own, then its identities, one row each with the picture,
  the email (else the name, else the subject), the name, the provider
  (the issuer's host, or `local`), when it was added and last seen. With
  authentication on and nobody signed in, it says to sign in and the
  profile isn't asked.

The API's hello, greetings and status endpoints are gone; the health
replaces the status.

## Kept across a reload

A reload of the page comes back as it was:

- The open tab, kept in the page's address as `?tab=<name>` (`sources`,
  `catalog`, `audit`, `health`, `profile`; `lib/persist/address.dart`),
  replaced in place as tabs change, so the back button leaves the page
  rather than walking the tabs. A bookmark or a shared link opens the
  same tab. Flutter's own route, after the `#`, is left alone.
- The sign-in: the ID token, kept in the browser tab's session storage
  (`lib/persist/session_store.dart`, key `datyx.idToken`) from sign-in to
  sign-out. At start, a kept token that was issued for the API's client
  id and expires in more than a minute signs in at once, with the user's
  name, email and picture read from it, and Google isn't asked; an
  expired or foreign one is dropped. When it expires, or the API refuses
  it, Google is asked to renew it silently; if it can't, the user is
  signed out here and the sign-in button shows. The dashboard reads the
  token's expiry and audience only; the API verifies it.
- The audit: the calls, in session storage as `datyx.calls`, the latest
  100. A call still waiting at the reload shows as never answered.

Session storage belongs to the browser tab: closing it forgets all this,
and another tab starts signed out. The data itself lives in the API.

## Sign-in

`AuthController` (`lib/auth/auth_controller.dart`) takes the API's
`GET /api/auth/config` at start, asked again with a growing delay (3 s
up to 30 s) while the API doesn't answer, so a dashboard opened before
the API is up still gets its sign-in. Off: nothing happens and every call goes
out anonymous. On: it initializes `google_sign_in` with the client id the
API published (nothing is built in), listens to its sign-in and sign-out
events, and tries a silent sign-in from a previous session. The web
renders Google's own button (`google_sign_in_web`'s `renderButton`, in
`sign_in_button_web.dart`, chosen by a conditional import); other
platforms get a button of ours that calls `authenticate()`. The signed-in
account's ID token (an OpenID Connect token, audience the client id) is
what `HttpDatyxApi` sends as `Authorization: Bearer` on every call; after
a 401 it asks for a silent re-sign-in once and retries, since Google's
tokens live an hour. Signing in or out refreshes the screen.

## The API client

`DatyxApi` (`lib/api/datyx_api.dart`): `authConfig()`, `me()`,
`profile()`, `status()`, `dataSources(limit)`, `addDataSource(NewDataSource)`,
`removeDataSource(id)`, `syncCatalog(id)`, `catalog(id)` (a database's
tables), `topics(id)` (a Kafka source's topics, `CatalogTopic` and
`CatalogField`), `timeSeries(id)`, `setTimeSeries(id, roles)`,
`training()`, `trainingRun(id)`, `trainNow(source, table, group)` and
`setRetrain(source, table, retrain)`, and the `CallLog` the Audit tab
listens to.
`HttpDatyxApi` is the real one, over `package:http`, with a token
provider for the bearer and one for a refresh after a 401, a 20 s timeout
on every call, and request bodies logged with their secrets (`password`,
`secretAccessKey`) replaced by dots; `API_BASE_URL`
at build time is the API's base, empty meaning the app's own origin, so
the app calls `/api/...` and whatever serves it proxies that to the API.
A non-2xx answer or a failed call throws `ApiException`, except a 503
from `/api/health`, which is a check down with the checks in the body. `DataSource`
keeps the access details as the API answers them (a map under the
type's key, secrets replaced by `passwordSet` and `secretAccessKeySet`)
and summarizes them on one line; `NewDataSource` is the `POST` body.
`Profile` and `ProfileIdentity` read `GET /api/profile`; `Me` carries
the profile id.
`SystemStatus.fromHealth` reads what the cards show from the health's
checks by name (`datyx`, `Database connections health check`,
`OpenMetadata`); `Dependency.fromCheck` takes a check's status, version,
URL and error (`data.error`, else its other value, where the database
check puts it).

## Serving

Under `/app/` (base href), with `/api/` and `/q/` reaching the API on the
same origin, so there's no CORS and a forwarded port works:

- `scripts/flutter-web.sh` in release mode (`devbox services up`): the
  release build, served by `bin/web_server.dart` (`lib/web_server.dart`,
  dart:io only) compiled to `build/web_server`: files under `/app/` with
  `index.html` as the fallback, `/api/` and `/q/` proxied to
  `DATYX_API_URL`, `/` redirected to `/app/`.
- `scripts/flutter-web.sh` in debug mode (`devbox run web`): Flutter's dev
  server on the web-server device with hot reload, its proxy generated in
  `web_dev_config.yaml` (git-ignored).
- Docker Compose: nginx (`docker/nginx.conf.template`) with the same
  shape, `DATYX_API_URL` filled in when the container starts.

Web is the only platform so far; `flutter create --platforms <name> .`
adds another, and `scripts/make.sh` a target for it.

## Tests

`flutter test` in `datyx_dashboard/`: a `FakeDatyxApi` answers from
memory with authentication off; the Data sources tab opens first and the
Health tab shows the fake's values and the missing version; the Audit tab
counts and lists the calls made at start and empties on clear; the
Profile tab shows the fake's profile with its local and Google
identities; a filesystem data source added through the dialog appears
with its path and author, is counted on the Health tab, its `POST` is in
the Audit tab, and it is gone after the remove button and its
confirmation; the tabs stand in their order and the Catalog lists a
folder source as not read yet, under its section; a Kafka source added
through the dialog sends its servers trimmed and plain text, shows as
`kafka://`, sits in Streams below Databases with room between the
cards, and its topics are read and opened on their settings, fields,
a nested field indented and a tag, an empty topic saying it has no
fields; a database source's schema is read and
its hourly table tagged for DeepAR, the dialog showing the API's problem
until a target is picked, then sending the roles, frequency and missing
rows in the default group; a tagged table gets a second group, named
`acute`, from the default's roles but its target, a second group of the
same name is refused, its box and tags take a color other than the
default's, and removing it sends it with no roles; a group tagged for
XGBoost with a 30D horizon sends both, and the table then says who
trains it (closed and open, the algorithm's tag in the group's color),
what it scores and each role in XGBoost's terms, and its Edit starts
from XGBoost and the horizon; groups' colors go
by name, the default first, gray past the third; the tab the address names opens; and,
with a session store in memory, the audit is read back after a reload
(a waiting call as never answered), a fresh token signs in without
Google, an expired, foreign or malformed one is dropped, a refused one
that can't be renewed signs out, and signing out forgets it. The
Training tab shows a model's scope, its next run, its latest run's
failure, its latest success's tiles (3.10 against 5.20, 40% better),
its features' bars in proportion with their shares, its scores and
every run newest first; **Train now** and saving *never* call the API.
