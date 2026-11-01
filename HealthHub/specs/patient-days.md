# Patient days

Each simulated person's days at the hospital, per run and simulated day:
how many visits they made that day, the hours of hospital care those
visits took, and the person's facts. A time series per person, the kind
of table a score of each patient's coming care is trained on (what datyx
will read, as it would a customer's). It is the view `patient_days` of
the `healthhub` database ([Database](database.md)), made by the API at
start from [lib/db.dart](../healthhub_api/lib/db.dart).

## What a row holds

One row per run, person and simulated day with at least one admission
([Simulation](simulation.md#admissions)) whose event id has the
simulation's shape (`<run>-<person>-d<day>-t<turn>`, the run 8 hex
digits). Admissions from builds before run ids are left out, as in
[Admissions per hour](admissions-hourly.md).

| Column | What |
|---|---|
| `run_id` | The run, the event id's first part. Each start of the API is a new run with new people from day 1, so a person is the run and the id together |
| `person_id` | The person's id within the run (`reus-3`) |
| `day` | The simulated day as a date, day 1 being 2026-01-01, as in `admissions_hourly` |
| `age`, `sex`, `city`, `hospital_id` | The person's, the same on every row of a run: ages don't advance and a person always goes to the same hospital |
| `chronic_condition` | The code of the chronic condition the run's admissions show for the person, on every row of the run, even before their first chronic visit; `none` when they show none |
| `visits` | The admissions of the day: one, rarely two |
| `acute_visits`, `chronic_visits` | Those of an acute episode and of the chronic condition, adding up to `visits` |
| `stay_hours` | The hours of care the day's visits take: each visit's stay as the simulation keeps the person, the condition's `stay_hours` for a first visit and `follow_up_stay_hours` after ([Medical conditions](conditions.md#visits)) |

Sparse: a day without a visit has no row, so a missing day is zero
visits and zero hours. A view, so it is always what the admissions say;
the API drops and makes it again at every start, so a new definition
replaces the old one.

## Known limitations

- The stay is the condition's as the seed says it now: a condition no
  longer in the seed leaves its visits' hours null.
- The chronic condition is read from the whole run, so a row before the
  person's first chronic visit already names it: what a hospital would
  know from the person's record, not from their visits so far.
- Simulated days run years ahead of the wall clock, as in
  `admissions_hourly`; a run's series stop when the API restarts.
- A view computes every read from all the admissions; fine for the
  simulation's few thousand a run, not for a hospital's history.
