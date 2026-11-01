# The map

The map on the [index](index.md) and on [home](home.md)'s first tile
([lib/location/](../healthhub_app/lib/location/)), built with
[flutter_map](https://pub.dev/packages/flutter_map).

- **Tiles**: OpenStreetMap's standard tiles, darkened to the aityx
  palette (`darkModeTileBuilder`), with the "© OpenStreetMap
  contributors" attribution in the corner, as its tile policy asks.
  Requests name the app (`ai.aletyx.healthhub`) where the platform lets
  them set a user agent.
- **The user's location, highlighted**: an orange (`#E36742`) dot in a
  white ring, in a soft orange halo, inside a faint orange circle as wide
  as the device's accuracy, in metres.
- **Moving**: the map shows the whole world (zoom 2) until the location
  comes, then centres on it at zoom 14, once; later fixes move only the
  dot, so looking around isn't undone. On [home](home.md) it then moves
  on to the **care center nearest the user**, of any kind, once the API
  says which (`GET /api/care-centers/nearest`): centred on it, at zoom
  14 or as far out as keeps the user's dot in view too (from Lisbon,
  Cornudella's CAP 900 km away, with Spain in between). It stays on the
  user when the API doesn't answer or knows none, or when the user has
  already moved the map. The nearest is pinned even when the care
  centers in view leave it out. The index centres on the user only. **Zoom in** and **Zoom out**
  buttons (+ and −, bottom right) step one level at a time, between
  zoom 2 and 19; below them, once there is a location, a **Back to
  where you are** button centres it again. Drag, pinch and wheel zoom
  work too; rotation doesn't.

## Care centers

The map asks `GET /api/care-centers?bbox=west,south,east,north` for
what is in view once it has stood still for 0.4 s (on the first view
and after every move or zoom), and pins each [care center](care-centers.md):
a white-ringed circle with the kind's icon, hospitals red
(`Icons.local_hospital`), clinics blue (`Icons.medical_services`) and
health stations green (`Icons.health_and_safety`). On the index, tapping
or hovering a pin shows its name, its type (the source's own: "CAP",
"UBS"...), its address and phone; on home a click or a tap opens the
[care center view](care-center.md) and the tooltip shows on hover or a
long press, ending "Click to open". A legend at the bottom left says which icon is which,
and "Zoom in to see them all" when the view holds more than the API
answers at once (500, hospitals first, then health stations, then
clinics). An answer that arrives after a newer question is dropped, and
a failed one keeps the pins shown.

## Simulated people (dev mode)

In dev mode (`HEALTHHUB_MODE=dev`) the API simulates people going
between their homes and the nearest care center a visit needs (a health
station, urgent care, a mental health or dialysis clinic, a general
hospital) when a visit for their condition is due ([Conditions](conditions.md)), and streams
their moves through Kafka ([Simulation](simulation.md)). The map asks
`GET /api/people?bbox=` for the people in view (there, or living there)
once the view has settled after a move, and every 5 seconds while it
stays shown, not at every turn, and draws:

- **Homes**: a small muted house (`Icons.home`, 11 px) where each
  person started.
- **People**: a small dot (8 px) in a thin dark ring, small enough for
  hundreds of people a city to show where care is under pressure, above the homes and the care
  centers and below the orange you-are-here dot, coloured by state:
  amber going for care, violet in care, cyan going home, off-white at
  home. On the index, tapping or hovering one shows who it is, its
  condition, what it does, naming the kind of care center ("Going to the
  health station", "At the clinic", "At the hospital"), the care center
  (of the visit under way, else the general hospital nearest home) and
  the simulated time as a date ("Jan 4, 2026 09:00"), one
  line each; on home, hovering (or a long press) shows it, ending "Click
  to open", and a click opens the person's view, as a click on a home
  does ([The person view](person.md)):

  ```
  Jordi Puig, 41, reus-3
  Influenza (acute)
  Going to the hospital · Hospital Universitari Sant Joan de Reus · Jan 4, 2026 09:00
  ```

  The name, age and condition come from the person's profile in the
  moves ([Simulation](simulation.md)); a record without them shows the
  id alone on the first line and no condition line.
- **Legend**: under the care centers' entries, Home and one Person
  entry per state (at home, going for care, in care, going home), and "Simulated time: Jan 4, 2026 09:00" once the stream
  has said.

When the API answers `"enabled": false` (prod), none of this shows. A
failed read keeps what the map shows; the next one tries again.

## Location

`LocationController` asks once, when the app starts, and follows the
location while the app runs, so both pages share one answer and the
user sees one permission prompt. It reads it through
[geolocator](https://pub.dev/packages/geolocator): the browser's
geolocation on the web, which asks the user and needs a secure page
(localhost and a codespace's https are); the platform's services on
Android (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`) and iOS
(`NSLocationWhenInUseUsageDescription`). Its states: **asking**,
**found**, **denied** (the user said no, or the browser blocks it) and
**unavailable** (services off, or a platform without them, such as
Linux). A failure after a location was found keeps the last one on the
map. On the index the location stays on the device: the API only sees
the areas the map asks for. Home sends it once, to find the nearest
care center (`GET /api/care-centers/nearest?lat=..&lon=..`); the API
uses it for that query only, and neither logs nor keeps it.

## Known limitations

- OpenStreetMap's tile servers are for light use; a demo with real
  traffic needs its own tile provider.
- Linux has no location: geolocator has no Linux implementation.
- Seen in Chrome only (with a location faked over the DevTools
  protocol); not on a phone.
