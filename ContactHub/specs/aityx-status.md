# aityx status light

A small dot at the top right of every screen says whether aityx is ready:
whether the API has an aityx key and whether aityx accepts it. It's
discreet on purpose: 8 px, at 0.8 opacity, 6 px from the corner, with no
label.

| Dot | Means | Tooltip |
|---|---|---|
| Grey | the first check is running | `aityx: checking` |
| Green | aityx accepts the key | `aityx: ready — accepts the key (<url>)` |
| Red | no key | `aityx: no key — AITYX_API_KEY is not set` |
| Red | a key, but aityx refused it, redirected or didn't answer | `aityx: not working — <detail>` |
| Red | the API didn't answer | `aityx: the API did not answer` |

The tooltip is also the dot's screen reader label.

The app asks the API's `GET /api/aityx` (see [API](api.md)) at start and
every minute, at `API_BASE_URL` like routing does. The light is mounted
once, over the Navigator through `MaterialApp.builder`
([lib/aityx_status.dart](../contacthub_app/lib/aityx_status.dart)), so
every screen has it; no screen has a control in that corner.

The API checks the key by posting an empty request to aityx's
`/v1/systemone`: aityx checks the key first, so a working key gets 400
`invalid_request` and a bad one 401, without running any model. Redirects
aren't followed: a 3xx names the host it points to, since an `AITYX_URL`
behind a login (such as Cloudflare Access) answers with one. The answer
is kept a minute, and requests that arrive during a check share it, so
the light never calls aityx more than once a minute. The key is never in
the answer.

## Known limitations

- A change, such as a key added to `.env`, shows within a minute of the
  API's restart; the API reads its key once, at start.
