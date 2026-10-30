# aityx status light

A small dot at the top right of every screen says whether aityx is ready:
whether there's a key, yours or the dev key, and whether aityx accepts
it. It's discreet on purpose: 8 px, at 0.8 opacity, 6 px from the corner,
with no label. It's the shared light of the aityx demos,
`AityxStatusLight` from [aityx_web](../../packages/aityx_web/README.md),
mounted once over the Navigator through `MaterialApp.builder`
(`withAityxStatus`, in [lib/main.dart](../contacthub_app/lib/main.dart)),
so every screen has it; no screen has a control in that corner.

| Dot | Means | Tooltip |
|---|---|---|
| Grey | a check is running | `aityx: checking` |
| Green | aityx accepts the key | `aityx: ready (your key, <url>)`, or `aityx: ready (dev key from .env, <url>)` |
| Red | no key | `aityx: no key — set yours on the index page` |
| Red | aityx refused the key | `aityx: key rejected — <detail>` |
| Red | no answer (network, CORS, a blocker, or the dev proxy couldn't reach aityx) | `aityx: not reachable — <detail>` |
| Red | another answer | `aityx: not working — <detail>` |

The tooltip is also the dot's screen reader label. A tap opens the index
page's key section, `/#aityx-key` at the origin's root, in the same tab.

The key is found as routing finds it (see
[Routing](routing.md#calling-aityx)): yours, set on the index page and
shared by every demo on the same origin, else the index server's dev key
through its proxy, else none. The check posts an empty request to aityx's
`/v1/systemone`: aityx checks the key first, so a working key gets 400
`invalid_request` and a bad one 401, without running any model. The
light checks at start, right away when the key changes (the index page,
in another tab, saves or forgets it), and when the window regains focus,
at most once every 30 s. There's no polling: each check spends a request
of your quota.

## Known limitations

- Your key lives in the browser's `localStorage` ("remember on this
  device") or `sessionStorage` ("only this session") for the index
  server's origin, readable by any script on it: the build keeps
  Flutter's own resources on the origin (`--no-web-resources-cdn`), but
  the voice input's worker loads transformers.js from jsDelivr (see
  [Request box](request.md#known-limitations)).
- `sessionStorage` is per tab: a key saved "only this session" reaches the
  app opened in the same tab, not in a new one.
- The Android, iOS and Linux builds have no index page and no dev proxy:
  their key store is in memory only, so the light stays red there.
