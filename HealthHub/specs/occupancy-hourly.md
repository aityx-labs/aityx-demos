# Occupancy per hour

How many people each care center has in care in each simulated hour of
a run: a time series per care center, the kind of table a forecast of
a hospital's load is trained on (what datyx reads, as it would a
customer's). It is the view `occupancy_hourly` of the `healthhub`
database ([Database](database.md)), made by the API at start from
[lib/db.dart](../healthhub_api/lib/db.dart), and the series of the care
center view's chart ([A care center's occupancy per hour](occupancy-timeline.md)).

Beside the live runs, the view holds run `00000001`,
[the simulated history](simulated-history.md): a year, by default, of
the simulation's people going for care, which the API simulates ahead at
start and writes into `admissions`, so that from the first start on a
new database each care center has a year of hours here for datyx's
DeepAR to learn from, where a live run starts with none. With
the defaults, 20,066 rows at 300 care centers, up to 2026-12-31 19:00,
the run's last arrival. The hourly history's run, `00000000`, has no
admissions, so nothing here.

## What a row holds

Each admission ([Simulation](simulation.md#admissions)) whose event id
has the simulation's shape (`<run>-<person>-d<day>-t<turn>`, the run 8
hex digits) is a stay: from its arrival (its simulated day and time) for
its condition's hours, `stay_hours` for a first visit and
`follow_up_stay_hours` after, as the simulation keeps the person
([Medical conditions](conditions.md#visits)). A stay counts in every
hour it covers any minute of: arriving at 09:10 for 2 hours is 09:00,
10:00 and 11:00.

| Column | What |
|---|---|
| `run_id` | The run, the event id's first part. Each start of the API is a new run from day 1, so the same hours repeat from run to run; `00000001` is the simulated history |
| `hospital_id`, `hospital_name` | The care center, any kind |
| `hour_start` | The simulated hour, day 1 being 2026-01-01, as in `admissions_hourly`; a timestamp without a time zone |
| `occupancy` | The people in care there at any minute of the hour, each once |

A run's hours go up to its latest arrival at any care center, its "now":
a stay under way adds no hours ahead of it, so the series ends where
the run is, as a hospital's census would. Sparse: an hour nobody is in
care has no row, so a missing hour is zero people. A view, so it is
always what the admissions say; the API drops and makes it again at
every start.

## In datyx

datyx's development catalogue tags it a time series, group `default`:
Timestamp `hour_start`, Target `occupancy`, SeriesKey `run_id` and
`hospital_id` (the care center a StaticCategorical too), frequency 1h, a
missing row zero, trained by DeepAR. It is described, owned and checked
like HealthHub's other series (the run id's shape, at least one person
a row), with the lineage from `admissions` and `medical_conditions`.
Its series still observed, the run whose end is the latest, are the
simulated history's until a live run passes its last day
([The simulated history](simulated-history.md#in-datyx)); the care
center view and the occupancy alarms name the live run's series.

## Known limitations

- The stay is the condition's as the seed says it now; an admission of a
  condition no longer in the seed is left out.
- The whole view is computed when read: about half a second for every
  run's hours, milliseconds for one care center's, as measured before
  the simulated history added its 6,082 admissions to every read.
- A care center nobody of the live run was admitted to yet has no series
  of that run; where the API falls back on the newest run with an
  admission there (in prod mode, or before the simulation has started),
  that can be the simulated history's
  ([A care center's occupancy per hour](occupancy-timeline.md#the-api)).
