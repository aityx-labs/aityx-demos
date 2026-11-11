# Admissions per hour

How many people each care center admitted in each simulated hour (a
hospital, a health station, a clinic: `hospital_id` names any since
visits go where they need, [Simulation](simulation.md#people)), counted
from the admissions stream by an Apache Flink job and kept in a Kafka
topic and a database table: a time series per hospital, the kind of
table a forecast is trained on (what datyx will read, as it would a
customer's). The job is
[flink/admissions-hourly.sql](../flink/admissions-hourly.sql); the
services that run it are in [compose.yaml](../compose.yaml). Beside the
live runs the job counts, the table holds a generated **history**, run
`00000000`, which the API writes ([The history](#the-history)), so a
forecast has long, full series to learn from.

## What it counts

Every record of `healthhub.admissions` ([Simulation](simulation.md#admissions))
that is an admission (`"type": "admission"`) with an event id of the
simulation's shape (`<run>-<person>-d<day>-t<turn>`, the run 8 hex
digits), a hospital, a day and a `simTime`. Admissions without a run in
their id, published by builds from before run ids, and records that
aren't JSON are skipped. Each event id counts once, the first time it
is read: the API retries a failed publish, so an admission can be on
the topic twice.

Each admission falls in one key:

- `run_id`: the run, the event id's first part (`3f9c0a7e`). Each start
  of the API is a new run whose clock starts again at day 1, so the same
  hours repeat from run to run; the run tells them apart.
- `hospital_id`: the hospital's id, as in `care_centers`.
- `hour_start`: the simulated hour of the arrival, on the simulation's
  calendar, where day 1 is 2026-01-01 ([Simulation](simulation.md#the-calendar)): `"day": 4, "simTime":
  "09:09"` is 2026-01-04 09:00. A timestamp without a time zone.

and is counted in `admissions`, and in `acute_admissions` or
`chronic_admissions` by the visit's condition type, so the two add up to
`admissions`. `hospital_name` is the hospital's name (the largest, if a
key ever saw two).

## Where the counts go

- **The table** `admissions_hourly` of the `healthhub` database
  ([Database](database.md)), one row per key, with the key as its primary
  key. The API makes it at start; the job upserts into it (`INSERT ... ON
  CONFLICT`), flushing every second or 500 rows, as user `healthhub`.
  Sparse: an hour with no admission at a hospital has no row, so a
  missing hour is a zero. The history run's rows are the API's, not the
  job's.
- **The topic** `healthhub.admissions.hourly`: each key's latest count,
  the key as JSON (`{"run_id":"adf5309c","hospital_id":2,"hour_start":"2034-11-08T16:00:00"}`)
  and the row as JSON, the same snake_case columns, timestamps in
  ISO-8601:
  `{"run_id":"adf5309c","hospital_id":2,"hospital_name":"Centre Mq Reus","hour_start":"2034-11-08T16:00:00","admissions":1,"acute_admissions":1,"chronic_admissions":0}`.
  Compacted as well as kept a day (`cleanup.policy=compact,delete`), so
  a reader from the start gets each hour's latest count; Kafka's health
  check makes it ([Development environment](dev-environment.md)).

A count changes as admissions come in, and each change is written to
both at once (one Flink statement set).

## How the job runs

- **No event-time windows.** The simulated clock runs an hour a real
  second and starts again from day 1 at every start of the API, so a
  watermark would declare whole runs late. The job is a plain `GROUP BY`
  over the key, which keeps a count per key and sends each change on.
- **A function of the topic.** The source reads `healthhub.admissions`
  from its earliest record every time the job is submitted (the
  consumer group `healthhub-flink-admissions-hourly` only records how
  far it read). The topic keeps a day, so a resubmitted job recounts
  that day and writes the same rows again; rows older than the topic
  stay as they were.
- **State**: on the heap, checkpointed every 10 s to the JobManager's
  memory; a key's count, and the dedup's memory of an event id, go 25
  hours after their last change (`table.exec.state.ttl`), past the
  topic's retention.
- **The cluster**: Flink 2.2 (`flink:2.2.1-java21`), a JobManager and a
  TaskManager with one slot, parallelism 1, in an image
  ([flink/Dockerfile](../flink/Dockerfile)) with the Kafka connector
  (`flink-sql-connector-kafka` 5.0.0-2.2), the JDBC connector and its
  PostgreSQL dialect (`flink-connector-jdbc-core` and
  `flink-connector-jdbc-postgres` 4.1.0-2.2), OpenLineage's Java client
  1.32.0 (the JDBC connector reports the tables it writes through it,
  and fails to plan without it) and the PostgreSQL driver 42.7.14, each
  downloaded from Maven Central and checked against a pinned SHA-256.
  768 MB for the JobManager, 1 GB for the TaskManager (5% of it managed
  memory, as the state is on the heap).
- **Submission**: the `flink-sql` service runs
  [flink/submit.sh](../flink/submit.sh), which every 30 s
  (`FLINK_SUBMIT_INTERVAL`) asks the JobManager's `/jobs/overview` for a
  job named `healthhub-admissions-hourly` that isn't finished, failed or
  canceled, and submits the SQL through Flink's SQL client when there is
  none, once Kafka takes a connection at the job's bootstrap address:
  compose starts the submitter after Kafka, but Kubernetes orders
  nothing, and a job submitted before the broker answers has its
  source's admin client retry without a pause (31 MB of JobManager log
  in the 39 s a new cluster's Kafka took to come up). A second `docker compose up` or a restart of the submitter finds
  the job and leaves it; a JobManager that restarted, and lost it, gets
  it back within 30 s; a job that failed for good is submitted again.
  The script puts `HEALTHHUB_DB_PASSWORD` into the SQL in a file only
  its user reads, removed after, with Kafka's and the database's
  addresses: compose's `kafka:19092` and `postgres:5432` unless
  `HEALTHHUB_KAFKA_BOOTSTRAP`, `HEALTHHUB_DB_HOST` and `HEALTHHUB_DB_PORT`
  name others (on Kubernetes, `healthhub-kafka` and `healthhub-postgres`), and logs only the client's verdict (the
  job's id or the error), never the statements, which hold the
  password. `submit.sh check` is the service's health check: healthy
  while the job is on the cluster.
- **Failures**: Flink restarts a failing job (exponential delay,
  without end), so a database or broker that is down, or the table not
  made yet (the API makes it at start), holds the counts back until it
  answers.

The JobManager's web UI is on http://localhost:9806
(`HEALTHHUB_FLINK_PORT`), always bound to 127.0.0.1: it has no
authentication and runs any job it is sent.

## The history

A live run is a poor training set: its few people (40 a city) leave
most hours of most care centers empty, and it starts again at day 1
whenever the API restarts. So the table also holds the **history run**,
`00000000` (`historyRun` in `lib/simulation.dart`, which a simulation's
random run id never takes): the admissions per hour of every care
center the simulation's people use, generated from rates rather than
simulated ([lib/history.dart](../healthhub_api/lib/history.dart)).

- **Who writes it**: the API, at start in dev mode, once the database
  is migrated and the care centers read, in the background beside the
  simulation; and `dart run bin/history.dart` in `healthhub_api/`, the
  same against any database `HEALTHHUB_DB_*` names (it migrates it
  first, as the API does), with `--days N` and `--dry-run` (writes
  nothing, prints the care centers, rows and admissions, and the mean
  admissions per care center by hour of day). The Flink job never
  writes it: no event has run `00000000`.
- **How long**: `HEALTHHUB_HISTORY_DAYS` days (90 by default, 2,160
  hours; 0 writes none; a whole number up to 730, two years, anything
  else stops the API), from day 1 of the simulated calendar, 2026-01-01 00:00, a
  Thursday, as the live runs' `hour_start`.
- **Which care centers**: those the simulation's people use, each one's
  hospital and the care center of every setting the conditions' visits
  go to. The API draws its people with a fixed seed (`populationSeed`,
  [Simulation](simulation.md#people)), so they are the same at every
  start, and the history covers exactly the care centers a live run
  admits people to; `bin/history.dart` draws the same people
  (`HEALTHHUB_SIM_PEOPLE` a city), so the same care centers. With the
  defaults, 271 (87 hospitals, 118 health
  stations, 66 clinics). `hospital_name` is the care center's
  name in `care_centers`.
- **The counts**: each hour's acute and chronic admissions are drawn
  from Poisson distributions whose means are, for a care center of
  level `peak` (its mean admissions in a weekday's busiest hour) and
  acute share `s`, at hour `h` of the day:

  ```
  profile(h) = (1 + cos(2π (h − 13) / 24)) / 2        1 at 13:00, 0 at 01:00
  weekly     = 1 on weekdays, 0.85 on Saturdays and Sundays
  acute(h)   = peak × s × profile(h) × weekly
  chronic(h) = peak × (1 − s) × profile(h) × weekly
  ```

  The profile is the simulation's daily profile of arrivals over its
  peak ([Simulation](simulation.md#visits)), the shape a live run's
  acute and chronic admissions both follow: one shape for both groups,
  a single harmonic, so the history and the live runs teach a forecast
  the same daily pattern. At 13:00 on a weekday the two add up to
  `peak`; the hours around 01:00 are mostly empty, as a live run's. A care
  center's level is drawn within its kind's range: a hospital 3 to 8,
  60% acute; a health station 1.5 to 4, 35% acute; a clinic 1 to 3, half
  acute. `admissions` is the sum; an hour with none has no row, as the
  job's.
- **Deterministic**: a care center's random numbers are seeded by its id
  (`historySeed + id`), so it always gets the same rows, and a longer
  history starts with the same days.
- **Idempotent**: one query reads each care center's rows of the run
  (their count, admissions, acute admissions, last hour and name); a
  care center whose rows match what it should have is left alone, any
  other's are deleted and inserted again in a transaction of its own (one
  `INSERT ... SELECT FROM unnest(...)`, the values as parameters, `ON
  CONFLICT DO NOTHING`); the rows of care centers no longer covered are
  deleted. A restart costs that one query; a change of the days or the
  care centers rewrites what changed. With the defaults, the first
  writing takes well under a minute and 359,962 rows. It runs on a
  connection of its own, closed after: the API's shared one refuses
  other statements during a transaction, so the simulation's admissions
  and the health checks, which go on meanwhile, would fail and close it
  under the history.

With the defaults, every series spans 2,160 hours (752 to 1,701 of them
with a row); the mean admissions per care center rise from none at
01:00 to 3.37 at 13:00, symmetric about it; the first harmonic fitted
to each series (y ≈ a + b cos(2πh/24) + c sin(2πh/24), the hours
without a row as zeros) peaks between 12.6 and 13.5 h (13.0 on
average) with an amplitude of 0.92 to 1.05 times its mean, its acute
and chronic parts alike; and a weekend day has 0.85 of a weekday's
admissions.

## Known limitations

- The hours are the simulation's, from an arbitrary 2026-01-01; with
  the defaults a run covers a simulated year in about two and a half real
  hours, so `hour_start` runs years ahead of the wall clock.
- A run's series stop when the API restarts; the next run is new series
  from day 1, not a continuation.
- Hours with no admission have no row: a reader fills them with zeros.
- The history is drawn, not simulated: its levels are well above a live
  run's (a few admissions a care center at the busiest hour, against a
  few a day), and its weekends are quieter while a live run's are not. A
  forecast learns the daily shape from it, not a live run's level.
- Its care centers follow the people: a change of `HEALTHHUB_SIM_PEOPLE`,
  of the care centers or of the conditions changes them, and the next
  start deletes the history of those no longer used and writes that of
  the new ones.
- No state survives a restart of the cluster: the resubmitted job
  recounts what the topic still holds. A key at the edge of the topic's
  retention, partly expired, is rewritten with the part left, a lower
  count.
- A row is never deleted: one written by an earlier version of the job
  (as the admissions without a run once were) stays until removed by
  hand.
- The password is in the job's options, which the JobManager holds; the
  UI and REST API are on 127.0.0.1 only, and anyone who reaches them can
  run any job anyway.
