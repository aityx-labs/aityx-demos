# The aityx light

A small dot over the top right corner of every screen says whether aityx
is ready for the table: whether the API has its aityx key and whether
aityx accepts it. It is 8 px, a little transparent and has no label, so
it stays out of the way; it sits in the corner's padding, clear of the
app bar's buttons, and taps elsewhere pass through to the app.

| Dot | Means | Tooltip (and screen-reader label) |
|---|---|---|
| grey | the first check is running | `aityx: checking` |
| green | aityx accepts the key | `aityx: ready — accepts the key (<aityx URL>)` |
| red | the API has no key | `aityx: no key — AITYX_API_KEY is not set` |
| red | aityx refuses the key or can't be reached | `aityx: not working — <why>` |
| red | the API didn't answer | `aityx: the API did not answer` |

The app asks the API's `GET /api/aityx` ([API](api.md)) at start and
every minute, on the same origin as its other calls (the web server
proxies `/api/`), or on `API_BASE_URL` when the build sets it. The API
keeps its answer for a minute, so the light never calls aityx more often
than that.

Code: [lib/aityx_status.dart](../pokerface_app/lib/aityx_status.dart),
mounted over every route by `MaterialApp.builder` in
[lib/main.dart](../pokerface_app/lib/main.dart).
