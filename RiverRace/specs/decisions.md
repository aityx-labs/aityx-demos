# Decisions

How aityx flies the two aityx pilots.

## The cycle

About every 0.2 s of real time, the time aityx takes to answer, whatever
the speed (every 6 frames at 1×, 3 at ½×, 12 at 2×, and in between as
the game speeds up), when no decision is under way, the app asks aityx
([decide.dart](../riverrace_app/lib/strategy/decide.dart)) about each
aityx pilot still flying: its id (`p1`, `p2`), its strategy's name and
rules, and what its plane senses now. It makes one call to aityx's
`/v1/systemone` for both, from the browser, on the user's key or the
index server's dev key (see [aityx calls](api.md)), and each plane flies
by the answer from then on. The player's plane never reaches aityx.

- The game doesn't wait: an answer applies when it arrives, typically
  150 to 300 ms later, so the pilots react that late. The steer commands
  are worked out every frame from the live river, so a pilot follows the
  channel between decisions.
- An answer that arrives after its pilot's plane was lost (and perhaps
  came back) is dropped for that plane: it was about the plane that
  crashed. The app keeps each pilot's loss count with its ask.
- When a decision fails (no key, a rejected key, no answer, an error from
  aityx; see [aityx calls](api.md) for the messages), it's shown above
  the river, the pilots keep their last decision, and the next call waits
  a second of game time.

## The model

[assets/models/river.json](../riverrace_app/assets/models/river.json),
an asset of the app, holds the types: `Sense` (the sensors, see
[Strategies](strategies.md)) and `Act` (`steer`, `throttle`, `fire`). For
each pilot the app adds
([lib/aityx/decision_request.dart](../riverrace_app/lib/aityx/decision_request.dart)):

- an input, `p1` or `p2`, of type `Sense`;
- a function, `strategy_p1` or `strategy_p2`, taking the sensors and
  returning `Act`: the pilot's rules as a FIRST decision table, with a
  column per sensor its rules test (`fuel` when none does), `=> steer`,
  `=> throttle`, `=> fire` and `# why`. aityx wants a FIRST table to end
  with an else row (every cell `-`), so one is added when the last rule
  isn't one: straight, normal, no fire. aityx also wants a why on every
  row: a rule without one gets `Rule N.`;
- a decision, `p1_action` or `p2_action`, calling it.

The state is what each plane senses. The answer's `answers.p1_action`
holds the commands and `receipt.functions.strategy_p1[0].rule` the row
that fired; the app reads it as the rule's number, or 0 for the else
row it added, with the rule's why.

## Verified

- `flutter test` in `riverrace_app/` (test/decision_request_test.dart and
  test/decide_test.dart): requests checked and refused, the tables built,
  the answers read, the call made against a stand-in for aityx.
- `bash scripts/model-test.sh` runs strategies on aityx: the first
  matching rule fires, an enum list cell (`left, right, ahead`) matches,
  and with nothing matching the else row does.
- `flutter test` in `riverrace_app/`: the game (same seed, same river; no
  dead ends; crashes; fuel; the player's controls; the senses match what
  the app checks), and the preset strategies flown for a minute on four
  rivers with a local stand-in for aityx's FIRST tables: they pass
  bridges and score, and Careful goes further than Rookie.

## Known limitations

- About 3 to 6 calls a second while the race runs; the calls panel keeps
  the latest 120.
- In real time, how well a pilot does depends on aityx's latency too.
