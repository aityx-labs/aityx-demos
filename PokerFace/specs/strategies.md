# Strategies

A player's strategy is a decision model run on aityx: the `decisions` of
the table model, run on the player's situation as the state. The models
are the app's assets, in
[pokerface_app/assets/models/](../pokerface_app/assets/models), read with
`rootBundle`: [table.json](../pokerface_app/assets/models/table.json)
holds the shared part, the `types` and `inputs` (what a player sees), and
each file in [strategies/](../pokerface_app/assets/models/strategies) one
strategy: its `id` (the file's name), `name`, `tagline` and `decisions`.
For each call the app composes `decision = {name, types, inputs,
decisions}` with the situation as `state` (see [Deciding on
aityx](aityx.md)).

## The situation: what a strategy sees

The inputs of table.json, computed by the app at each turn:

| Input | Type | Meaning |
|---|---|---|
| `street` | preflop, flop, turn, river | The betting round |
| `position` | early, middle, late, blinds | By the order of play this round: the first third early, the last third late (the button among them); the blinds before the flop |
| `hole`, `board` | lists of cards, `Ah`, `Td` | The player's cards and the community cards, for reading; the rules use the inputs below |
| `hand` | premium, strong, medium, speculative, weak | The hole cards' class: premium AA KK QQ AKs; strong JJ TT AKo AQs AJs KQs; medium 99–77, AQo AJo ATs KQo KJs QJs JTs; speculative small pairs, suited connectors, suited aces, KTs QTs J9s T8s; weak the rest |
| `made_hand` | high_card … straight_flush | The best five-card hand now (before the flop: pair or high card) |
| `flush_draw` | boolean | Four to a flush with cards to come |
| `straight_draw` | none, gutshot, open_ended | A straight draw with cards to come: one rank completes it, or two or more |
| `equity` | 0..1 | The chance of winning at showdown against the players still in, by 200 random run-outs |
| `pot` | chips | In the pot, this round's bets included |
| `current_bet` | chips | The highest bet this round |
| `to_call` | chips | What the player must add to stay in (capped at their stack) |
| `pot_odds` | 0..1 | `to_call / (pot + to_call)`: the share of the pot a call costs; 0 when checking is free |
| `can_check`, `can_raise` | boolean | Whether a check is free, and whether a raise is possible (chips beyond the call and someone left to raise) |
| `raises` | count | Bets and raises this round before the player's turn (the blinds don't count) |
| `stack`, `stack_bb` | chips, big blinds | Chips behind |
| `big_blind` | chips | The big blind at the current level |
| `min_raise`, `max_raise` | chips | The smallest and largest total bet a raise can be made to (all in) |
| `players_in_hand`, `players_after` | count | Still in the hand (the player included); still to act after the player this round |
| `random` | 0..1 | Drawn for this decision, so a strategy can mix its play |

The app checks every input (presence, type, range) before calling aityx.

## The rules: what a strategy says

`decisions` must have:

- `action`: type `Action` (fold, check, call, raise, all_in), as a
  decision table over the situation and the strategy's own decisions. The
  header lists the columns, rows are objects with `when` (only the
  columns tested: `"true"`, `"preflop"`, `"premium, strong"`, `">= 0.5"`,
  `"<= 3 * big_blind"`), `then` the action, and `why` the reason the app
  shows. Rows are tried top to bottom, the first match wins, and the last
  row has no `when`: the else row.
- `raise_to`: type number, an expression for the total bet when raising,
  for instance `if street = "preflop" then (if raises = 0 then 3 *
  big_blind else 3 * current_bet) else decimal(pot * 0.66, 0)`. The table
  keeps it between `min_raise` and `max_raise`.

and may have any other decisions the action table needs, by name:
booleans like `profitable_call: equity > pot_odds`, numbers like `edge:
equity - pot_odds`, coin flips like `bluffing: random < 0.5`. The
expression language is aityx's (`and`, `or`, `not()`, `if then else`,
arithmetic, comparisons, `decimal`), documented at
[aityx.ai/docs/resources/model-format](https://aityx.ai/docs/resources/model-format).

## The presets

| Strategy | In short |
|---|---|
| [The Rock](../pokerface_app/assets/models/strategies/rock.json) | Raises premium cards, opens strong ones and calls one raise with them, folds everything else (checks a free flop). After the flop bets two pair or better, calls with a pair likely best, never bluffs. Opens 3 BB, re-raises 3×, bets half the pot |
| [The Maniac](../pokerface_app/assets/models/strategies/maniac.json) | Raises almost anything before the flop (folds weak cards to two raises only when the coin says no bluff). After the flop bets any pair or draw, bluffs when `random < 0.5`, calls three times in ten with nothing. Opens 4 BB, re-raises 3.5×, bets the pot |
| [The Calling Station](../pokerface_app/assets/models/strategies/station.json) | Calls to see what happens: before the flop up to ten big blinds with weak cards, after it unless hopeless (under 10% equity against a bet over half the pot). Raises the minimum, and only with a straight or better |
| [The Mathematician](../pokerface_app/assets/models/strategies/mathematician.json) | Pot odds: calls when `equity > pot_odds`, bets or raises when the edge is 20 points or more (or 60% equity when a check is free), folds otherwise; never bluffs. Opens 3 BB, re-raises 3×, bets two thirds of the pot |
| [The Shark](../pokerface_app/assets/models/strategies/shark.json) | Tight and aggressive: raises premium and strong cards, opens medium ones and calls a raise with them in position, calls cheap with speculative ones, steals from late position three times in five. After the flop bets for value (two pair or better, or a pair with 60% equity), semi-bluffs flush draws and open-enders when nobody has bet, continuation-bets two times in three against few players, calls when the odds say so with at least 30% equity. Opens 2.5 BB, re-raises 3×, bets two thirds of the pot |

## Verified

`bash scripts/model-test.sh` runs
[model_scenarios_test.dart](../pokerface_app/test/model_scenarios_test.dart)
on aityx, with the key from the repository's root `.env`: every strategy answers with a rule that fired, and each one
plays its character in fixed situations (the Rock's premium raise and
strong call, the Maniac's coin, the Station's ten-big-blind limit and
hopeless fold, the Mathematician's call at 30% equity against 25% pot
odds and fold against 40%, the Shark's steal, semi-bluff and position).
The app's tests ([table_test.dart](../pokerface_app/test/table_test.dart))
also check that every action table's rows test only columns in its header
and end with an else row.

## Known limitations

- `raises` counts the player's own earlier bets too, and nothing says who
  the preflop aggressor was; the Shark's continuation bet is approximated
  by "nobody has bet yet on the flop against few players".
- `equity` is against random hands, not against the ranges the others'
  actions imply.
