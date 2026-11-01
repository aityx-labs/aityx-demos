# The dashboard

The datyx dashboard is a Flutter web app in `datyx_dashboard/` (package
`datyx_dashboard`), in the aityx dark palette like every demo's app. It
invokes the datyx API ([../../datyx/specs/api.md](../../datyx/specs/api.md))
and shows what it answers, with the details of each call. It computes,
stores and decides nothing on its own: when a view needs data the API
doesn't have, the API gets it first.

## What it shows

One screen, `DashboardScreen`, with an app bar and five tabs under it
(a `TabBar`, as the demos' apps have), in the order of `DashboardTab`:
Data sources, Catalog, Audit, Health, Profile. Data sources opens at
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
  TimeSeries tag shown as its role and DeepAR field (`Target ·
  target`), with its group first when it isn't the default one
  (`acute: Target · target`). A table can hold several time series, one
  per group of tags, each read by the API on its own. Each group has a
  color, on its tags and its DeepAR box (a dot and the border): the
  default group first, then the others by name, take orange, blue and
  aqua (`groupPalette`, checked with the dataviz skill's validator to
  stay apart side by side on the dark surface, for color blindness too;
  no fourth hue does with these three), and any past the third a neutral
  gray. The status colors (green, amber, red) are never a group's. The
  name is always on the chip and the box, so the color is never alone. A tagged table has
  a badge, *time series: ready* or *needs work* for one group, *3 time
  series: all ready* (or how many are) for several, and a DeepAR box per
  group (`DeepAR · acute`, the default's first) with the inputs its tags
  give (`item_id = run_id + hospital_id`, `freq = 1h`, a missing row as
  0 or unknown), whether it is ready, the API's problems and **Edit**.
  **Tag for DeepAR** on an untagged table, **Add a group** on a tagged
  one, and **Edit** open `TimeSeriesDialog`: for a new group, its name
  (`default` for a table's first, else empty to type; a name the table
  has already is refused there, other names by the API), starting from
  the first group's roles but its Target; for a group, the API's
  reading of it. One row per role (Timestamp, Target, SeriesKey,
  StaticCategorical, StaticReal, KnownCovariate, PastCovariate, with the
  DeepAR field and what it means as a tooltip), each a chip per column,
  one column for Timestamp and Target and any number for the others; the
  table's frequency (typed, or 15min, 1h, 1D, 1W, 1MS) and whether a
  missing row counts as 0 or is unknown, shared by its groups. **Save
  tags** sends `PUT .../timeseries` with the group: a ready group closes
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

- **Audit** (`CallsPanel`): every call made, newest first, up to 100
  (the panel says how many it keeps; the tab's label is just *Audit*,
  since the refresh every 15 s soon fills it to 100): method, path with its query, status (or
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
  otherwise, and the same red line when the API didn't answer.

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
`CatalogField`), `timeSeries(id)`, `setTimeSeries(id, roles)`, and the
`CallLog` the Audit tab listens to.
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
default's, and removing it sends it with no roles; groups' colors go
by name, the default first, gray past the third; the tab the address names opens; and,
with a session store in memory, the audit is read back after a reload
(a waiting call as never answered), a fresh token signs in without
Google, an expired, foreign or malformed one is dropped, a refused one
that can't be renewed signs out, and signing out forgets it.
