# Players and strategies

**Players (n)** in the controls opens the panel
([PlayersPanel](../pokertour_app/lib/players/players_panel.dart)) as a
dialog with three parts.

## At the table

One card per seat: the name, which opens the player's rules (below); the
stack, the net result (chips now minus the starting stack), hands won of
hands played, the place once out, and "leaving" when a removal waits for
the end of the hand; a dropdown to change the player's strategy, which
counts from their next decision; and a remove button. A player removed
during a hand leaves after it.

## A player's rules

A seat playing another player's strategy from the tour (sealed, below)
opens no rules: a dialog says which strategy it plays, its tagline, and
that its rules are its owner's.

Tapping a seat at the table, or a name in the panel, opens the player's
rules ([rules_sheet.dart](../pokertour_app/lib/players/rules_sheet.dart)):
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

Every strategy known to the app: the presets (the app's
[assets/models/strategies/](../pokertour_app/assets/models/strategies))
first, then the tour's (the strategies players entered, read from the
server once signed in, with "In the tour, by <alias or name>" in their
tagline; not the server's copies of the presets, so no preset is listed,
or seated by a random tournament, twice),
then those written in the app, each with its tagline and buttons:
**Rules** opens a preset's rules, **Edit** a custom strategy's;
**Download as JSON** saves the strategy's `name`, `tagline` and
`decisions` as a file (`<name>.json`), to start from or to upload; the trophy, on
one written in the app, enters it in the tour ([The tour](tour.md)). **Write one**
starts a new strategy from the first preset, named after it ("My
Maniac"); a custom strategy can be deleted when no player uses it. The
player's own, written in the app or entered in the tour, are marked
"yours".

Another player's strategy from the tour is **sealed**
(`Strategy.sealed`, set by `tableStrategies` in
[main.dart](../pokertour_app/lib/main.dart) for every entry whose owner
id isn't the signed-in player's, and for all of them until `GET
/api/me` has answered): it can be seated and plays like any other, but
its row has a lock instead of **Edit**, and no download or delete. Its
rules still reach the browser, since the table runs them on the
player's key, and every call in the calls sidebar shows them; the app
just doesn't offer to open or save them.
Signed in to the tour, **Upload a strategy** beside it picks a strategy
file and enters it, as Profile's does ([The sidebar and the
profile](profile.md)).

The editor
([strategy_editor.dart](../pokertour_app/lib/players/strategy_editor.dart))
shows the strategy as JSON in a monospace text field: its `name`,
`tagline` and `decisions` (see [Strategies](strategies.md) for what they
can say). A preset's rules can be read and changed there, but saving
always makes a strategy of your own (**Save as mine**); a custom one is
saved in place (**Save**). Saving checks the JSON and that `decisions` has
an `action` and a `raise_to`; anything else aityx checks on the first
call, and its message reaches the editor ([Deciding on
aityx](aityx.md)). **Try it on aityx**
sends the rules as they are in the editor with a sample situation (A♥ K♦
on K♠ 7♣ 2♦: top pair, 40 to call into a pot of 120, 78% equity) and
shows the action, the rule that fired and its reason, or aityx's error,
so the rules can be fixed before a player uses them. **Enter it in the
tour** saves the rules as a strategy of yours and sends them to the
server, which checks them on aityx the same way and seats them from the
next tournament; its answer shows in the editor.

Every decision sends aityx the strategy's rules whole, a preset's or a
custom one's; the app checks a custom one as the presets are checked
(a name of up to 60 characters, `decisions.action` and
`decisions.raise_to`) before the call.

## Known limitations

- Custom strategies live in the browser tab; reloading loses them.
  Download one, or enter it in the tour, to keep it.
- The editor is a text field, not a structured one: no autocompletion of
  the situation's inputs.
