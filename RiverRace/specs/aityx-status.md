# aityx status

A small light in the top right corner, over every screen: aityx_web's
`AityxStatusLight`, mounted by `withAityxStatus` in `MaterialApp.builder`
([lib/main.dart](../riverrace_app/lib/main.dart)), the same light as in
every aityx demo and on the index page (see the
[package's README](../../packages/aityx_web/README.md)). It says whether
aityx can decide: an 8 px dot, slightly transparent, with no label.

| Dot | When | Tooltip |
|---|---|---|
| Grey | a check is running | `aityx: checking` |
| Green | aityx accepts the key | `aityx: ready — the key works with <aityx URL>` |
| Red | no key, the user's or a dev key | `aityx: no key — set yours on the index page` |
| Red | aityx refuses the key | `aityx: key rejected — <why>` |
| Red | aityx doesn't answer | `aityx: not reachable — <why>` |
| Red | aityx answers something else | `aityx: not working — <why>` |

The tooltip is also the dot's screen-reader label. A tap opens the index
page's key section (`/#aityx-key`) in the same tab.

The check uses the key the decisions use ([aityx calls](api.md)): it posts
an empty request, `{}`, to aityx's `/v1/systemone`, which checks the key
first, so a working key gets 400 `invalid_request` without running any
model. It runs at start, at once when the key changes (the index page, in
another tab, saves or forgets it), and when the window regains focus, at
most once every 30 s. There is no polling timer: each check is a request
on the user's quota.
