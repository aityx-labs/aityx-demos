# Cellfie — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

Cellfie: every generation, the cells take a picture of themselves, and
aityx says who's in it. It plays Conway's Game of Life on an infinite board, with the rules
of Life (Conway's, and two variants that can be switched on), and a
catalogue of its well-known patterns, as a decision model on aityx. Every generation is one call to aityx: the app counts what is on
the board (every distinct situation a cell is in, and every cluster of
live cells with its shape), aityx decides what lives, what dies, what is
born and which clusters are patterns, and the app draws the next board,
labels the patterns, notifies of new ones, and shows every call, request
and response, in a side panel.

## Features

**App**

- [Board](board.md): the infinite board, drawn on a canvas; drag to move,
  scroll or pinch to zoom, tap to flip a cell; **Random start**, **Clear**,
  **Play**/**Pause**, **Step**, the **Acceleration** control and the zoom.
- [Generation](generation.md): how a generation is run: what the app
  counts, the Life model on aityx (the rules as a decision table), and how
  the answer becomes the next board.
- [Rules](rules.md): the rules as switches, Conway's on at the start,
  HighLife's birth and Life without death off; the **Rules** dialog.
- [Patterns](patterns.md): the catalogue of patterns (still lifes,
  oscillators, spaceships and methuselahs, as Wikipedia lists them),
  recognized by aityx from each cluster's shape; labeled on the board,
  with a notice when one appears.
- [Calls panel](calls-panel.md): the side panel with every call to aityx,
  newest first: what it decided, and the request and the response as
  readable JSON with the key parts labeled; the patterns noticed.
- [Theme](theme.md): the aityx dark palette.
- [App icon](app-icon.md): a glider on the dark background; the favicon
  and every platform's icon, generated from SVG masters.

**Backend**

- [API](api.md): `cellfie_api`, a Dart server that holds the aityx key and
  serves `POST /api/step` and `GET /api/health`.

**Project**

- [Development environment](dev-environment.md): devbox, process-compose,
  the health monitor, the builds, Docker Compose and the dev container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
