# Poker Tour — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

Poker Tour is PokerFace for a team: the same poker simulator, no-limit
Texas hold'em at a table of up to nine where every player is a set of
rules run on aityx, with a Google sign-in for the people of aletyx and a
leaderboard. The app plays the hands and computes each player's
situation; one aityx call per turn runs the player's strategy on it and
answers with the action, the amount and the rule that decided it, from
the browser, on the player's own key: players never get the host's. The
server ([pokertour_api](../pokertour_api)) serves the app, takes the
strategies players enter (kept in DynamoDB, with their aliases), and
plays a tournament among the strategies in the tour four times a day,
whenever an admin asks and whenever a player enters a strategy, one at
a time (queued in DynamoDB), on the leaderboard's own key, keeping the
standings; on AWS it runs serverless, as Lambda functions behind
CloudFront, and on a laptop on Floci, the local AWS. The
table, the sidebar, the pace and the strategies are PokerFace's; the
engine is shared with the server ([poker_core](../poker_core)).

## Features

**The tour**

- [The tour](tour.md): the sign-in with Google and the allowed domains,
  the keys (the players' own, the leaderboard's), the leaderboard with
  its owners by alias, entering and withdrawing strategies, the
  schedule, the admins' "now", a tournament per new strategy, the queue
  that plays them one at a time, the runner, and where the tour is kept
  (DynamoDB and S3).
- [On AWS](aws.md): the serverless deployment: S3 and CloudFront for
  the app, two Lambda functions for the API and the runner, the tour's
  table, the data bucket with the leaderboard's key, the EventBridge
  schedule, and the deploy script.

**App**

- [The sidebar and the profile](profile.md): the table on the left, the
  sidebar's tabs on the right (the leaderboard, the aityx calls, the
  profile); the player's alias, their own aityx key and URL (the only
  key their table uses, on staging locally and production deployed),
  and their strategies in the tour.

- [The table](table.md): the felt, the seats, the board and the pot; the
  rules of the game as the app plays them (blinds, betting rounds, side
  pots, showdown, blind levels, eliminations, the winner); the controls:
  play, pause, step (waiting for a working key), the pace slider and a
  new tournament.
- [The aityx calls](calls.md): the sidebar's list of every decision asked
  of aityx, and the full request and response with the key parts marked;
  the hand log.
- [Players and strategies](players.md): adding and removing players,
  changing a player's strategy, the preset strategies and the tour's,
  the editor for strategies of your own, with **Try it on aityx**,
  downloads, **Enter it in the tour** and **Upload a strategy**.
- [The aityx light](aityx-status.md): the dot, top right, that says
  whether the player's key is there and aityx accepts it.
- [Music](music.md): five minimal lo-fi jazz tracks, synthesized by a
  script, played in a random loop at the table, with mute and volume.
- [Theme](theme.md): the aityx dark palette, and the felt.
- [App icon](app-icon.md): an orange ace of spades with a chip.

**Rules**

- [Strategies](strategies.md): the table model (what a player sees) and
  how a strategy's rules are written; the five presets.

**aityx**

- [Deciding on aityx](aityx.md): the app calls aityx from the browser,
  one systemone call per decision, on the player's key; the presets from
  the app's assets, the checks before a call, and the errors. The server
  calls it the same way for the leaderboard.

**Project**

- [Development environment](dev-environment.md): devbox, Floci (the
  local AWS), the server that serves the web build at `/pokertour/` on port
  9810, the tests, the container, the local Kubernetes cluster and the
  multyx group's dev container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
