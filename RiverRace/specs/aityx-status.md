# aityx status

A small light in the top right corner, over every screen
([lib/aityx_status.dart](../riverrace_app/lib/aityx_status.dart), mounted
by `MaterialApp.builder` in [lib/main.dart](../riverrace_app/lib/main.dart)),
that says whether aityx can decide: an 8 px dot, slightly transparent, with
no label.

| Dot | When | Tooltip |
|---|---|---|
| Grey | the first check is running | `aityx: checking` |
| Green | the API has its key and aityx accepts it | `aityx: ready — accepts the key (<aityx URL>)` |
| Red | the API has no key | `aityx: no key — AITYX_API_KEY is not set` |
| Red | aityx refuses the key, redirects or doesn't answer | `aityx: not working — <why>` |
| Red | the API doesn't answer | `aityx: the API did not answer` |

The tooltip is also the dot's screen-reader label. The app asks the
[API](api.md)'s `GET /api/aityx` at start and every minute, at the same
place as `POST /api/decide`: the app's own origin on the web, through the
web server's or nginx's `/api/` proxy, and `http://localhost:8941` in a
native app, unless `API_BASE_URL` says.

`GET /api/aityx` ([lib/aityx_check.dart](../riverrace_api/lib/aityx_check.dart))
posts an empty request to aityx's `/v1/systemone` with the key, which aityx
checks first: a working key gets 400 `invalid_request` (the request has no
state), without running any model, so the check costs nothing. It answers
`{"key", "ok", "url", "detail"}`; the key is never in it. A redirect, as
from an endpoint behind a login page, is reported as one, with where it
leads. The result is kept for a minute, and requests that arrive while a
check runs share it.
