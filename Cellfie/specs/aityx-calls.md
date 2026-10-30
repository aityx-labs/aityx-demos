# aityx calls

The app calls aityx itself, from the browser: there's no Cellfie API.
[AityxGenerationStepper](../cellfie_app/lib/aityx/generation_stepper.dart),
the app's `GenerationStepper`, runs each [generation](generation.md) as
one `POST /v1/systemone` through the shared package
[aityx_web](../../packages/aityx_web/README.md), which finds the key and
makes the call.

## Whose key

aityx_web's order, in the browser:

1. **The user's key**, set once on the index page ("Your aityx key"),
   which every demo shares, since the index server serves them all on one
   origin (Cellfie at `/cellfie/`): the app calls `<url>/v1/systemone`
   directly (`https://api.aityx.ai` unless the user set another URL), with
   `Authorization: Bearer <key>`. aityx allows CORS from any origin.
2. **The dev key**: with no user key, when the index server has a key in
   its environment or the repository's `.env` (its `/aityx/config` says
   so), the app POSTs to `/aityx/v1/systemone` on its own origin and the
   index server adds the key. The key never reaches the browser.
3. **None**: no call is made, and the generation says
   `aityx is not set up: set your key on the index page.`, with a
   **Set your key** button that opens the index page's key section in
   the same tab.

## A generation

1. The board's body (`generationBody`: the generation, the rules, the
   situations and the clusters) is checked by `stateFrom`
   ([lib/aityx/life.dart](../cellfie_app/lib/aityx/life.dart)), the
   former API's checks, verbatim: a `generation` that isn't a whole
   number, a `rules` that isn't an object of booleans keyed `conway`,
   `highlife` and `no_death` (any left out is as by default: Conway's on,
   the others off), more than 18 situations or a repeated one, a
   situation with `neighbours` outside 0–8 or `cells` under 1, more than
   24 clusters, a cluster wider or taller than 64, or whose `shape` isn't
   `height` rows of `width` `o` or `.` with `cells` `o`, is refused before
   any call.
2. The Life model ([assets/models/life.json](../cellfie_app/assets/models/life.json),
   an asset of the app, read once with `rootBundle`) is sent with that
   state (`generationRequest`).
3. The call waits 30 s for aityx's whole answer.
4. `toGeneration` reads the answer: the fate of each situation, with the
   rule and its why, the counts, and each cluster's pattern, with the
   catalogue row that matched and what the pattern is. The outcome
   carries the call for the [calls panel](calls-panel.md): the body sent
   (never the headers, which hold the key), aityx's answer, and how long
   it took, as the app measured it, from sending to the whole answer.
   The call is left out if aityx's answer somehow contains the user's
   key (`withAityx`).

## What the user sees when it fails

A snackbar says why, and playback pauses:

| When | Notice |
|---|---|
| no key | `aityx is not set up: set your key on the index page.` (with **Set your key**) |
| the board fails a check | `Could not run the generation: <the check>.` |
| aityx answers 401 or 403 | `Could not run the generation: aityx rejected the key.` |
| no answer (network, CORS, a blocker) | `Could not run the generation: aityx did not answer.` |
| no whole answer within the 30 s | `Could not run the generation: aityx did not answer in time.` |
| aityx answers another error | `Could not run the generation: aityx answered HTTP <n>: <aityx's detail>.` |
| an answer that isn't JSON, or a field of the wrong type | `Could not run the generation: unexpected answer from aityx.` |
| a `decision_error`, or lists of the wrong length | `Could not run the generation: aityx could not decide it: <why>.` |
| the Life model asset doesn't load (read again on the next generation) | `Could not run the generation: the Life model did not load.` |

In dev mode, the index server's own failures (aityx unreachable, or a
redirect) come back as its 502 with a detail, shown the same way.

## Tests

[test/aityx/](../cellfie_app/test/aityx): `life_test.dart`, the former
API's tests of the checks and of reading a real answer
([generation-7.json](../cellfie_app/test/fixtures/generation-7.json)),
verbatim; `generation_stepper_test.dart`, the calls against a MockClient:
the body sent and the generation read, the headers on a user key and in
dev mode, every failure above, and the call left out when the answer
holds the key; and `model_scenarios_test.dart`, tagged `aityx`, which
`flutter test` skips and `bash scripts/model-test.sh` runs on aityx with
the key from the repository's `.env` (see [Generation](generation.md#verified)).

## Known limitations

- One call per generation; nothing is cached or stored.
- Each generation spends a request of the key's quota: the user's own,
  or the dev key's.
- The native builds (Android, iOS, Linux) have no index page and no dev
  proxy, and aityx_web keeps a key only in memory there: they run, but
  no generation can.
