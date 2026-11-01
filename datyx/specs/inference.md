# Inference

The models datyx trains ([training.md](training.md)) score series on
demand, and every call is accounted for. Code in
`datyx-api/src/main/java/datyx/training/` (`Inference`,
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
it came from): its series are read from the source as they are now, only
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
(at most 10,000 calls):

- `totals`: `calls`, `failed`, `scored` (series), `avgMillis`,
  `p50Millis` and `p95Millis` (nearest rank), `lastCalledAt`;
- `lastHour`: the calls of the last hour;
- `models`: each group with a trained model, and any a call named, with
  its latest model (`runId`, `trainedAt`), what it predicts (`target`,
  `horizon`, `seriesKey`, from the run) and its calls' `stats`, as the
  totals;
- `perHour`: the last 24 hours, each `hour` with its `calls` and
  `failed`, the current hour last;
- `calls`: the latest 50, newest first: the source, table, group, run,
  when, `millis`, `requested`, `scored`, `status` (`ok`, `failed`), the
  error and the caller.

Both within the caller's profile, secured like the data sources.

## Tests

`InferenceTest`, against the Dev Services Postgres standing in for the
source: a model trained on a table of two runs (a key with an INT
column) scores a person named by key as training scored them, and a
person without rows says so; with none named, the series still observed
as training's scores; a series missing a key column is a 400; no model
yet a 404; the account counts the calls, the failure, the series, the
hour, the model's calls and key, newest first, and forgets them with
the source; percentiles by nearest rank.

## Known limitations

- The latest model of a group answers; an older one can't be asked for.
- Scoring reads the series' rows from the source at every call: fast for
  a few series, a scan of the table for all those still observed.
- The account is the database's: no metrics endpoint (Prometheus) yet,
  and nothing prunes old calls.
- With missing rows unknown, a series ends at its own last row, as in
  training.
