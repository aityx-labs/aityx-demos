# The table

[TableScreen](../pokerface_app/lib/table/table_screen.dart) is the app's
one screen: the table with its controls, and beside it, on a window at
least 1100 px wide, the sidebar of [aityx calls](calls.md); narrower, the
sidebar opens from the app bar's receipt icon as a bottom sheet. The app
bar says **PokerFace**, "every player is a set of rules, run on aityx",
and the build's version when the build sets `POKERFACE_VERSION`.

## What the table shows

[TableView](../pokerface_app/lib/table/table_view.dart), in the style of
the online poker rooms: a green felt with a wooden rail, and the seats on
an ellipse around it, the first seat at the bottom, clockwise. In the
middle: the hand number and the street (or, between hands, who won what,
or what to do: "Press play to deal."; once the tournament is over, who
won it), the five board slots with the community cards as they come, the
pot as a pile of chips with its amount, and the level with its blinds and
how many hands until they go up. Each seat
([avatar.dart](../pokerface_app/lib/table/avatar.dart)) shows the
player's avatar, their strategy's face in a ring of the seat's color (🪨
the Rock, 🤪 the Maniac, 📞 the Calling Station, 🧮 the Mathematician, 🦈
the Shark, 🎭 a strategy written in the app), their two hole cards fanned
beside it (everyone's cards are face up: it is a simulator, and the point
is to judge the rules), a small pile of chips for their stack, and a
plate with their name, their strategy, their stack in amber, and their
last action ("Raises to 120", "Calls 40", "Folds", "Checks", "All in,
960", or the hand shown at the showdown). The player to act has an orange
ring and glow while aityx decides; a folded player's cards are dimmed; the
winners of a hand get an amber ring and "wins"; a player out of the
tournament is grayed, with their place. The bet of the round sits between
the seat and the board as a pile of chips with its amount, the dealer
button beside it as a white "D". Chips are drawn in casino colors
([chips.dart](../pokerface_app/lib/table/chips.dart)): 1 white, 5 red, 25
green, 100 black, 500 purple, 1000 amber, one column per denomination,
with at most a couple of dozen chips in a pile, the small ones dropped
first. Tapping a seat opens the player's rules ([Players and
strategies](players.md#a-players-rules)).

## The rules of the game

[PokerGame](../pokerface_app/lib/engine/game.dart) plays a tournament,
one step at a time: blinds and the deal, a decision, a street dealt, the
showdown, the end of the hand. Everyone starts with 1000 chips. The
blinds go up every 10 hands through the levels 5/10, 10/20, 15/30, 25/50,
50/100, 75/150, 100/200, 150/300, 200/400, 300/600, 400/800, 500/1000,
750/1500 and 1000/2000, where they stay; the log notes each new level.
The button moves one seat each hand; heads up the button posts the small
blind and acts first before the flop. Before the flop the player after
the big blind acts first and the big blind has its option; after it, the
first player after the button. A bet or a full raise reopens the round
for everyone else; a raise is at least the size of the last one (the big
blind to start), and a raise for less is made the minimum, or all in when
the stack doesn't reach it. When nobody can act any more (all in, or all
but one), the board runs out. At the showdown every level of commitment
is a pot, shared by the best hand among the players who reached it, so
side pots are paid right and chips nobody matched go back; odd chips go
to the first winner after the button. When everyone else folds, the last
player takes the pot without a showdown. There are no rebuys: a player
out of chips is out of the tournament, with a place (those who bust in
the same hand share the place after everyone still in). When one player
has every chip the tournament is over: the table announces the winner
([winner_dialog.dart](../pokerface_app/lib/table/winner_dialog.dart)),
with their strategy and its tagline, the standings (place, name,
strategy, hands won), **The winner's rules**, and **New tournament**,
which starts everyone again with 1000 chips. A player added during a hand
is dealt in at the next (a late entry, with the full starting stack); one
removed during a hand leaves after it; one added after the tournament
ended starts a new one against the winner.

The hand evaluator ([evaluator.dart](../pokerface_app/lib/engine/evaluator.dart))
ranks any five, six or seven cards, with the wheel as a five-high
straight, and estimates a player's equity against the players still in
the hand by 200 random run-outs. It also classes the hole cards and spots
flush draws and straight draws, all for the [situation](strategies.md)
sent to aityx.

## What the strategy decides, made legal

The action aityx answers is played as it is when it is legal. Otherwise
the nearest legal action is played, and the call in the sidebar notes it:
a fold with nothing to call is a check; a call of nothing is a check; a
check facing a bet is a fold; a raise when none is possible (no chips
beyond the call, or nobody left to raise) is a call; a raise below the
minimum is made the minimum, and above the stack is all in.

## The controls

[ControlsBar](../pokerface_app/lib/table/controls_bar.dart), under the
table:

- **Play** / **Pause**: the table runs on its own, one step after
  another, each decision asked of aityx. It pauses by itself when a call
  fails (the error shows in a banner above the table) or when fewer than
  two players have chips.
- **Step**: one step while paused: a deal, a decision, a street, the end
  of a hand.
- The **pace slider**, slow on the left, fast on the right: the seconds
  between steps, from 4 s down to 0, "Full speed", where the only wait is
  aityx's answer. The end of a hand waits two and a half times as long,
  so the showdown can be read.
- **Players (n)**: opens [Players and strategies](players.md).
- **New tournament**: everyone starts again with 1000 chips; the hand
  count, the calls and the log start over.

## Known limitations

- No human seat: every player is a strategy. Everyone's cards are face
  up.
- The blind levels are counted in hands, not minutes, and there are no
  antes.
- The equity estimate is Monte Carlo with 200 run-outs, so it moves by a
  few points from one decision to the next in the same spot.
- The game lives in the browser tab: reloading the page starts over.
