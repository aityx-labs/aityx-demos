# aityx calls (no API)

RiverRace has no API of its own any more: the app, in the browser, calls
aityx's `POST /v1/systemone` itself for each decision
([Decisions](decisions.md)), through the shared package
[aityx_web](../../packages/aityx_web/README.md) (`AityxClient`). The
former `riverrace_api` (a Dart server that held the key and served
`POST /api/decide`, `GET /api/aityx` and `GET /api/health`) is gone, with
its web server, Docker images and process-compose services.

## Whose key

The app is served by the index server with every aityx demo and the index
page, on one origin, at `/riverrace/`
(http://localhost:8800/riverrace/), so the key a user sets once on the
index page reaches every demo. `AityxClient` looks, in this order:

1. **The user's key**, set on the index page ("Your aityx key"):
   `sessionStorage['aityx.key']` ("only this session"), else
   `localStorage['aityx.key']` ("remember on this device"), with its
   `aityx.url` (default `https://api.aityx.ai`). The app calls
   `<url>/v1/systemone` directly, with `Authorization: Bearer <key>`;
   aityx allows it from any origin (CORS).
2. **The dev key**: with no user key, the app asks the origin's
   `/aityx/config`; when the index server has a key (`AITYX_API_KEY` in
   its environment or the repository's `.env`), calls go to
   `/aityx/v1/systemone` on the same origin, with no `Authorization`
   header, and the index server adds the key. That key never reaches the
   browser.
3. **None**: decisions fail with *aityx is not set up: set your key on the
   index page*, and the [status light](aityx-status.md) is red.

The key the user sets lives in the browser: anything running on the
origin can read it. The build keeps CanvasKit on the origin
(`--no-web-resources-cdn`), so no third-party script runs there. The
calls panel shows the request body, never the headers, so the key is in
neither the panel nor what its Copy button copies; and the call is left
out of the panel if aityx's answer contains the key (it never should).

## A decision

[decide.dart](../riverrace_app/lib/strategy/decide.dart)'s `AityxDecider`
(the app's `Decider`) builds the request from the pilots' rules and senses
with [lib/aityx/decision_request.dart](../riverrace_app/lib/aityx/decision_request.dart)
and the model in [assets/models/river.json](../riverrace_app/assets/models/river.json),
a bundled asset loaded once, then calls aityx with a 30 s timeout.

A rule is `{"when": {sensor: cell}, "then": {"steer": ..., "throttle":
..., "fire": true|false}, "why": ...}`; cells that are empty or `-` are
left out, and commands left out are `straight`, `normal` and `false`.
Before it calls aityx, the app refuses, as the API did, a `tick` that
isn't a whole number, other than one or two pilots, a pilot id other than
`p1` or `p2` or a repeated one, more than 40 rules, an unknown sensor or
command value, a `fire` that isn't a boolean, a text over 200 characters,
and a `sense` missing a sensor or with a value of the wrong kind.

What the user sees when a decision fails, above the river and on the
call's card:

| When | Message |
|---|---|
| No key at all | `aityx is not set up: set your key on the index page` |
| aityx answers 401 or 403 | `aityx rejected the key` |
| No answer (network, CORS, the timeout; or the dev proxy's 502 `proxy_unreachable`) | `aityx did not answer` |
| Another status | `aityx could not decide: aityx answered HTTP n: <aityx's detail> (<its problems' messages>).`, a cell aityx can't read, for instance |
| A request the app refuses | `aityx could not decide: <why>.`, for instance `p1: at most 40 rules.` |
| 200 but not JSON | `aityx could not decide: unexpected answer from aityx.` |
| 200 without the actions | `aityx could not decide: aityx could not decide it: <why>.` |

## Tests

- `flutter test` in `riverrace_app/`:
  [test/decision_request_test.dart](../riverrace_app/test/decision_request_test.dart),
  the API's request, table and answer tests, moved with the logic; and
  [test/decide_test.dart](../riverrace_app/test/decide_test.dart),
  `AityxDecider` against a stand-in for aityx (`MockClient`): the request
  sent, with the bundled model, the user's key and the dev proxy; the
  actions and the call read back, and the call left out when aityx's
  answer holds the key; every message in the table above; and a refused
  strategy that never reaches aityx.
- `bash scripts/model-test.sh` runs
  [test/model_scenarios_test.dart](../riverrace_app/test/model_scenarios_test.dart)
  (tagged `aityx`, which `flutter test` skips) on aityx with the key from
  the environment or the repository's `.env`, exported to the test only.

## Known limitations

- One call per decision; nothing is cached or stored.
- A native build (Android, iOS, Linux) has no index page and no dev proxy,
  and keeps a key only in memory, which nothing sets: its aityx pilots fly
  straight on.
- The user's key is spent from the user's own browser: every decision, 3
  to 6 a second while the race runs, is a request on the user's quota.
