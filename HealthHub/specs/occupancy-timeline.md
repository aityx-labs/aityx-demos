# A care center's occupancy per hour

The time series of the [care center view](care-center.md): how many
people were in care at the care center in each simulated hour up to now
([Occupancy per hour](occupancy-hourly.md)), and how many datyx's DeepAR
model expects in each of the next 24. App in
[occupancy_timeline.dart](../healthhub_app/lib/care_centers/occupancy_timeline.dart),
API in [routes.dart](../healthhub_api/lib/routes.dart),
[db.dart](../healthhub_api/lib/db.dart) and
[server.dart](../healthhub_api/bin/server.dart).

## The card

**Occupancy per hour** (`OccupancyTimelineCard`), in the care center
view under the map and the capacity, as wide as the view:

- **The past, solid**: the people in care in each of the last 72
  simulated hours of the run going on (three simulated days), an hour
  with nobody a zero, as a solid orange line with a solid point per hour.
  "Now" is the run's latest arrival at any care center, where its series
  end, as datyx reads them.
- **The future, dashed and transparent**: datyx's DeepAR forecast of
  the next 24 hours from that hour: its mean, a dashed, lighter line
  starting from the last hour, with a hollow, translucent point per hour,
  in a faint band from the 10th to the 90th percentile of its sample
  paths. A faint dashed line marks where the past ends and the forecast
  begins.
- **The capacity**: the care center's places in the simulation, a faint
  dotted line labelled "8 beds" (none when the view doesn't know it).
- The axes: whole people on y, from 0 to a whole number above the
  highest hour, 90th percentile or the capacity; on x each simulated
  midnight as its date ("Jun 3"), and noon when there is room. The
  points get smaller when the hours are close together.
- Hovering an hour, or touching it, shows its numbers: "Jun 3, 2026 09:00 ·
  3 in care of 8 beds", or for a forecast hour the mean and the 80%
  range.
- Above the chart, where the series end as a simulated date and time,
  never the run's id ("Now · Jan 19, 2026 12:00", or "Ended …" for a
  past run), and a line: how many
  are in care at the latest hour and the most in the hours shown, of the
  capacity; then what datyx expects on average over the next 24 and at
  most, and from which training run, or why there is no forecast (datyx's
  own words: no model of the group trained yet, not signed in, datyx not
  answering). The hours show either way.
- Under it, the key: "In care", "DeepAR forecast (mean; the band, 10th to
  90th percentile)" when there is one, and "Capacity, 8 beds".

Both are asked for together when the view opens and every 10 seconds
(a simulated hour is a real second, so each read moves the series about
ten hours); a failed read keeps what is shown. A care center nobody was
ever admitted to says so instead of a chart. The view gets the card's
two calls from home through `CareCenterOpener`, as it gets its own.

## The API

A care center has two series per hour (`CareCenterSeries`), each with
its two endpoints, open the same way:

- `GET /api/care-centers/{id}/occupancy?run=&hours=72`: the people in
  care there per hour from `occupancy_hourly`, of the run going on (or
  `run`; in prod, the newest run with an admission there): `{"hospitalId",
  "run", "current", "end", "hours": [{"hour", "occupancy"}]}`, the
  `hours` hours up to `end` (at most 720), oldest first, the hours as
  `YYYY-MM-DDTHH:MM` in simulated time (day 1 is 2026-01-01), an hour
  without a row a zero. `end` is the run's latest hour. Open to everyone,
  like the care centers; 400 for hours that aren't a positive number, 503
  without the database.
- `GET /api/care-centers/{id}/occupancy/forecast?run=`: datyx's
  inference of the care center's series of `occupancy_hourly` (group
  `default`, key `run_id` and `hospital_id`), asked with the user's own
  token from their datyx source for HealthHub's database, as the person
  view's prediction is (both through `_inference`): datyx's answer with
  `forecast`, its steps from the series' end, each `{"at", "mean", "p10",
  "p50", "p90"}`, empty when datyx can't say. datyx's own error when it
  refuses (404 while no model of the group is trained), 404 without a
  source or admissions, 502 when datyx doesn't answer, 401 without a user
  once sign-in is on.
- `GET /api/care-centers/{id}/admissions?run=&hours=72` and
  `.../admissions/forecast?run=`: the same for its admissions per hour,
  from `admissions_hourly` ([Admissions per hour](admissions-hourly.md)),
  each hour `{"hour", "admissions", "acute", "chronic"}`, `end` the run's
  latest counted hour, and datyx's forecast of that table's `default`
  group. The card doesn't show them now.

## Tests

`routes_test.dart`: the paths of both series; every hour up to the run's
end, missing hours zero, 72 unless asked and at most 720, open to
everyone; hours that aren't a number; the forecast's steps from datyx's
answer, sign-in and datyx's errors. `occupancy_test.dart`, against the
live database, rolled back: each stay counted in every hour it covers,
up to the run's latest arrival. `widget_test.dart`: the card with the
hours solid and DeepAR's four hours after them, its status line, key
(with the capacity) and semantics, an hour and a forecast hour touched;
without a model the hours still show and the card says why; without a
capacity no capacity line; a care center nobody was admitted to; and the
care center view opened from home shows the card under the capacity and
above the people, asking for its id.

## Known limitations

- The forecast needs datyx to have trained a DeepAR model of
  `occupancy_hourly`'s `default` group, which datyx's development
  catalogue tags; until then the card shows only the hours.
- "Now" is the run's latest arrival, not the simulated clock: between
  arrivals the series stands still.
- Occupancy is counted from the stays the conditions say, not from the
  moves: it can exceed the capacity, which the simulation doesn't
  enforce.
- The series are the run's: when the API restarts, a new run starts
  from day 1 and its hours from nothing.
