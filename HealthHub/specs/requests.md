# Requests

The requests that shaped HealthHub, oldest first, each with what changed.
The feature files hold the current specification; see the
[index](README.md).

## 2026-10-28

1. **Create a new demo, HealthHub, following the same pattern as the
   others; this one needs a database (PostgreSQL). Copy the structure
   (version and artifact identification, devbox, process-compose, Docker
   Compose, dev container, ...), but for now a single hello world on the
   UI is fine.** Added `HealthHub/`, built like PokerFace: a Flutter app
   (`healthhub_app`, web, Android, iOS and Linux) and a Dart API
   (`healthhub_api`), devbox, process-compose and the health monitor, the
   Makefile and the version files (`0.1`, `aityx:healthhub`; the group
   became `datyx` the same day, see below), Docker
   Compose, and the dev container in `.devcontainer/HealthHub/`, on ports
   8900 (app), 8901 (API) and 8902 (PostgreSQL), moved the same day to
   9800 to 9802 (next request); see [Development
   environment](dev-environment.md). The database is the `postgres`
   service of `compose.yaml`, which `devbox services up` starts with
   `docker compose up postgres` as datyx does, and whose first start
   makes the `healthhub` database and user; the API makes a `greetings`
   table and writes "Hello, world" in it once ([Database](database.md)).
   `GET /api/hello` reads the greeting with PostgreSQL's version, and
   `GET /api/health` reports whether the database answers and whether the
   aityx key is set ([API](api.md)). The app has one screen: the
   greeting, where it was read from, three chips for the API, the
   database and the key, and a refresh button (the welcome screen, since replaced by [Index](index.md) and [Home](home.md)), in
   the aityx [theme](theme.md). Nothing calls aityx yet. The repository's
   README, index page and all-demos dev container list it; the dev
   containers gain Docker (the `docker-in-docker` feature) for the
   database.
2. **Make HealthHub use the 98xx port prefix, for all components, with
   no clashes with the others.** The app is on 9800, the API on 9801 and
   PostgreSQL on 9802 (they were 8900 to 8902, the range of the other
   demos' apps), in every default, script, Dockerfile, compose file, dev
   container, the index page and the READMEs; the 98xx range was unused
   (the other demos have 88xx and 89xx, datyx 99xx). See [Development
   environment](dev-environment.md).
3. **Make sure every group.id.txt is correct.** HealthHub's group ID is
   `datyx`, not `aityx`: the demos start and stop in two groups, aityx
   (Mortgage Hub, Contact Hub, PokerFace, RoboRules and Cellfie) and
   datyx (the datyx API and dashboard, and HealthHub), and the group ID
   names the group. The coordinates are `datyx:healthhub`.

## 2026-10-28, later

1. **OIDC authentication on the API, the dashboard and the app, with the
   user's identity propagated through, from HealthHub to the datyx API
   seamlessly; Google sign-in, with `healthhub` as the Google ids.**
   The API verifies Google ID tokens (`openid_client`) when
   `OIDC_CLIENT_ID` is set, answers `/api/auth/config` and `/api/me`,
   addresses `/api/hello` to the signed-in user, and forwards
   `/api/datyx/me` and `/api/datyx/datasources` to the datyx API
   (`DATYX_API_URL`) with the user's own token ([API](api.md)). The app
   signs in with Google (`google_sign_in`) using the client id the API
   publishes, sends the token on every call, and shows the account corner,
   a sign-in chip and the datyx card (the welcome screen, since replaced by [Index](index.md) and [Home](home.md)). Settings in
   `.env.example`, `scripts/env.sh`, `scripts/api.sh`,
   `process-compose.yaml` and `compose.yaml`. Tests for the routes and
   the screen.

## 2026-10-29

1. **Generate an appropriate favicon for HealthHub, in the same style
   and colors as the other demos', reflecting what it is for.** A heart
   with a pulse line cut out of it, aityx orange on the dark page
   background: `assets/icon/icon.svg` and `icon_foreground.svg`, rendered
   to PNG, and `flutter_launcher_icons` in `pubspec.yaml` generating the
   web, Android and iOS icons from them (Flutter's default launcher
   icons are gone). The tab shows `web/favicon.svg`, the heart as a flat
   orange glyph with no background, as aityx.ai's own favicon is drawn;
   `index.html` keeps the PNG tile as the fallback. See
   [App icon](app-icon.md).

2. **Make the index page just a full-screen map, with the user's
   location highlighted and an overlay saying "Welcome to HealthHub".
   The index is the page for someone not signed in; home is where the
   user lands after signing in: a dashboard whose only tile, for now, is
   the same map with the user's position highlighted.** The welcome
   screen (the greeting, the health chips and the datyx card) is gone.
   `IndexScreen` shows the map full screen with the welcome card, the
   location's state and the sign-in; `HomeScreen` a grid of tiles with
   the app bar and the account corner (`UserMenu`, moved to
   `lib/auth/`); `HealthHubApp` shows home once someone is signed in or
   when sign-in is off, the index otherwise. `UserLocationMap`
   (`flutter_map`, OpenStreetMap tiles darkened, an orange dot in a halo
   and the accuracy circle) and `LocationController` (`geolocator`,
   asked once and shared) in `lib/location/`; location permissions for
   Android and iOS. Tests for the index, a refused location, home and
   signing out, and sign-in off. See [Index](index.md), [Home](home.md)
   and [The map](map.md).

1. **Separate the dev containers, images and Codespaces configurations by
   demo group.** HealthHub now opens in the datyx group's dev container,
   **datyx demos** (`.devcontainer/datyx/`), on the group's image
   `docker.io/aletyxcode/samples-and-demos-datyx` (`bash
   image/build-image.sh datyx`), which starts it with the datyx API, the
   datyx dashboard and the index page. Its own dev container,
   `.devcontainer/HealthHub/`, was removed. The start-up log is
   `startup.log` at the repository root. The README's codespace link
   points at the group's container. See [Development
   environment](dev-environment.md).

1. **Make the datyx index the first port of the datyx group, 9800.** The
   index moves from 9907 to 9800, so HealthHub moves up one: the app to
   9801, the API to 9802 and PostgreSQL to 9803, everywhere (the scripts,
   process-compose, compose, nginx, the Dart defaults, the dev container's
   forwarded ports, the index page, the READMEs and these specs). The
   datyx API's dev data source for HealthHub's database follows to 9803.
   The Google OAuth client needs http://localhost:9801 among its
   authorized JavaScript origins. See [Development
   environment](dev-environment.md).

## 2026-10-30

1. **Zoom the default map out one level and add zoom controls.** Once
   the location is known, the map centres on it at zoom 14, from 15.
   Zoom in and Zoom out buttons (+ and −) sit at the bottom right, above
   Back to where you are, and step one level between zoom 2 and 19. See
   [The map](map.md).

1. **Fix the Google sign-in error at http://localhost:9801.** The
   `healthhub` OAuth client still listed only the app's old origins, on
   port 9800; http://localhost:9801 and http://127.0.0.1:9801 were added
   to its authorized JavaScript origins in Google Cloud Console. The
   README's Sign-in section now says which origins the client needs.

1. **Add care center locations to the HealthHub database: every
   hospital, clinic and health station of Cornudella de Montsant,
   Barcelona, Reus, Miami, Fort Lauderdale, Rio de Janeiro and São
   Paulo.** 7,256 care centers from each country's official registries
   (the Spanish catalogues and Catalan directories, Florida's AHCA and
   federal lists, Brazil's CNES), each city then checked independently,
   in `healthhub_api/data/care_centers.jsonl`, compiled into the API and
   seeded into a new `care_centers` table at every start. The CAP of
   Cornudella de Montsant is in, and the CAPs and consultoris locals of
   Reus and Barcelona were checked against the national primary-care
   catalogue and the city directory. See [Care centers](care-centers.md)
   and [Database](database.md).

1. **Show the care centers on the map of the index and of home, with an
   icon for each kind.** `GET /api/care-centers?bbox=` answers the
   centers in the map's view (hospitals first, at most 500); the map
   asks after every move and pins hospitals (red), clinics (blue) and
   health stations (green), with a legend. See [The map](map.md) and
   [API](api.md).

1. **Keep the sign-in across a refresh.** The ID token is kept in the
   tab's session storage until it expires or the user signs out, and
   read as the app starts. See [Index](index.md).

1. **Add a Kafka message stream to HealthHub, in the startup scripts,
   Docker Compose, process-compose and devbox, with a health check; then,
   in dev mode only, simulate people moving across the map, each its own
   virtual thread in one of the cities, going to the nearest hospital by
   day and home at night, starting from a random home, with homes and
   people on the map.** Apache Kafka (`kafka`, KRaft, 127.0.0.1:9804) and
   Karapace's REST proxy (`kafka-rest`, 127.0.0.1:9805) in compose and
   process-compose (`4-kafka`, `5-kafka-rest`), a devbox `kafka` script,
   and 📨 Kafka in the health monitor. The API, in Dart, talks to Kafka
   over the REST proxy (Dart has no solid Kafka client), and, with
   `HEALTHHUB_MODE=dev` (the default), runs one async loop per person,
   Dart's nearest to a virtual thread: 10 people per city, publishing
   every move to `healthhub.people.moves`, read back by the API's own
   consumer for `GET /api/people`. `/api/health` adds `kafka` and
   `simulation`. The map polls the people every 2 s and draws homes and
   people, coloured by state, with the simulated time in the legend. A
   review then made `/api/health` report a cached Kafka status, the API
   delete its consumer when stopped, the feed check every field, and
   Kafka bind to 127.0.0.1 only. See [Simulation](simulation.md),
   [API](api.md), [The map](map.md) and [Development
   environment](dev-environment.md).

1. **Make the map on home larger: full width and a bit taller.** The
   map's tile spans the page's width and 78% of the window's height
   (520 to 1100 px), from a grid tile of at most 720 px wide at 4:3. See
   [Home](home.md).

1. **Update the map with the people in the view area every 5 seconds,
   not at every turn.** `GET /api/people` takes the map's `bbox` and
   answers the people there or living there; the map asks every 5
   seconds, from every 2, and once the view settles after a move. See
   [The map](map.md) and [API](api.md).

1. **Add an events widget under the map with the latest events on the
   stream.** The API's consumer keeps the latest 100 records it read,
   with partition and offset, served newest first by `GET /api/events`;
   home shows the latest 20 under the map, refreshed every 5 seconds, in
   dev mode. See [Home](home.md) and [Simulation](simulation.md).

1. **Create the table of medical conditions, the most common diseases
   and illnesses, acute or chronic, with their treatment procedures and
   duration, and a few complaint templates each for what a person says
   at their first, repeated and last arrival at the hospital, filled with
   their name, age and details. Record an admission event every time a
   person reaches the hospital (movements need no database), highlight
   them in the stream, run the simulation at one simulated hour per real
   second, and make movement realistic.** 38 conditions (19 acute, 19
   chronic), written and reviewed for clinical accuracy, with prevalence,
   ages, share of women, treatment, duration, visit schedule, stays and 9
   English templates each, in `healthhub_api/data/conditions/`, seeded
   into `medical_conditions` and `complaint_templates`. People get a name
   typical of their city, an age, a sex, an occupation, at most one
   chronic condition (reviewed in courses for life) and acute episodes at
   random; they stay home until a visit is due, travel at walking,
   transit or car speed by distance (most trips within a city take
   minutes, so within the hour's turn), are admitted at the arrival
   minute at the nearest general hospital, and publish an admission with
   the rendered complaint to `healthhub.admissions`. The API records each
   admission once in `admissions` (`GET /api/admissions`) and home's
   events card shows admissions highlighted with the complaint in full. A
   review then made admission ids unique across runs, read admissions
   from a stable consumer group, kept chronic patients from being
   re-diagnosed, weighed conditions by sex, let emergencies arrive at
   night, and skipped specialised and restricted hospitals. See
   [Conditions](conditions.md), [Simulation](simulation.md),
   [Database](database.md), [API](api.md) and [Home](home.md).
- **Sync git (commit the work above).** A review before committing found
  email addresses (two of them people's) that registries put in eleven
  care centers' `website`: they are gone from the data, and the API reads
  any website with an `@` as none. A view that settles while the map is
  still waiting for the people of the old one is now asked for as soon
  as that answer comes, and the old answer is dropped. See
  [Care centers](care-centers.md) and [The map](map.md).
