# RoboRules — software specification

The current specification, one file per feature. Update the feature files a
request changes, and add one when a request adds a feature.
[requests.md](requests.md) holds the history of requests that shaped it.

## Product

A web take on the old Robocode where every robot's behavior is an aityx
decision model and every turn of the battle (sensors, decisions, motion,
bullets, collisions, damage) and every round's score is played by aityx.
Random robots to start with, or Robocode's sample robots written as rules,
added, removed and customized at will; select one to change its rules; see
which rules win, with every event and every aityx call in the log.

## Features

- [The battle on aityx](battle.md): the world model, one call per batch of
  turns, Robocode's physics in FEEL.
- [Robots](robots.md): a robot as an aityx model, its sensors and commands,
  random robots, the rules editor.
- [Scoring](scoring.md): Robocode's round score, as an aityx model.
- [The window](window.md): Robocode's look, the battlefield, the controls,
  the speed, the dialogs, the aityx call viewer.
- [Development environment](dev-environment.md): devbox, ports, Docker
  Compose, the dev container, the tests.
- [App icon](app-icon.md): a tank seen from above, orange on the dark
  background; the favicon in aityx\'s style, and the web icons.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. See [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected specs and the
  [request log](requests.md) in the same PR.
