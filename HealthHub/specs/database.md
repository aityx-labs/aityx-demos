# Database

HealthHub's data lives in PostgreSQL 17, the `postgres` service of
[compose.yaml](../compose.yaml), the official `postgres:17` image with
its data in the `postgres-data` Docker volume. It is the same container
in every way of running the demo:

- `docker compose up` runs it with the API and the web app, on the
  compose network, where the API reaches it as `postgres:5432`.
- `devbox services up` ([process-compose.yaml](../process-compose.yaml))
  runs it alone from the same file, `docker compose up postgres` attached
  through [scripts/infra.sh](../scripts/infra.sh) (`1-postgres`), and the
  API on the host reaches it on the published port, 127.0.0.1:9803
  (`HEALTHHUB_DB_PORT`). The process's readiness probe is the container's
  health, and its shutdown is `docker compose stop postgres`, so the
  container and its data outlive the services. `bash scripts/infra.sh
  down -v` removes the container and the volume; `bash scripts/infra.sh
  psql` opens a prompt as the `healthhub` user.
- A dev container adds Docker with the `docker-in-docker` feature and
  does the same as a laptop.

On the first start of an empty volume the image runs
[docker/postgres-init.sh](../docker/postgres-init.sh), which creates the
`healthhub` user, with `HEALTHHUB_DB_PASSWORD` (`healthhub` by default,
a development password), and the `healthhub` database it owns. The
superuser's password is `HEALTHHUB_DB_ADMIN_PASSWORD` (`postgres`). The
container is healthy once `pg_isready` sees the `healthhub` database.

The schema is the API's ([API](api.md),
[lib/db.dart](../healthhub_api/lib/db.dart)): at start it creates what is
missing, and the view anew, so a fresh database works without a separate
migration step. It then describes every table, the view and every
column with a PostgreSQL comment (`COMMENT ON`), from `schemaComments`
in [lib/schema_comments.dart](../healthhub_api/lib/schema_comments.dart):
what the table holds, and for each column what it is, its values or
range, and which table a reference points to (`care_centers.id`). A
catalogue that reads the schema takes them as descriptions: datyx
carries them into OpenMetadata. They are set again at every start, so
a changed text replaces the old one, and the view, made anew, gets its
own again. A table or column added to the schema needs its comment too:
`test/schema_comments_test.dart` checks, against a live database
(skipped when none answers), that the described tables, views and
columns are exactly the schema's.

| Table | Columns | What |
|---|---|---|
| `greetings` | `id SERIAL PRIMARY KEY`, `message TEXT NOT NULL`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()` | The greeting the app shows. One row, "Hello, world", inserted when the table is empty; `GET /api/hello` reads the first by `id` |
| `medical_conditions` | `code TEXT PRIMARY KEY`, `name`, `type` (`acute` or `chronic`, checked), `prevalence DOUBLE PRECISION`, `min_age` and `max_age INT`, `summary`, `treatment`, `treatment_duration_days INT` (null for a chronic condition), `duration`, `visit_count`, `visit_interval_days` and `stay_hours INT`, `female_share DOUBLE PRECISION` (default 0.5), `urgent BOOLEAN` (default false), `follow_up_stay_hours INT` (the seed's value, or `stay_hours` when it has none), `course_gap_days INT` (null for a random gap), `setting` and `follow_up_setting TEXT` (where the visits go, the seed's `follow_up_setting` or `setting`; `hospital` by default); the last six added with `ADD COLUMN IF NOT EXISTS` to a table made before them | The common conditions of [Medical conditions](conditions.md), their treatment and how they bring people to the hospital, made to hold exactly the API's compiled-in seed at every start (by code, in one transaction with their templates; a condition no longer in the seed is deleted) |
| `complaint_templates` | `id SERIAL PRIMARY KEY`, `condition_code TEXT REFERENCES medical_conditions ON DELETE CASCADE`, `visit` (`first`, `repeat` or `last`, checked), `position INT`, `text`, `triage` (`red` to `blue`, checked); unique `(condition_code, visit, position)` | What a patient with the condition says on arrival, three per visit kind, with placeholders the simulation fills ([conditions.md](conditions.md#complaint-templates)), and each one's reference triage level ([conditions.md](conditions.md#triage-reference-levels)); seeded with the conditions, keyed by code, visit and position |
| `admissions` | `id SERIAL PRIMARY KEY`, `event_id TEXT NOT NULL UNIQUE`, `person_id`, `person_name`, `age INT`, `sex`, `occupation`, `city`, `condition_code`, `condition_name`, `condition_type`, `visit` (`first`, `repeat` or `last`, checked), `visit_number INT`, `complaint TEXT`, `template INT` (which of the visit kind's templates, 0 to 2; null before it was recorded), `hospital_id INT`, `hospital_name`, `sim_day INT`, `sim_time`, `admitted_at TIMESTAMP` (generated and stored from `sim_day` and `sim_time`, the arrival as a date and time on the simulation's calendar, [Simulation](simulation.md#the-calendar); added with `ADD COLUMN IF NOT EXISTS`), `recorded_at TIMESTAMPTZ DEFAULT now()`; index on `person_id` (`admissions_person_idx`), for a person's view, and on `(hospital_id, id)` (`admissions_hospital_idx`), for a care center's | Every simulated arrival at a hospital, as the API's feed reads it from `healthhub.admissions` ([Simulation](simulation.md#admissions)): inserted with `ON CONFLICT (event_id) DO NOTHING RETURNING id`, so a retry or a replay never doubles one and the API knows (and logs) when it skipped one; the event id starts with the run's id, so runs never collide; `GET /api/admissions` reads the latest. The one run that doesn't come from the stream is `00000001`, [the simulated history](simulated-history.md): a year, by default, of the people's visits, which the API simulates ahead at start in dev mode and inserts itself, 2,000 an `INSERT ... SELECT FROM unnest(...)`, every value a parameter, replacing the run when it no longer matches. The simulated people's moves are not stored |
| `admission_triage` | `event_id TEXT PRIMARY KEY REFERENCES admissions (event_id) ON DELETE CASCADE`, `level` (`red` to `blue`, checked), `wait_minutes INT`, `area`, `nurse_check BOOLEAN`, `level_rule INT`, `level_why`, `area_rule INT`, `area_why`, `signs JSONB`, `choices JSONB`, `receipt JSONB`, `reference` (checked), `error`, `input_tokens INT`, `millis INT`, `mode`, `triaged_at TIMESTAMPTZ DEFAULT now()`, `via` (`datyx` or `aityx`, checked; added after, `ADD COLUMN IF NOT EXISTS`); a level or an error, never both | Each admission's triage by aityx ([Triage at the desk](triage.md)): the level, the wait, the area, the nurse's check, the rules behind them, what Jev read, aityx's receipt and the template's reference level; or why it failed; and which way the call went, through datyx's gateway or directly. Inserted once, `ON CONFLICT DO NOTHING`; `GET /api/triage` counts and lists them |
| `admissions_hourly` | `run_id TEXT`, `hospital_id INT`, `hospital_name TEXT`, `hour_start TIMESTAMP` (simulated, day 1 being 2026-01-01), `admissions`, `acute_admissions` and `chronic_admissions INT`, all `NOT NULL`; primary key `(run_id, hospital_id, hour_start)` | The admissions per run, hospital and simulated hour ([Admissions per hour](admissions-hourly.md)). The API makes it; the Flink job writes the live runs', upserting by the key, and the API two runs at start in dev mode: the history run's, `00000000`, drawn from rates ([The history](admissions-hourly.md#the-history)), and the simulated history's, `00000001`, counted from that run's rows of `admissions` ([The simulated history's run](admissions-hourly.md#the-simulated-historys-run)). Sparse: an hour without admissions at a hospital has no row |
| `patient_days` (a view) | `run_id`, `person_id`, `day DATE` (simulated, day 1 being 2026-01-01), `age`, `sex`, `city`, `hospital_id`, `chronic_condition` (`none` when none), `visits`, `acute_visits`, `chronic_visits` and `stay_hours INT` | Each person's visits and hours of hospital care per run and simulated day ([Patient days](patient-days.md)), computed from `admissions` and `medical_conditions` at every read, so of the live runs and of the simulated history, run `00000001`; dropped and made again at every start. Sparse: a day without visits has no row |
| `occupancy_hourly` (a view) | `run_id`, `hospital_id`, `hospital_name`, `hour_start TIMESTAMP` (simulated, day 1 being 2026-01-01) and `occupancy INT` | The people in care at each care center per run and simulated hour: each admission's stay, from its arrival for its condition's hours, counted in every hour it covers, up to the run's latest arrival; an hour nobody is in care has no row. Of the live runs and of the simulated history, run `00000001`. Dropped and made again at every start ([Occupancy per hour](occupancy-hourly.md)) |
| `occupancy_alarm` | `id TEXT PRIMARY KEY` (the run, the care center and a counter), `kind` (`alarm`, `downgraded` or `cleared`, checked), `run_id`, `hospital_id INT`, `hospital_name`, `care_center_kind`, `capacity INT`, `unit`, `horizon_hours INT`, `raised_at TIMESTAMPTZ`, all `NOT NULL`; `level` and `previous_level` (`possible`, `expected` or `actual`, checked by the named checks `occupancy_alarm_level_check` and `occupancy_alarm_previous_level_check`, made again at every start; `level` null exactly when cleared), `threshold DOUBLE PRECISION` (the share of the capacity), `occupancy INT` and `observed_at TIMESTAMP` (the occupancy at the run's latest hour, and that hour; the three added to tables made before them, null in their older rows), `overflow_at`, `peak_at` and `series_end TIMESTAMP` (simulated, day 1 being 2026-01-01), `lead_hours INT`, `mean`, `p90`, `peak_mean` and `peak_p90 DOUBLE PRECISION`, `training_run BIGINT`, `sim_day INT`, `sim_time`; index on `(run_id, hospital_id, raised_at)` | Each [occupancy alarm](occupancy-alarms.md) event: a care center's level against the threshold of its capacity, by its occupancy observed or datyx's forecast, rising, falling or clearing. Inserted once by its id (`ON CONFLICT (id) DO NOTHING`), every value a parameter, from a queue retried until the database takes it; also published to `healthhub.alarms` |
| `occupancy_forecast` | `run_id TEXT`, `hospital_id INT`, `hour_start TIMESTAMP` (the hour predicted, simulated), `series_end TIMESTAMP` (where the forecast started from, before `hour_start`, checked), `lead_hours INT`, `mean`, `p10` and `p90 DOUBLE PRECISION`, `forecast_at TIMESTAMPTZ`, all `NOT NULL`; `training_run BIGINT`; primary key `(run_id, hospital_id, hour_start)` | What datyx's DeepAR predicted of each care center's occupancy in each hour of a run before it was observed ([A care center's occupancy per hour](occupancy-timeline.md)): every step of every forecast the occupancy alarms' checks and the care center view get, upserted in one statement (the rows a `jsonb` parameter read by `jsonb_to_recordset`), a forecast from a later `series_end` replacing an earlier one's, never the other way round, one from the same `series_end` only when its numbers or training run differ (the same forecast asked again writes nothing); pruned to the three runs forecast last, each its last 744 hours forecast |
| `care_centers` | `id SERIAL PRIMARY KEY`, `key TEXT NOT NULL UNIQUE`, `name`, `kind` (`hospital`, `clinic` or `health_station`, checked), `subtype`, `address`, `postal_code`, `city`, `region`, `country CHAR(2)`, `latitude` and `longitude DOUBLE PRECISION`, `phone`, `website`, `ownership` (`public`, `private` or `unknown`, checked), `source`, `source_id`, `updated_at`; index on `(country, city, kind)` | The hospitals, clinics and health stations of [Care centers](care-centers.md), made to hold exactly the API's compiled-in seed at every start; `GET /api/care-centers` reads them |

## Known limitations

- A development password, and no TLS between the API and the database:
  fine on a laptop, a codespace or the compose network, not anywhere
  shared.
- No migration tool yet: the API's `CREATE TABLE IF NOT EXISTS` is the
  whole schema management. A real schema will want one.
- `admissions` and `admissions_hourly` grow with every run of the
  simulation and nothing prunes them (`admissions_hourly` by at most a
  row per hospital and simulated hour, fewer, as most hours have none).
  The two runs the API writes are a fixed size, replaced and never added
  to: with the defaults on a new database, the history run is 542,350
  rows of `admissions_hourly`, and the simulated history 6,082 rows of
  `admissions` and 5,995 of `admissions_hourly`.
  `admissions`: one row per visit of a live run, about eighty a minute of real time with the
  defaults at the start of a run, when most people's first visits fall,
  and fewer after.
- `occupancy_alarm` grows by a row per alarm event, a few a simulated
  day per care center at most, and nothing prunes it either.
- `occupancy_forecast` grows by a row per care center and simulated
  hour watched (each forecast's 24 steps update the hours ahead in
  place, and a forecast asked again unchanged writes nothing). A run has
  admissions at 33 or 34 care centers with today's population (80 people
  a city); older runs of other populations had 58 to 210. With 33, about
  800 rows a simulated day, 12,000 a real hour at the default pace (a
  simulated hour every 10 s); with 200, about 72,000 a real hour. The
  API prunes it (`Db.pruneForecasts`, at a run's first write after a
  start or a new run, and every 500 writes): only the three runs forecast
  last are kept, each its last 744 hours (31 simulated days, the 720
  hours the care center view reads at most and a day), so at most about
  3 × 744 × 200 = 450,000 rows.
