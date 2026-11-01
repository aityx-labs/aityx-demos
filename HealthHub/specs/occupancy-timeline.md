# A care center's occupancy per hour

The time series of the [care center view](care-center.md): how many
people were in care at the care center in each simulated hour up to now
([Occupancy per hour](occupancy-hourly.md)), observed, and what datyx's
DeepAR model predicted of every hour: of each past hour before it was
observed, and of each of the next 24 now; against the capacity and the
[occupancy alarms](occupancy-alarms.md)' threshold. App in
[occupancy_timeline.dart](../healthhub_app/lib/care_centers/occupancy_timeline.dart),
API in [routes.dart](../healthhub_api/lib/routes.dart),
[db.dart](../healthhub_api/lib/db.dart) and
[server.dart](../healthhub_api/bin/server.dart).

## The card

**Occupancy per hour** (`OccupancyTimelineCard`), in the care center
view under the map and the capacity, as wide as the view, 220 px high.
Both series always show:

- **Observed, solid orange**: the people in care in each of the last 72
  simulated hours of the run going on (three simulated days), an hour
  with nobody a zero, a solid line with a solid point per hour. The
  hours end at the run's latest arrival at any care center, where its
  series end, as datyx reads them.
- **Predicted, dashed blue**: what DeepAR predicted of every hour, a
  dashed line with a hollow point per hour, in a faint band from the
  10th to the 90th percentile. Over the past hours, what it predicted of
  each before it was observed (the forecast made closest to it, kept by
  the API: [The API](#the-api)), beside the observed line, so how far off
  it was shows; an hour nothing was kept of has no point, and the line
  breaks there. Over the next 24 hours, datyx's forecast now, going on
  from the last hour's prediction (from its observed point when there is
  none). The blue is the theme's (`Aityx.blue`), apart from the orange
  for colour-blind readers too (ΔE 21 protan), and dashed, hollow.
- **Now**: a solid vertical line at the simulated clock (the API's
  `now`; within the hours shown, the last hour observed without it),
  labelled at its top "Now Jan 19 12:40". The header says it too, "Now ·
  Jan 19, 2026 12:40" ("Ended Jan 19, 2026 12:00" for a past run), never
  the run's id.
- **The capacity**: the care center's places in the simulation, a faint
  dotted line labelled "8 beds" at its right end; **the threshold**, the
  alarms' share of it (`threshold`, 90% unless the API says otherwise), a
  red dashed line labelled "90% · 7.2" at its left end. None without a
  capacity.
- **Marks**: every point at or above the threshold, observed or
  predicted, past or ahead, is marked: a larger red point in a red halo
  when observed, a hollow red ring in a faint red halo when predicted;
  ahead, an hour whose 90th percentile alone reaches it, a small amber
  ring at its 90th percentile. The first hour ahead the forecast reaches
  it, by its mean (else by its 90th percentile), is ringed in red (amber)
  and labelled at the top of the plot, joined to it by a thin line: "90%
  expected at Jan 19 16:00" ("90% possible at ...").
- The axes: whole people on y, from 0 to a whole number above the
  highest observed hour, mean, 90th percentile or the capacity; on x
  each simulated midnight as its date ("Jun 3"), and noon when there is
  room, an hour a slot (the forecast placed by its hours, its steps
  inside the hours shown left out). The points get smaller when the hours
  are close together.
- Hovering an hour, or touching it, shows its numbers: "Jan 19, 2026
  09:00 · 3 in care of 8 beds (38%) · predicted 2.8, 1 h before · 1 to
  3.5 (80%)", and "at or above the 90% threshold" when it is; for an hour
  ahead, "Jan 19, 2026 15:00, forecast · 2.0 expected of 8 beds (25%) · 0
  to 3 (80%)", and "90% threshold expected" (or "possible").
- Above the chart, a line: how many are in care at the latest hour and
  the most in the hours shown, of the capacity; how many of those hours
  datyx predicted before they came and how far off it was on average
  (the mean absolute difference of its mean); then what datyx expects on
  average over the next 24 and at most, from which training run, and the
  first hour ahead the threshold is expected or possible ("90% of the
  capacity expected at Jan 19, 2026 16:00"), or why there is no forecast
  (datyx's own words: no model of the group trained yet, not signed in,
  datyx not answering). The hours show either way, and what was
  predicted of them.
- Under it, the key: "In care (observed)", "Predicted by DeepAR before
  each hour and ahead (mean; the band, 10th to 90th percentile)" when
  anything was predicted, "Now", "Capacity, 8 beds", "Alarm threshold,
  90% (7.2)", "In care at or above it" and "Predicted at or above it".
- Its semantics label says it all in words: now and its time, the most,
  the hours predicted before, the forecast's average, the threshold, how
  many hours observed and predicted reach it, and the first ahead.

Both are asked for together when the view opens and every 10 seconds (a
simulated hour at the simulation's pace, [The
simulation](simulation.md#pace)); a failed read keeps what is shown. A
care center nobody was ever admitted to says so instead of a chart. The
view gets the card's two calls from home through `CareCenterOpener`, as
it gets its own.

## The API

A care center has two series per hour (`CareCenterSeries`), each with
its two endpoints, open the same way:

- `GET /api/care-centers/{id}/occupancy?run=&hours=72`: the people in
  care there per hour from `occupancy_hourly`, of the run going on (or
  `run`; in prod, the newest run with an admission there): `{"hospitalId",
  "run", "current", "end", "threshold", "now", "hours": [{"hour",
  "occupancy", "predicted"}]}`, the `hours` hours up to `end` (at most
  720), oldest first, the hours as `YYYY-MM-DDTHH:MM` in simulated time
  (day 1 is 2026-01-01), an hour without a row a zero. `end` is the run's
  latest hour; `threshold` the occupancy alarms' share of the capacity
  (`HEALTHHUB_ALARM_THRESHOLD`, 0.9); `now` the simulated clock (`{"day",
  "simTime", "date"}`) for the run going on, else null. `predicted` is
  what datyx predicted of the hour before it was observed, from
  `occupancy_forecast` ([Database](database.md)): `{"mean", "p10", "p90",
  "leadHours"}` (the forecast made closest to the hour, `leadHours` ahead
  of it), null when nothing was kept, and null for every hour, with
  sign-in on, for a caller who isn't signed in (it is datyx's forecast,
  as the forecast route is theirs only). Open to everyone, like the care
  centers; 400 for hours that aren't a positive number, 503 without the
  database.
- `GET /api/care-centers/{id}/occupancy/forecast?run=`: datyx's
  inference of the care center's series of `occupancy_hourly` (group
  `default`, key `run_id` and `hospital_id`), asked with the user's own
  token from their datyx source for HealthHub's database, as the person
  view's prediction is (both through `_inference`): datyx's answer with
  `forecast`, its steps from the series' end, each `{"at", "mean", "p10",
  "p50", "p90"}`, empty when datyx can't say. datyx's own error when it
  refuses (404 while no model of the group is trained), 404 without a
  source or admissions, 502 when datyx doesn't answer, 401 without a user
  once sign-in is on. In dev mode, an answer from the datyx source the
  occupancy alarms read (or any, before they read one) is kept in
  `occupancy_forecast`, as the alarms' checks keep theirs
  ([Occupancy alarms](occupancy-alarms.md#the-checks)).
- `GET /api/care-centers/{id}/admissions?run=&hours=72` and
  `.../admissions/forecast?run=`: the same for its admissions per hour,
  from `admissions_hourly` ([Admissions per hour](admissions-hourly.md)),
  each hour `{"hour", "admissions", "acute", "chronic"}` (no `predicted`,
  `threshold` nor `now`), `end` the run's
  latest counted hour, and datyx's forecast of that table's `default`
  group. The card doesn't show them now.

## Tests

`routes_test.dart`: the paths of both series; every hour up to the run's
end, missing hours zero, 72 unless asked and at most 720, open to
everyone; what was predicted of each hour with the threshold and the
clock, an hour without one null, none for a caller who must sign in, and
none of it for the admissions; hours that aren't a number; the
forecast's steps from datyx's answer, sign-in and datyx's errors.
`occupancy_test.dart`, against a scratch database, rolled back: each
stay counted in every hour it covers, up to the run's latest arrival.
`occupancy_alarm_db_test.dart`: what was predicted kept per hour, the
forecast made closest to it winning, and read back.
`widget_test.dart` (group "a care center's occupancy per hour"): the
card with both series (the hours observed and what was predicted of
them, the forecast after), the now line at the clock and its header, the
status line (how far off the predictions were, the forecast, no
crossing), the key (threshold and marks included) and semantics; an
hour touched with its prediction, one without, a forecast hour; with a
capacity of 3, the hours observed and predicted at or above 90% counted,
the first crossing ahead (possible) in the status and semantics, the
tooltips saying so; the first crossing by the mean, else the 90th
percentile; the now line without a clock and with one, the predicted past
without a forecast, another threshold; without a model the hours and
what was predicted still show and the card says why; without a capacity
no capacity line; a care center nobody was admitted to; and the care
center view opened from home shows the card under the capacity and above
the people, asking for its id.

## Known limitations

- The forecast needs datyx to have trained a DeepAR model of
  `occupancy_hourly`'s `default` group, which datyx's development
  catalogue tags and retrains every 15 minutes (106 s a run on the
  development machine; a fresh datyx trains the other groups first,
  about 6 minutes in all); until then the card shows only the hours.
- What was predicted of the past hours is kept only while someone
  signed in watches (the events panel's polls set the alarms' checks
  off, and the card asks for its own forecast): hours nobody watched have
  no prediction. A restarted API keeps what it kept, by run.
- The series end at the run's latest arrival, the clock runs on: the now
  line can stand past the last hour observed by up to an hour or so.
- Occupancy is counted from the stays the conditions say, not from the
  moves: it can exceed the capacity, which the simulation doesn't
  enforce.
- The series are the run's: when the API restarts, a new run starts
  from day 1 and its hours from nothing.
