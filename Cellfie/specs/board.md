# Board

[LifeScreen](../cellfie_app/lib/life/life_screen.dart) is the app's one
screen: a single row at the top, the title on the left and the
[controls](#controls) on its right, then the board, and (on windows 1000
px wide or more) the [calls panel](calls-panel.md) on the right, 440 px
wide. On narrower windows the panel opens as a drawer from the calls
button at the end of the top row (its tooltip `Calls (n)`, the count as a
badge once there are calls). The app's version isn't shown.

## The infinite board

[Board](../cellfie_app/lib/life/board.dart) is a sparse set of live cells
on an unbounded integer grid (y grows downwards), with the generation
number and the cells born in it. [BoardView](../cellfie_app/lib/life/board_view.dart)
draws it on a canvas through a camera (the cell at the view's center and
the pixels per cell, 2 to 64, 14 at first):

- live cells in orange, those born in the last generation in green, and
  those that died in it in grey (for that one generation; a cell drawn
  back to life over one shows orange), with a hairline gap once a cell
  is 6 px or more;
- a grid once a cell is 7 px or more; the axes through the origin always,
  so it can be found again;
- the patterns aityx recognized outlined in amber with their name (see
  [Patterns](patterns.md));
- a legend at the bottom left (alive, born this generation, died this
  generation, pattern aityx recognized), and, over an empty board, the
  hint
  "Press Random start, or tap cells to draw. Drag to move around the
  infinite board; scroll or pinch to zoom.";
- the map buttons at the bottom right, as on an online map: **Back to the
  origin** on its own, and under it **Zoom in** (+) and **Zoom out** (−)
  together;
- without the calls panel (narrower windows), the status at the top
  right (see [Controls](#controls)).

The board opens with a **Sparse soup** over the cells in view (see
**Random start** below), so **Play** is all it takes to start.

Drag to move. Zoom with the mouse wheel, a pinch on a touch screen or a
trackpad (in the browser, too), or the + and − buttons: gestures zoom
around the pointer or the fingers, the buttons around the center. **Back
to the origin** resets the view. Tap a cell to flip it, alive or dead,
also while playing: a cell flipped while aityx is answering is applied
again on top of its answer.

## Controls

On the right of the title. Where the window leaves them less than 900 px,
the buttons are icons, their labels as tooltips; where even that doesn't
fit (a phone), the row scrolls sideways, starting at **Play**:

- **Play** / **Pause**: runs generations one after the other (see
  [Generation](generation.md)) until paused, or until the board is empty,
  or a generation fails (then a message says why).
- **Step**: one generation; disabled while playing or while one runs.
- **Random start**: a menu of starts over the cells in view (at most 100
  × 70), at generation 0; the patterns noticed start over
  ([startBoard](../cellfie_app/lib/life/board.dart)):
  - **Sparse soup**, **Soup** and **Dense soup**: each cell alive with
    probability 0.06, 0.35 and 0.6;
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
- **Rules (n of 3)**: opens the [Rules](rules.md) dialog.
- **Acceleration**: a slider (its tooltip *Acceleration*) followed by the
  speed, `1 generation/s`, with no label before it. Six stops: ½, 1 (the
  default), 2, 4 and 8 generations per second, and *as fast as aityx
  answers*. A generation that takes longer than its slot runs late, never
  twice at once.

The status, `Generation N · M cells · aityx answered in T ms` (or
`asking aityx…` while it is), is in the calls panel, under its title;
without the panel, over the board at the top right.

## Verified

Widget tests draw a blinker by tapping, step it through a fake aityx and
check the request (5 situations, one 1 × 3 cluster, Conway's rules
alone), the next board, the call in the panel and the notice; switch a
rule on in the dialog and see it in the next request; play at 1 generation/s until paused;
a failed generation pausing with its message; the app opening on a
sparse soup, with the buttons as icons, the map buttons and the status
over the board at 800 px; the random start menu, a soup, and Clear; and
the calls drawer on a 390 px phone.

## Known limitations

- The board is unbounded, but the view is where you take it: a glider
  flies out of sight unless followed.
- A generation with many clusters sends the first 24 (top to bottom)
  that are at most 64 cells wide and high; the rest are not identified.
- No keyboard shortcuts.
