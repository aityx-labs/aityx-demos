# aityx status light

A small dot in the top right corner of every screen
([aityx_status.dart](../cellfie_app/lib/aityx_status.dart)), over the app
bar, says whether aityx is ready for the generations:

| Dot | Meaning | Tooltip |
|---|---|---|
| grey | the first check is running | `aityx: checking…` |
| green | the API has its key and aityx accepts it | `aityx: ready — accepts the key (<aityx URL>)` |
| red | the API has no key | `aityx: no key — AITYX_API_KEY is not set` |
| red | aityx refuses the key, redirects, or doesn't answer | `aityx: not working — <why>` |
| red | the API itself doesn't answer | `aityx: the API did not answer` |

The dot is 8 px, at 80% opacity, with no text; the tooltip, on hover or
long press, says why, and screen readers read the same. It is mounted
once, through `MaterialApp.builder`, in an `Overlay` of its own so its
tooltip works above the app's navigator, 6 px from the corner inside the
safe area. The app bar keeps its last action 16 px clear of it.

The app asks the API's `GET /api/aityx` ([API](api.md)) at start and
every minute, at `API_BASE_URL` like the generations (empty: the app's
own origin, through the `/api/` proxy). The API checks aityx at most once
a minute, so the polling doesn't call aityx each time.

## Known limitations

- Changes show within a minute, not at once: after fixing `.env`, the API
  must restart to read it, and the dot turns green at its next check.
