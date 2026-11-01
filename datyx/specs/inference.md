# Inference

The models datyx trains ([training.md](training.md)) score series on
demand, XGBoost's the Target summed over the horizon ahead, DeepAR's each
step of it, and every call is accounted for. Code in
`datyx-api/src/main/java/datyx/training/` (`Inference`, `DeepArInference`,
`SourceInferenceResource`, `InferenceResource`, `InferenceCall`).

## Scoring

`POST /api/datasources/{id}/inference` with a table (its name,
`schema.table` or FQN), its group (`default` when left out), and the
series to score, each its SeriesKey's values by column:

```json
{"table":"public.patient_days","group":"care",
 "series":[{"run_id":"adf5309c","person_id":"reus-3"},{"run_id":"adf5309c","person_id":"nobody"}]}
```

The latest model that succeeded for that group answers (the training run
it came from), of the `algorithm` the request names (`XGBoost` or
`DeepAR`, optional); none named, a group trained with both answers with
XGBoost's: its series are read from the source as they are now, only
their rows (their key's values as query parameters, compared as text, so
a key of any type takes a string) and their cohort's latest time, so a
series ends where training would end it; their features are built as
the run built them, from the group as it was when trained and the codes
its categories had (both kept with the run; a category value the model
never saw is missing), and the model predicts the Target summed over the
horizon ahead:

```json
{"callId":51,"runId":3,"trainedAt":"...","table":"datyx-ds-1.healthhub.public.patient_days","group":"care",
 "target":"stay_hours","horizon":"30D","requested":2,"scored":1,"millis":38,
 "predictions":[{"series":{"run_id":"adf5309c","person_id":"reus-3"},"predicted":3.25,"last":2.0,"note":null},
  {"series":{"run_id":"adf5309c","person_id":"nobody"},"predicted":null,"last":null,"note":"no rows for this series"}]}
```

`last` is the series' Target over the last horizon, for comparison. With
no series, every series still observed (whose end is the latest) is
scored, the highest `limit` (25, at most 100) answered. At most 100
series a call. The model is loaded from the run once and kept (the
latest 8). A model trained the same way scores a series as its training
scored it: the tests check it.

### A DeepAR model

The same call, on a group DeepAR trained, answers each series' forecast
from its end (its cohort's, as training ends it), step by step over the
horizon: the step's time (`at`, the step's start, as the table's
timestamps read, without a zone), the mean, and the 10th, 50th and 90th
percentiles of 100 sample paths. `predicted` is the mean summed over the
horizon, `last` the Target over the last horizon, and `horizon` the one
it forecasts (the table's, or 24 steps of the frequency):

```json
{"callId":12,"runId":1,"trainedAt":"...","table":"datyx-ds-1.healthhub.public.admissions_hourly","group":"default",
 "target":"admissions","horizon":"1D","requested":1,"scored":1,"millis":62,
 "predictions":[{"series":{"run_id":"1349d576","hospital_id":"2"},"predicted":0.69,"last":2.0,"note":null,
   "forecast":[{"at":"2026-01-19T18:00","mean":0.02,"p10":0.0,"p50":0.0,"p90":0.0},...]}]}
```

The series are read and laid out as the run laid them out (the codes its
categories had: a value never seen is unknown), the network is loaded
from the run once and kept (the latest 8), and its calls take turns. An
XGBoost model's predictions have no `forecast`.

No model for the group is a 404 (`no model of the group care of
public.patient_days has been trained yet`); a run trained before datyx
kept the group and codes with it a 409 (train it again); a series
without its whole key a 400, the source unreachable a 502, both
accounted for as failed calls with the call's id.

## The account

Every call that reached a model is kept (`InferenceCall`, table
`inference_call`, migration `V6__inference_calls.sql`): the source, the
training run, the table and group, when, how long (milliseconds, the
reading and the predicting), how many series were asked for (0 for all
those still observed) and scored, `OK` or `FAILED` with the error, and
who asked (the signed-in identity's email, else its subject; none while
authentication is off). Removing the source or the run removes its
calls.

`GET /api/inference` answers the caller's account over the last 7 days
(at most 10,000 calls), `?hours=` of them hour by hour (24 by default,
1 to 168, the window's; out of range, the nearest):

- `totals`: `calls`, `failed`, `scored` (series), `avgMillis`,
  `p50Millis` and `p95Millis` (nearest rank), `lastCalledAt`;
- `lastHour`: the calls of the last hour;
- `models`: each algorithm a group has a trained model of (a group
  trained with both has two), and any a call named, newest run first,
  with its latest model (`algorithm`, `runId`, `trainedAt`), what it
  predicts (`target`, `horizon`, `seriesKey`, from the run) and its
  calls' `stats`, as the totals: the calls that algorithm answered
  (a call naming none gets XGBoost's, when the group has both);
- `hours`: the hours `perHour` covers;
- `perHour`: the last `hours` hours, the current hour last, each `hour`
  (its start) with its `calls`, `failed`, `scored` (series),
  `p50Millis` and `p95Millis` (nearest rank; null without a call), and
  `byModel`: each model's calls in it (a group's algorithm: the run that
  answered), `sourceId`, `table`, `name`, `group`, `algorithm`, `calls`,
  `failed`, `scored`, in the order of their latest call in the hour;
- `calls`: the latest 50, newest first: the source, table, group,
  `algorithm`, run, when, `millis`, `requested`, `scored`, `status`
  (`ok`, `failed`), the error and the caller.

Both within the caller's profile, secured like the data sources.

```json
{"since":"...","hours":24,"totals":{"calls":12,"failed":1,"scored":40,"avgMillis":18.5,"p50Millis":14,"p95Millis":61,"lastCalledAt":"..."},
 "lastHour":5,"models":[{"sourceId":1,"source":"HealthHub","table":"datyx-ds-1.healthhub.public.patient_days","name":"patient_days",
   "group":"care","algorithm":"XGBoost","runId":7,"trainedAt":"...","target":"stay_hours","horizon":"30D",
   "seriesKey":["run_id","person_id"],"stats":{"calls":12,"failed":1,...}}],
 "perHour":[...,{"hour":"2026-11-01T10:00:00Z","calls":10,"failed":1,"scored":30,"p50Millis":12,"p95Millis":61,
   "byModel":[{"sourceId":1,"table":"datyx-ds-1.healthhub.public.patient_days","name":"patient_days","group":"care",
     "algorithm":"XGBoost","calls":7,"failed":1,"scored":10},...]}],
 "calls":[{"id":31,"sourceId":1,"source":"HealthHub","table":"...","name":"patient_days","group":"care","algorithm":"XGBoost",
   "runId":7,"calledAt":"...","millis":14,"requested":2,"scored":1,"status":"ok","error":null,"caller":"ana@example.com"}]}
```

## Tests

`InferenceTest`, against the Dev Services Postgres standing in for the
source: a model trained on a table of two runs (a key with an INT
column) scores a person named by key as training scored them, and a
person without rows says so; with none named, the series still observed
as training's scores; a series missing a key column is a 400; no model
yet a 404; the account counts the calls, the failure, the series, the
hour (its calls, failure, series, latency and its model's, an hour
without a call empty), the model's calls, algorithm and key, newest
first, a model of each of the group's algorithms (DeepAR's call its
own, in the models as in the hour), 168 hours when asked (at most 168, at least 1), and forgets them
with the source; an hour counts each model's calls apart (XGBoost's and
DeepAR's of a group); percentiles by nearest rank. A DeepAR model trained on an
hourly table of two runs and four hospitals forecasts a hospital named by
key over the next 24 hours from its run's end, step by step, its
percentiles in order and whole, its mean summing to `predicted`; a
hospital without rows says so, with no forecast; with none named, the
running run's hospitals, the highest first.

## Known limitations

- The latest model of a group's algorithm answers; an older one can't be
  asked for.
- Scoring reads the series' rows from the source at every call: fast for
  a few series, a scan of the table for all those still observed.
- The account is the database's: no metrics endpoint (Prometheus) yet,
  and nothing prunes old calls.
- With missing rows unknown, a series ends at its own last row, as in
  training.
