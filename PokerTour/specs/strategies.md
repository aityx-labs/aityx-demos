# Strategies

A player's strategy is a decision model run on aityx: the `decisions` of
the table model, run on the player's situation as the state. The models
are the app's assets, in
[pokertour_app/assets/models/](../pokertour_app/assets/models), read with
`rootBundle`: [table.json](../pokertour_app/assets/models/table.json)
holds the shared part, the `types` and `inputs` (what a player sees), and
each file in [strategies/](../pokertour_app/assets/models/strategies) one
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
| [The Rock](../pokertour_app/assets/models/strategies/rock.json) | Tight and passive. Raises premium cards when nobody has, calls a raise with them; opens strong ones; calls one raise with strong or medium cards, or a small one (four big blinds) with speculative ones; limps medium and speculative cards for up to two big blinds; folds the rest (checks a free flop). Short-stacked, 25 big blinds or less, goes all in with any playable hand. After the flop bets two pair or better, never lets go of premium cards with a pair likely best (50% equity; not ace-king on a paired board), calls with a pair at 30% equity, never bluffs. Opens 3 BB, re-raises 3×, bets half the pot |
| [The Maniac](../pokertour_app/assets/models/strategies/maniac.json) | Raises almost anything before the flop, except junk (weak or speculative) with three or more players still to act, and weak cards against a raise when the coin (`random < 0.5`) says no bluff; folds anything but premium and strong cards to a re-raise, unless bluffing. After the flop bets any pair or draw when nobody has, raises it at 60% equity, calls it at 40%; bluffs on the coin when three players or fewer are left. Folds any call of 15% of its stack or more without 55% equity. Opens 4 BB, re-raises 3.5×, bets the pot |
| [The Calling Station](../pokertour_app/assets/models/strategies/station.json) | Calls to see what happens: before the flop up to four big blinds with weak cards, anything with the rest; after it unless hopeless (under 25% equity against a bet over 30% of the pot, or a call of a fifth of its stack without 50%). Raises the minimum, and only with three of a kind or better |
| [The Mathematician](../pokertour_app/assets/models/strategies/mathematician.json) | Pot odds: calls when `equity > pot_odds`, bets or raises when the edge is 30 points or more (or 70% equity when a check is free), folds otherwise; never bluffs. Opens 3 BB, re-raises 3×, bets two thirds of the pot |
| [The Shark](../pokertour_app/assets/models/strategies/shark.json) | Tight and aggressive: raises premium and strong cards, opens medium ones and calls a raise with them in position, calls cheap with speculative ones, at a table of three or fewer re-raises a single raise with medium cards out of position and with speculative ones when the raise costs more than three big blinds (punishing a loose opener; a cheaper one it calls), steals from middle or late position four times in five. After the flop bets for value (two pair or better, or a pair with 60% equity), semi-bluffs flush draws and open-enders when nobody has bet, continuation-bets four times in five against few players, calls when the odds say so with at least 30% equity. Opens 2.5 BB, re-raises 3×, bets two thirds of the pot |

## Balance

No preset dominates. They were tuned against each other on 2026-11-08
by simulation: the engine of [poker_core](../poker_core) playing
thousands of tournaments, with the rules evaluated locally instead of on
aityx, tables drawn as the leaderboard draws them (three to five of the
five, at random; 1000 chips, blinds up every ten hands). Each preset's
points and wins are measured against its fair share (the points and the
wins it would get if every strategy were as good, at the tables it sat
at; 1.00 is fair):

| Strategy | Points | Wins |
|---|---|---|
| The Rock | 1.17 | 0.86 |
| The Shark | 1.02 | 0.86 |
| The Mathematician | 1.01 | 1.08 |
| The Calling Station | 0.92 | 1.06 |
| The Maniac | 0.84 | 1.13 |

(1400 tournaments, equity from 30 run-outs to make thousands of
tournaments affordable; 100 run-outs gave the same picture. Before the
tuning, 700 tournaments measured the same way gave the Rock
1.35 points and 0.42 wins, the Mathematician 1.23 and 1.70, the Shark
1.20 and 1.39, the Maniac 0.65 and 0.96, the Station 0.52 and 0.54.)

Before, the Mathematician won 1.7 times its share and the Station got
half its points: the Station and the Maniac busted first, the Rock
outlasted them and the Mathematician and the Shark took the chips.
Now each has its weakness and its strength: the Rock still outlasts the
gamblers (it finishes second most often) but rarely wins heads-up; the
Maniac wins often once the table is short and busts early as often; the
Station, the Mathematician and the Shark sit in between. Luck decides
a single tournament: any of the five wins its share of them.

## Verified

`bash scripts/model-test.sh` runs
[model_scenarios_test.dart](../pokertour_app/test/model_scenarios_test.dart)
on aityx, with the key from the repository's root `.env`: every strategy answers with a rule that fired, and each one
plays its character in fixed situations (the Rock's premium raise and
strong call, cheap flop and short-stack all in; the Maniac's coin, its
bluff with few players left and its stack-saving fold; the Station's
four-big-blind limit, hopeless fold and stack-saving fold; the
Mathematician's call at 30% equity against 25% pot odds and fold
against 40%; the Shark's steal, semi-bluff, position and short-table
raise).
The app's tests ([table_test.dart](../pokertour_app/test/table_test.dart))
also check that every action table's rows test only columns in its header
and end with an else row.

## Known limitations

- `raises` counts the player's own earlier bets too, and nothing says who
  the preflop aggressor was; the Shark's continuation bet is approximated
  by "nobody has bet yet on the flop against few players".
- `equity` is against random hands, not against the ranges the others'
  actions imply.
