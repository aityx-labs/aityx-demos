# Deciding on aityx

The app calls aityx itself, from the browser, one `POST /v1/systemone`
per decision, as PokerFace does; the Poker Tour server plays the
leaderboard's tournaments the same way ([The tour](tour.md)), and is not
in the way of the app's calls.
[AityxPokerApi](../pokertour_app/lib/api/aityx_poker_api.dart) implements
the app's `PokerApi` (the presets, and one decision) on `AityxClient` from
the repository's shared package,
[packages/aityx_web](../../packages/aityx_web/README.md); the table logic
is [poker_core](../poker_core)'s `table.dart`, shared with the server.

## Whose key

The player's own key, set in the Profile tab, and no other: players
never get the host's, which only the leaderboard plays on, on the server
([The sidebar and the profile](profile.md), [The tour](tour.md)). The
table's `TourAityxClient` asks `PlayerKeys` for the connection at every
decision, so a key set or forgotten takes effect at the next one: a
`POST <url>/v1/systemone` with `Authorization: Bearer <key>`, `url` being
the player's, else this environment's (the server's config: staging on
a laptop, production deployed). On a laptop, calls to staging go
through the local server's relay, `/aityx/v1/systemone`, as staging
takes no browser calls. There is no index page here and no dev key.

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
situation}`, where the name is the table's and the strategy's ("Poker Tour
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
| no key | `no aityx key for your table: set yours in Profile` |
| aityx answers 401 or 403 | `aityx rejected the key` |
| no answer in 30 s, a network or CORS error, or the dev proxy can't reach aityx (502 `proxy_unreachable`) | `aityx did not answer` |
| any other status | `aityx answered HTTP n`, then aityx's code, detail and first errors' paths and messages (`: invalid_decision; ...; decision.decisions.action: ...`), so a custom strategy's mistake reaches the editor; left out if they somehow hold the user's key |
| a `decision_error`, or no action in the answer | `aityx could not decide it: ...` |
| an answer that isn't JSON, or isn't shaped like aityx's | `unexpected answer from aityx` |

## Tests

[test/aityx_poker_api_test.dart](../pokertour_app/test/aityx_poker_api_test.dart)
runs the presets from the asset bundle and every decision path against a
MockClient (the user's key, the dev proxy without an Authorization header,
each error); [test/table_test.dart](../pokertour_app/test/table_test.dart)
is the API's table tests, ported. The scenarios on the real aityx are
tagged `aityx` and run by `scripts/model-test.sh`
([Strategies](strategies.md#verified)).

## Known limitations

- One aityx call per decision; nothing is cached, and nothing is stored.
- The player's key is used from the browser: anything running on the
  origin could read it, hence Profile's advice to use a key made for
  demos. The web build takes CanvasKit from the origin
  itself (`--no-web-resources-cdn`); Google's sign-in SDK is the one
  third-party script.
- Native builds (Android, iOS, Linux) have no sign-in and no key: they
  never reach the table.
