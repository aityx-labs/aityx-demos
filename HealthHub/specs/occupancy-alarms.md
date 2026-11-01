# Occupancy alarms

A care center over its capacity is a bad thing to happen, so HealthHub
warns of it as early as it can: from datyx's DeepAR forecast of every
care center's occupancy per hour ([A care center's occupancy per
hour](occupancy-timeline.md)) against its capacity in the simulation
([The care center view](care-center.md)), the API keeps an alarm per
care center of the run going on, fires an event when one rises, falls
or clears, stores it and streams it on Kafka, and the events panel pins
the active ones at its top. API in
[occupancy_alarms.dart](../healthhub_api/lib/occupancy_alarms.dart),
[routes.dart](../healthhub_api/lib/routes.dart),
[db.dart](../healthhub_api/lib/db.dart) and
[server.dart](../healthhub_api/bin/server.dart).

## The levels

Each check reads datyx's forecast of every care center of the run going
on, step by step over its whole horizon (24 simulated hours from the
series' end), and compares it with the care center's capacity (its beds
or places, the same the care center view shows):

- **`expected`**: the forecast's mean is over the capacity (strictly
  greater) at some hour of the horizon.
- **`possible`**: else, its 90th percentile (`p90`) is over it at some
  hour: the early warning, as soon as one sample path in ten fills the
  care center.
- else none.

For the level, the alarm says the earliest hour over the capacity
(`overflowAt`, the mean's for `expected`, the p90's for `possible`), how
many simulated hours ahead of the series' end it is (`leadHours`, 1 for
the first forecast hour), and of the simulated clock at the check
(`leadFromNowHours`, to a tenth: the clock is past the series' end by
then, negative once the hour is past), the forecast's mean and p90 at
that hour, and the peak over the horizon (the hour with the highest mean
for `expected`, the highest p90 for `possible`, with its mean and p90).

## The checks

datyx needs a user's token, and the API keeps none: a check is set off
by a request that carries the caller's bearer token, `GET /api/events`
(the events panel asks every 5 seconds) or `GET /api/alarms`, at most
once every `HEALTHHUB_ALARM_EVERY_MS` (5000 by default; `0` turns the
alarms off; anything but a whole number from 0 stops the server), and
never while one is under way. The request isn't delayed: the check runs
in the background with that request's token for its datyx calls only,
and the next poll sees what it found. With sign-in on, a request without
a signed-in user sets off nothing; with sign-in off, no token is needed.
The checks run in dev mode only, once the simulation has started. While
the simulation is paused nothing moves, so there is no check once one has
read the run (one is made if none has, after a restart).

A check reads the run's care centers from the database (those with an
admission in it, by the run of the admission's event id, as
`occupancy_hourly` reads it, with their names, kinds and seed keys from
`care_centers`), then asks datyx for each by name, as the occupancy
forecast asks (`_inference`, with the caller's datyx source for
HealthHub's database): `POST /api/datasources/{id}/inference` with
`{"table": "public.occupancy_hourly", "group": "default", "algorithm":
"DeepAR", "series": [{"run_id": "<run>", "hospital_id": "<id>"}, ...]}`,
100 series a call at most (datyx's limit), so a run with 167 care
centers takes two calls. Named, a series ends where its run ends: datyx
without series would score only the series ending at the latest hour of
the whole table, an older run's while one ran longer than the run going
on, and answer the highest 100 only. A care center datyx answers no
forecast of (no rows yet, or left out) keeps its alarm, marked `stale`,
and is never cleared that way. When datyx refuses (no model of the group
yet: 404) or doesn't answer, the alarms stay as they were, the answer
says why (`note`), and they are `stale`; when a later call of a check
fails, the earlier calls' care centers are read and the rest kept.
datyx takes a few seconds a call (7 s for 33 care centers on the
development machine), a few simulated hours: the alarm is that much
later than the series' end, which is why the app counts the lead from
its own clock.

**One datyx source.** The alarms are everyone's, but each check is asked
with its caller's token, and `_inference` picks the caller's datyx
source whose database is named as HealthHub's. The first answer's source
(`sourceId`) is kept: a check whose answer comes from another source (a
user's own source of another database of that name, or a user who sees
a source of their own) is ignored and logged, so one user's datyx can't
change the alarms, the table and the topic everyone sees. Restarting the
API forgets it.

## The events

A care center's level changing fires an event:

- **`alarm`**: it rises, none to `possible`, none to `expected`,
  `possible` to `expected`.
- **`downgraded`**: `expected` to `possible`.
- **`cleared`**: back to none.

A rise is at once. A fall (a downgrade, or cleared) only once
`lowerAfter` checks in a row (3) read the care center lower, to the
highest level they read, with its numbers: DeepAR draws its 100 sample
paths again at every call, so a p90 at the capacity reads over it at one
check and not at the next, and an alarm would otherwise fire and clear
every 5 s. Meanwhile the alarm stays at its level. The same level again
fires nothing, whatever its numbers (they update the active alarm, and
reset the count). A new run starts with no alarms; the old run's are
dropped without an event.

Each event is stored in the table `occupancy_alarm`
([Database](database.md)) and published to the Kafka topic
`healthhub.alarms` (key: the care center's id as text, value: the
event), so the alarm is on the stream too. Both are queued and retried
every 3 s in the background until they succeed (a row the database
refuses is dropped and logged; at most 1000 wait each, the oldest
dropped beyond that): a failure never stops the API or the checks.

### An event

```json
{
  "kind": "alarm",
  "id": "1349d576-12-3",
  "run": "1349d576",
  "hospitalId": 12,
  "hospitalName": "Hospital del Mar",
  "careCenterKind": "hospital",
  "level": "expected",
  "previous": null,
  "overflowAt": "2026-06-03T16:00",
  "overflowDay": 154,
  "leadHours": 7,
  "leadFromNowHours": 6.8,
  "mean": 10.2,
  "p90": 12.4,
  "peak": {"at": "2026-06-03T18:00", "day": 154, "mean": 11.3, "p90": 13.0},
  "capacity": 8,
  "unit": "beds",
  "end": "2026-06-03T09:00",
  "horizonHours": 24,
  "trainingRun": 4,
  "now": {"day": 154, "simTime": "09:12", "date": "2026-06-03"},
  "raisedAt": "2026-11-01T14:03:05.120Z"
}
```

- `kind`: `alarm`, `downgraded` or `cleared`. `id`: the run, the care
  center and a counter of the API's, unique.
- `level`: the level now, `possible` or `expected`; null for `cleared`.
  `previous`: the level before, null for a new alarm.
- `overflowAt` (simulated, `YYYY-MM-DDTHH:MM`, day 1 being 2026-01-01,
  as the forecast's `at`), `overflowDay` (its day, from 1), `leadHours`
  (from the series' end), `leadFromNowHours` (from `now`), `mean`,
  `p90`: the earliest hour over the capacity for the level and the
  forecast there; all null for `cleared` (`leadFromNowHours` too without
  a clock). `leadFromNowHours` isn't stored in the table.
- `peak`: `{"at", "day", "mean", "p90"}` as above; null when the
  forecast has no step.
- `capacity`, `unit` (`beds` or `places`): the care center's.
- `end`: the series' end (the run's latest hour, where the forecast
  starts from); `horizonHours`: the forecast's steps; `trainingRun`:
  datyx's training run that answered.
- `now`: the simulated clock at the check (the newest move's day and
  time, and the day as a date); null before the first move.
- `raisedAt`: when the check found it, real time, ISO 8601 UTC.

An **active alarm** is the same object without `kind` and `id`, for the
level it has now, its numbers from the latest check, with `since` (the
`raisedAt` of the event that gave it its level, whose `previous` it
keeps), `checkedAt` (the latest check's real time) and `stale` (true when
the latest check that got a forecast had none of it, or the whole answer
is `stale`).

### On Kafka

Topic `healthhub.alarms`, one record per event: `{"key": "12",
"value": <the event above>}`. The `kafka` service's health check makes
the topic with the others ([Development
environment](dev-environment.md)).

## The API

`GET /api/alarms?limit=20`, for a signed-in user once sign-in is on (401
otherwise), as the forecast route is: it is datyx's forecast, and its
`note` is datyx's words to whoever's check it was:

```json
{
  "enabled": true,
  "paused": false,
  "everyMs": 5000,
  "now": {"day": 154, "simTime": "09:12", "date": "2026-06-03"},
  "checkedAt": "2026-11-01T14:03:05.120Z",
  "status": 200,
  "note": null,
  "stale": false,
  "trainingRun": 4,
  "active": [ <active alarm>, ... ],
  "recent": [ <event>, ... ]
}
```

- `enabled`: dev mode with `HEALTHHUB_ALARM_EVERY_MS` above 0. In prod,
  or with the alarms off, `enabled` false, `checkedAt`, `status`, `note`,
  `trainingRun` null and both lists empty (`now` is still the clock in
  dev mode).
- `now`: the simulated clock, the newest move's (as `/api/people`'s
  `simTime` and `day`), with the day as a date; null before the first
  move and in prod.
- `checkedAt`: the latest check that got datyx's answer (real time);
  null before the first. `status`: datyx's status at the latest check
  (200, or its refusal, such as 404 with no model trained; 502 when it
  didn't answer); `note`: why there is no forecast then (datyx's own
  words), null when there is one. `stale`: the active alarms may be out
  of date: the latest check got no forecast, or no check got one for
  four intervals (30 s at least).
- `active`: the care centers with a level now, `expected` first, then
  `possible`, each the soonest overflow (`overflowAt`) first.
- `recent`: the latest events, newest first, `limit` of them (20 unless
  asked, at most 100; 400 when `limit` isn't a positive number). The API
  keeps the latest 100 of its own in memory (the table keeps all).

`GET /api/events` (both reads of the events panel) carries the same, so
the panel needs no other poll:

- `"now"`: the simulated clock, as above (null in prod and before the
  first move).
- `"alarms"`: `{"enabled", "checkedAt", "status", "note", "stale",
  "active": [...], "recent": [...]}`, as `/api/alarms` has them, `recent`
  the 10 latest events. The events are open to everyone; with sign-in on
  and nobody signed in, `alarms` says only `enabled`, with `"signIn":
  true`, nulls and empty lists.

`GET /api/people` keeps its `simTime` and `day` (the newest move's):
the day's date is 2026-01-01 plus the day less one.

## The app

The events panel ([stream_events.dart](../healthhub_app/lib/events/stream_events.dart))
reads the alarms from the events it already asks for every 5 seconds
(`alarms` and `now` of `GET /api/events`, the later of its two reads'
alarms): no other poll; it doesn't call `GET /api/alarms`. The client
([health_hub_api.dart](../healthhub_app/lib/api/health_hub_api.dart),
`OccupancyAlarms`, `OccupancyAlarm`, `SimNow`) reads them leniently: an
entry without a care center is left out, an active alarm without a level
too; an active alarm (no `kind`) reads as an alarm; `peak` is its `at`,
`mean` and `p90`; `kind` is the event's when it is `alarm`, `downgraded`
or `cleared`.

- **Pinned at its top**, a banner per active alarm, in the API's order,
  whatever the conditions chosen: **expected** in red with
  `Icons.crisis_alert`, "Over capacity expected at Hospital del Mar in
  7 h" and "Day 154, 16:00: 10 in care of 8 beds (90% range up to
  12.4) · peak 11.3 at Day 154, 18:00 (90% range up to 13)"; **possible**
  in amber with `Icons.warning_amber`, "Over capacity possible: Clínica
  X may exceed its 3 places in 3 h" and "Day 154, 12:00: 2.4 expected in
  care of 3 places, 90% range up to 3.6"; a 2 px border and a glow in
  the colour; the care center a link to its view. Numbers within 0.05 of
  a whole one are whole. The lead is from the panel's clock (the events'
  `now`, the time on top of the panel), not from the check, which is
  hours behind it by then: `overflowAt` less the clock, "in 6 h 20 min",
  and "now, since Day 154, 16:00" once the clock is past it; `leadHours`
  only without a clock. When the alarm may be out of date (the answer's
  `stale`, or its own), a line in amber, "Not current: last checked Day
  154 · Wed 3 Jun 2026, 09:00" (its `now`).
- **The header** has a red badge, "2 alarms", while any is active.
- **The rows**: the latest 6 alarm events among the stream's records by
  the check's simulated time (an alarm first in its minute), of the
  rows' shape: raised in red, downgraded in amber, cleared in green
  ("Cleared: no longer over capacity", "datyx's forecast stays within 8
  beds"), the care center a link; their lead is from the check's own
  `now`, the time the row shows.
- **datyx can't forecast** (`note`, alarms enabled, none active): one
  muted line says why. With alarms active and the answer `stale` or a
  `note`, a line in amber under the banners: "Occupancy alarms may be
  out of date · last checked Day 154, 09:00 · the datyx API is not
  answering" (the newest `now` of the active ones, and the note).
- **The clock**, "Day 154 · Wed 3 Jun 2026, 16:00" with **Paused**, on
  top of the panel and of the map's tile, and under the index's welcome:
  [Home](home.md#the-simulated-clock).

Tests in [widget_test.dart](../healthhub_app/test/widget_test.dart)
(group "occupancy alarms and the simulated clock"): the answer read (the
clock with and without `now` or a date, the alarms' fields, entries left
out); the banners' text, icon and colour for expected and possible, and
their place above the rows; the lead from the panel's clock, and "now,
since" once past; the stale marks (the answer's, and one alarm's alone)
and the out-of-date line with datyx's note; the link to the care center
view; the rows raised, downgraded and cleared in their colours, their
height and order, and the condition filter; no alarm, no banner nor
badge, and datyx's note; the clock on the map tile and the events, with Paused; the index's
clock; nothing before the simulation's time; `SimClock`'s newest reading
and a new run.

## Tests

`occupancy_alarms_test.dart`: the level (the mean against the p90,
strictly over, the earliest hour, the lead hours, the peak; no forecast,
none); the events (a rise, an escalation, a downgrade, a clear, nothing
when the level stays, only the run going on, a new run's reset); the
care centers asked for by name, 100 a call (167: 100 and 67), as an
older, longer run would hide them otherwise; one left out kept and
stale, cleared only by a forecast within the capacity; a p90 flapping at
the capacity one alarm, cleared after three checks lower, expected
falling to the highest of them; no check while paused once read; an
answer from another datyx source ignored; stale after a while or a
failure; the throttle (one check per interval, none while one is under
way, the request not waiting); the token used for its calls only and not
kept; the answer's order; the Kafka record. `routes_test.dart`:
`/api/alarms` (limit, prod, off, 401 without a user once sign-in is on)
and `/api/events`' `now` and `alarms` (nothing of the forecast without
a user once sign-in is on).
`occupancy_alarm_db_test.dart`, against a scratch database when
`HEALTHHUB_DB_*` reaches one: the row stored once by its id, the values
as parameters.

## Known limitations

- The checks need someone polling with a token (a signed-in user on
  home, once sign-in is on): with nobody watching, no alarm fires, and
  those up go `stale`.
- The forecast is of the run's series end, which is its latest arrival,
  and datyx takes seconds to answer for all care centers, so an alarm
  comes a few simulated hours after the hour it is checked from (the app
  counts the lead from its clock, so it says so).
- A fall waits three checks (15 s, about 15 simulated hours): a cleared
  alarm stays up that long.
- The datyx source is the first that answered since the API started:
  checks set off by a user whose datyx sees another source are ignored,
  and if that source is replaced, a restart is needed.
- The capacity is the simulation's, which the simulation doesn't
  enforce: people are admitted over it.
- The recent events are kept in memory: a restart starts a new run with
  none, though the table keeps every run's.
