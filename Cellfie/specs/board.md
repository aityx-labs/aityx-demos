# Board

[LifeScreen](../cellfie_app/lib/life/life_screen.dart) is the app's one
screen: the controls bar, the board, and (on windows 1000 px wide or more)
the [calls panel](calls-panel.md) on the right, 440 px wide; on narrower
windows the panel opens from **Calls (n)** in the app bar, as a drawer.

## The infinite board

[Board](../cellfie_app/lib/life/board.dart) is a sparse set of live cells
on an unbounded integer grid (y grows downwards), with the generation
number and the cells born in it. [BoardView](../cellfie_app/lib/life/board_view.dart)
draws it on a canvas through a camera (the cell at the view's center and
the pixels per cell, 2 to 64, 14 at first):

- live cells in orange, those born in the last generation in green, with
  a hairline gap once a cell is 6 px or more;
- a grid once a cell is 7 px or more; the axes through the origin always,
  so it can be found again;
- the patterns aityx recognized outlined in amber with their name (see
  [Patterns](patterns.md));
- a legend at the bottom left, and, over an empty board, the hint
  "Press Random start, or tap cells to draw. Drag to move around the
  infinite board; scroll to zoom."

Drag to move; the mouse wheel, a trackpad pinch or the **Zoom** buttons
zoom around the pointer (the buttons, around the center); the **Back to
the origin** button resets the view. Tap a cell to flip it, alive or dead,
also while playing: a cell flipped while aityx is answering is applied
again on top of its answer.

## Controls

The bar above the board, wrapping on narrow windows:

- **Play** / **Pause**: runs generations one after the other (see
  [Generation](generation.md)) until paused, or until the board is empty,
  or a generation fails (then a message says why).
- **Step**: one generation; disabled while playing or while one runs.
- **Random start**: a menu of starts over the cells in view (at most 100
  × 70), at generation 0; the patterns noticed start over
  ([startBoard](../cellfie_app/lib/life/board.dart)):
  - **Sparse soup**, **Soup** and **Dense soup**: each cell alive with
    probability 0.12, 0.35 and 0.6;
  - **Islands**: 4 to 16 discs (one per 600 cells in view) of radius 3 to
    6, each cell in them alive with probability 0.55;
  - **Glider fleet**: 3 to 20 gliders (one per 400 cells), each turned or
    flipped at random, placed where no other cell is within two cells;
  - **Zoo**: one of each pattern in the catalogue
    ([seeds.dart](../cellfie_app/lib/life/seeds.dart)), turned or flipped
    at random, placed the same way; a pattern that finds no room in 40
    tries, or doesn't fit the view, is left out;
  - **R-pentomino** and **Acorn**: the seed alone, in the middle.
  Each item shows a one-line summary.
- **Clear**: empties the board, generation 0.
- **Acceleration**: a slider with six stops: ½, 1, 2 (the default), 4 and
  8 generations per second, and *as fast as aityx answers*. A generation
  that takes longer than its slot runs late, never twice at once.
- **Rules (n of 3)**: opens the [Rules](rules.md) dialog.
- **Zoom out**, **Zoom in**, **Back to the origin**.
- The status: `Generation N · M cells · aityx answered in T ms` (or
  `asking aityx…` while it is).

## Verified

Widget tests draw a blinker by tapping, step it through a fake aityx and
check the request (5 situations, one 1 × 3 cluster, Conway's rules
alone), the next board, the call in the panel and the notice; switch a
rule on in the dialog and see it in the next request; play at 2 generations/s until paused;
a failed generation pausing with its message; the random start menu,
a soup, and Clear; and the calls drawer on a 390 px phone.

## Known limitations

- The board is unbounded, but the view is where you take it: a glider
  flies out of sight unless followed.
- A generation with many clusters sends the first 24 (top to bottom)
  that are at most 64 cells wide and high; the rest are not identified.
- No keyboard shortcuts.
