# Patient days

Each simulated person's days at the hospital, per run and simulated day:
how many visits they made that day, the hours of hospital care those
visits took, and the person's facts. A time series per person, the kind
of table a score of each patient's coming care is trained on (what datyx
will read, as it would a customer's). It is the view `patient_days` of
the `healthhub` database ([Database](database.md)), made by the API at
start from [lib/db.dart](../healthhub_api/lib/db.dart).

Beside the live runs, the view holds run `00000001`,
[the simulated history](simulated-history.md): a year, by default, of
the simulation's people going for care, which the API simulates ahead at
start and writes into `admissions`, so that from the first start on a
new database the people have a year of days here, enough for datyx's
XGBoost to train on. With the defaults, 6,042 rows of 554 people, from 2026-01-01
to 2026-12-31. The hourly history's run, `00000000`, has no admissions,
so nothing here.

## What a row holds

One row per run, person and simulated day with at least one admission
([Simulation](simulation.md#admissions)) whose event id has the
simulation's shape (`<run>-<person>-d<day>-t<turn>`, the run 8 hex
digits). Admissions from builds before run ids are left out, as in
[Admissions per hour](admissions-hourly.md).

| Column | What |
|---|---|
| `run_id` | The run, the event id's first part. Each start of the API is a new run from day 1, its people drawn the same but living it afresh, so a person is the run and the id together; `00000001` is the simulated history |
| `person_id` | The person's id within the run (`reus-3`) |
| `day` | The simulated day as a date, day 1 being 2026-01-01, as in `admissions_hourly` |
| `age`, `sex`, `city` | The person's, the same on every row of a run: ages don't advance |
| `hospital_id` | The care center of the day's visits (the highest id, should two differ). A person's visits go where each needs ([Simulation](simulation.md#people)), so it can change from one of their days to another: in the simulated history, 351 of the 554 people go to more than one care center, three at most |
| `chronic_condition` | The code of the chronic condition the run's admissions show for the person, on every row of the run, even before their first chronic visit; `none` when they show none |
| `visits` | The admissions of the day: one, rarely two |
| `acute_visits`, `chronic_visits` | Those of an acute episode and of the chronic condition, adding up to `visits` |
| `stay_hours` | The hours of care the day's visits take: each visit's stay as the simulation keeps the person, the condition's `stay_hours` for a first visit and `follow_up_stay_hours` after ([Medical conditions](conditions.md#visits)) |

Sparse: a day without a visit has no row, so a missing day is zero
visits and zero hours. A view, so it is always what the admissions say;
the API drops and makes it again at every start, so a new definition
replaces the old one.

## In datyx

datyx's development catalogue tags it a time series, group `care`:
Timestamp `day`, Target `stay_hours`, SeriesKey `run_id` and
`person_id`, a missing row zero, a horizon of 30 days, trained by
XGBoost from `sex`, `city`, `hospital_id`, `chronic_condition`, `age`
and the visits and hours before. A run is a cohort that ends on its last
day, and an example needs 30 days after its cutoff, so a run shorter
than a few horizons gives few or none: a new database's first training
run failed with "too few examples" until the simulated history gave
every person a year ([The simulated history](simulated-history.md#in-datyx)).
The person view asks for a person's prediction
([The person view](person.md)).

## Known limitations

- The stay is the condition's as the seed says it now: a condition no
  longer in the seed leaves its visits' hours null.
- The chronic condition is read from the whole run, so a row before the
  person's first chronic visit already names it: what a hospital would
  know from the person's record, not from their visits so far.
- Simulated days run ahead of the wall clock, as in
  `admissions_hourly`; a run's series stop when the API restarts.
- The simulated history's people are the live run's, under the same
  ids, in another year of their own: the two runs' rows of `reus-3`
  share the person's facts, not their visits.
- A view computes every read from all the admissions; fine for the
  simulation's few thousand a run (6,082 in the simulated history), not
  for a hospital's history.
