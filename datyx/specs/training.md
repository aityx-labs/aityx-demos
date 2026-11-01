# Training

datyx trains the groups tagged for XGBoost in its catalogue
([catalog.md](catalog.md)) by itself: a component of the API, started
with it, finds them in OpenMetadata, reads their table from the source,
trains, and keeps every run and what it found. Nothing about a customer
is written in the code: the tags say what to train on, and the table's
custom properties how far ahead and how often; switching a group on in
the catalogue is what trains it with every one of its algorithms. Code
in `datyx-api/src/main/java/datyx/training/`.

```
OpenMetadata ──tags, horizon, retrain──▶ Training (every minute) ──due?──▶ run
                                                                           │
source's table ──JDBC, read-only──▶ Dataset ──▶ XgbTrainer (XGBoost4J) ──▶ training_run
                                                                           │
                    GET /api/training, /api/training/runs/{id} ◀───────────┘
```

## When a group is trained

`Training`, an application-scoped bean, checks every minute
(`datyx.training.check-every`, 60 s), the first time 5 s after start
(`datyx.training.first-check`), every database source of every profile:
each group of its catalogue tagged `TimeSeries.XGBoost` (or
`TimeSeries.{group}.XGBoost`, beside DeepAR's or not) and ready has its
XGBoost queued

- when it was never trained: the **initial** run, so a group is trained
  as soon as the API starts, or as soon as it is tagged;
- when its table's `timeSeriesRetrain` has passed since its latest run
  of XGBoost (queued): a **schedule** run. `timeSeriesRetrain` is a custom property
  of the table in OpenMetadata, a span (`30min`, `1h`, `6h`, `1D`, `1W`)
  or `never` (trained once); `1D` when not set. After a failed run, an
  hour at most, so a fix is picked up soon;
- never while one of its XGBoost runs is queued or running: one run of
  a group's algorithm at a time (a unique index of `training_run` on the
  source, table, group and algorithm of the runs queued or running holds
  it, beside the trainer's own lock).

A group **switched off** (its table tagged `TimeSeries.Disabled` or
`TimeSeries.{group}.Disabled`, [catalog.md](catalog.md)) is never queued,
nor trained on request (a 409 saying so). **Switching it on is the
trigger**: one **enabled** run per algorithm of the group (XGBoost and
DeepAR, both when the table names both), queued at once, whether or
not datyx can train it, each with a `triggerNote` naming the change
and the switch it came from (`eventId`, a GroupEvent,
[catalog.md](catalog.md)). datyx learns of the switch three ways, and
`Training.switched` decides for all of them, one decision at a time:

- **OpenMetadata's webhook**, within seconds of a change in its UI (or
  anywhere): `TimeSeries.chronic.Disabled removed in OpenMetadata (table
  version 0.6, by admin, 2026-11-01 11:38 UTC; webhook)`;
- **datyx's switch** (`PUT .../timeseries/enabled`), which queues the
  runs before it answers: `TimeSeries.chronic.Disabled removed through
  datyx's switch (table version 0.6, by julio@example.com, ...)`;
- the **minute's check**, a safety net for a webhook that never came
  (datyx stopped, OpenMetadata unable to reach it): the tag is gone and
  the trainer saw it at its last look, or OpenMetadata's version history
  of the table shows it removed after the group's latest run and latest
  switch on (or ever, when there are none): `TimeSeries.chronic.Disabled
  removed in OpenMetadata (table version 0.9, by admin, 2026-11-01 12:00
  UTC)`, or, when OpenMetadata merged one user's quick off-and-on into
  one version, when datyx saw it.

One switch on, one run per algorithm, never twice: an algorithm is
queued only when it has no run queued at or after the switch (when it
was switched on, or when datyx kept the switch off before it or the
trainer saw it off, whichever is later; for datyx's switch, when the call
began), and a switch datyx knows already is kept no more
([catalog.md](catalog.md)), so the webhook's post of datyx's own switch,
a post delivered again and the check's look queue nothing more. A switch
off told late (the webhook's post of an off that a switch on through
datyx has undone already) is passed over, so it doesn't queue that switch
on's runs again; only a switch off datyx keeps is noted as seen by the
trainer. A group read switched off again by
then queues nothing. A DeepAR run fails at once, `datyx has no DeepAR
trainer yet: only XGBoost groups train`, saying how to train the group
with XGBoost (or that its XGBoost run does). The schedule takes over
XGBoost after its enabled run. The webhook and the switch queue runs
even with the checks off.

And whenever someone asks: `POST /api/datasources/{id}/training`, a
**manual** run of one of the group's algorithms (XGBoost). Runs go one at a time to the trainer's own thread
(`datyx-training`). Runs a stopped API left queued or running are failed
at the next start (`interrupted: the API stopped before the run
finished`). A catalogue that can't be read is skipped until the next
check. `DATYX_TRAINING_ENABLED=false` (`datyx.training.enabled`) turns
the checks off; the tests run with them off.

How often to train again is set where the rest of the dataset is
described, so it travels with it: in OpenMetadata's UI (the table's
Custom Properties), through datyx (`PUT .../training`, below), or on the
dashboard's Training tab. It is the table's, shared by its groups, like
the frequency and the horizon.

## A run

1. The group is read again from OpenMetadata: still switched on, the
   run's algorithm XGBoost and still the group's, and ready, or the run
   fails saying why (a DeepAR run, that datyx has no DeepAR trainer yet).
2. Its table is read from the source (`TableReader`), signed in with the
   source's access details (decrypted with its profile's key), read-only,
   streamed in a transaction it rolls back: only the Timestamp, Target,
   SeriesKey, static and covariate columns, quoted as identifiers; no
   value goes into the query. More than 5,000,000 rows is refused.
3. The dataset is built (`Dataset`), generic over the tags:
   - rows are summed into steps of the frequency, per series (the
     SeriesKey's values); the frequency and the horizon must be fixed
     spans (`min`, `h`, `D`, `W`), the horizon a whole number H of steps;
   - a series runs from its first row to its end. With missing rows as
     `zero`, the end of its **cohort**: the latest row of the series that
     share its key but the last column (in HealthHub, the run's last
     day: a run's patients are all observed until the run stops), or the
     table's latest with one key column; steps without rows are 0. With
     missing rows `unknown`, its own last row, and steps without rows are
     gaps: a label over a gap isn't made;
   - one example per series and **cutoff**, stepping back from its end
     every quarter of the horizon (more, past 250,000 examples): the
     label is the Target summed over the H steps after the cutoff; the
     features, what is known at the cutoff: each StaticCategorical (a
     category, coded), each StaticReal, the steps of history, the steps
     since the Target was last above zero, the Target and each
     PastCovariate summed over the last 1, H, 3H and 12H steps (`stay_hours,
     last 30D`), each KnownCovariate summed over the next H;
   - split by time: the latest 20% of cutoffs **test**, the 15% before
     **validation**, the rest **training**, each part's labels ending
     before the next part's first cutoff. Fewer than 30 training or 10
     test examples fails the run;
   - the series **still observed** (whose end is the latest) are scored
     at their end.
4. XGBoost trains (`XgbTrainer`, XGBoost4J 3.4, the C++ library through
   JNI): `hist` trees, depth 6, learning rate 0.08, rows and columns
   sampled at 80%, up to 400 rounds stopped after 30 without a better
   validation MAE; a Target never below zero is fitted as a Poisson count
   (`count:poisson`), any other with squared error. Categories are
   XGBoost's own categorical features.
5. On the test examples, never seen in training: the mean absolute error
   (MAE) and RMSE, against two baselines, **naive** (the next horizon
   like the last one) and the training labels' **mean**, and the share of
   the naive error saved (`improvement`). Each feature's weight is its
   share of the mean absolute SHAP contribution over the test examples:
   how much it moved the predictions. The 25 highest scores of the series
   still observed, with their Target over the last horizon.
6. The run keeps all of it as JSON (`results`) and the model, XGBoost's
   UBJSON (`model`), with what scoring needs to build features as it did
   ([inference.md](inference.md)): the group as it was trained (`spec`),
   its categories' codes (`categories`), and the features' names and
   types in order. What went wrong fails it with the
   reason: the catalogue or the source unreachable, the group no longer
   ready, too few examples, XGBoost's native library missing.

## Runs

`TrainingRun`, table `training_run` (migration `V5__training_runs.sql`):
the source (removing it removes its runs), the table's FQN, the group,
the algorithm (each of a group's has runs of its own), `trigger`
(`INITIAL`, `SCHEDULE`, `MANUAL`, `ENABLED`), `trigger_note` (V7: for
`ENABLED`, the change that switched the group on) and `group_event_id`
(V8: the switch that queued it), `status` (`QUEUED`, `RUNNING`, `SUCCEEDED`,
`FAILED`), when it was queued, started and finished, the error, the
results and the model.

## Endpoints

Within the caller's profile, like the data sources; secured like them.

`GET /api/training`: each group of the caller's sources tagged for
XGBoost (among its algorithms), ready or not, with its XGBoost runs,
and the latest 50 runs of them all, whatever their algorithm:

```json
{"models":[{"sourceId":1,"source":"HealthHub","table":"datyx-ds-1.healthhub.public.patient_days",
  "schema":"public","name":"patient_days","group":"care","algorithm":"XGBoost","target":"stay_hours",
  "seriesKey":["run_id","person_id"],"ready":true,"problems":[],"frequency":"1D","horizon":"30D",
  "retrain":"1h","retrainEvery":"1h","nextAt":"2026-11-01T11:02:11Z",
  "latest":{...},"lastSucceeded":{"id":51,"sourceId":1,"source":"HealthHub","table":"...","name":"patient_days",
   "group":"care","algorithm":"XGBoost","trigger":"initial","triggerNote":null,"eventId":null,"status":"succeeded","queuedAt":"...","startedAt":"...",
   "finishedAt":"...","seconds":1.8,"error":null,"examples":42000,
   "test":{"examples":8300,"mae":4.1,"rmse":7.9,"naiveMae":6.2,"meanMae":7.4,"improvement":0.34,"meanLabel":5.6}}}],
 "runs":[...],"errors":[]}
```

`retrain` is the table's property as set (null when not), `retrainEvery`
what applies (`1D` then), `nextAt` when the group is due (now when never
trained; null while a run is on, after a run with `never`, or when the
group isn't ready). A source whose catalogue can't be read is in
`errors`.

`GET /api/training/runs/{id}`: a run (`run`, as above) and its `results`:
`dataset` (rows, series, steps, examples, train, valid, test, stride,
features, frequency, horizon, first and last cutoff, when the scores
are, how many series were scored), `params`, `bestIteration`, `test`,
`importance` (`[{"feature":"stay_hours, last 30D","share":0.31},...]`,
the 12 heaviest) and `scores` (`[{"series":{"run_id":"adf5309c",
"person_id":"reus-3"},"predicted":41.2,"last":12.0},...]`). Another
profile's run is a 404.

`POST /api/datasources/{id}/training` with `{"table":"public.patient_days",
"group":"care","algorithm":"XGBoost"}` (`algorithm`, in any case,
optional: XGBoost when the group has it): queues a manual run and
answers it, a 202. A table the catalogue doesn't have is a 404, an
algorithm there isn't a 400; a group switched off, an algorithm not the
group's, DeepAR (`datyx has no DeepAR trainer yet, only XGBoost's`), a
group not ready, or one whose algorithm is being trained already, a 409
saying why; OpenMetadata unreachable a 502.

`PUT /api/datasources/{id}/training` with `{"table":"public.patient_days",
"retrain":"1h"}`: sets the table's `timeSeriesRetrain` in OpenMetadata
(null or blank removes it: `1D`), keeping its other properties, and
answers `{"table":...,"retrain":"1h","retrainEvery":"1h"}`. Neither a
span nor `never` is a 400. The next check uses it.

Both are their own resource (`SourceTrainingResource`) under
`/api/datasources/{id}/training`: a request goes to the resource whose
path matches most of it, and the catalogue's has `/api/datasources/{id}`.

## XGBoost's native library

XGBoost4J's jar carries the native library for macOS (arm64, x86_64),
Linux (aarch64, x86_64) and Windows, loaded through JNI. It needs an
OpenMP runtime: on macOS, Homebrew's `libomp` (`brew install libomp`,
where the library looks for it); on Linux, GCC's `libgomp`, which the
API's JVM image installs (`docker/api.jvm.Dockerfile`). The Scala
compiler XGBoost4J brings for its Scala API is left out, and its
commons-logging goes to JBoss Logging. Without the runtime a run fails
saying so; the rest of the API works.

## HealthHub, as a customer

In development the HealthHub data source's `patient_days` (a view of
HealthHub's, a row per run, person and simulated day with a visit) is
tagged as the `care` group: XGBoost, `stay_hours` over the next 30 days
per `run_id` and `person_id`, from `sex`, `city`, `hospital_id` and
`chronic_condition` (categories), `age`, and the visits and hours
before. Its runs (a cohort) end on their last simulated day, so a
patient's quiet days to the end of the run count as zero, and the
patients of the run still going are the ones scored: who will need the
most hours of hospital care in the next 30 days.

## Tests

`XgbTrainerTest`, no server: a dataset from a tagged group (the
features' names and types, the stride, every series to its cohort's end,
the split by time, the series scored), XGBoost learning a 14-day visit
rhythm better than repeating the last week (with XGBoost4J's native
library), why a group can't be trained (a horizon not a whole number of
steps, too little data, no rows), and missing rows unknown making no
label over a gap. `TrainingTest`, against the Dev Services Postgres
standing in for the source: a group's table read (a column name needing
quotes, an untagged column left out) and trained on; when a group is due
(never trained, the table's interval, 1D by default, an hour after a
failure, never, one run of an algorithm at a time, another algorithm's
beside it); a run a stop interrupted failed at start and answered by the
endpoints, gone with its source; with a fake catalogue, a group switched
on in OpenMetadata found by the check (once, kept as its switch) and by
the table's history; OpenMetadata's post refused unsigned, wrongly
signed, for another body, over 1 MB, not JSON, and changing nothing then,
another source's table passed over; a group with XGBoost and DeepAR
switched on through datyx queuing a run of each at once, the webhook's
post of the same change and the check queuing nothing more, nor again
once the runs failed, a switch off and on in OpenMetadata's UI told by
the webhook queuing both again, delivered twice queuing once, the
switches answered by `GET /api/catalog/events` and the run's `eventId`;
the webhook's posts of an off and on through datyx coming after both, and
of an off in OpenMetadata's UI coming after datyx switched it on again,
queuing nothing more and keeping no off; the check, with no webhook,
seeing a switch on again at the version OpenMetadata gave the one before
(its quick off and on merged); a group removed while off (its Disabled
tag gone with it) switching nothing on;
a manual run with an algorithm (DeepAR, one the group hasn't, an
unknown one, not ready, switched off refused; XGBoost queued); the
endpoints' 404s and 400. `InferenceTest` checks a later DeepAR run is
never what scores. OpenMetadata isn't started, so no run is
trained end to end in the tests.

## Known limitations

- XGBoost only: DeepAR runs are queued (switching a group on) and fail
  at once; DeepAR isn't trained yet.
- The API trains: one run at a time, on a thread of its own, sized for
  datasets of up to 5,000,000 rows and 250,000 examples, not a cluster.
- The JVM only: the native executable has no JNI configuration for
  XGBoost4J, so its runs fail saying the library can't load.
- The hyperparameters are fixed; only the horizon and how often to train
  again are settings.
- A series' end with missing rows as zero is its cohort's (all of its
  key but the last column): right for HealthHub's runs, a guess for a
  table whose last key column isn't the one within a cohort.
- With several API instances on one database, each would train: one
  instance only.
