# Players and strategies

**Players (n)** in the controls opens the panel
([PlayersPanel](../pokerface_app/lib/players/players_panel.dart)) as a
dialog with three parts.

## At the table

One card per seat: the name, which opens the player's rules (below); the
stack, the net result (chips now minus the starting stack), hands won of
hands played, the place once out, and "leaving" when a removal waits for
the end of the hand; a dropdown to change the player's strategy, which
counts from their next decision; and a remove button. A player removed
during a hand leaves after it.

## A player's rules

Tapping a seat at the table, or a name in the panel, opens the player's
rules ([rules_sheet.dart](../pokerface_app/lib/players/rules_sheet.dart)):
the strategy's tagline, then its action table one rule a row, numbered,
each with its conditions as chips (`street = preflop`, `hand in premium,
strong`, `equity >= 0.5`), its action as a colored badge, and its why; the
last rule, with no conditions, is "otherwise". Each rule has up, down and
remove buttons, since the first match wins. **Add a rule** takes any
number of conditions (a name to test, picked from the table's columns,
the strategy's own decisions and the situation's inputs, and the
condition: a value, alternatives, a range or an expression), the action
and the why; the new rule goes in above the "otherwise" rule. Below, the
raise expression can be edited, and the strategy's other decisions are
listed with their expressions. **Try it on aityx** runs the rules as
they stand on the sample situation; **As JSON** opens the editor;
**Remove <name>** takes the player off the table.

**Save** keeps the changes for that player only: the first save gives
them a strategy of their own, "<Name>'s <Strategy>" (Rocky's Rock),
based on the one they played and marked "yours" in the strategies list,
and the preset stays as it is; later saves change it in place. The sheet
says which of the two will happen. A strategy whose action is an
expression rather than a table can only be edited as JSON.

## Add a player

A name (suggested from the strategy: Rocky, Max, Sunny, Ada, Finn, with a
number when taken), the strategy, and **Add**. The strategy's tagline
shows under the form. Up to nine seats. A player added during a hand is
dealt in at the next. When the app starts at an empty table it seats one
player per preset.

## Strategies

Every strategy known to the app, the presets from the API first, then
those written in the app (marked "yours"), each with its tagline and a
button: **Rules** opens a preset's rules, **Edit** a custom strategy's.
**Write one** starts a new strategy from the first preset, named after it
("My Maniac"); a custom
strategy can be deleted when no player uses it.

The editor
([strategy_editor.dart](../pokerface_app/lib/players/strategy_editor.dart))
shows the strategy as JSON in a monospace text field: its `name`,
`tagline` and `decisions` (see [Strategies](strategies.md) for what they
can say). A preset's rules can be read and changed there, but saving
always makes a strategy of your own (**Save as mine**); a custom one is
saved in place (**Save**). Saving checks the JSON and that `decisions` has
an `action` and a `raise_to`; anything else aityx checks on the first
call, and its message comes back through the API. **Try it on aityx**
sends the rules as they are in the editor with a sample situation (A♥ K♦
on K♠ 7♣ 2♦: top pair, 40 to call into a pot of 120, 78% equity) and
shows the action, the rule that fired and its reason, or aityx's error,
so the rules can be fixed before a player uses them.

Strategies written in the app are sent to the API whole with every
decision; the presets are sent by id.

## Known limitations

- Custom strategies live in the browser tab; reloading loses them. Copy
  the JSON out to keep one.
- The editor is a text field, not a structured one: no autocompletion of
  the situation's inputs.
