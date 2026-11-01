# A care center's admissions per hour

The time series of the [care center view](care-center.md): how many
people the care center admitted in each simulated hour up to now, and
how many datyx's DeepAR model expects in each of the next 24. App in
[admissions_timeline.dart](../healthhub_app/lib/care_centers/admissions_timeline.dart),
API in [routes.dart](../healthhub_api/lib/routes.dart),
[db.dart](../healthhub_api/lib/db.dart) and
[server.dart](../healthhub_api/bin/server.dart).

## The card

**Admissions per hour** (`AdmissionsTimelineCard`), in the care center
view under the map and the capacity, as wide as the view:

- **The hours up to now**, a solid orange line: the care center's
  admissions in each of the last 72 simulated hours of the run going on
  (three simulated days), an hour with none a zero. "Now" is the run's
  latest counted hour at any care center, where its series end, as datyx
  reads them.
- **The next 24 hours**, datyx's DeepAR forecast from that hour: its
  mean, a dashed, lighter line starting from the last hour, in a faint
  band from the 10th to the 90th percentile of its sample paths. A faint
  dashed line marks where the hours end and the forecast begins.
- The axes: whole admissions on y, from 0 to a whole number above the
  highest hour or 90th percentile; on x each simulated midnight as its
  day ("Day 154"), and noon when there is room.
- Hovering an hour, or touching it, shows its numbers: "Day 154, 09:00 ·
  2 admitted (1 acute, 1 chronic)", or for a forecast hour the mean and
  the 80% range.
- Above the chart, the run ("run 1349d576, now") and a line: how many
  were admitted in the hours shown and up to which hour, and what datyx
  expects over the next 24 and from which training run, or why there is
  no forecast (datyx's own words: no model of the group trained yet, not
  signed in, datyx not answering). The hours show either way.
- Under it, the key: "Admitted", and "DeepAR forecast (mean; the band,
  10th to 90th percentile)" when there is one.

Both are asked for together when the view opens and every 10 seconds
(a simulated hour is a real second, so each read moves the series about
ten hours); a failed read keeps what is shown. A care center nobody was
ever admitted to says so instead of a chart. The view gets the card's
two calls from home through `CareCenterOpener`, as it gets its own.

## The API

- `GET /api/care-centers/{id}/admissions?run=&hours=72`: the care
  center's admissions per hour from `admissions_hourly`
  ([Admissions per hour](admissions-hourly.md)), of the run going on (or
  `run`; in prod, the newest run with an admission there): `{"hospitalId",
  "run", "current", "end", "hours": [{"hour", "admissions", "acute",
  "chronic"}]}`, the `hours` hours up to `end` (at most 720), oldest
  first, the hours as `YYYY-MM-DDTHH:MM` in simulated time (day 1 is
  2026-01-01), an hour without a row a zero. `end` is the run's latest
  hour at any care center. Open to everyone, like the care centers; 400
  for hours that aren't a positive number, 503 without the database.
- `GET /api/care-centers/{id}/admissions/forecast?run=`: datyx's
  inference of the care center's series of `admissions_hourly` (group
  `default`, key `run_id` and `hospital_id`), asked with the user's own
  token from their datyx source for HealthHub's database, as the person
  view's prediction is (both through `_inference`): datyx's answer with
  `forecast`, its steps from the series' end, each `{"at", "mean", "p10",
  "p50", "p90"}`, empty when datyx can't say. datyx's own error when it
  refuses (404 while no model of the group is trained), 404 without a
  source or admissions, 502 when datyx doesn't answer, 401 without a user
  once sign-in is on.

## Tests

`routes_test.dart`: the paths; every hour up to the run's end, missing
hours zero, 72 unless asked and at most 720, open to everyone; hours
that aren't a number; the forecast's steps from datyx's answer, sign-in
and datyx's errors. `widget_test.dart`: the card with the hours solid and
DeepAR's four hours after them, its status line, key and semantics, an
hour and a forecast hour touched; without a model the hours still show
and the card says why; a care center nobody was admitted to; and the
care center view opened from home shows the card under the capacity and
above the people, asking for its id.

## Known limitations

- The forecast needs datyx to have trained a DeepAR model of
  `admissions_hourly`'s `default` group, which datyx's DeepAR training
  does; until then the card shows only the hours.
- Hours are counted by the Flink job, a second or so behind the
  simulation, so "now" is the latest counted hour, and the forecast
  starts from it.
- A care center's admissions are few (most hours are zeros), so the
  forecast's mean is a fraction of an admission most hours.
- The series are the run's: when the API restarts, a new run starts
  from day 1 and its hours from nothing.
