# The care center view

Every care center HealthHub names on home, of any kind (hospital, clinic,
health station), is a link to its view: where it is on a map, with the
people there and on their way; what it is; its capacity in the simulation
and how much of it is in use now; its occupancy per hour with datyx's
forecast of the next 24; who is there; its admissions. App in
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
   from.
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
     have it as their hospital; the simulated time; and that the capacity
     is the simulation's. In prod, that nobody is there.
3. **Occupancy per hour**: the people in care at the care center in each
   of the last 72 simulated hours up to now, a solid line with a point
   per hour, and datyx's DeepAR forecast of the next 24, dashed and
   lighter with hollow points, in its band, kept over the hours as they
   pass to compare with what happened, under a faint line at its
   capacity ([A care center's occupancy per hour](occupancy-timeline.md)).
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
  "unit" ("beds" or "places"), "simulated": true}, "now": {"enabled",
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
as their hospital, the admissions; in prod nobody now; 404 and 503.
`widget_test.dart`: a pin on home opens the view (its tooltip says so):
the header, the map with the person on the way and the badge, the
capacity in use, the occupancy per hour with the forecast (under the
capacity, above the people), the people, the admissions with who and
their triage, a read every 5 seconds, a person opened from it and their hospital back to
it; a hospital in the events opens it, and the person in a triage's
detail opens theirs; a clinic's view says nobody comes; a 404.

## Known limitations

- The capacity is the simulation's, not the building's: the registries
  have no beds. CNES, the Catálogo Nacional de Hospitales and AHCA's
  files do list beds for hospitals, and could replace it.
- Only the care centers the simulation sends people to have anyone in
  them: general hospitals, health stations, and the urgent care, adult
  mental health and dialysis clinics ([Simulation](simulation.md#people)).
- Who is there is the stream's latest move of each person, read every 5
  seconds: someone admitted and gone between two reads isn't seen.
