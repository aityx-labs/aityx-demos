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
