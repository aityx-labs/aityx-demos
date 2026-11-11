# The simulated history

A year of the simulation's people going for care, lived at once when the
API starts instead of turn by turn, so that the `admissions` table
holds, from the first start on a new database, what a live run takes a
real day to make. It is one run, `00000001` (`simulatedRun` in
`lib/simulation.dart`, beside the hourly history's `historyRun`; a live
run's random id never takes either). The code is
[lib/simulated_history.dart](../healthhub_api/lib/simulated_history.dart).

`patient_days` ([Patient days](patient-days.md)) and `occupancy_hourly`
([Occupancy per hour](occupancy-hourly.md)) are views of `admissions`,
so they get the run's series with it: each person's days of care over a
year, and each care center's people in care hour by hour. The run's rows
of `admissions_hourly` ([Admissions per hour](admissions-hourly.md)) are
counted from its admissions too.

## What it is for

datyx trains its models on HealthHub's tables ([In datyx](#in-datyx)):
XGBoost on `patient_days`, a person's hours of care over the next 30
days, and DeepAR on `admissions_hourly` and `occupancy_hourly`. Until
this run, `admissions` held live runs only, so on a new database (a new
Kubernetes cluster) the two views had almost nothing for hours: XGBoost
needs series several 30-day horizons long, its first training run failed
with "too few examples", and the person view's prediction answered
datyx's 404, "no model of the group care of public.patient_days has been
trained yet" ([The person view](person.md)); DeepAR's occupancy model
had a few simulated days. Only `admissions_hourly` had a generated
history, run `00000000`, drawn from rates
([The history](admissions-hourly.md#the-history)), which has no
admissions behind it and so gives the views nothing.

## Who writes it and when

- **The API**, at start in dev mode, once the database is migrated, the
  care centers read and the people drawn, and before the feed and the
  live simulation start. It simulates the year, then writes it: one try
  is awaited, so on a new database the history's rows have lower ids
  than the live run's. If that try fails (the database busy or gone),
  five more go on in the background, 5 s apart, each failure logged, and
  the live run starts anyway. What it did is one line of the log:
  `simulated history: run 00000001, 365 days, 6082 admissions (written),
  5995 hours of admissions_hourly (counted from them)`, or `(up to
  date)` for either part. In prod mode nothing is written; a database a
  dev run wrote to keeps what it has.
- **`dart run bin/history.dart`** in `healthhub_api/`, which writes both
  histories to the database `HEALTHHUB_DB_*` names without starting the
  API (it migrates it first, as the API does): `--sim-days N` sets the
  days of this one, `--days N` the hourly history's, and `--dry-run`
  writes nothing and prints what each would hold, for this one the
  admissions, acute and chronic, the people and care centers with one,
  the days of care (`patient_days`) and the hours with an admission
  (`admissions_hourly`).

The admissions go straight into the `admissions` table. They never go
through Kafka: nothing is published to `healthhub.admissions` or
`healthhub.people.moves`, so the people don't move on the map, the
events don't show them, aityx triages none of them
([Triage at the desk](triage.md)), and the Flink job counts none of
them, nor does `healthhub.admissions.hourly` carry their counts. The
writing has a connection of its own, closed after (`Db.writeSimulated`),
as the hourly history's has ([API](api.md)).

## How long

`HEALTHHUB_SIM_HISTORY_DAYS` days: 365 by default, 0 for none, a whole
number up to 730 (two years); anything else stops the API at start. The
year starts where a live run does, at 06:00 on day 1, 2026-01-01
([The calendar](simulation.md#the-calendar)), and ends with the last
day: an arrival of the last turn that falls past midnight isn't the
history's. A longer history starts with the same days as a shorter one.

With 0 the API writes nothing and leaves a history already there as it
is; `dart run bin/history.dart --sim-days 0` removes it.

## Which people, and what they do

The people are the ones the live run starts with: `HEALTHHUB_SIM_PEOPLE`
a city, drawn with the same seed (`populationSeed`,
[Simulation](simulation.md#people)), so the same ids, names, ages,
homes, care centers and chronic conditions. `reus-3` of run `00000001`
is who `reus-3` of the live run is, living another year.

They live it through the simulation's own `advance` function, the one a
live run calls every turn ([Turns and the clock](simulation.md#turns-and-the-clock)),
with turns of `HEALTHHUB_SIM_MINUTES_PER_TURN` minutes and random
numbers from a fixed seed (`simulatedSeed`), so the same settings always
make the same admissions: the same visits, complaints, templates and
times, with event ids of the simulation's shape
(`00000001-reus-3-d130-t12396`). The turns in which a person has nothing
to do (at home with no visit due, or in care before the stay ends) are
passed over; a test checks that the result is the one of living every
turn. No care center's flow is changed
([The flow at a care center](simulation.md#the-flow-at-a-care-center)),
and nobody joins or leaves.

## How it is kept up to date

Every start simulates the year again (a fraction of a second) and
compares a **mark** of it with the table's: how many admissions the run
has, and the sums of their days, visit numbers, care center ids and
ages, and of the lengths of their complaints, care center names,
condition names and times.

- **Equal**: nothing is written. A restart costs the simulation and two
  queries, this one and the hourly counts' below.
- **Different** (other people, conditions, care centers, seeds, days or
  turn length, or a writing that stopped half way): the run's admissions
  are deleted and inserted again, 2,000 an `INSERT ... SELECT FROM
  unnest(...)`, every value a parameter, `ON CONFLICT (event_id) DO
  NOTHING`, in the order they happen, so their ids follow the simulated
  time.

The run's rows of `admissions_hourly` are then counted from its
admissions in SQL, by care center and simulated hour, acute and chronic,
as the Flink job counts a live run's: deleted and inserted again in one
transaction when the admissions were written, or when the rows there
don't add up to the admissions (their number, or the admissions they
count).

## What it holds

With the defaults (80 people a city in 7 cities, 560 people, turns of 15
minutes, 365 days) and the care centers of today's seed on a new
database:

| | |
|---|---|
| Admissions | 6,082: 3,571 acute and 2,511 chronic |
| People with one | 554 of the 560, from 1 to 26 each, 11 for the median person |
| Care centers with one | 300: 82 hospitals, 181 health stations, 37 clinics |
| `patient_days` | 6,042 rows, from 2026-01-01 to 2026-12-31 |
| `admissions_hourly` | 5,995 rows, the hours with an admission |
| `occupancy_hourly` | 20,066 rows, the hours with someone in care, up to 2026-12-31 19:00, the run's last arrival |

The numbers follow the care centers' ids, which a database gives in the
order it first saw them: one seeded long ago, with care centers added
since, draws other homes and so other admissions, about as many.

## In datyx

- **XGBoost** (`patient_days`, group `care`): `stay_hours` over the next
  30 days per `run_id` and `person_id`. A run is a cohort that ends on
  its last day, so each person's series goes from their first day of
  care to 2026-12-31, the days without a row zeros. datyx makes an
  example per series and cutoff, every 7 days back from the last day
  with 30 days after it (day 335): from this run alone, 23,709 examples
  of 553 people, up to 48 a person and 43 on average, enough for its
  split by time into training, validation and test, where a new
  database's live run had none.
- **DeepAR** (`occupancy_hourly`, group `default`): 300 series, one per
  care center, a year of hours each. `admissions_hourly`'s three groups
  get the same 300 care centers' series, at a live run's level, beside
  the hourly history's.
- The **series still observed**, those datyx scores when asked for no
  series in particular (the run whose end is the latest), are this
  run's until a live run passes day 365, about a real day at the default
  pace; in `admissions_hourly` they were the hourly history's before,
  until day 90. HealthHub's own calls name the live run's series, so
  they aren't affected.
- datyx's checks hold for the run as for a live one: the event ids carry
  their rows' person and day, and `admissions_hourly` counts no more
  than `admissions` has, as the counts come from it.

## Tests

`test/simulated_history_test.dart`: the setting (the default, 0, the
most, what is refused); the run id, never the hourly history's nor a
live run's; `CareIndex` answering as `nearestHospital` and
`nearestCareCenter` do; the simulation (none for no days, the same
admissions every time, those of every turn lived, in the order they
happen, valid events of the run, a longer one starting with a shorter
one's days, another turn length another history); the mark and the
hourly counts; and the writing, against a live database in temporary
tables (skipped without one): written once with its hourly counts, left
alone when up to date, written again when it changes.

## Known limitations

- The admissions are never triaged, so the person and care center views
  show them as "Not triaged yet" for good, and `/api/triage` counts none
  of them.
- The run covers the same calendar days a live run starts on: it is
  another year of the same people, not the live run's past. A live run's
  series start empty on day 1 whatever the history holds.
- Only the people of the start are in it, at the normal flow: people who
  join while the simulation runs, and care centers whose flow was
  changed, have no history of it.
- The same settings always make the same admissions, so every new
  database has the same year. A change of the people, the care centers,
  the conditions, the turn length or the days rewrites the whole run,
  under new row ids and a new `recorded_at`.
- Its rows are the table's newest whenever it is written after other
  runs (on a database that had runs before it, or when it is rewritten):
  until the live run has recorded as many as a caller asks for,
  `GET /api/admissions` fills its list with the history's last
  admissions, and where the API looks for "the newest run with an
  admission" of a person or a care center (in prod mode, or before the
  simulation has started) it finds this run.
- The mark is sums, not a comparison row by row: a change that keeps
  every sum, such as a care center renamed to a name as long, isn't
  seen, and the run keeps the old rows.
- The live run waits for the first try: a few seconds on a new database,
  two queries on a later start, and up to the connection's timeouts when
  the database doesn't answer.
- The care center view's counts "in all runs" include the run's
  admissions.
- Nothing prunes it, but it doesn't grow: the run is replaced, never
  added to.
