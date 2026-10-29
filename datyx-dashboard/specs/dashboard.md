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
  at endpoint`, or the path), the description, when and by whom it was
  added, and a remove button, which confirms and then `DELETE`s. An Add
  button opens `AddDataSourceDialog`: the kind (Database, S3 bucket,
  Filesystem), name and description, then the fields of that kind
  (engine and port, host, database, username and password; bucket,
  region and prefix, endpoint, access key id and secret access key; or
  the path), the required ones checked before the `POST`; secrets go as
  typed, the rest trimmed. Errors the API answers show in a snack bar.
  With authentication on and nobody signed in, the card says to sign in
  and the list isn't asked. A line in red above the card when the API
  itself didn't answer.

- **Catalog** (`CatalogTab`): what datyx makes of the data in each data
  source: the datasets it holds (tables, files, objects), their fields
  and types, as OpenMetadata records them. The API doesn't read the
  sources yet, so for now the tab says so and lists each source on
  record, from the same `GET /api/datasources`, as not catalogued yet.
  With authentication on and nobody signed in, it says to sign in.

- **Audit** (`CallsPanel`): every call made, newest first, up to 100
  (the tab's label counts them): method, path with its query, status (or
  pending, or error), time of day and duration; expanded, the request and
  the response bodies pretty-printed. A button clears it. The calls are
  kept across a reload of the page.

- **Health** (`HealthTab`): cards from `GET /api/status`: API (name and
  version, uptime, started at), PostgreSQL (version, or the error),
  OpenMetadata (version and URL, or the error), Sign-in (off, with no
  `OIDC_CLIENT_ID` on the API; on and nobody signed in; or the issuer,
  whom the API sees and their profile id, from `GET /api/me`), Records
  (how many data sources and profiles),
  and Dashboard: this build's version, when built by the scripts
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

The API's hello and greetings endpoints, which the first dashboard showed
to prove the path, are not shown any more.

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
`removeDataSource(id)`, and the `CallLog` the Audit tab listens to.
`HttpDatyxApi` is the real one, over `package:http`, with a token
provider for the bearer and one for a refresh after a 401, a 20 s timeout
on every call, and request bodies logged with their secrets (`password`,
`secretAccessKey`) replaced by dots; `API_BASE_URL`
at build time is the API's base, empty meaning the app's own origin, so
the app calls `/api/...` and whatever serves it proxies that to the API.
A non-2xx answer or a failed call throws `ApiException`. `DataSource`
keeps the access details as the API answers them (a map under the
type's key, secrets replaced by `passwordSet` and `secretAccessKeySet`)
and summarizes them on one line; `NewDataSource` is the `POST` body.
`Profile` and `ProfileIdentity` read `GET /api/profile`; `Me` carries
the profile id.
`SystemStatus` reads what the cards show; the status's `greetings` count
is ignored.

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
source as not catalogued yet; the tab the address names opens; and,
with a session store in memory, the audit is read back after a reload
(a waiting call as never answered), a fresh token signs in without
Google, an expired, foreign or malformed one is dropped, a refused one
that can't be renewed signs out, and signing out forgets it.
