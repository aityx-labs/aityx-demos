# Home

Where the user lands after signing in
([home_screen.dart](../healthhub_app/lib/screens/home_screen.dart)): a
dashboard in rows under an app bar titled **HealthHub** with the
account corner. From 1000 px wide, an explainer card 340 px wide sits to
the right of the first two rows (the map, the triage), its top level with
theirs; narrower, each goes under its row.

- **The account corner** (`UserMenu`,
  [user_menu.dart](../healthhub_app/lib/auth/user_menu.dart)): the
  user's picture, name and a sign-out button. Signing out goes back to
  the [index](index.md).
- **The tiles**: a tile is a card with a header (an orange icon, the
  title and a status line) and its content filling the rest. For now
  there is one, as wide as the page (less a 16 px margin) and 78% of the
  window's height, between 520 and 1100 px:
  - **Where you are**: the [map](map.md) with the user's position
    highlighted, centred on the care center nearest them once both are
    known, the status line saying "The orange dot is you." or why there
    is no location. Beside the title (under it when narrow), while the
    simulation runs, its date and time, large and bold with a clock:
    "Jun 3, 2026 16:00" (the calendar starting on Jan 1, 2026), and
    **Paused** in amber beside it while it is paused (see [The simulated
    clock](#the-simulated-clock)).
- **The data, and the simulation** (`SimulationExplainer`,
  [explainers.dart](../healthhub_app/lib/screens/explainers.dart)), beside
  the map, briefly: real care centers (7,256, from the official
  registries of Spain, the US and Brazil), simulated people (eighty per city to start, as many as the events set,
  some with a chronic condition, anyone falling ill now and then), an
  hour a second (the trip to the nearest care center the visit needs, a
  health station, urgent care or a general hospital, the desk, the stay,
  home), and a real stream (Kafka, the admissions recorded, Flink's
  hours of care, datyx learning from them; a restart is a new run).
- **Triage at the desk, by aityx** (`TriageCard`,
  [triage_card.dart](../healthhub_app/lib/triage/triage_card.dart)), under
  the map, when the API triages admissions or has triaged some
  (`GET /api/triage`, every 5 seconds; [Triage at the desk](triage.md)).
  The header says "Jev reads what each patient says; the triage rules
  decide. Tap one to see why." and how many were triaged and how many at
  the reference level. Below it, every triage counted: a chip per level
  in its colour (🔴 Immediate, 🟠 Very urgent, 🟡 Urgent, 🟢 Standard,
  🔵 Non-urgent), within one level of the reference, less and more
  urgent than it, for a nurse, failed, and the median time. Then the 8
  latest, newest first, each with a bar and a chip in its level's colour
  with the longest wait ("Very urgent · within 10 min"), the area, "a
  nurse checks" when the rules ask for it, how it compares with the
  reference ("✓ the reference level", "one level more urgent than the
  reference"), who (a link to their view, [The person view](person.md))
  and at which hospital, what they said (two lines), and
  the level rule's why, or the error of a triage that failed.
  - **A tap** opens why (`TriageDetailDialog`, from
    `GET /api/triage/{eventId}`): the level and wait, who, the area and
    the hospital; what the patient said, and that aityx gets only that and
    the age; what Jev read, each danger sign's probability as a bar with
    the 0.35 and 0.7 thresholds marked ("0.86 present", "0.41 in
    doubt"), and the four choices with their confidence; the level and
    area tables' rules tried in order, ✗ until the ✓ that fired, with
    their why; the nurse's check; the reference (the simulated patient's
    condition and visit, the level a nurse applying the same rules gives,
    and how aityx's compares); and the receipt (how many inputs came from
    Jev and which from the desk, the time and the tokens).
- **What aityx does at the desk** (`AityxExplainer`), beside the triage,
  briefly: **Jev reads** (only what the patient said and their age, into
  eight danger signs' probabilities and four choices), **rules decide**
  (DMN decision tables, the first rule that matches: 14 rules for the
  level, 8 for the area, written by people, not learned), **in one call**
  (Jev and the tables together on aityx, about a quarter of a second, a
  fraction of a cent), and **explained** (the receipt: each reading, the
  rule that fired and why; rules change without retraining; any triage
  can be audited).
- **Latest events** (`StreamEventsCard`,
  [stream_events.dart](../healthhub_app/lib/events/stream_events.dart)),
  under the map, in dev mode only: the latest records on the Kafka
  streams, `healthhub.people.moves`, `healthhub.admissions` and
  `healthhub.alarms`, as **one stream, newest first by simulated time,
  the kinds among each other**. One read, every 5 seconds, asks for the
  60 latest events of every kind (`GET /api/events?limit=60`, no type);
  the API already keeps only a person's changes of state among the moves
  (left home, arrived, going home, back home; [Simulation](simulation.md#the-stream)),
  not every turn's position, so the moves don't bury the admissions and
  the alarms. The card sorts them by simulated day and time; at the same
  minute, in the order the API gave them, the order they were read (a
  record's offset within its topic), never by kind. At most 20 rows show.
  The header: **Latest events**, and beside it, as on the map's header,
  the simulated date and time ("Jan 19, 2026 17:00",
  [The simulated clock](#the-simulated-clock)), with **Paused** while
  paused, in place of any count of what is shown. Beside them, while
  care centers have an occupancy alarm, a red badge with a warning, "2
  alarms", then every event the API read, those left out too, and how
  many a second over the last minute, a moving average: "48,213 events ·
  70.4/s" (nothing from an API that doesn't count); all under the title
  when narrow. Under it the topics, "On Kafka, healthhub.people.moves,
  healthhub.admissions; every 5 seconds". Under the header, the
  simulation's controls, in a row that wraps when narrow:
  **80 people a city**, a menu of 10, 20, 40, 80, 120, 160 and 200 that
  sets how many people each city has (`POST /api/simulation/people`;
  [Simulation](simulation.md#people)), showing what the API answered
  until the next read says it too, a refusal in a snack bar ("Sign in to
  change the people of the simulation."); and
  **Pause the simulation** (`POST /api/simulation/pause`; then **Resume
  the simulation**, `/resume`; [Simulation](simulation.md#pausing)):
  while paused the topics line reads "Paused: nobody moves, the clock
  stands", in amber. The button shows what the API answered until the
  next read says it too; a refusal shows in a snack bar ("Sign in to
  pause the simulation." when the API wants a user).
  - **The occupancy alarms, pinned** under the header and the
    simulation's controls, above the rows: a banner per
    care center whose occupancy reaches the alarm threshold, 90% of its
    capacity, observed or by datyx's DeepAR forecast ([Occupancy
    alarms](occupancy-alarms.md)), as the API orders them (actual first,
    then expected, then the soonest). Unmistakable: a tint, a 2 px border
    and a glow in the level's colour, a large icon, bold text, the care
    center a link to its [view](care-center.md):
    - **actual** (the occupancy now reaches it), red, with
      `Icons.emergency`: "Occupancy now at 100% at Hospital del Mar",
      under it "Jun 3, 2026 09:00: 8 in care of 8 beds (100%)".
    - **expected** (the forecast mean reaches it), red, with
      `Icons.crisis_alert`: "90% occupancy expected at Hospital del Mar
      in 7 h", under it "Jun 3, 2026 16:00: 10 in care of 8 beds (90%
      range up to 12.4) · peak 11.3 at Jun 3, 2026 18:00 (90% range up
      to 13)".
    - **possible** (only the 90th percentile reaches it), amber, with
      `Icons.warning_amber`: "90% occupancy possible: Clínica X may
      reach 90% of its 3 places in 3 h", under it "Jun 3, 2026 12:00:
      2.4 expected in care of 3 places, 90% range up to 3.6 · peak …".

    How far ahead ("in 7 h") is from the clock in the card's header, not
    from the check, which is hours behind it by then; "now, since Jun 3,
    2026 16:00" once the clock is past that hour. On hover, which level
    it is, the simulated time of the check and datyx's training run.
    One that may be out of date (datyx didn't answer the latest check,
    or no check got a forecast for a while, or not of that care center)
    says so in amber, "Not current: last checked Jun 3, 2026 09:00",
    and a line under the banners says why ("Occupancy alarms may be out
    of date · last checked Jun 3, 2026 09:00 · the datyx API is not
    answering"). With none, nothing; while datyx can't
    forecast (no model trained yet), one muted line says why
    ("Occupancy alarms: datyx can't forecast yet (…)").
  - Under it, an invitation: "Open anyone by their name to see their
    data and statistics: their admissions, aityx's triage, their days of
    care and datyx's prediction."
  - **Pills** over the rows (`events-filter`), styled as the app's chips
    (compact, orange when chosen), one chosen at a time, **All** first and
    chosen until another is; the choice holds over the reads. Each but All
    says how many of the rows read it keeps ("Admissions 7"), and what it
    keeps on hover:
    - **Busiest: Hospital del Mar · 3**, with a flame: the events at the care
      center with the most people in care now, which the API names
      (`busiest`, from everyone's latest move; how many are in care there
      on hover): its admissions, the people going to, at or leaving it
      (not someone at home, whose record names their usual hospital), and
      its alarm events. Only once the API names one; chosen while none is,
      it reads as All.
    - **Alarms**: the alarm events, raised, downgraded and cleared.
    - **Urgent**: the admissions aityx triaged red (Immediate) or orange
      (Very urgent).
    - **Admissions**: every admission.
    - **On the move**: the people who left home for a care center.
    - **Acute** and **Chronic**: the moves and admissions of a condition
      of that type.

    A pill that keeps none of the rows read says so, "No urgent event
    among the latest." ("Nothing at Hospital del Mar among the latest
    events." for the busiest); before the first event, "Waiting for the
    first event…".
  - **Every event is a row of the same shape and height** (`EventRow`,
    `AlarmRow`), whatever its kind: a bar on its left and a faint tint in its colour,
    a mark, and two lines that never wrap (cut with "…" when they don't
    fit). The first line: the person's name and age (a link to their
    view, [The person view](person.md); the id on hover), a heart
    monitor (`Icons.monitor_heart_outlined`) when they are monitored (why
    on hover: "Monitored at home: aged 84"), the condition
    and whether it is acute or chronic, for an admission aityx has
    triaged its level, a small pill in the level's colour ("Very urgent",
    the level on hover), and when, a date and time on the
    simulation's calendar ("Jan 4, 2026 09:09", [Simulation](simulation.md#the-calendar)).
    The second: what happened and the record's partition and offset.
    The time and the offset end at the row's right edge, the one over
    the other, so they line up down the list whatever the names.
    - **A move**: the person's state colour (the map's) for the bar and
      a dot; what they are doing, and the hospital, on the way there or
      in it, a link to its [view](care-center.md). The link opens the
      person of the run going on now.
    - **An admission**: orange, with a hospital icon
      (`Icons.local_hospital`); the visit ("First visit", "Return visit,
      the 2nd", "Last visit, the 3rd") and the hospital (a link to its
      view), then, in italics
      and quotes, as much of what the person said on arrival as fits
      ([Conditions](conditions.md)), all of it on hover, and, before the
      partition and offset, the hours of hospital care datyx expects of
      the person over the next 30 days, with a bed icon ("9 h expected
      in 30 days"; the model and the hours of the last 30 days on hover).
      The link opens the person of that admission's run.
    - **An alarm event** (`healthhub.alarms`, the 10 latest the events
      carry, in time order among the others by the simulated time of the
      check, before the records of its own minute, which its check read): no person, the care
      center instead, a link to its view. **Raised**, red with the
      level's icon: "Alarm: 90% expected · Hospital del Mar", then "in 7
      h, Jun 3, 2026 16:00 · 10 in care of 8 beds (90% range up to
      12.4)" ("Alarm: 90% reached now", "Alarm: 90% possible").
      **Downgraded** (to a lower level), amber: "Downgraded: 90%
      possible". **Cleared**, green with a check: "Cleared: below 90%",
      then "In care and forecast below 90% of 8 beds". The time is the
      check's, a date as an event row's ("Jun 3, 2026 09:00"); the record's place on the topic when the API gives it,
      else `healthhub.alarms`.

    The 30-day hours are datyx's XGBoost prediction for the person of
    the admission's run, the one their view highlights ([The person
    view](person.md)), asked once per admission read (`GET
    /api/people/{id}/prediction?run=`) and kept while the admission is
    among the latest; nothing shows while it loads, nor when datyx can't
    say (no model trained, no rows, not answering, nobody signed in),
    nor on the index, which opens no person.

  The alarms and the clock come with the events (`GET /api/events`
  carries `alarms` and `now`): no other poll. Nothing shows in prod, nor
  before the API answers. A failed read keeps what is shown.

  Tests in [widget_test.dart](../healthhub_app/test/widget_test.dart):
  one read without a type; the rows in simulated time, the kinds among
  each other, a tie in the API's order, the alarm events among them; no
  counts in the header, the clock beside the title; each pill's rows and
  count, one chosen at a time, the choice kept over reads, the busiest
  named with how many are in care, a pill that keeps nothing; what the
  busiest keeps (not someone at home); the triage pill on an admission.
  The API's ([simulation_test.dart](../healthhub_api/test/simulation_test.dart),
  [visits_test.dart](../healthhub_api/test/visits_test.dart),
  [routes_test.dart](../healthhub_api/test/routes_test.dart)): only
  changes of state kept, the merge by simulated time with ties in the
  order read, the busiest care center, an admission's triage.
- At the bottom, when the build has one, the version: `HealthHub X.Y.Z`.

## The simulated clock

`SimClockText` ([simulated_clock.dart](../healthhub_app/lib/events/simulated_clock.dart)):
"Jun 3, 2026 16:00", the date (the API's `now.date`, or Jan 1, 2026 plus
the day less one) and the time as the rest of the app writes them
([sim_clock.dart](../healthhub_app/lib/sim_clock.dart)), bold, with a clock icon (amber while paused) and the amber
**Paused**; the meaning on hover. The events card reads it from its
events (`now`, the newest move's; the newest record's without it) and
`paused`; the map from `GET /api/people`'s `day` and `simTime`. Both
report what they read to the page's `SimClock`, which the map's header
follows: the newest reading (a slower poll's older one doesn't move it
back, but more than an hour back is a new run and does), paused as the
events (or the pause button) last said. It updates with each read,
every 5 seconds. Nothing shows before the simulation says its time, nor
in prod. The index shows it too, under its welcome ([Index](index.md)).

## Known limitations

- The pause is the API's, so everyone watching sees it: there is one
  simulation.
- One tile so far. The API still serves `/api/hello`, `/api/health` and
  the datyx routes, and the API client still has them, but no page shows
  them now.
