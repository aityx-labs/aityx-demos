# The care center view

Every care center HealthHub names on home, of any kind (hospital, clinic,
health station), is a link to its view: where it is on a map, with the
people there and on their way; what it is, with buttons beside it to
double and halve the flow of people there in the simulation; its
capacity in the simulation and how much of it is in use now; its
occupancy per hour with datyx's forecast of the next 24; who is there;
its admissions. App in
[care_center_screen.dart](../healthhub_app/lib/care_centers/care_center_screen.dart),
API in [routes.dart](../healthhub_api/lib/routes.dart),
[db.dart](../healthhub_api/lib/db.dart) and
[care_centers.dart](../healthhub_api/lib/care_centers.dart).

## Where the links are

On home only, where `CareCenterOpener` gives the view's call to
everything under it; on the index a pin shows its tooltip, as before.

- **The map**: a care center's pin opens the view on a click or a tap;
  its tooltip (name, type, address, phone) shows on hover or a long
  press, and ends "Click to open".
- **Latest events**: the hospital of a move (on the way there or in it)
  and of an admission.
- **Triage at the desk**: the hospital in a row and in the triage's
  detail.
- **The person view**: the hospital of each admission, and the pill of
  what they do now when they are going to or at the hospital.

A link is the name in its usual style, underlined on hover with a hand
cursor (`CareCenterLink`, as `PersonLink`, both a `LinkText`). The view
is a page of its own, over home, with a back button and a refresh. A
page or a dialog opened from home sits above it on the app's navigator,
so it is given home's openers again (`withOpeners`): the people in a care
center's view open their view, the hospitals in a person's view open
theirs, and the person in a triage's detail is a link too.

## The view

`CareCenterScreen`, at most 960 px wide, read again every 5 seconds while
shown (a failed read after a good one keeps what is shown), in this
order:

1. **What and where**: the kind's icon in its colour (the map's), the
   name large, the kind and the registry's type ("Hospital · Hospitales
   Generales"), the address with postal code, city, region and country,
   the phone and website, the id, who runs it and the registry it comes
   from. Beside it, from 720 px wide (under it when narrower), as tall,
   **Flow of people** ([below](#the-flow)), while the simulation runs
   and sends people there.
2. **The map** and, beside it from 720 px wide (under it when narrower),
   **Capacity in use now**:
   - The map: OpenStreetMap's darkened tiles around the care center at
     zoom 15 (fitted to take in the people on their way, up to zoom 16),
     its pin with a badge in the at-the-hospital colour of how many are
     there now, and a dot for each person on their way, where they are,
     a link to their view. A care center without coordinates (666 rows)
     says the registry has no location for it.
   - The highlighted card: how many are there now, large, "of 8 beds"
     (places for a clinic or a health station), a bar and the share in
     use, green, amber from 60%, red from 90% ("over capacity" past
     100%); how many are on the way and, for a hospital, how many people
     have it as their hospital; the simulated time, as a date; and that the capacity
     is the simulation's. In prod, that nobody is there.
3. **Occupancy per hour**: the people in care at the care center in each
   of the last 72 simulated hours up to now, a solid orange line with a
   point per hour, and what datyx's DeepAR predicted of every hour, a
   dashed blue line with hollow points in its band: of each past hour
   before it was observed, and of the next 24; a vertical line at now,
   labelled with the simulated time; a faint line at its capacity and a
   red one at the alarm threshold, 90% of it, every hour observed or
   predicted at or above it marked in red, the first ahead labelled ("90%
   expected at Jan 19 16:00") ([A care center's occupancy per
   hour](occupancy-timeline.md)).
4. **People here now**, then those on their way: a row each in their
   state's colour, the name and age (a link), the condition and what they
   do ("At the health station"). When nobody can come: the simulation
   runs in dev mode only; it sends nobody to this kind of care center (a
   specialised hospital, a dental or rehabilitation clinic: `serves` is
   empty).
5. **Admissions**: how many this run, acute and chronic this run, and in
   all runs; then the latest, of this run when it has any there, else of
   any run: the time and day, the condition, the person (a link to the
   person of that admission's run), the visit, aityx's triage and what
   they said, as in the person view (`AdmissionRow`).

## The flow

The card beside what the care center is (`FlowCard`, 320 px wide, as
the capacity card under it) doubles or halves the flow of people to it
in the simulation ([The flow at a care
center](simulation.md#the-flow-at-a-care-center)): its factor now, large
("Flow ×2", "Flow ×1/4"; orange above normal, blue below), what it means
("The visits headed here come twice as often.", "... a quarter as
often."; "People come here as usual." at ×1), and two buttons:

- **Double the flow** (a double arrow up; its tooltip "Twice as many
  arrivals here: the visits headed here come twice as often (up to
  ×8)"), disabled at ×8;
- **Halve the flow** (a double arrow down; "Half as many arrivals here:
  the visits headed here come half as often (down to ×1/8)"), disabled
  at ×1/8;

and, away from ×1, a reset icon ("Back to the normal flow"). A press
calls `POST /api/care-centers/{id}/flow` and shows the factor it answers;
all are disabled, with a spinner, while a press is under way, and the
view's reads every 5 seconds keep the factor in step with other users'
presses (a read that started before a press doesn't undo it). A refusal
is a snack bar: "Sign in to change the flow." for a 401, else "The flow
can't be changed:" and why. The card isn't shown in prod or while the
simulation doesn't run (`flow` null), nor for a care center it sends
nobody to (`serves` empty).

## Capacity

The registries don't say how big a facility is, and the simulation's
people (`HEALTHHUB_SIM_PEOPLE` a city) would fill no real hospital, so
each care center has a capacity sized to the simulation instead
(`simulatedCapacity`): 4 to 12 beds for a hospital, 2 to 6 places for a
clinic, 2 to 5 for a health station, drawn from its key with FNV-1a, so
it is the same at every start and in every run. In use is the people the
stream last saw at it (`at_hospital`, at a care center of any kind).

## The API

- `GET /api/care-centers/{id}`: `{"id", "name", "kind", "subtype",
  "address", "postalCode", "city", "region", "country", "lat", "lon",
  "phone", "website", "ownership", "source", "serves" (the settings the
  simulation sends people to it for: `hospital`, `primary`,
  `urgent_care`, `mental_health`, `dialysis`), "capacity": {"places",
  "unit" ("beds" or "places"), "simulated": true}, "flow" (its flow
  factor this run, 1/8 to 8, 1 the normal flow; null in prod or while
  the simulation doesn't run), "now": {"enabled",
  "run", "simTime", "day", "inUse", "usage" (in use over places),
  "assigned", "here": [...], "onTheWay": [...]}, "admissions": {"run",
  "thisRun", "thisRunAcute", "thisRunChronic", "total", "acute",
  "chronic", "latestOf" ("run" or "all"), "latest": [...]}}`. `here` and
  `onTheWay` are the people whose latest move (read back from Kafka, in
  dev mode) has this care center as their hospital and says
  `at_hospital` or `to_hospital`, each `{"id", "name", "age", "city",
  "state", "mode", "lat", "lon", "conditionName", "conditionType",
  "simTime", "day"}`; `assigned` counts everyone whose hospital it is,
  wherever they are. Each of the latest 30 admissions has `eventId`,
  `personId`, `name`, `age`, `sex`, `city`, the condition, the visit, the
  complaint, `day`, `simTime` and `triage` (`level`, `waitMinutes`,
  `area`, `nurseCheck`, `error`), null before aityx triaged it. 404 for
  an id that is not a care center (or not a positive number), 503 without
  the database; open to everyone.
- `POST /api/care-centers/{id}/flow`, `{"action": "double" | "halve" |
  "reset"}`: changes the care center's flow factor for the rest of the
  run ([The flow at a care
  center](simulation.md#the-flow-at-a-care-center)) and answers `{"id",
  "factor"}`, the factor now. Anyone signed in (anyone while
  authentication is off), as for pausing the simulation: 401 without a
  user once it is on, 409 when the simulation doesn't run, 400 for
  another action, 404 for a care center the simulation sends nobody to
  (one without a location).
- `GET /api/care-centers/{id}/occupancy` and `.../occupancy/forecast`:
  its people in care per hour and datyx's forecast of them; the same for
  its admissions, `.../admissions` and `.../admissions/forecast`
  ([A care center's occupancy per hour](occupancy-timeline.md#the-api)).
- The moves of `GET /api/people` and `GET /api/events`, a person's `now`
  and the rows of `GET /api/triage` carry `hospitalId`, for the links.
- `admissions` has an index on `(hospital_id, id)`
  (`admissions_hospital_idx`), for a care center's latest.

## Tests

`care_centers_test.dart`: a care center path's id; the capacity by kind,
within its range and the same for a key every time; a care center's
answer with its capacity, who is there and on the way, how many have it
as their hospital, the admissions; in prod nobody now; 404 and 503; its
flow factor in dev only; the flow's route: 401, 409, 400 for another
action, 404, and the factor after each action. `flow_test.dart`: the
factor's steps and bounds; a moved visit's daytime slot; nothing changes
at the normal flow; in a seeded run the admissions at the hospital and at
the health station scale with their factor (×2, ×1/2, ×8) and the daily
profile stays; a change brings a planned visit forward or puts it off by
the time left, draws the next acute onset again at the new pace, and
thins the episodes headed to a care center slowed down; the simulation
keeps a factor per care center, a new run at the normal flow.
`widget_test.dart`: a pin on home opens the view (its tooltip says so):
the header, the map with the person on the way and the badge, the
capacity in use, the occupancy per hour with the forecast (under the
capacity, above the people), the people, the admissions with who and
their triage, a read every 5 seconds, a person opened from it and their hospital back to
it; a hospital in the events opens it, and the person in a triage's
detail opens theirs; a clinic's view says nobody comes, without the
flow's buttons; a 404. The flow: beside the header on its right, ×1,
both buttons; a press disables them until the API answers, then says
"Flow ×2"; up to ×8, where doubling stops, halved to ×1/4, which a read
keeps, and reset; a 401 in a snack bar; no card without the control; on
a narrow window the card under the header.

## Known limitations

- The capacity is the simulation's, not the building's: the registries
  have no beds. CNES, the Catálogo Nacional de Hospitales and AHCA's
  files do list beds for hospitals, and could replace it.
- Only the care centers the simulation sends people to have anyone in
  them: general hospitals, health stations, and the urgent care, adult
  mental health and dialysis clinics ([Simulation](simulation.md#people)).
- Who is there is the stream's latest move of each person, read every 5
  seconds: someone admitted and gone between two reads isn't seen.
