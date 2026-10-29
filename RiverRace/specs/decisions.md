# Decisions

How aityx flies the two aityx pilots.

## The cycle

Every **aityx decides every** frames (6 by default, a tenth of a second
of game time), when no decision is under way, the app sends `POST
/api/decide` ([decide.dart](../riverrace_app/lib/strategy/decide.dart))
with, for each aityx pilot still flying, its id (`p1`, `p2`), its
strategy's name and rules, and what its plane senses now. The API makes
one aityx call for both, and each plane flies by the answer from then on.
The player's plane never reaches the API.

- **Real time** (the default): the game doesn't wait; an answer applies
  when it arrives, typically 150 to 300 ms later, so the pilots react
  that late. The steer commands are worked out every frame from the live
  river, so a pilot follows the channel between decisions.
- **Fair race**: the game holds once a decision is more frames late than
  the interval, until aityx answers, so the pilots never fly on an old
  decision. The game then runs as fast as aityx allows.
- An answer that arrives after its pilot's plane was lost (and perhaps
  came back) is dropped for that plane: it was about the plane that
  crashed. The app keeps each pilot's loss count with its ask.
- When the API answers an error, it's shown above the river, the pilots
  keep their last decision, and the next call waits a second of game
  time.

## The model

[models/river.json](../riverrace_api/models/river.json) holds the types:
`Sense` (the sensors, see [Strategies](strategies.md)) and `Act` (`steer`,
`throttle`, `fire`). For each pilot the API adds
([lib/strategy.dart](../riverrace_api/lib/strategy.dart)):

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
that fired; the API reports it as the rule's number, or 0 for the else
row it added, with the rule's why.

## Verified

- `dart test` in `riverrace_api/`: requests checked and refused, the
  tables built, the answers read.
- `bash scripts/model-test.sh` runs strategies on aityx: the first
  matching rule fires, an enum list cell (`left, right, ahead`) matches,
  and with nothing matching the else row does.
- `flutter test` in `riverrace_app/`: the game (same seed, same river; no
  dead ends; crashes; fuel; the player's controls; the senses match what
  the API checks), and the preset strategies flown for a minute on four
  rivers with a local stand-in for aityx's FIRST tables: they pass
  bridges and score, and Careful goes further than Rookie.

## Known limitations

- About 3 to 6 calls a second while the race runs; the calls panel keeps
  the latest 120.
- In real time, how well a pilot does depends on aityx's latency too.
