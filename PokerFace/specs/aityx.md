# Deciding on aityx

There is no PokerFace API: the app calls aityx itself, from the browser,
one `POST /v1/systemone` per decision.
[AityxPokerApi](../pokerface_app/lib/api/aityx_poker_api.dart) implements
the app's `PokerApi` (the presets, and one decision) on `AityxClient` from
the repository's shared package,
[packages/aityx_web](../../packages/aityx_web/README.md); the table logic,
once the API's, is in
[lib/aityx/table.dart](../pokerface_app/lib/aityx/table.dart).

## Whose key

The app is served by the index server at `/pokerface/`, on the same
origin as the index page and the other aityx demos, and aityx_web finds
the key in this order:

1. **The user's key**, set once on the index page's "Your aityx key"
   (`sessionStorage`, else `localStorage`, `aityx.key` and `aityx.url`):
   the app calls `<url>/v1/systemone` (by default
   `https://api.aityx.ai`) with `Authorization: Bearer <key>`.
2. **The dev key**: with no user key, when the index server has one
   (`AITYX_API_KEY` or the repository's `.env`; its `/aityx/config` says
   so, never the key), the app posts to `/aityx/v1/systemone` on its own
   origin, and the server adds the key. The key never reaches the
   browser.
3. **None**: every decision fails with "aityx is not set up: set your key
   on the index page", and [the aityx light](aityx-status.md) is red.

## The presets

The table model and the five presets are the app's assets,
`assets/models/table.json` and `assets/models/strategies/*.json` (both
folders listed in `pubspec.yaml`), read once with `rootBundle`, the
strategies sorted by file name ([Strategies](strategies.md)). A preset
whose file has no name or no `decisions.action` and `decisions.raise_to`
stops the app from loading the strategies ("Could not load the
strategies: ..." on the table).

## A decision

Before calling aityx, the app checks what it is about to send, as the API
did, and refuses with these words: a strategy and situation over 64 KB
(`request too large`), an unknown preset id, a custom strategy without a
name (or one over 60 characters) or without `decisions.action` and
`decisions.raise_to`, and a situation that misses an input of the table
model, has one of the wrong type or out of range, or cards not written
like `Ah` (`situation.equity is required`, `situation.street must be one
of ...`).

It sends `{"decision": {name, types, inputs, decisions}, "state":
situation}`, where the name is the table's and the strategy's ("PokerFace
· a player's turn ... · The Rock"), and waits 30 s. From aityx's answer it
reads `action` (fold, check, call, raise, all_in), `raise_to`, `rule` (the
1-based row of the action table that fired, from the receipt) and its
`why` (the row's annotation), and `decisions`, the strategy's other
answers by name. The calls sidebar ([The aityx calls](calls.md)) gets the
body sent, aityx's answer and how long it took; never the headers, which
hold the key, and not the call at all if aityx's answer somehow contains
the key.

### Errors

What the calls sidebar, the table's error line and the editor's **Try it
on aityx** show:

| When | Message |
|---|---|
| no key | `aityx is not set up: set your key on the index page` |
| aityx answers 401 or 403 | `aityx rejected the key` |
| no answer in 30 s, a network or CORS error, or the dev proxy can't reach aityx (502 `proxy_unreachable`) | `aityx did not answer` |
| any other status | `aityx answered HTTP n`, then aityx's code, detail and first errors' paths and messages (`: invalid_decision; ...; decision.decisions.action: ...`), so a custom strategy's mistake reaches the editor; left out if they somehow hold the user's key |
| a `decision_error`, or no action in the answer | `aityx could not decide it: ...` |
| an answer that isn't JSON, or isn't shaped like aityx's | `unexpected answer from aityx` |

## Tests

[test/aityx_poker_api_test.dart](../pokerface_app/test/aityx_poker_api_test.dart)
runs the presets from the asset bundle and every decision path against a
MockClient (the user's key, the dev proxy without an Authorization header,
each error); [test/table_test.dart](../pokerface_app/test/table_test.dart)
is the API's table tests, ported. The scenarios on the real aityx are
tagged `aityx` and run by `scripts/model-test.sh`
([Strategies](strategies.md#verified)).

## Known limitations

- One aityx call per decision; nothing is cached, and nothing is stored.
- A user's key is used from the browser: anything running on the origin
  could read it. The web build takes CanvasKit from the origin itself
  (`--no-web-resources-cdn`), so no third-party script runs there.
- Native builds (Android, iOS, Linux) have no dev proxy and only an
  in-memory key store, empty at start: their decisions answer "aityx is
  not set up".
