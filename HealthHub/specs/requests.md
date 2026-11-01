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

## 2026-10-31

1. **Aggregate the admissions coming through Kafka with an Apache Flink
   application, into another stream and the database, so that datyx can
   find the series in OpenMetadata and train a DeepAR model on it (the
   timestamp, the target, the number of admissions in the next hours,
   and the other fields DeepAR can take), treating HealthHub as a
   customer it knows nothing about.** A Flink 2.2 SQL job counts the
   admissions of `healthhub.admissions` per run, hospital and simulated
   hour (day 1 being 2026-01-01), each event id once, with acute and
   chronic apart, and upserts the counts into the compacted topic
   `healthhub.admissions.hourly` and the `admissions_hourly` table, which
   the API makes. No event-time windows, as the simulated clock runs an
   hour a second and restarts with every run; the job reads the topic
   from its start at every submission, so it is a function of what the
   topic keeps. Three services run it, `flink-jobmanager`,
   `flink-taskmanager` and `flink-sql`, which keeps the job submitted;
   Flink's UI is on 9806; the health monitor gains 🌊 Flink; `devbox run
   flink` starts it alone. Nothing in HealthHub knows about datyx or
   DeepAR: datyx reads the table through OpenMetadata. See [Admissions
   per hour](admissions-hourly.md), [Database](database.md) and
   [Development environment](dev-environment.md).

## 2026-11-01

1. **Score each patient's hospital care in the next 30 days (the horizon
   a parameter) with XGBoost, the dataset found by its tags in
   OpenMetadata as datyx does for DeepAR, HealthHub being the customer.**
   HealthHub's part is the data: the view `patient_days`, each person's
   visits and hours of hospital care per run and simulated day (day 1
   being 2026-01-01), with their age, sex, city, hospital and chronic
   condition, made by the API at every start from `admissions` and
   `medical_conditions`. The stay of a visit is its condition's, for a
   first visit or a follow-up, as the simulation keeps people. Nothing in
   HealthHub knows about datyx or XGBoost. See [Patient
   days](patient-days.md) and [Database](database.md).

1. **Use aityx for triage at the desk, and write a document apart from
   the specs about HealthHub's aityx features, starting with this one:
   how Jev and aityx help, sample classifications, plenty of cases in the
   data, matching the tables, explainable.** Each admission the API
   records is triaged by aityx from what the patient said and their age,
   nothing else: one call, in which Jev reads eight danger signs as
   probabilities and four choices (pain, onset, why they came, the part
   of the body), and a decision (`data/triage/triage.json`) gives the
   level on five levels after the Manchester Triage System's, the longest
   wait, the area of the hospital and a nurse's check, with the rule
   behind each. The API keeps each triage with aityx's receipt
   (`admission_triage`) and answers `GET /api/triage` and
   `GET /api/triage/{eventId}`; home gains the **Triage at the desk**
   card, whose rows open why: the signs against the thresholds and each
   rule tried in order. `HEALTHHUB_TRIAGE=off` turns it off. For plenty
   of cases, every complaint template now has a reference level, the one
   a nurse applying the same policy gives it, and admissions say which
   template they were said from, so every triage is set against it; three
   acute conditions bring immediate and time-critical cases: anaphylaxis,
   acute coronary syndrome and stroke. `scripts/model-test.sh` checks the
   decision on aityx at each rule and threshold, and
   `scripts/triage-cases.sh` triages all 369 templates into
   `docs/aityx-triage-cases.md`: 93.5% at the reference level, 97.8%
   within one, after the questions were made more precise (85.1% at
   first). The document is [docs/aityx.md](../docs/aityx.md). See
   [Triage at the desk](triage.md), [Medical conditions](conditions.md),
   [Simulation](simulation.md), [Database](database.md), [API](api.md),
   [Home](home.md) and [Development environment](dev-environment.md).

1. **In HealthHub, let each person's id or name be clickable, opening a
   view of the person with what the system knows of them; in it, show
   datyx's XGBoost inference of the 30-day return, highlighted in a
   card.** Every person named on home is now a link: a move's id, an
   admission's name, a triage's name (in the row and its detail), and a
   person or home on the map (a click opens; the tooltip shows on hover).
   The person view shows who they are, what they do now, a highlighted
   card with datyx's prediction of their hours of hospital care over the
   next 30 days against the last 30, their admissions with aityx's
   triage, and their days of care. A person's id comes back in every run
   as someone new, so a view is of one run: an admission's own, else the
   current one. The API gains `GET /api/people/{id}` (from the database
   and the latest move) and `GET /api/people/{id}/prediction` (datyx's
   inference of `patient_days`, group `care`, asked with the user's token
   from their datyx source for HealthHub's database), an index on
   `admissions.person_id`, and `personId` on the triage rows. See
   [The person view](person.md), [Home](home.md), [The map](map.md),
   [API](api.md) and [Database](database.md).

1. **On HealthHub's dashboard: beside the map, explain the data and how
   the simulation works; beside the triage at the desk, what aityx does,
   where Jev is, where the rules (DMN, decision tables) are and what
   aityx adds, briefly. In the events, name the person on each row, a
   link to their view, and invite opening anyone's. In the person view,
   explain the XGBoost inference beside the return chance, and why Jev
   can't calculate it: it depends on history.** Two explainer cards sit
   to the right of the map and the triage from 1000 px wide (under them
   when narrower); a move's row now names the person, not their id; the
   events card invites opening anyone; the person view explains how
   datyx's XGBoost model predicts from the person's own history, and why
   Jev, which reads text, can't. See [Home](home.md) and
   [The person view](person.md).
1. **On top of the events, a button to pause the simulation.** **Pause
   the simulation** (then **Resume the simulation**) heads the events
   card. The API has `POST /api/simulation/pause` and `/resume`,
   answering `{"paused": true|false}` (idempotent), 401 without a user
   once sign-in is on, 409 when the simulation doesn't run. Pausing stops
   the simulation's clock and holds every person's loop before its next
   turn: nobody moves or is admitted, the simulated time stands still,
   and resuming goes on from the same turn with none skipped. There is
   one simulation, so a pause is everyone's. `GET /api/health` and
   `GET /api/events` say `"paused"`; the API logs each pause and resume.
   See [Simulation](simulation.md#pausing), [API](api.md) and
   [Home](home.md).

1. **Add more people to the simulation: double it.** The default of
   `HEALTHHUB_SIM_PEOPLE` is now 20 a city, not 10: 140 people across the
   seven cities, each publishing a move a turn, and about twice the
   admissions (and so twice the aityx triage calls). The explainer beside
   the map says twenty per city. See [Simulation](simulation.md),
   [Home](home.md), [API](api.md), [Database](database.md) and
   [Development environment](dev-environment.md).
1. **In the events view, make the event cards look the same always,
   with filterable conditions on top, in a new row below the pause
   control.** Moves and admissions are now rows of one shape and
   height: a bar and tint in the event's colour (the state's for a move,
   orange for an admission), a mark, and two lines that never wrap: who,
   the condition and the time; what happened, the hospital and where the
   record sits. An admission's complaint is cut to what fits, in full on
   hover, instead of wrapped below. Under the header with the pause, a
   row of chips, **All conditions** and one per condition of the events
   with its count, filters the events in the app, several at once, kept
   through the 5-second reads; the header counts what is shown. See
   [Home](home.md).
1. **The hospital view: clicking a care center's name or id opens a view,
   for every kind of care center, with its position on the map, the
   people in it, its capacity and its current usage.** Every care center
   named on home is now a link: a pin on the map (a click opens, the
   tooltip shows on hover), the hospital of a move or an admission in the
   events, of a triage (in the row and its detail) and of a person's
   admissions and what they do now. The view shows what and where it is,
   a map around it with a badge of who is there and the people on their
   way, a highlighted card of the capacity in use ("1 of 8 beds", a bar,
   the share, green, amber, red), who is there and on the way (links to
   them), and its admissions, counted this run and in all, the latest
   with who and aityx's triage; it reads again every 5 seconds. The
   registries have no beds, so the capacity is the simulation's, sized to
   its people and fixed per care center. Pages and dialogs opened from
   home now carry home's links, so the person in a triage's detail opens
   too. The API gains `GET /api/care-centers/{id}`, `hospitalId` on the
   moves, a person's now and the triage rows, and an index on
   `admissions (hospital_id, id)`. See [The care center
   view](care-center.md), [The map](map.md), [Home](home.md), [The person
   view](person.md), [API](api.md) and [Database](database.md).
1. **Route people by need: send them to health stations and clinics, not
   only hospitals, so that every kind of care center has people.** Each
   condition now says where its first visit goes (`setting`) and, when
   elsewhere, its follow-ups (`follow_up_setting`): primary care (a
   health station) for colds, flu, check-ups of hypertension or diabetes;
   urgent care (a CUAP, a UPA, an urgent care center, or a hospital's
   emergency department, whichever is nearer) for a sprain, a laceration,
   a migraine, gastroenteritis; adult mental health clinics for
   depression and anxiety; dialysis centers for end-stage kidney disease;
   a general hospital for emergencies and the specialists'
   conditions. A pneumonia is admitted at the hospital and checked at the
   health station after. Each person goes to the nearest care center
   serving the visit's setting, travelling by its distance; the moves and
   admissions say `careCenterKind`, and the app names it ("Going to the
   health station"); the legend says going for care and in care. The
   care center view says what each serves and when the simulation sends
   nobody there. `medical_conditions` gains `setting` and
   `follow_up_setting`. See [Medical conditions](conditions.md#where-visits-go),
   [Simulation](simulation.md#people), [The map](map.md), [The care
   center view](care-center.md), [API](api.md), [Database](database.md)
   and [Admissions per hour](admissions-hourly.md).
1. **Check HealthHub's data classification and quality indexing in
   OpenMetadata, add the OpenMetadata calls needed after the data
   initialization, reset what needs it: the console should show
   everything at top quality, described and in context.** HealthHub's
   part is the descriptions, set by its data initialization: every table,
   the `patient_days` view and every column of the schema says what it
   is, as a PostgreSQL comment that the migration sets at every start
   (`COMMENT ON TABLE`, `COMMENT ON VIEW`, `COMMENT ON COLUMN`, from
   `schemaComments` in
   [lib/schema_comments.dart](../healthhub_api/lib/schema_comments.dart)).
   HealthHub still knows nothing of datyx or OpenMetadata: datyx's schema
   read carries a database's comments into OpenMetadata, and datyx, in
   development, waits for them before it catalogues and curates
   HealthHub (its own spec, `catalog.md`). A test checks against a live
   database that the described tables and columns are exactly the
   schema's, so a table or column added without a description fails. See
   [Database](database.md).
1. **When the HealthHub dashboard is opened, centre the map on the care
   center nearest to the user.** Home's map, once the location is known,
   asks the API for the nearest care center of any kind and centres on
   it, at zoom 14 or as far out as keeps the user in view; it stays on
   the user when there is no answer or the user has moved the map. The
   index still centres on the user. The API has
   `GET /api/care-centers/nearest?lat=..&lon=..`, answering the care
   center and its great-circle distance in metres, the point used for
   the query only and never logged. See [The map](map.md), [API](api.md)
   and [Home](home.md).
1. **In the care center view, plot a time series: for a start only the
   admissions per hour, historically until now in simulation time, and
   predicted for the next 24 hours in simulation time** (after an
   earlier ask, "start by adding a timeline of admissions to the care
   center view, the past solid and the future predictions dashed and a
   bit transparent", whose card was written while the view was built
   apart). The care center view now shows **Admissions per hour** under
   its map and capacity (`AdmissionsTimelineCard`): the care center's
   admissions in each of the last 72 simulated hours up to the run's
   latest hour, solid, and datyx's DeepAR forecast of the next 24, dashed,
   lighter, in the band of its 10th to 90th percentiles, with hover and
   touch for each hour's numbers, refreshed every 10 seconds. Until datyx
   has a model of the group, the card shows the hours and says why there
   is no forecast. The API gains `GET /api/care-centers/{id}/admissions`
   (from `admissions_hourly`, missing hours zero) and
   `GET /api/care-centers/{id}/admissions/forecast` (datyx's inference of
   the care center's series, group `default`, asked with the user's
   token, as the person's prediction is, now through a shared
   `_inference`). See [A care center's admissions per
   hour](admissions-timeline.md), [The care center view](care-center.md)
   and [API](api.md).

1. **In the events where a person reaches a hospital, show their
   expected 30-day bed usage on the event line.** Each admission in the
   latest events shows datyx's XGBoost prediction of the person's hours
   of hospital care over the next 30 days, the person view's, with a bed
   icon ("9 h expected in 30 days"; the model and the last 30 days on
   hover). The card asks for it once per admission, for the person of
   the admission's run, and shows nothing when datyx can't say. See
   [Home](home.md) and [The person view](person.md).

1. **Have a new "monitored" property on people: only monitored people
   show "at home" events, hidden for the others. Keep the total events
   count on top, and a moving average too. Most patients aren't
   monitored, only the high-risk: the elderly, pregnant women, some
   mentally ill; the others' at-home events only count.** People are
   monitored at home for being 80 or over, pregnant (a new fact of the
   simulation: 7% of women aged 18 to 44), or having depression,
   Alzheimer's disease, heart failure or end-stage kidney disease as
   their chronic condition, about one in ten; every move says whether
   and why (`monitored`, `monitoredFor`). The API's feed keeps a move at
   home among the events only for a monitored person (the map still
   shows everyone), counts every move and admission it reads, hidden
   ones too, and averages how many a second over the last minute; `GET
   /api/events` answers them as `total` and `perSecond`. The events card
   shows them beside its title, "48,213 events · 70.4/s", and a
   monitored person's rows carry a heart monitor, why on hover. See
   [Simulation](simulation.md), [API](api.md) and [Home](home.md).
1. **(Previewing the monitored people) Fewer at-home events: monitored
   people check in, spread over the day.** A monitored person at home is
   now an event once a simulated day, their first move at home from
   their check-in hour on, an hour drawn from their id, so the check-ins
   spread over the day; their other moves at home only count, as
   everyone else's.
   See [Simulation](simulation.md#the-stream), [Home](home.md) and
   [API](api.md).
1. **Still little to no occupancy in the care centers: double the
   population of each city.** Forty simulated people a city, double the
   twenty: 280 in all, 280 moves a second. Over 90 simulated days (after
   a 30-day warm-up) about one person is in care at any hour across the
   seven cities, against 0.6 with twenty, and 149 care centers see
   someone, against 91: the capacities (2 to 12) are still mostly empty.
   See [Simulation](simulation.md#people).
1. **Make the cards' attributes align in the events view.** The time of
   each row drifted with the length of its person's name: the name and
   the condition each had half the row's spare width up front, and what
   a short name left over went after the time. Now they share what the
   time leaves, so every row's time ends at its right edge, over the
   record's partition and offset, in figures of one width. See
   [Home](home.md).
1. **The care center view should have a time series: at first, the most
   important metric, the occupancy, and its forecast by DeepAR, the past
   solid and the future dashed and transparent, with points.** The care
   center view's chart now plots the people in care at the care center
   in each of the last 72 simulated hours, a solid line with a solid
   point per hour, and datyx's DeepAR forecast of the next 24, a dashed,
   lighter line with hollow, translucent points in its 80% band, under a
   faint dotted line at its capacity ("8 beds"); hovering an hour says
   how many were in care of the capacity. The series is a new view,
   `occupancy_hourly`: each admission's stay, from its arrival for its
   condition's hours, counted in every hour it covers, up to the run's
   latest arrival, so nothing ahead of now is known. The API gains
   `GET /api/care-centers/{id}/occupancy` and `.../occupancy/forecast`
   (datyx's inference of `occupancy_hourly`'s `default` group), beside
   the admissions' (kept, no longer shown). datyx's development catalogue
   tags the view for DeepAR and describes it. See [Occupancy per
   hour](occupancy-hourly.md), [A care center's occupancy per
   hour](occupancy-timeline.md), [The care center view](care-center.md),
   [API](api.md) and [Database](database.md).
1. **The simulation date and time on the top of the simulation, and on
   the top of the event panel.** Home's map tile shows, beside its title
   "Where you are", the simulated date and time, large and bold with a
   clock, "Day 154 · Wed 3 Jun 2026, 16:00" (day 1 being 1 Jan 2026), and
   **Paused** in amber while the simulation is paused; the events card
   has the same at its top, and the index under its welcome. It updates
   with each read (every 5 seconds): the events' `now` and `paused`, the
   map's people's `day` and `simTime`, the newest of them. The events
   card also now keeps the API's `paused` across its two reads (it was
   dropped when the moves and admissions were merged, so a pause made
   elsewhere didn't show). The app part of the occupancy alarms (the
   banners pinned at the top of the events, the badge, the alarm rows)
   is in [Occupancy alarms](occupancy-alarms.md#the-app). See
   [Home](home.md#the-simulated-clock) and [Index](index.md).
1. **Now that we have predictions on occupancy, fire an alarm, an event,
   and highlight it pretty evidently in the events panel, when the
   expected occupancy in the future surpasses the limit for the care
   center, which is a pretty bad thing to happen, so warn as much as
   possible in advance.** The API keeps an alarm per care center of the
   run going on from datyx's DeepAR forecast of `occupancy_hourly`
   against its capacity in the simulation: `expected` when the forecast's
   mean is over it at some hour of the horizon, `possible` (the early
   warning) when only its 90th percentile is, with the earliest hour over
   it, how many hours ahead, the forecast there and the peak. datyx's
   inference scores the run's care centers, named, 100 a call, asked
   with the token of the request that set the check off (`GET
   /api/events`, the events panel's poll, or `GET /api/alarms`), at most
   every `HEALTHHUB_ALARM_EVERY_MS` (5000; 0 turns them off), in the
   background; the token is used for that call and kept nowhere. A level
   rising fires an `alarm` event, falling a `downgraded` one, back to
   none a `cleared` one: each stored in the new table `occupancy_alarm`
   and published to the new topic `healthhub.alarms` (the `kafka`
   health check makes it), both retried until they succeed. `GET
   /api/alarms` answers the active alarms, worst and soonest first, and
   the latest events; `GET /api/events` carries them too, with `now`,
   the simulated day, time and date, for the clock. The events panel pins
   the active alarms at its top. After review: the run's care centers are
   asked for by name, 100 a call (datyx without series scores only the
   series ending latest in the whole table, an older, longer run's, and
   the highest 100); a fall waits three checks lower (DeepAR's samples
   change every call, so a forecast at the capacity flapped); a care
   center left out of an answer is kept, marked stale, never cleared; no
   check while paused once one has read the run; the first datyx source
   that answered is kept, another's answers ignored; the answer says when
   the alarms may be out of date (`stale`), and the panel says so, with
   the lead counted from its own clock ("now, since …" once past); with
   sign-in on, `/api/alarms` and the alarms of `/api/events` are for a
   signed-in user only, as the forecast is. See [Occupancy
   alarms](occupancy-alarms.md), [API](api.md), [Database](database.md),
   [Home](home.md) and [Development environment](dev-environment.md).
