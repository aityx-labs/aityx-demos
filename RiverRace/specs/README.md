# RiverRace — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

RiverRace remakes the 1982 Atari river shooter with three planes up one
river at once: two flown by aityx, each by its own strategy (rules you
can read, change, add and remove while they fly), and one flown by the
player. Every few frames one aityx call decides what both aityx pilots
do; the side panel shows every call, sent and received, and the rule that
fired. Which strategy wins?

## Features

**App**

- [Game](game.md): the river, its banks, islands and bridges, tankers,
  helicopters, jets and fuel depots; the three planes, fuel, missiles,
  scoring, lives, the screen; the controls and the HUD.
- [Strategies](strategies.md): the sensors and commands, the strategies
  to pick, and the pilot cards where rules are explored and edited.
- [Decisions](decisions.md): the decision cycle (real time or a fair
  race), the model on aityx, and how the answer flies the planes.
- [Calls panel](calls-panel.md): the side panel with every call to aityx,
  newest first: what each pilot sensed and decided, and the request and
  the response as readable JSON with the key parts labeled.
- [Theme](theme.md): the aityx dark palette, and the Atari's colors on the
  river.
- [App icon](app-icon.md): the yellow plane over the river, in pixels.
- [aityx status](aityx-status.md): the light, top right, that says
  whether there is a key (the user's, or the index server's dev key) and
  aityx accepts it.
- [aityx calls](api.md): no API of its own; the app calls aityx from the
  browser, on the key the user set on the index page, or through the
  index server's dev proxy; the checks before a call, and the messages
  when one fails.

**Project**

- [Development environment](dev-environment.md): devbox, the web build
  the index server serves at `/riverrace/`, the native builds, the model
  tests and the dev container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
