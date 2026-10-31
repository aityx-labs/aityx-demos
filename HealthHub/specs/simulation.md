# Simulation

In dev mode (`HEALTHHUB_MODE=dev`, the default) the API simulates people
going to the hospital with their complaints, so that HealthHub has
patients to route. Each person lives in one of the cities HealthHub
covers and may have a chronic condition and, now and then, an acute
one ([Medical conditions](conditions.md)); they stay home until one of
them calls for a visit, travel to the general hospital nearest home, say
what is wrong at the desk, stay, and travel back. Every move and every arrival goes
through Kafka, and the app shows what comes back out of it. The code is
[lib/simulation.dart](../healthhub_api/lib/simulation.dart) and
[lib/people_profiles.dart](../healthhub_api/lib/people_profiles.dart);
in prod mode none of it runs.

## People

At start, once the database migration succeeded, the API reads every care
center with a location ([Care centers](care-centers.md)) and makes
`HEALTHHUB_SIM_PEOPLE` people (10) for each city that has one: Cornudella
de Montsant, Reus, Barcelona, Miami, Fort Lauderdale, Rio de Janeiro and
São Paulo. A person's id is the city as a slug and a number from 1
(`sao-paulo-3`, `cornudella-de-montsant-1`).

- **Home**: a random point within 1.5 km of a random care center of the
  city, uniform over the disc, so homes fall in the city and, since care
  centers are on land, mostly on land. It is the starting position.
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
- **Travel mode**: by the straight-line distance from home to the
  hospital, at a door-to-door speed that includes waiting and getting to
  the stop or the car: on foot (`walk`) up to 2 km at 5 km/h, city
  transport (`transit`) up to 15 km at 20 km/h, and by car (`car`)
  beyond, at 50 km/h. Each turn a traveller moves at most that speed
  times the turn's simulated time, in a straight line, stopping exactly
  at the destination. With an hour a turn, a walk or a city trip ends in
  the turn it starts; Cornudella de Montsant to Reus, about 20 km by car,
  too; with shorter turns the trips take several. The arrival is timed to
  the minute: the departure plus the distance at that speed (a 1 km walk
  that leaves at 09:00 arrives at 09:13).

## Turns and the clock

The simulated clock starts at 06:00 on day 1 and advances
`HEALTHHUB_SIM_MINUTES_PER_TURN` minutes (60) every turn, a turn every
`HEALTHHUB_SIM_TURN_MS` real milliseconds (1000): a real second is a
simulated hour, a simulated day 24 seconds, a simulated month about 12
minutes. Each turn every person does one thing, in the state `home`,
`to_hospital`, `at_hospital` or `to_home`:

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
([conditions.md](conditions.md#complaint-templates)). The arrival is an
admission, published once to the Kafka topic `healthhub.admissions`,
keyed by the person's id:

```json
{"type": "admission", "eventId": "3f9c0a7e-reus-3-d4-t75", "personId": "reus-3",
 "name": "Núria Puig Soler", "age": 54, "sex": "woman",
 "occupation": "teacher", "city": "Reus",
 "conditionCode": "influenza", "conditionName": "Influenza",
 "conditionType": "acute", "visit": "first", "visitNumber": 1,
 "complaint": "Hi, I'm Núria Puig Soler, 54...",
 "hospitalId": 42, "hospitalName": "Hospital Universitari de Sant Joan de Reus",
 "simTime": "09:09", "day": 4, "turn": 75}
```

`simTime` is the minute of arrival: Núria left home at 09:00, the start
of turn 75, and walked 750 m in 9 minutes. `eventId` is the run's id
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
 "hospitalId": 42, "hospitalName": "Hospital Universitari de Sant Joan de Reus",
 "state": "at_hospital", "mode": "walk", "conditionName": "Influenza",
 "conditionType": "acute", "simTime": "09:00", "day": 4, "turn": 75}
```

The move of the turn of the admission above: `simTime` is the turn's,
and Núria is already at the hospital, as she arrived within the turn.
`conditionName` and `conditionType` are the condition of the visit under
way; at home, the acute episode's if one is on, else the chronic
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
- **Events**: the feed keeps the latest 100 moves and, apart, the latest
  100 admissions, so the many moves never push the few admissions out,
  each with its type, partition and offset: `GET /api/events` merges
  them newest first by arrival (or one type with `?type=`), the events
  under home's map, where admissions are highlighted ([Home](home.md)).

A failing consumer is closed and a new one made after 3 s. When the API
is stopped (SIGINT or SIGTERM: Ctrl-C, process-compose, a rebuild,
Docker) it stops the people, deletes the feed's two consumers on the
proxy,
gives the admissions still queued 5 s to be written (logging how many
are lost) and exits, so restarts don't leave consumers behind.
`Simulation.stop` ends every person's loop, even one asleep until its
next turn.

`/api/health` says `"simulation": true` once the people are moving and
`"kafka"` whether the proxy answered its last ping (every 5 s).

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
- Everyone goes to the general hospital nearest home, whatever the
  condition, and is admitted on arrival; nothing routes them yet. The
  specialised hospitals are told apart by keywords in their subtype and
  name, which a new data source may word differently.
- A person has at most one chronic condition, and one acute episode at
  a time; ages don't advance.
- Two APIs in dev mode on the same Kafka publish the same person ids, and
  each one's map shows a mix of both; each also records the other's
  admissions, told apart by the run id in the event id. They also share
  the `healthhub-api-admissions` group, so each reads and records only
  the admissions of the partitions Kafka gives it.
- The topics keep records for 24 hours; nothing reads the history.
