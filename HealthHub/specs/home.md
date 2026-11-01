# Home

Where the user lands after signing in
([home_screen.dart](../healthhub_app/lib/screens/home_screen.dart)): a
dashboard of tiles under an app bar titled **HealthHub** with the
account corner.

- **The account corner** (`UserMenu`,
  [user_menu.dart](../healthhub_app/lib/auth/user_menu.dart)): the
  user's picture, name and a sign-out button. Signing out goes back to
  the [index](index.md).
- **The tiles**: a tile is a card with a header (an orange icon, the
  title and a status line) and its content filling the rest. For now
  there is one, as wide as the page (less a 16 px margin) and 78% of the
  window's height, between 520 and 1100 px:
  - **Where you are**: the [map](map.md) with the user's position
    highlighted, the status line saying "The orange dot is you." or why
    there is no location.
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
  reference"), who and at which hospital, what they said (two lines), and
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
  an admission before the moves of its own hour. The header names the
  topics and counts what is shown, "3 admissions · 12 moves".
  - **A move** is one compact row: a dot in the person's state colour
    (the map's), the simulated time and day, the person's id, what they
    are doing (and the hospital, on the way there or in it), and the
    record's partition and offset.
  - **An admission** stands out: an orange bar on its left and an orange
    tint, a hospital icon (`Icons.local_hospital`), the person's name and
    age, the condition and whether it is acute or chronic, the visit
    ("First visit", "Return visit, the 2nd", "Last visit, the 3rd") and
    the hospital, the simulated time and the record's partition and
    offset, and below, in full, wrapped, in italics and quotes, what the
    person said on arrival ([Conditions](conditions.md)).

  Nothing shows in prod, nor before the API answers. A failed read keeps
  what is shown.
- At the bottom, when the build has one, the version: `HealthHub X.Y.Z`.

## Known limitations

- One tile so far. The API still serves `/api/hello`, `/api/health` and
  the datyx routes, and the API client still has them, but no page shows
  them now.
