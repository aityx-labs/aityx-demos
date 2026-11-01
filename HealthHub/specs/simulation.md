# Simulation

In dev mode (`HEALTHHUB_MODE=dev`, the default) the API simulates people
going for care with their complaints, so that HealthHub has patients to
route. Each person lives in one of the cities HealthHub covers and may
have a chronic condition and, now and then, an acute one ([Medical
conditions](conditions.md)); they stay home until one of them calls for
a visit, travel to the care center nearest home of the kind the visit
needs (a health station, urgent care, a mental health or dialysis
clinic, a general hospital), say what is wrong at the desk, stay, and
travel back. Every move and every arrival goes
through Kafka, and the app shows what comes back out of it. The code is
[lib/simulation.dart](../healthhub_api/lib/simulation.dart) and
[lib/people_profiles.dart](../healthhub_api/lib/people_profiles.dart);
in prod mode none of it runs.

## People

At start, once the database migration succeeded, the API reads every care
center with a location ([Care centers](care-centers.md)) and makes
`HEALTHHUB_SIM_PEOPLE` people (80, at most 200) for each city that has
one: Cornudella de Montsant, Reus, Barcelona, Miami, Fort Lauderdale, Rio
de Janeiro and São Paulo. A person's id is the city as a slug and a
number from 1 (`sao-paulo-3`, `cornudella-de-montsant-1`).

The people a city can change while the simulation runs
(`POST /api/simulation/people`, `{"perCity": n}`, 1 to 200, for anyone
signed in, from home's events; [Home](home.md)). More: each city's
newcomers join at the turn now, made as at the start (a home, a profile,
their conditions), their chronic condition's first visit and their first
acute episode counted from that moment, so nobody arrives with visits
overdue. Fewer: each city's last to join leave, their loop ending at its
next turn, off the map at once. A number is never given twice in a run,
so a newcomer is never someone who left (`reus-81` after `reus-80`
left, not `reus-80` again). The change lasts until the API restarts,
which starts again from `HEALTHHUB_SIM_PEOPLE`.

- **Home**: a random point within 1.5 km of a random care center of the
  city, uniform over the disc, so homes fall in the city and, since care
  centers are on land, mostly on land. It is the starting position.
- **Care centers**: for each setting a visit can need
  ([conditions.md](conditions.md#where-visits-go)), the care center
  nearest the home that serves it, among all of them, not only the
  city's:
  - `hospital`: a general hospital (below);
  - `primary`: a health station (a CAP, a UBS, a community health
    center);
  - `urgent_care`: a clinic of urgent care without beds (a subtype
    naming CUAP, UPA, pronto atendimento, pronto socorro geral, urgent
    care or walk-in) or a general hospital's emergency department,
    whichever is nearer;
  - `mental_health`: an adult community mental health clinic (CSMA, a
    centre de salut mental, a community mental health center, a CAPS I,
    II or III; not those for children, or for alcohol and drugs) or a
    health station, whichever is nearer;
  - `dialysis`: a dialysis center (Florida's end-stage renal disease
    centers; the Catalan and Brazilian registries list none apart) or a
    general hospital, whichever is nearer.

  A setting nothing serves goes to the hospital. The other clinics
  (specialty, dental, rehabilitation, ambulatory surgery, day hospitals,
  addiction) get nobody: their subtypes don't say what for.
- **Hospital**: the general hospital nearest the home, among all the
  care centers of kind `hospital`, not only the city's: Cornudella de
  Montsant has none, so its people go to one in or near Reus. A hospital
  specialised in a kind of patient or care is skipped, since it doesn't
  take a pneumonia or a fracture: by its `subtype` (Brazil's `HOSPITAL
  ESPECIALIZADO` of any specialty, Spain's `Hospitales especializados`,
  `Hospitales de salud mental y tratamiento de toxicomanías` and
  `Hospitales de media y larga estancia`, a US psychiatric hospital) or
  by its name where the subtype says only `Hospital` or `HOSPITAL GERAL`
  (children's, infantil, criança, pediatria, maternidade but not
  "Hospital e Maternidade", psychiatric, behavioral, mental health,
  rehabilitation, sociosanitari, the long-term acute care Kindred and
  Select Specialty, Douglas Gardens' long-term care, transition and
  geriatric hospitals, eye, cancer (Miami's Sylvester), infectious
  disease, dermatology and rheumatology hospitals). So is a hospital
  that only takes one group of people: the VA's (veterans), military,
  navy, air force, police and fire brigade hospitals, prison hospitals
  (SEAP) and the state servants' hospital. Only with no general hospital
  at all would the nearest of any kind do.
- **Name**: typical of the city, from lists in the code with 60 first
  names (by sex) and over 40 surnames each: Catalan and Spanish for
  Cornudella de Montsant, Reus and Barcelona, with two surnames (`Núria
  Puig Soler`); American for Miami and Fort Lauderdale (`James Rivera`);
  Brazilian Portuguese for Rio de Janeiro and São Paulo, with one or two
  surnames (`Ana Souza Lima`).
- **Age**: 18 to 90, by the adult population's shape: 19% 18 to 29, 26%
  30 to 44, 33% 45 to 64, 17% 65 to 79 and 5% 80 to 90. Ages don't
  advance.
- **Sex**: `man` or `woman`, even, but 62% women from 80, as women
  outlive men.
- **Occupation**: one of 40 jobs (`teacher`, `bus driver`, `software
  developer`...), each starting with a consonant sound because the
  templates say "a {occupation}"; often `university student` up to 24;
  `retired <job>` from 67, and sometimes from 63.
- **Conditions**: a chronic condition for 60% of people, drawn by
  prevalence, weighed by sex, among the chronic conditions for their age,
  kept for life; and acute episodes, drawn the same way among the acute
  ones, from time to time ([Visits](#visits)).
- **Pregnant**: 7% of women aged 18 to 44 (`pregnantShare`), for the
  whole run, as ages don't advance.
- **Monitored at home**: the high-risk only, so most people aren't
  (`Person.monitoredFor`, which says why): everyone 80 or over
  (`"aged 84"`), the pregnant (`"pregnant"`), and those whose chronic
  condition is mental illness (major depressive disorder, Alzheimer's
  disease) or a failing heart or kidneys (heart failure, end-stage kidney
  disease), by the condition's name. With the seed's conditions, about
  one person in ten: half of them for their age, a third for depression.
  Their moves say so (`monitored`, `monitoredFor`), and the events mark
  them; like everyone's, only their changes of state are events
  ([The stream](#the-stream)), and everyone is on the map either way.
- **Travel mode**: by the straight-line distance from home to the care
  center of the trip, chosen again at every departure, at a door-to-door
  speed that includes waiting and getting to
  the stop or the car: on foot (`walk`) up to 2 km at 5 km/h, city
  transport (`transit`) up to 15 km at 20 km/h, and by car (`car`)
  beyond, at 50 km/h. Each turn a traveller moves at most that speed
  times the turn's simulated time, in a straight line, stopping exactly
  at the destination. With the default quarter of an hour a turn, a
  walk of up to 1.25 km, a city trip of up to 5 km or a drive of up to
  12.5 km ends in the turn it starts, and longer ones take several:
  Cornudella de Montsant to Reus, about 20 km by car, two turns; a 2 km
  walk two, a 15 km city trip three. The map shows them on the way. The arrival is timed to
  the minute: the departure plus the distance at that speed (a 1 km walk
  that leaves at 09:00 arrives at 09:13).

## Turns and the clock

The simulated clock starts at 06:00 on day 1 and advances
`HEALTHHUB_SIM_MINUTES_PER_TURN` minutes (15) every turn, a turn every
`HEALTHHUB_SIM_TURN_MS` real milliseconds (2500): a simulated hour every
10 real seconds, a simulated day 4 minutes, a simulated month about 2
hours ([The pace](#pace) says why). Each turn every person does one
thing, in the state `home`, `to_hospital`, `at_hospital` or `to_home`:

- **home**: nothing, until a visit is due; then they leave at the
  turn's time, and travel in the same turn.
- **to_hospital**: one step towards the hospital. Arriving is an
  admission (below), at the minute of arrival, and the state becomes
  `at_hospital` in the turn they arrive.
- **at_hospital**: they stay the visit's hours from the minute they
  arrived (`stay_hours` for a first visit, `follow_up_stay_hours` after),
  then leave at the first turn after.
- **to_home**: one step towards home. Arriving home schedules the next
  visit.

Each person is its own async loop, Dart's equivalent of a virtual thread:
one task per person, waiting on its own timer, not one loop that moves
everyone. The loops agree on the clock because each derives its turn from
the time since the simulation started; a loop that overran a turn (a slow
publish) skips to the current one instead of falling behind.

## Pace

A simulated hour takes 10 real seconds by default (a turn of 15
simulated minutes every 2.5 s), so that datyx's forecasts stay
meaningful for the live run: the [occupancy alarms](occupancy-alarms.md)
warn before a care center fills, and the [care center
view](occupancy-timeline.md) keeps what was predicted of each hour
before it came. Measured on the development machine (datyx's
`training_run` and `inference_call`, 2026-11-01):

| | Real time | At 1 s an hour (before) | At 10 s an hour (now) |
| --- | --- | --- | --- |
| datyx's DeepAR inference, 33 care centers | about 7 s a call (two calls past 100 care centers) | 7 simulated hours | 0.7 h |
| The alarms' check interval | 5 s at least, a check at a time | 5 h | half an hour |
| A forecast's horizon, 24 h | | 24 s of warning | 4 minutes |
| A DeepAR training of `occupancy_hourly` | 106 s (`admissions_hourly`'s first, 182 s) | 106 h | 11 h |
| datyx's retraining of it (`15min`) | 15 minutes | 900 h | 90 h, almost 4 days |
| The care center card's refresh | 10 s | 10 h | 1 h |

At a second an hour a forecast arrived 7 simulated hours after the hour
it started from, a third of its horizon gone, and the alarms' checks
kept one forecast in every five or more hours: what was predicted of an
hour was mostly made many hours before it. At 10 s an hour the
forecast comes within the hour, a check reads every care center about
once a simulated hour, so the prediction kept of each hour is the one
made an hour before it, and an alarm warns up to 4 real minutes ahead.
datyx retrains the occupancy model every 15 minutes
([datyx's curation](../../datyx/specs/curation.md), its development
document), 90 simulated hours of the run's new data each time, and
the model reads the run's latest 48 hours at every forecast anyway.
The quarter-hour turns also move people on the map four times a
simulated hour, with fewer records a real second than before (one turn
every 2.5 s, not every second).

Both stay settings: `HEALTHHUB_SIM_TURN_MS=1000` and
`HEALTHHUB_SIM_MINUTES_PER_TURN=60` run it at the old pace (an `.env`
copied from an older `.env.example` has them: remove them for the new
one).

## The calendar

Simulated time is a calendar that starts on 2026-01-01 at 00:00 (day 1)
and runs from there, a simulated hour every 10 real seconds with the
defaults: a run's day 4 at 09:09 is 2026-01-04 09:09, its day 554
2027-07-08. Every record carries its `day` and `simTime` and the same
moment as `at`, ISO 8601 without a zone (`simAt`); the admissions table
keeps it as `admitted_at` ([Database](database.md)), and the series
(`admissions_hourly`, `patient_days`, `occupancy_hourly`) are dated on
it. The app shows every simulated time as a date, "Jan 4, 2026 09:09",
never as a day number. Each run starts the calendar again from
2026-01-01.

## Pausing

`POST /api/simulation/pause` freezes the simulation and `POST
/api/simulation/resume` lets it go on ([API](api.md)), for anyone signed
in (anyone at all while authentication is off). Paused, the clock that
the turns are counted on stops, and every person's loop waits before its
next turn: nobody moves, nobody is admitted, nothing is published, and
the simulated time and day stand still (a publish already under way when
the pause comes still lands). Resumed, the turns go on from the one they
stood at, with none skipped for the time spent paused. The admissions
already published go on being recorded and triaged, and the map and the
events keep showing the last moves. Pausing a paused simulation, or
resuming a running one, changes nothing. The API logs each pause and
resume with the run and the turn.

There is one simulation, in the API's process, so a pause is everyone's:
every app watching sees it stand still, and anyone can resume it.
`/api/health` and `GET /api/events` say `"paused"`. It is dev mode only:
in prod, and before the simulation has started, both calls answer 409.
Restarting the API starts a new run, not paused. `Simulation.stop` ends
the loops of a paused simulation too.

## The flow at a care center

Anyone signed in (anyone while authentication is off) can double or
halve the flow of people to a care center, from its view ([The care
center view](care-center.md#the-flow)): `POST
/api/care-centers/{id}/flow` with `{"action": "double"}`, `"halve"` or
`"reset"` ([API](api.md)). Each care center has a flow factor for the
run, 1 (the normal flow) unless changed, doubled or halved at each press
from 1/8 to 8 (`flowMin`, `flowMax`; a press past them leaves it there),
and set back to 1 by a reset. The factor scales the arrivals there: the
visits headed to that care center come that many times as often, made
by the same people (nobody joins, nobody is sent elsewhere), so its
admissions per hour are about the factor times what they would have
been, and the other care centers keep about theirs. How, by the kind of
visit (`Simulation.changeFlow`, `retime`, `Person.acuteRate`):

- **Chronic visits** come at intervals: the wait before a visit whose
  care center has factor f (the interval after the last visit, or a
  course's gap), counted from when the person is home again, is divided
  by f, and the visit is put at a daytime slot (`visitSlotFrom`): the
  next hour from 08:00 to 17:00 that day when it falls between them,
  else a random one of those hours, that day before 08:00, the next day
  after 17:00. Twice as often at ×2, half as often at ×1/2.
- **Acute episodes** start as a Poisson process (a gap with a mean of 90
  days), the condition, and with it the care center of the first visit,
  drawn at the onset. Under the factors a person's onsets come at F times
  the rate, F the highest factor among the care centers their visits may
  go to (their hospital and the nearest of each setting), and an episode
  whose first visit goes to a care center of factor f is kept with
  probability f / F; one not kept starts nothing, and the next gap
  begins. That is Poisson thinning: the episodes that start at each care
  center come at its factor times their normal rate, exactly, and those
  of the others as before. An episode's visits after the first are as
  usual.
- **The hours** don't change: an emergency is made at once, at any hour,
  and a planned visit in the daytime, so the daily profile of the
  admissions there stays the same, only taller or flatter.

A press shows at once, not only after the visits already planned: the
people whose next chronic visit goes to that care center have it brought
forward or put off, the time left until it times the old factor over the
new (at a daytime slot; an emergency's time as it comes), and those whose
F changed have their next acute onset drawn again from now at the new
rate (the gaps are exponential, so drawing again from now is the same
process). A visit under way is left as it is. Newcomers
([People](#people)) join under the factors as they are. At the normal
flow nothing changes, not even the random draws, so a run nobody touched
is the run it was. The API logs every change, with the care center, the
factor and the one before, the run, the turn and how many people were
retimed (`simulation: flow at care center 13 (CAP Llibertat) ×2, was
×1, run 3f9c0a7e at turn 412, 96 people retimed`). The factors are the
run's: a new run (an API restart) starts at the normal flow everywhere.
`GET /api/care-centers/{id}` says the care center's factor (`flow`).

How close to the factor, in a seeded run of 400 people of Reus over 120
days (`test/flow_test.dart`), whose primary care and mental health visits
go to a health station and the rest to a hospital, the factor set from
the start: at the hospital, ×2 made 1.75 times its admissions, ×1/2 0.48
and ×8 6.6; at the health station, ×2 1.94 and ×1/2 0.62. Short of the
factor because an acute episode that started elsewhere still has its
follow-ups there as before (a pneumonia admitted at the hospital and
checked at the health station), and a planned visit keeps to the
daytime, so one due every day or two (dialysis) comes at most about once
a day whatever the factor. The other care center kept about its own,
but the follow-ups move with the episodes (the health station had 12%
more with the hospital at ×2, 50% more at ×8), and a person has one
acute episode at a time, so more of them at one care center leaves a
little less time for the others' (the hospital had a fifth fewer with
the health station at ×2).

## Visits

A condition's visits come in courses of `count` visits, `interval_days`
apart ([Medical conditions](conditions.md#visits)). A planned visit
starts on the hour, at a random hour from 08:00 to 17:00; the first visit
of an `urgent` condition (appendicitis, renal colic, a fracture, a
laceration, pneumonia) is made as soon as it starts, at any hour of day
or night. A person has two processes of visits, apart:

- **Chronic**: 60% of people have one chronic condition, for life. Its
  first visit falls within the first 10 simulated days, then one every
  `interval_days` until `count`; after the last, the next course begins
  `course_gap_days` later (30 to 120 days when the condition doesn't
  say; 0, end-stage kidney disease, is continuous dialysis, every
  `interval_days` on). Only the condition's very first visit is `first`;
  the later courses' visits are `repeat`, each course's last `last`, and
  the visit number and the days since the first visit go on counting
  across courses.
- **Acute**: episodes start at random, a gap after the start or after
  the last episode ended that is exponential with a mean of 90 days (at
  least a day), so they come about every three months, as a Poisson
  process. Each draws an acute condition by prevalence, weighed by sex,
  for the person's age; its visits are one course, `first`, `repeat`
  and `last`, and when it ends the next gap begins. Someone without a
  chronic condition is healthy (no condition) between episodes.

The two interleave, one visit at a time: a visit that falls due while
the person is out on another (an episode that starts during a chronic
check-up) waits until they are home, then goes at the next daytime slot,
or at once for an emergency. When both are due at once, the earlier due
goes first.

## Admissions

On arrival at the hospital the person says what is wrong: a template of
the condition for the visit's kind, chosen at random among its three,
with its placeholders replaced by the person's details
([conditions.md](conditions.md#complaint-templates)); `template` says
which (0 to 2), so the complaint's reference triage level is known
([Triage at the desk](triage.md)). A consumer reads an admission without
it, from before, as valid. The arrival is an
admission, published once to the Kafka topic `healthhub.admissions`,
keyed by the person's id:

```json
{"type": "admission", "eventId": "3f9c0a7e-reus-3-d4-t75", "personId": "reus-3",
 "name": "Núria Puig Soler", "age": 54, "sex": "woman",
 "occupation": "teacher", "city": "Reus",
 "conditionCode": "influenza", "conditionName": "Influenza",
 "conditionType": "acute", "visit": "first", "visitNumber": 1,
 "complaint": "Hi, I'm Núria Puig Soler, 54...", "template": 0,
 "hospitalId": 13, "hospitalName": "CAP Llibertat", "careCenterKind": "health_station",
 "simTime": "09:09", "day": 4, "at": "2026-01-04T09:09", "turn": 75}
```

`simTime` is the minute of arrival: Núria left home at 09:00, the start
of turn 75, and walked 750 m in 9 minutes. `at` is the same moment as a
date and time on the simulation's calendar ([The calendar](#the-calendar)). `eventId` is the run's id
(random hex, new at every start of the simulation), the person's id, the
day and the turn: the people's ids and the turns repeat from run to run,
and the run id keeps every event id unique. An admission that fails to
publish is kept and tried again the next turn (up to 20 per person;
beyond that the oldest is dropped, and logged).

## The stream

Every turn each person also publishes one record to the Kafka topic
`healthhub.people.moves` through the REST proxy ([API](api.md#kafka)),
keyed by the person's id, valued:

```json
{"id": "reus-3", "name": "Núria Puig Soler", "age": 54, "city": "Reus",
 "lat": 41.1554, "lon": 1.1076, "homeLat": 41.1621, "homeLon": 1.1081,
 "hospitalId": 13, "hospitalName": "CAP Llibertat", "careCenterKind": "health_station",
 "state": "at_hospital", "mode": "walk", "monitored": false, "monitoredFor": null, "conditionName": "Influenza",
 "conditionType": "acute", "simTime": "09:00", "day": 4, "at": "2026-01-04T09:00", "turn": 75}
```

The move of the turn of the admission above: `simTime` is the turn's,
and Núria is already at the health station, as she arrived within the
turn (the state says `at_hospital` for a care center of any kind).
`hospitalId`, `hospitalName` and `careCenterKind` (`hospital`, `clinic`
or `health_station`) are the care center of the visit under way; at
home, the general hospital nearest home. `conditionName` and
`conditionType` are the condition of the visit under way; at home, the acute episode's if one is on, else the chronic
condition's; null while the person is healthy. A failed publish is logged at most once a minute per topic, for
all the people together, and the person carries on; when Kafka comes
back the records do too.

The API reads both topics back (`PeopleFeed`), each with its own
consumer and poll loop:

- the moves in a consumer group of its own, `healthhub-api-<random>`,
  new at every start, from the newest records on, so a restart never
  replays an old run on the map;
- the admissions in a stable group, `healthhub-api-admissions`, the
  same at every start, from the earliest record the topic keeps when the
  group has no committed offset yet, and from where it left off after
  (the proxy commits the offsets read), so no admission published while
  the API was restarting or down is lost. Replays are harmless: the
  database records each event id once, and the feed drops an event id
  among the latest 1,000 it kept.

Only this simulation's people are kept, and only records with every
field of the right type and range (integers within a Postgres `INT`, a
day and a visit number below sane bounds, no text with a NUL), so a
test's record, another API's people or a malformed record is skipped,
and one bad record can't break an answer, grow the memory or stall the
recorder.

- **Moves**: the feed keeps each person's latest move: what `GET
  /api/people` answers, with the time and day of the newest record. The
  map is fed from the stream, not from the simulation's memory. Moves are
  not stored in the database.
- **Admissions**: each valid admission is recorded in the database's
  `admissions` table ([Database](database.md)), by its event id, so a
  replay never doubles it: an admission already there is skipped, and
  logged. Recording is queued and written in the background, so the
  poll loop never waits on the database; a failed write is logged and
  retried every 3 s, in order, and the queue holds up to 10,000 (each
  dropped one is logged). One the database refuses as data (SQLSTATE
  class 22, a data exception, or 23, an integrity violation) would fail
  the same way forever: it is logged and dropped, and the rest go on.
  `GET /api/admissions` answers the latest from the table.
- **Events**: a move is an event only when it changes the person's state
  from their previous move (left home, arrived, going home, back home):
  everyone moves every turn, and every move would bury the admissions and
  the alarms. The first move read of someone (after the API starts, or
  they join) says no change. Everyone is on the map either way. The feed
  keeps the latest 100 of those moves and, apart, the latest 100
  admissions, each with its type, partition and offset, an admission
  with aityx's triage level (`triage`, "red" to "blue") once the triage
  is recorded ([Triage](triage.md); null until then, or when it failed):
  `GET /api/events` gives them as one stream, newest first by simulated
  time (day and time), the kinds among each other, a tie in the order
  they were read (within a topic, by offset), or one type with `?type=`;
  the events under home's map ([Home](home.md)). It also names the
  busiest care center now, the one with the most people in care (at it
  by their latest move; the lower id on a tie): `busiest`. The feed
  counts every valid move and
  admission it reads, those left out too (a replayed admission once), and
  how many a second over the last minute, a moving average of one count
  per second (over the time since the first, before a minute has gone
  by): `GET /api/events` says them as `total` and `perSecond`.

A failing consumer is closed and a new one made after 3 s. When the API
is stopped (SIGINT or SIGTERM: Ctrl-C, process-compose, a rebuild,
Docker) it stops the people, deletes the feed's two consumers on the
proxy,
gives the admissions still queued 5 s to be written (logging how many
are lost) and exits, so restarts don't leave consumers behind.
`Simulation.stop` ends every person's loop, even one asleep until its
next turn.

`/api/health` says `"simulation": true` once the people are moving
(paused or not), `"paused"` whether they are paused, and `"kafka"`
whether the proxy answered its last ping (every 5 s).

## Known limitations

- The simulation lives in the API's process: restarting the API starts a
  new one, with new people, from 06:00 on day 1, under a new run id. The
  admissions of earlier runs stay in the database. The last run's
  admissions the feed had not read yet are read at start, recorded under
  their own event ids and shown among the events, as the people's ids
  are the same.
- People travel in a straight line, through buildings and, near the
  coast, over water; homes near a seaside care center can fall in the
  sea. The speeds are door-to-door averages, with no traffic or timetable.
- Everyone goes to the nearest care center of the visit's setting and is
  admitted on arrival, whatever its queue or capacity; nothing routes
  them by load yet. A care center's flow factor changes how often its
  visits come, not where people go: halving it doesn't send anyone
  elsewhere, and doubling it doesn't bring anyone from elsewhere. The settings a care center serves, and the
  specialised hospitals, are told apart by keywords in their subtype and
  name, which a new data source may word differently. Only Florida lists
  dialysis centers; elsewhere dialysis is at the hospital.
- The triage at the desk names a hospital's areas (emergency,
  outpatients) whatever the care center: at a health station they stand
  for how soon and where in it.
- The moves, the admissions and their tables keep the names
  `hospitalId` and `hospitalName` (`hospital_id`, `hospital_name`) for
  the care center of any kind, so the Flink job and datyx's sources
  read them as before.
- A person has at most one chronic condition, and one acute episode at
  a time; ages don't advance.
- Two APIs in dev mode on the same Kafka publish the same person ids, and
  each one's map shows a mix of both; each also records the other's
  admissions, told apart by the run id in the event id. They also share
  the `healthhub-api-admissions` group, so each reads and records only
  the admissions of the partitions Kafka gives it.
- The topics keep records for 24 hours. Only the Flink job reads the
  admissions' history ([Admissions per hour](admissions-hourly.md)),
  from the earliest record each time it is submitted; nothing reads
  the moves'.
