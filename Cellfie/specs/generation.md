# Generation

A generation is one call to aityx's `POST /v1/systemone`, through the
[API](api.md), with the Life model
([models/life.json](../cellfie_api/models/life.json)) as the `decision`
and what the app counted on the board as the `state`. No questions are
asked: the board is facts, and the rules decide.

## What the app counts

[board.dart](../cellfie_app/lib/life/board.dart):

- **Situations** (`situationsOf`): the live neighbours of every cell that
  has any are counted cell by cell; then every live cell, and every dead
  cell with at least one live neighbour, is grouped by its situation,
  *alive or not* × *0 to 8 neighbours*: at most 18 groups, live ones
  first, then by neighbours. Each is sent as
  `{"alive": true, "neighbours": 2, "cells": 9}`. Dead cells with no live
  neighbour, the rest of the infinite board, are left out: the rules keep
  them dead.
- **Clusters** (`clustersOf`): live cells within two cells of each other
  (so one empty cell between them, as in a beacon or a pulsar, keeps them
  together), top to bottom, left to right; each sent with its cell count
  and its canonical shape, with the shape's own width and height (see
  [Patterns](patterns.md)).
- The **generation** number, and the **rules** that are on.

## The Life model

A native aityx model, `decision`-only:

- `types`: `Fate` (`survives|dies_lonely|dies_crowded|is_born|stays_empty`),
  `Situation`, `Pattern`, `Kind` and `Cluster`.
- `inputs`: `generation`, `rules` (the switches, see [Rules](rules.md)),
  `situations` (a list of `Situation`) and `clusters` (a list of
  `Cluster`).
- `functions.fate(alive, neighbours, conway, highlife, no_death)`: the
  rules as a FIRST decision table with a `# why` on every row, each
  rule's rows gated by its switch; Conway's, as Wikipedia states them:

  | conway | alive | neighbours | fate | why |
  |---|---|---|---|---|
  | true | true | < 2 | dies_lonely | Underpopulation |
  | true | true | [2..3] | survives | Survival |
  | true | true | > 3 | dies_crowded | Overpopulation |
  | true | false | 3 | is_born | Reproduction |
  | - | true | - | dies_no_rule | No enabled rule keeps the live cell alive |
  | - | - | - | stays_empty | A dead cell no enabled rule brings to life stays dead |

  with Life without death's and HighLife's rows above them (see
  [Rules](rules.md)).
- `functions.identify(cells, width, height, shape)` and
  `functions.kind_of(pattern)`: the pattern catalogue (see
  [Patterns](patterns.md)).
- `decisions`: `fates` (`for s in situations return fate(s.alive,
  s.neighbours, rules.conway, rules.highlife, rules.no_death)`), `alive_next` (survives or is born, per situation),
  `population`, `population_next`, `births`, `deaths` and `survivors`
  (sums of the cells of the situations with that fate), `next_generation`,
  and `patterns`, `kinds` and `recognized` for the clusters. The sums are
  0 on an empty board.

aityx answers the lists as `value`s and the counts as `number`s, and its
receipt holds, under `functions.fate`, one entry per call to `fate` in
the order of the situations, with the `rule` (the 1-based row) that
fired; likewise `functions.identify` and `functions.kind_of` per cluster.
The API turns that into the fate of each situation with its rule and
why, and the pattern of each cluster with the row that matched and what
the pattern is.

## The next board

`Board.next` keeps the cells of every situation aityx answered alive for,
in the order sent, and marks those of dead situations as born. The
generation counts up. The clusters aityx recognized become the labels on
the board, and the patterns noticed are updated (see
[Patterns](patterns.md)). The call goes to the [panel](calls-panel.md).

## Verified

`bash scripts/model-test.sh` runs the model on aityx
([model_scenarios_test.dart](../cellfie_api/test/model_scenarios_test.dart)):
all 18 situations against Conway's rules, with the counts; HighLife, Life
without death and no rule on; every shape in the catalogue recognized;
shapes that aren't, unknown; an empty board.
The API's unit tests read a real answer
([generation-7.json](../cellfie_api/test/fixtures/generation-7.json)).
The app's tests check the counting on a blinker, a block, a glider and
a beacon, and that Conway's rules, run locally for the tests, turn a
blinker.

## Known limitations

- Every generation is a round trip to aityx (about half a second from
  here), which is the point: *as fast as aityx answers* is a few
  generations a second.
- The board's own numbers (positions) never leave the app: aityx sees
  situations and shapes, not coordinates.
