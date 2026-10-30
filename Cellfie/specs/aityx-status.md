# aityx status light

A small dot in the top right corner of every screen says whether aityx is
ready for the generations. It is aityx_web's `AityxStatusLight`
([packages/aityx_web](../../packages/aityx_web/README.md)), shared by
every aityx demo, mounted once through `MaterialApp.builder` with
`withAityxStatus` ([main.dart](../cellfie_app/lib/main.dart)):

| Dot | Meaning | Tooltip |
|---|---|---|
| grey | a check is running | `aityx: checking` |
| green | aityx accepts the user's key | `aityx: ready (your key, https://api.aityx.ai)` |
| green | aityx accepts the index server's dev key | `aityx: ready (dev key from .env, https://api.aityx.ai)` |
| red | no key anywhere | `aityx: no key — set yours on the index page` |
| red | aityx refuses the key | `aityx: key rejected — <why>` |
| red | no answer (network, CORS, a blocker, or the dev proxy can't reach aityx) | `aityx: not reachable — <why>` |
| red | any other answer | `aityx: not working — <why>` |

The dot is 8 px, at 80% opacity, with no text; the tooltip, on hover or
long press, says why, and screen readers read the same. It sits in an
`Overlay` of its own so its tooltip works above the app's navigator, 6 px
from the corner inside the safe area. The app bar keeps its last action
16 px clear of it. A tap opens the index page's key section
(`/#aityx-key`) in the same tab.

The check uses the key the generations use (see [aityx calls](aityx-calls.md)):
it POSTs `{}` to `/v1/systemone`, which aityx answers with 400
`invalid_request` once it has accepted the key, without running a model.
It checks at start, at once when the key changes (the index page, in
another tab, saves or forgets it), and when the window regains focus, at
most once every 30 s. There's no polling: each check spends a request of
the key's quota.

## Known limitations

- A key set as "only this session" lives in that tab's sessionStorage: a
  demo opened in a new tab doesn't see it.
