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
| `medical_conditions` | `code TEXT PRIMARY KEY`, `name`, `type` (`acute` or `chronic`, checked), `prevalence DOUBLE PRECISION`, `min_age` and `max_age INT`, `summary`, `treatment`, `treatment_duration_days INT` (null for a chronic condition), `duration`, `visit_count`, `visit_interval_days` and `stay_hours INT`, `female_share DOUBLE PRECISION` (default 0.5), `urgent BOOLEAN` (default false), `follow_up_stay_hours INT` (the seed's value, or `stay_hours` when it has none), `course_gap_days INT` (null for a random gap); the last four added with `ADD COLUMN IF NOT EXISTS` to a table made before them | The common conditions of [Medical conditions](conditions.md), their treatment and how they bring people to the hospital, made to hold exactly the API's compiled-in seed at every start (by code, in one transaction with their templates; a condition no longer in the seed is deleted) |
| `complaint_templates` | `id SERIAL PRIMARY KEY`, `condition_code TEXT REFERENCES medical_conditions ON DELETE CASCADE`, `visit` (`first`, `repeat` or `last`, checked), `position INT`, `text`, `triage` (`red` to `blue`, checked); unique `(condition_code, visit, position)` | What a patient with the condition says on arrival, three per visit kind, with placeholders the simulation fills ([conditions.md](conditions.md#complaint-templates)), and each one's reference triage level ([conditions.md](conditions.md#triage-reference-levels)); seeded with the conditions, keyed by code, visit and position |
| `admissions` | `id SERIAL PRIMARY KEY`, `event_id TEXT NOT NULL UNIQUE`, `person_id`, `person_name`, `age INT`, `sex`, `occupation`, `city`, `condition_code`, `condition_name`, `condition_type`, `visit` (`first`, `repeat` or `last`, checked), `visit_number INT`, `complaint TEXT`, `template INT` (which of the visit kind's templates, 0 to 2; null before it was recorded), `hospital_id INT`, `hospital_name`, `sim_day INT`, `sim_time`, `recorded_at TIMESTAMPTZ DEFAULT now()`; index on `person_id` (`admissions_person_idx`), for a person's view | Every simulated arrival at a hospital, as the API's feed reads it from `healthhub.admissions` ([Simulation](simulation.md#admissions)): inserted with `ON CONFLICT (event_id) DO NOTHING RETURNING id`, so a retry or a replay never doubles one and the API knows (and logs) when it skipped one; the event id starts with the run's id, so runs never collide; `GET /api/admissions` reads the latest. The simulated people's moves are not stored |
| `admission_triage` | `event_id TEXT PRIMARY KEY REFERENCES admissions (event_id) ON DELETE CASCADE`, `level` (`red` to `blue`, checked), `wait_minutes INT`, `area`, `nurse_check BOOLEAN`, `level_rule INT`, `level_why`, `area_rule INT`, `area_why`, `signs JSONB`, `choices JSONB`, `receipt JSONB`, `reference` (checked), `error`, `input_tokens INT`, `millis INT`, `mode`, `triaged_at TIMESTAMPTZ DEFAULT now()`; a level or an error, never both | Each admission's triage by aityx ([Triage at the desk](triage.md)): the level, the wait, the area, the nurse's check, the rules behind them, what Jev read, aityx's receipt and the template's reference level; or why it failed. Inserted once, `ON CONFLICT DO NOTHING`; `GET /api/triage` counts and lists them |
| `admissions_hourly` | `run_id TEXT`, `hospital_id INT`, `hospital_name TEXT`, `hour_start TIMESTAMP` (simulated, day 1 being 2026-01-01), `admissions`, `acute_admissions` and `chronic_admissions INT`, all `NOT NULL`; primary key `(run_id, hospital_id, hour_start)` | The admissions per run, hospital and simulated hour ([Admissions per hour](admissions-hourly.md)). The API only makes it; the Flink job writes it, upserting by the key. Sparse: an hour without admissions at a hospital has no row |
| `patient_days` (a view) | `run_id`, `person_id`, `day DATE` (simulated, day 1 being 2026-01-01), `age`, `sex`, `city`, `hospital_id`, `chronic_condition` (`none` when none), `visits`, `acute_visits`, `chronic_visits` and `stay_hours INT` | Each person's visits and hours of hospital care per run and simulated day ([Patient days](patient-days.md)), computed from `admissions` and `medical_conditions` at every read; dropped and made again at every start. Sparse: a day without visits has no row |
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
  `admissions`: one row per visit, about ten a minute of real time with the
  defaults at the start of a run, when most people's first visits fall,
  and fewer after.
