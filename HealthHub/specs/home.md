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
    is no location.
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
  streams, `healthhub.people.moves` and `healthhub.admissions`, asked
  every 5 seconds. The card asks for them apart, the 12 latest moves
  (`GET /api/events?type=move`) and the 8 latest admissions
  (`GET /api/events?type=admission`), because every person moves every
  second and the latest records of the stream are nearly always all
  moves: asked together, an admission would scroll out before anyone saw
  it. It shows them as one list, newest first by simulated day and time,
  an admission before the moves of its own hour. Someone at home shows
  only when monitored, the high-risk, and once a day, their check-in (the
  API leaves the others out; [Simulation](simulation.md#people)). Beside the title, every event the
  API read, those left out too, and how many a second over the last
  minute, a moving average: "48,213 events · 70.4/s" (under the title
  when narrow; nothing from an API that doesn't count). The header names
  the topics and counts what is shown, "3 admissions · 12 moves". Under
  it, the simulation's controls, in a row that wraps when narrow:
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
  - Under it, an invitation: "Open anyone by their name to see their
    data and statistics: their admissions, aityx's triage, their days of
    care and datyx's prediction."
  - **Every event is a row of the same shape and height** (`EventRow`),
    whatever its kind: a bar on its left and a faint tint in its colour,
    a mark, and two lines that never wrap (cut with "…" when they don't
    fit). The first line: the person's name and age (a link to their
    view, [The person view](person.md); the id on hover), a heart
    monitor (`Icons.monitor_heart_outlined`) when they are monitored (why
    on hover: "Monitored at home: aged 84"), the condition
    and whether it is acute or chronic, and when, a date and time on the
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

    The 30-day hours are datyx's XGBoost prediction for the person of
    the admission's run, the one their view highlights ([The person
    view](person.md)), asked once per admission read (`GET
    /api/people/{id}/prediction?run=`) and kept while the admission is
    among the latest; nothing shows while it loads, nor when datyx can't
    say (no model trained, no rows, not answering, nobody signed in),
    nor on the index, which opens no person.

  Nothing shows in prod, nor before the API answers. A failed read keeps
  what is shown.
- At the bottom, when the build has one, the version: `HealthHub X.Y.Z`.

## Known limitations

- The pause is the API's, so everyone watching sees it: there is one
  simulation.
- One tile so far. The API still serves `/api/hello`, `/api/health` and
  the datyx routes, and the API client still has them, but no page shows
  them now.
