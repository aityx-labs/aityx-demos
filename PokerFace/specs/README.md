# PokerFace — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

PokerFace is a poker simulator, no-limit Texas hold'em at a table of up
to nine, where every player is a set of rules run on aityx. The app plays
the hands and computes each player's situation; one aityx call per turn
runs the player's strategy on it and answers with the action, the amount
and the rule that decided it. The app calls aityx itself, from the
browser: there is no server of its own. The table shows the hand like an
online poker room, a sidebar shows every aityx call, a slider sets the
pace, and players with different strategies, preset or written in the
app, can be added at any time.

## Features

**App**

- [The table](table.md): the felt, the seats, the board and the pot; the
  rules of the game as the app plays them (blinds, betting rounds, side
  pots, showdown, blind levels, eliminations, the winner); the controls:
  play, pause, step, the pace slider and a new tournament.
- [The aityx calls](calls.md): the sidebar's list of every decision asked
  of aityx, and the full request and response with the key parts marked;
  the hand log.
- [Players and strategies](players.md): adding and removing players,
  changing a player's strategy, the preset strategies, and the editor for
  strategies of your own, with **Try it on aityx**.
- [The aityx light](aityx-status.md): the dot, top right, that says
  whether there is an aityx key (the user's, or the dev key) and aityx
  accepts it.
- [Theme](theme.md): the aityx dark palette, and the felt.
- [App icon](app-icon.md): an orange ace of spades with a chip.

**Rules**

- [Strategies](strategies.md): the table model (what a player sees) and
  how a strategy's rules are written; the five presets.

**aityx**

- [Deciding on aityx](aityx.md): the app calls aityx from the browser,
  one systemone call per decision, on the key the user set on the index
  page or the index server's dev key; the presets from the app's assets,
  the checks before a call, and the errors.

**Project**

- [Development environment](dev-environment.md): devbox, the web build
  the index server serves at `/pokerface/`, the tests, the native builds
  and the dev container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
