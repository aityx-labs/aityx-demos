# Requests

The history of requests that shaped the datyx dashboard, newest first.
Its earlier history, as the `datyx-dash` module inside `datyx/`, is in
[../../datyx/specs/requests.md](../../datyx/specs/requests.md).

## 2026-10-29: the audit header fits a narrow window

Asked: fix the review's finding that the Audit tab's count of kept calls
could push the Clear button out of a narrow panel.

Changed: the count takes the room left in the header row and ends in an
ellipsis when short of it, so the Clear button always shows.

## 2026-10-29: tabs reordered, a Catalog tab, kept across a reload

Asked: the tabs in the order Data sources, Catalog, Audit, Health,
Profile, with a new Catalog tab right after Data sources showing datyx's
interpretation of the data in the data sources; and a refresh of the
page keeps everything: the sign-in, the open tab, the rest.

Changed: `DashboardTab` holds the tabs' order, labels and names, and a
`TabController` of the screen's own; `CatalogTab` explains that the API
doesn't read the sources yet and lists each as not catalogued (the
interpretation itself needs the API first); the open tab is kept in the
address as `?tab=<name>` (`lib/persist/address.dart`); the ID token and
the audit are kept in the browser tab's session storage
(`lib/persist/session_store.dart`, `package:web` now a direct
dependency): a kept, fresh token for the API's client signs in at once,
and one refused and not renewed signs out; the tests for each.

## 2026-10-29: the Profile tab

Asked: profiles on the datyx API and the dashboard (see
[../../datyx/specs/requests.md](../../datyx/specs/requests.md)).

Changed: a Profile tab (`ProfileTab`, key `tab-profile`, second) showing
`GET /api/profile`: the profile, its data source count, the note on its
key, and its identities; `Profile` and `ProfileIdentity` in the client,
`profile()`, the profile id in `Me`, and the profiles count in
`SystemStatus`, shown on the Health tab's Records and Sign-in cards; the
profile asked with every refresh when not locked; the tests.

## 2026-10-29: a favicon of its own

Asked: an appropriate favicon for datyx, in the same style and colors as
the other demos', reflecting what the project is for.

Changed: a database cylinder with its catalog cut into it, the lid and a
band as curved slots and a lineage branching from one source to two,
aityx orange on the dark page background: `assets/icon/icon.svg` and
`icon_foreground.svg`, rendered to PNG, and `flutter_launcher_icons` in
`pubspec.yaml` generating the web icons from them, which also set the
manifest's colors to the page's. The tab shows `web/favicon.svg`, the
cylinder as a flat orange glyph with no background, as aityx.ai's own
favicon is drawn; `index.html` keeps the PNG tile as the fallback. See
[App icon](app-icon.md).

## 2026-10-29: navigation tabs; hello and greetings gone

Asked: navigation tabs like the other apps: Data sources first, with the
same content as before; the health checks in a Health tab, with the
version; an Audit tab for the API calls. Remove the hello and greetings
parts, which have proved the path.

Changed: `DashboardScreen` got a `TabBar` under the app bar with Data
sources, Health and Audit (the Audit label counts the calls); the status
cards moved to `HealthTab` (`lib/dashboard/health_tab.dart`) with a
Dashboard card holding the version, which left the app bar, and the
Records card counting data sources only; the calls panel fills the Audit
tab and says how many calls it keeps; the Hello and Greetings cards, and
`hello`, `greetings`, `addGreeting` and `Greeting` in the API client, are
gone (the API still serves them). The tests follow the tabs.

## 2026-10-29: the dev containers by demo group

Asked: separate the dev containers, images and Codespaces configurations
by demo group.

Changed: the dashboard now runs in a codespace, in the datyx group's dev
container, **datyx demos** (`.devcontainer/datyx/devcontainer.json` at
the repository root), on the group's image
`docker.io/aletyxcode/samples-and-demos-datyx` (`bash
image/build-image.sh datyx`), which carries the API's GraalVM and the
dashboard's release web build and starts it with the API, HealthHub and
the index page. There was no per-demo dev container for it to replace;
the per-demo ones of the other folders were removed. The known
limitation saying it had no codespace is gone from
[dev-environment.md](dev-environment.md).

## 2026-10-28: data sources, and signing in with Google

Asked: let users add or remove data sources (databases, S3, filesystem,
each with its access details), the first entity of datyx; OIDC
authentication on the API, the dashboard and HealthHub, with the user's
identity propagated through; Google sign-in.

Changed: the data sources card and the add dialog, the Sign-in and
Records status cards, the account corner with Google's sign-in button
(`google_sign_in`, `google_sign_in_web`), `AuthController` reading the
client id from the API's `GET /api/auth/config`, the ID token as a bearer
on every call with one silent retry after a 401, the API client's new
calls, and the tests. No setting here: the client id lives with the API.

## 2026-10-28: datyx-dashboard, a folder of its own

Asked: create `datyx-dashboard`, a Flutter app like the other demos',
accessing the datyx API; the `datyx` module becomes API only, and the
dashboard a separate app that invokes it.

Changed: `datyx/datyx-dash/` moved here as `datyx_dashboard/` (package
`datyx_dashboard`), unchanged but for its name and its web server's
settings (`FLUTTER_WEB_PORT`, `DATYX_BIND_HOST`, `DATYX_API_URL`); this
folder got the demos' layout: `devbox.json` (Flutter, with the demos'
lock), `process-compose.yaml` (the dashboard and the health monitor, no
API), `compose.yaml` (nginx with the API's address as a template
variable, the host's 9900 by default), `scripts/` (`flutter-web.sh`,
`build.sh`, `make.sh`, `health-check.sh` with Dash, API and Proxy,
`env.sh`, `version.sh`), the Makefile, the id and version files
(`datyx:datyx-dashboard`, `0.1`), README, AGENTS.md, CLAUDE.md and these
specs. The port stays 9906. The repository's `start-all.sh` learned to
wait for a demo without a web app on its API's `/api/health`, the index
page got a card for the dashboard and the datyx card points at the API,
and the README lists both.
