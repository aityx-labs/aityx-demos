# The aityx light

A small dot over the top right corner of every screen says whether aityx
is ready for the table: whether the player has set their key and whether
aityx accepts it. It is 8 px, a little
transparent and has no label, so it stays out of the way; it sits in the
corner's padding, clear of the app bar's buttons, and taps elsewhere pass
through to the app. A tap on the dot opens the sidebar's Profile tab,
where the key is set ([The sidebar and the profile](profile.md)).

| Dot | Means | Tooltip (and screen-reader label) |
|---|---|---|
| grey | a check is running | `aityx: checking` |
| green | aityx accepts the key | `aityx: ready — the key works with https://api.aityx.ai` |
| red | no key at all | `aityx: no key — set yours in Profile` |
| red | aityx refuses the key | `aityx: key rejected — <why>` |
| red | aityx (or the dev proxy) can't be reached | `aityx: not reachable — <why>` |
| red | any other answer | `aityx: not working — <why>` |

The check (`TourSession.checkKey`) posts `{}` to aityx's `/v1/systemone`
on the key in use (through the local relay to staging on a laptop):
aityx checks the key first, so a working key gets 400 `invalid_request`
without running a model, and a bad one 401. It runs at start, right away
when the key changes (set or forgotten in Profile), and when the window regains focus, at most once every 30 s;
there is no polling timer, since each check spends a request of the
key's quota. Its verdict is the Profile tab's too, and a rejected key
opens it; until it is green, **Play** and **Step** are disabled ([The
table](table.md)).

Code: `AityxStatusLight` and `withAityxStatus` in the shared package
[packages/aityx_web](../../packages/aityx_web/README.md), mounted over
every route by `MaterialApp(builder: withAityxStatus)` in
[lib/main.dart](../pokertour_app/lib/main.dart). The decisions use the
same key, in the same order ([Deciding on aityx](aityx.md)).
