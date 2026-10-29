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
  comes, then centres on it at zoom 15, once; later fixes move only the
  dot, so looking around isn't undone. A **Back to where you are**
  button (bottom right, once there is a location) centres it again.
  Drag, pinch and wheel zoom work; rotation doesn't.

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
map. The location stays on the device: nothing sends it to the API.

## Known limitations

- OpenStreetMap's tile servers are for light use; a demo with real
  traffic needs its own tile provider.
- Linux has no location: geolocator has no Linux implementation.
- Seen in Chrome only (with a location faked over the DevTools
  protocol); not on a phone.
