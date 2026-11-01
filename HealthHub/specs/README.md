# HealthHub — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

HealthHub is a demo built like Mortgage Hub, Contact Hub and PokerFace,
with one more part: a PostgreSQL database. For now the app is a map: the
index, for someone not signed in, shows where they are with a welcome
over it; home, after signing in, is a dashboard whose one tile is the
same map. aityx triages every patient who arrives at a hospital, from
what they say at the desk ([Triage at the desk](triage.md)); what aityx
does in HealthHub is described feature by feature in
[docs/aityx.md](../docs/aityx.md).

## Features

**App**

- [Index](index.md): the page for someone not signed in, the map with
  the welcome over it and the sign-in; and which page the app shows.
- [Home](home.md): after signing in, the dashboard of tiles, for now the
  map.
- [The map](map.md): OpenStreetMap's tiles, darkened, with the user's
  location highlighted; how the location is asked for.
- [Theme](theme.md): the aityx dark palette.
- [App icon](app-icon.md): the heart with the pulse line, the launcher
  icons and the favicon.

**Backend**

- [API](api.md): `healthhub_api`, a Dart server that holds the aityx key,
  talks to PostgreSQL and to Kafka through its REST proxy, and serves
  hello, health, sign-in, the care centers, the simulated people, their
  events, their admissions and the admissions' triage.
- [Simulation](simulation.md): in dev mode, people with a profile and a
  medical condition who travel to the nearest care center a visit needs
  (a health station, urgent care, a mental health or dialysis clinic, a
  general hospital) when it is due and say what is wrong there, each its own async loop, every move
  and admission streamed through Kafka and read back for the map, the
  events and the database.
- [Admissions per hour](admissions-hourly.md): an Apache Flink job that
  counts the admissions per run, hospital and simulated hour from the
  stream into the `healthhub.admissions.hourly` topic and the
  `admissions_hourly` table, a time series per hospital.
- [Patient days](patient-days.md): the view `patient_days`, each
  person's visits and hours of hospital care per run and simulated day,
  with their facts, a time series per person.
- [Occupancy per hour](occupancy-hourly.md): the view `occupancy_hourly`,
  the people in care at each care center per run and simulated hour, a
  time series per care center that datyx forecasts with DeepAR.
- [The person view](person.md): every person named on home opens their
  view: who they are, what they do now, datyx's XGBoost prediction of
  their hours of care over the next 30 days (highlighted), their
  admissions with aityx's triage and their days of care.
- [The care center view](care-center.md): every care center named on
  home, of any kind, opens its view: where it is on a map, its capacity
  in the simulation and how much is in use now, its occupancy per hour
  with datyx's forecast, who is there and on the way, its admissions.
- [A care center's occupancy per hour](occupancy-timeline.md): the
  care center view's time series, the people in care up to now as a
  solid line with its points and datyx's DeepAR forecast of the next 24
  dashed and lighter, in its band, under the capacity.
- [Occupancy alarms](occupancy-alarms.md): when datyx's DeepAR forecast
  puts a care center's occupancy over its capacity (by its mean,
  expected; by its 90th percentile, possible), an alarm as early as the
  forecast allows: an event stored in `occupancy_alarm` and streamed on
  `healthhub.alarms`, `GET /api/alarms`, and a banner pinned at the top
  of home's events.
- [Triage at the desk](triage.md): each admission triaged by aityx from
  what the patient said and their age (Jev reads the danger signs, a
  decision gives the level, the wait, the area and a nurse's check, with
  the rules behind them), recorded with aityx's receipt and set against
  each complaint's reference level.
- [Medical conditions](conditions.md): the common acute and chronic
  conditions, their treatment and duration, the visits they bring, and
  what a patient says on arrival.
- [Database](database.md): PostgreSQL as a container, the `healthhub`
  database and user, the tables the API makes, among them the conditions,
  the admissions and the admissions per hour, and the patient days and
  occupancy views.
- [Care centers](care-centers.md): the hospitals, clinics and health
  stations of seven cities, from official registries, seeded at start.

**Project**

- [Development environment](dev-environment.md): devbox, process-compose,
  Docker for the database, Kafka and Flink, the health monitor, the builds, Docker Compose
  and the dev container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
