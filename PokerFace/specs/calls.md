# The aityx calls

Every decision at the table is one call to aityx, and the sidebar shows
them all, newest first, under the **aityx calls (n)** tab
([CallsPanel](../pokerface_app/lib/sidebar/calls_panel.dart)). Each
entry says:

- its number, the player and their strategy, the hand and the street;
- the situation in a line, in monospace: the hole cards, the board, the
  made hand, the equity, what there is to call out of what pot, and the
  pot odds;
- while aityx decides, "Asking aityx…" with a spinner;
- then the action played, as a colored badge (fold gray, check and call
  green, raise orange, all in red) with its amount, the rule of the
  action table that fired, the rule's reason (its `why`), how long aityx
  took, and in amber the table's note when the decision was made legal
  (see [The table](table.md));
- or, in red, what went wrong (the API's error, which for a strategy
  written in the app carries aityx's validation message).

Tapping an entry opens the whole call full screen:
[AityxCallView](../pokerface_app/lib/calls/aityx_call_view.dart), the
same viewer as Contact Hub's, with the request (`POST /v1/systemone` as
the API sent it) and the response, pretty-printed, numbered and colored,
and the key parts highlighted and listed in a **Jump to** bar, each with
a line that explains it when jumped to:

| Side | Part | Why it matters |
|---|---|---|
| request | `decision.inputs` | The situation, declared: everything a strategy may look at |
| request | `decision.decisions` | The strategy's rules |
| request | `decision.decisions.action` | The action table, tried top to bottom |
| request | `decision.decisions.action.table.<rule>` | The row that fired |
| request | `decision.decisions.raise_to` | The raise amount's expression |
| request | `state` | The situation as the app computed it |
| request | `state.equity`, `state.pot_odds` | The two numbers most rules turn on |
| response | `answers.action`, `answers.raise_to` | What aityx answered |
| response | `receipt.decisions.action` | Which row fired, and which cells matched |

**Copy request**, **Copy response** and **Copy section** put the JSON on
the clipboard.

## The hand log

The sidebar's second tab, **Hand log**
([LogPanel](../pokerface_app/lib/sidebar/log_panel.dart)), tells the
hands' story newest first: each hand's header (number, button, blinds)
in orange, the deal and the streets in amber, every action in plain
text, the showdown and who won what in green, and players sitting down,
leaving, busting out, new levels and the tournament's end in gray. An
action's line has an arrow and expands when tapped into why the player
did it: the strategy and the rule that fired with its why; the rule's
conditions, each with the value the situation had for it (`equity >=
0.5 ← 0.78`); the table's note when the decision was made legal; the
situation as chips (cards and board, street and position, hand class,
made hand, draws, equity, pot, to call and pot odds, bet and raises,
stack, minimum and maximum raise, players in hand and after, the random
number); the strategy's own decisions with their values; and **The whole
call**, which opens the viewer above.

## Known limitations

- The calls live in memory, for the session; nothing is stored or
  exported.
- The list grows without bound; a long session has thousands of entries.
