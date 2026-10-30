# Patterns

aityx recognizes the well-known patterns of Life among the clusters of
live cells, from a catalogue in the Life model, and the app labels them
on the board and notifies when one appears.

## The catalogue

The patterns Wikipedia's
[Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life)
page lists, seeded in [seeds.dart](../cellfie_app/lib/life/seeds.dart):

| Kind | Patterns |
|---|---|
| Still lifes | block, beehive, loaf, boat, tub |
| Oscillators | blinker (period 2), toad (2), beacon (2), pulsar (3), penta-decathlon (15) |
| Spaceships | glider, light-weight, middle-weight and heavy-weight spaceship (all period 4) |
| Methuselahs | R-pentomino, diehard, acorn (recognized as seeded, before they grow) |

`dart run tool/catalogue.dart` (in `cellfie_app/`) runs each seed by
Conway's rules for its period and writes one row per distinct phase into
the model's `identify` table
([models/life.json](../cellfie_app/assets/models/life.json)): 37 rows for the
17 patterns. Each row matches the cell count, the width, the height and
the shape (a comma list when several phases share a size), outputs the
pattern, and says which pattern and phase it is in its `# why`; the else
row answers `unknown`. The `kind_of` table maps each pattern to its kind
(`still_life`, `oscillator`, `spaceship`, `methuselah`) and describes it
in its `# why`, which is what the notices say. A test checks the model's
table is what the tool generates (`--check` does too), so the app's
shapes and the model's rows can't drift.

## Shapes

A cluster's shape (`canonicalShape`) is its cells as rows of `o` (alive)
and `.` (dead) joined by `/`, from the top left of its bounding box, in
the one of its 8 turned and flipped forms that sorts first, with that
form's width and height. A glider reads `..o/o.o/.oo` whichever way it
flies, a blinker `o/o/o` standing or lying, so the catalogue needs one row
per phase, not per direction. Clusters are cells within two of each
other, so a beacon's two blocks, or a pulsar's four arms, are one cluster.

## On the board

Each cluster aityx recognized is outlined in amber on the board, with
the pattern's name above it, until the next generation. The app keeps how
many of each pattern the last generation had; when a generation has more,
a notice appears over the board for 8 seconds, `Generation 12: A glider
appeared` (or `2 blocks appeared`), with what the pattern is under it, and
goes into **Patterns noticed** at the top of the [calls panel](calls-panel.md).
The counts start over on **Random start** and **Clear**.

## Verified

`bash scripts/model-test.sh` sends every shape of the catalogue to aityx
and checks each comes back as its pattern with a kind and a description,
and that other shapes come back unknown. The app's tests check the
canonical shape is the same for a glider turned, flipped and moved; a
widget test checks a blinker drawn by hand is noticed.

## Known limitations

- Only whole, isolated patterns are recognized: two patterns within two
  cells of each other are one cluster, unknown; a glider leaving a soup
  is recognized once it's clear of it.
- Guns and the infinite-growth patterns aren't in the catalogue.
- Diehard's two halves are three cells apart, so on the board it's two
  clusters and is never recognized; it's in the catalogue, and the Zoo
  places it, all the same.
- A pattern is noticed when its count goes up, so one that moves is not
  noticed again; a pattern gone is not announced.
