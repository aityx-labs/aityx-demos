# Health Plan

Which 2027 health plan will actually cost you less? Open enrollment ends
Dec 15, and the lowest premium can still be the priciest year once you add
the care you'll need. You say who's on the plan and describe the year in
plain words; [aityx](https://aityx.ai) reads it and prices three plans,
Bronze, Silver and Gold, with the same rules every time, and shows every
number.

Each comparison is one call to aityx's `/v1/systemone`:

- **Jev reads the message**: for each person, the care they need in 2027
  (light, some or ongoing) and, for adults, how likely they are to give
  birth, plus whether the message is about health at all.
- **The rules price the plans** with what Jev read: each person's expected
  care, what they pay under each plan's deductible, coinsurance and
  out-of-pocket limit, the family cap, the premium for single or family
  coverage (a newborn counts), each plan's expected total and worst case,
  the cheapest plan and what it saves.

The page computes no amounts: every number on it is in aityx's answer. Fix
what Jev read (a person's care, a birth), change the plans or the price of a
year of care, or turn on a what-if switch, and the page prices again in one
rules-only call, with no AI.

Without a key, the page shows real aityx calls recorded with a key: the
three example years (a baby on the way, a kid with asthma, just me), each
with a different winner, and their what-if switches. The plans stay locked.

## Technology

| Part | Technology |
|---|---|
| App ([healthplan_app/web/](healthplan_app/web)) | A static page: HTML, CSS and plain JavaScript, no framework and no packages |
| Rules | Written by the page for each call ([app.js](healthplan_app/web/app.js), `buildDecision()`): the plans, the prices of care, and the pricing as decisions; Jev's questions in `jevQuestions()` |
| aityx | [aityx.js](healthplan_app/web/aityx.js): the key, where calls go, and the key check, as in [packages/aityx_js](../packages/aityx_js/README.md) |
| Recorded calls | [recordings.js](healthplan_app/web/recordings.js): each example year's call, and each what-if's, as aityx returned them |
| Serving | The repository's index server ([Index/](../Index)) serves the build at `/demos/healthplan/`, beside the index page and the other aityx demos, on one origin |

The plans are fictional, built on public averages (KFF's 2025 Employer
Health Benefits Survey, the 2027 out-of-pocket maximums from CMS, and
Peterson-KFF's costs of pregnancy and birth); the page lists its sources.
It is not insurance or medical advice.

## The key

As in every aityx demo ([packages/aityx_web](../packages/aityx_web/README.md)),
the key is set once on the index page (**Your aityx key**,
`/demos/#aityx-key`), and the page reads it from the origin's storage:
`sessionStorage`, else `localStorage`, `aityx.key` with `aityx.url`. It calls
`<url>/v1/systemone` itself. With no key there, it asks the index server's
`/demos/aityx/config` and, when the server holds a dev key, calls through its
proxy at `/demos/aityx/v1/systemone`, which adds the key. The page never asks
for, saves, shows or logs a key.

The **Run it with aityx** panel and the pill at the top right say whether
aityx accepts the key. The check POSTs `{}` (a working key gets 400
`invalid_request` and no model runs), on start, when the index page saves or
forgets the key in another tab, and when the window regains focus, at most
once every 30 s. **Set your aityx key** opens the index page's key section;
embedded (`?embed=1`), it posts `"aityx:key"` to the page around it.

Only this origin's files run on the page (no CDN: the fonts are served from
[healthplan_app/web/](healthplan_app/web)), and its content security policy
lets it connect only to this origin and `https://*.aityx.ai`.

To record the examples again, open `/demos/healthplan/#record` with a key
set: **Record all examples** runs each example and its what-ifs on aityx
(reusing the recorded Jev reads) and downloads `health-recordings.json`, to
paste into `recordings.js`.

## Run it

From the root of the repository, `./start-aityx.sh HealthPlan` (or
`./start-aityx.sh` for the whole group) builds it and starts the index, on
http://localhost:8800/demos/healthplan/. The build
([scripts/build.sh](scripts/build.sh)) copies `healthplan_app/web/` into
`healthplan_app/build/web/`, only when it changed.
