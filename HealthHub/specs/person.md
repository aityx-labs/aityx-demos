# The person view

Every person HealthHub names on home is a link to their view: who they
are in the simulation, what they do now, datyx's prediction of their care
over the next 30 days, their admissions with aityx's triage, and their
days of care. App in
[person_screen.dart](../healthhub_app/lib/people/person_screen.dart), API
in [routes.dart](../healthhub_api/lib/routes.dart) and
[db.dart](../healthhub_api/lib/db.dart).

## Which person

A person's id (`reus-5`) comes back in every run of the simulation, a new
person each time: a new name, age, condition and history. So a view is of
one person of one **run** (the first part of every event id,
`df0837e4-reus-5-d141-t3369`):

- an admission (in the events or the triage) opens the person of its own
  run, which may be a past one;
- a move, or a person or home on the map, opens the person of the run
  going on now.

## Where the links are

On home only, where `PersonOpener` gives the view's two calls to
everything under it; the index (nobody signed in) names nobody as a link.

- **Latest events**: a move's person id; an admission's name and age.
  An admission also shows the prediction's hours, from the same call
  ([Home](home.md)).
- **Triage at the desk**: a row's name and age (the rest of the row still
  opens the triage), and the name in the triage's detail.
- **The map**: a person's dot and a home open the view on a click or a
  tap; their tooltip shows on hover or a long press, and ends "Click to
  open". On the index a tap shows the tooltip, as before.
- **The care center view** ([care-center.md](care-center.md)): the people
  there and on their way, and each admission's person.

The view's own hospitals are links to the [care center
view](care-center.md): each admission's, and the pill of what they do now
when they are going to or at the hospital.

A link is the name in its usual style, underlined on hover with a hand
cursor (`PersonLink`). The view is a page of its own, over home, with a
back button and a refresh.

## The view

`PersonScreen`, the window's full width (less a 16 px margin), in this order:

1. **Who**: the name large, then age, sex, occupation and city (sex and
   occupation come from an admission: a move doesn't carry them), the
   id and run, and "a past run" when it isn't the current one. Now, when
   it is: a pill in their state's colour (the map's) with the hospital
   when going to or at one, their condition, the simulated time, as a
   date ("Jan 4, 2026 09:00").
2. **Return in the next 30 days**, the highlighted card: an orange
   border and an orange wash, set apart from the plain cards around it.
   datyx's XGBoost prediction of the hours of hospital care the person
   will take over the next 30 days, large ("9.0 h of hospital care
   expected"), against the hours of the last 30 days, with an arrow up
   (amber), down (green) or flat; and which model said it: the group,
   the target and horizon, the training run, when it was trained, how
   long the call took. While it loads, a spinner; when datyx can't say,
   its words: no model trained yet, the person has no rows, datyx not
   answering. The rest of the view doesn't wait for it.
   Under it, **How this prediction is made** (`PredictionExplainer`):
   datyx's XGBoost model, trained on `patient_days`, builds for this
   person the features training built, from their own days up to now (the
   hours of care over the last day, 30, 90 and 360 days, the days since
   their last stay, how much history there is), and its trees add up to
   the hours of the next 30 days; what it knows is what followed similar
   histories in every other patient's days. And **why not Jev**: Jev reads
   text, and this number isn't in anything the person says; it comes from
   their history and everyone else's, rows of numbers Jev never sees.
3. **Counts**: admissions, acute and chronic, triaged by aityx, days of
   care, hours of care.
4. **Admissions**, newest first: the time and day, the condition and
   type, which visit and the hospital, aityx's triage (level and wait,
   area, in the level's colour, as on home; "Not triaged yet"; "Triage
   failed"), a nurse's check, and what they said, in italics.
5. **Days of care**: `patient_days`, the latest first, the series datyx
   predicts from: the date, the visits, acute and chronic, the hours.

## The API

- `GET /api/people/{id}?run=`: the person of `run`, else the current run
  (the simulation's), else the newest run with an admission of theirs:
  `{"id", "run", "current", "name", "age", "sex", "occupation", "city",
  "now": {"state", "mode", "lat", "lon", "homeLat", "homeLon",
  "hospitalName", "conditionName", "conditionType", "simTime", "day"} or
  null, "summary": {"admissions", "acute", "chronic", "triaged", "days",
  "stayHours"}, "admissions": [...], "days": [...]}`. `now` is the
  person's latest move, read back from Kafka, only for the current run in
  dev mode. Each admission has the fields of `GET /api/admissions` and
  `triage` (`level`, `waitMinutes`, `area`, `nurseCheck`, `reference`,
  `error`), null before aityx triaged it; each day `day` (the date),
  `visits`, `acuteVisits`, `chronicVisits`, `stayHours`,
  `chronicCondition`. At most 200 of each. 404 when nothing is known of
  them, 503 without the database; open to everyone.
- `GET /api/people/{id}/prediction?run=`: datyx's prediction for the
  person of `run` (as above), asked with the user's own token, as
  `/api/datyx/*`: the API finds the user's datyx data source for its own
  database (a database source whose database is `HEALTHHUB_DB_NAME`,
  `healthhub`) and asks it to score the person's series of
  `public.patient_days`, group `care`
  (`POST /api/datasources/{id}/inference` with `{"run_id", "person_id"}`;
  datyx's [inference](../../datyx/specs/inference.md)). It answers
  `{"predicted", "last", "note", "series", "target", "horizon", "group",
  "table", "trainingRunId", "trainedAt", "sourceId", "millis"}`; datyx's
  own status and error when it refuses (404 without a trained model, 409
  for a model trained before datyx kept its codes); 404 when datyx has no
  source for HealthHub's database; 502 when it doesn't answer; 401 with
  sign-in on and nobody signed in.
- `GET /api/triage` and `/api/triage/{eventId}` carry `personId`, for the
  link.

## Tests

`routes_test.dart`: a person path's id, encoded or not, and whether it
asks for the prediction; nothing for an empty, nested or undecodable id;
a person's facts from their move and admission, now, the counts; a past
run without now; moving this run without admissions; 404 and 503; the
prediction trimmed, datyx's 404 passed on, 502 and 401.
`widget_test.dart`: a move's id opens the current person, the
prediction card highlighted above the rest, its value, the last 30 days
and the model, the admissions with their triage and the days, and back;
an admission's name opens the person of its run, "a past run"; a
triage's name opens the person without opening the triage, and so does a
person on the map; without a model the card says why and the rest shows;
a run is eight hex digits.

## Known limitations

- The prediction needs datyx's inference (`datyx-xgboost-inference`) and
  a model trained for `patient_days`, group `care`; without them the card
  says why.
- Which datyx source is HealthHub's is found by the database's name: two
  sources of the user's on databases of that name, the first wins.
- A run's person is the same only within the run: an id opened from a
  past admission is a different person from the one moving now. The one
  exception is the simulated history, run `00000001`
  ([The simulated history](simulated-history.md)): its people are the
  live run's at its start, in another year of their own, their
  admissions never triaged. Where the API looks for the newest run with
  an admission of a person (no `run` asked, in prod mode or before the
  simulation has started), it can find that run.
