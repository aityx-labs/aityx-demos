# Rules

The rules of the game are rows of the fate table in the Life model
([models/life.json](../cellfie_app/assets/models/life.json), `functions.fate`),
and each rule has a switch: a boolean in the request's `state.rules`,
which is a column of the table, so a row fires only when its rule is on.

| Rule | `state.rules` | Rows | On at start |
|---|---|---|---|
| Conway's rules | `conway` | B3/S23: a dead cell with three live neighbours is born; a live cell with two or three lives on, and dies of loneliness (fewer) or crowding (more) | yes |
| HighLife birth | `highlife` | B6: a dead cell with exactly six live neighbours is also born, which lets replicators grow | no |
| Life without death | `no_death` | a live cell never dies, whatever its neighbours: patterns only grow, into ladders and lace | no |

The table, in order: Life without death's survival row, HighLife's
birth row, Conway's four rows, then two else rows: a live cell no
enabled rule keeps alive dies (`dies_no_rule`), and a dead cell none
brings to life stays dead. With every rule off, the board empties in one
generation.

The app lists the same rules ([rules.dart](../cellfie_app/lib/life/rules.dart))
with a name and a one-line summary, and sends every switch with every
generation, Conway's alone on until changed. `stateFrom`
([lib/aityx/life.dart](../cellfie_app/lib/aityx/life.dart)) fills in the
defaults for a body that doesn't say (see [aityx calls](aityx-calls.md)).

## In the app

**Rules (1 of 3)** in the controls bar opens the **Rules** dialog: a
checkbox per rule, with its summary, and a line explaining that each is
rows of the table aityx runs. A change applies from the next generation
on, also while playing; the button's count says how many are on. The
pattern catalogue is Conway's: with other rules on, a shape is still
named when it matches, whatever it does next.

## Verified

`bash scripts/model-test.sh` runs on aityx: HighLife bringing a dead
cell with six neighbours to life, Life without death keeping a cell with
no neighbours and one with eight, and no rule on emptying the board. A
widget test switches Life without death on in the dialog and checks the
next request carries it; a unit test checks the app's rules are the
model's `Rules` type and columns of the fate table, with Conway's alone
on.

## Known limitations

- The switches are the rules the model has: a new rule is rows in the
  model and an entry in the app's list, not something typed in the app.
