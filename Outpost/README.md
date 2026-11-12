# Outpost

Keep a growing city's lights on. You run the power of a city that gets
bigger every night: by day you build one thing (a solar panel, a battery or
a wind turbine), before night you set the rules for what goes dark first
when power runs short, and [aityx](https://aityx.ai) runs the night, hour by
hour, as a decision model. Keep the hospital on and approval at 50% or more
and the city makes it to morning. From night 6 a public building opens each
night, and after night 10 the sun fades a little more every day. There is no
last night: the game is how many your city survives.

Each night is one call to aityx's `/v1/systemone`. The page sends the model
(the loads, the penalties, your rules, the six hours of the night) and the
city's state, and draws only what aityx answers: the battery, the houses lit,
the hospital, the factory and approval at each hour, the stars, and a receipt
with the rule behind each line (the **Why** tab). The page computes nothing.

Without a key, the **Play** tab replays four games recorded on aityx (real
requests and responses), so a visitor sees the game before setting a key.

## Technology

| Part | Technology |
|---|---|
| App ([outpost_app/web/](outpost_app/web)) | A static page: HTML, CSS and plain JavaScript, no framework and no packages. The city is an SVG drawn from aityx's answers |
| Rules | Written by the page for each night ([outpost.js](outpost_app/web/outpost.js), `decision()`): loads, penalties, the order you chose, and each hour as decisions with a why |
| Recorded games | [recordings.js](outpost_app/web/recordings.js): four games, every night's request and response as aityx returned them |
| Serving | The repository's index server ([Index/](../Index)) serves the build at `/demos/outpost/`, beside the index page and the other aityx demos, on one origin |

## The key

As in every aityx demo ([packages/aityx_web](../packages/aityx_web/README.md)),
the key is set once on the index page (**Your aityx key**,
`/demos/#aityx-key`), and the page reads it from the origin's storage:
`sessionStorage`, else `localStorage`, `aityx.key` with `aityx.url`. It calls
`<url>/v1/systemone` itself. With no key there, it asks the index server's
`/demos/aityx/config` and, when the server holds a dev key, calls through its
proxy at `/demos/aityx/v1/systemone`, which adds the key. The page never asks
for, saves, shows or logs a key.

The status light at the top right is the same as the Flutter demos': grey
while it checks, green when aityx accepts the key, red otherwise. The check
POSTs `{}` (a working key gets 400 `invalid_request` and no model runs), on
start, when the index page saves or forgets the key in another tab, and when
the window regains focus, at most once every 30 s. A tap opens the key
section; embedded (`?embed=1`), it posts `"aityx:key"` to the page around it.

Only this origin's files run on the page (no CDN: the fonts are served from
[outpost_app/web/](outpost_app/web)), and its content security policy lets it
connect only to this origin and `https://*.aityx.ai`.

To record the games again, open `/demos/outpost/#record` with a key set: the
**Record** button replays the plans on aityx and downloads
`outpost-nights-recordings.json`, to paste into `recordings.js`.

## Run it

From the root of the repository, `./start-aityx.sh Outpost` (or
`./start-aityx.sh` for the whole group) builds it and starts the index, on
http://localhost:8800/demos/outpost/. The build
([scripts/build.sh](scripts/build.sh)) copies `outpost_app/web/` into
`outpost_app/build/web/`, only when it changed.
