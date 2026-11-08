# tatyx — software specification

The current specification, one file per feature. Update the feature files
a request changes, and add one when a request adds a feature.
[requests.md](requests.md) holds the history of requests that shaped it.

## Product

tatyx is a web game where three teams of the five bots of aityx race to
hack into the mainframe in the middle of the map: each team, on its
sector of the map, finds the map's sites and the links between them,
builds bytes on the sites over links that rot unless renewed, and every
megabyte it builds is one decision on aityx, what to deploy, a bot of
one of the five kinds (an Anchor, a Builder, a Tester, a Combinator, an
Explorer) or one of its bots sent to the mainframe, where every bot
builds the hack. Played entirely by aityx: each
team's strategy is an aityx decision model, a preset or the team's own,
uploaded, and the game plays itself from them, every call shown beside
the map; signed-in players play on their own key, and a leaderboard
plays the presets and the players' entries on a key of its own, one
tournament at a time. Tron's look, a synthwave
soundtrack. A Phaser 4 game, in the **tatyx** group of the aityx demos,
on port 9710.

What exists now is the game: the title with the teams' strategies, the
map and the match with its controls, the world and its rules, the five
bots' behaviours, the decisions on aityx, the sidebar (leaderboard,
calls, profile), the Google sign-in, the leaderboard's tournaments, the
soundtrack, the server, the group. The balance of the rules and a
strategy editor are marked as **next** in each file.

## Features

**The game**

- [The game](game.md): the concept (the mainframe, the teams in a
  triangle, the origins, the sites and the links, the bytes), the rules
  and their numbers, the map on screen, the headless match; what's
  next.
- [The bots](characters.md): the five characters, their parts on the map
  and their behaviours; the teams, their colour tags, orange being the
  computer's, and their strategies; the art.
- [Screens](screens.md): the shell (the bar, the light, the key dialog,
  the music button, the calls panel), the title and the map.
- [Sound](sound.md): the synthwave soundtrack, synthesized in the
  browser, and when it plays.

**aityx**

- [Deciding on aityx](aityx.md): the one decision, what a team's next
  megabyte buys: the team model's inputs, the three strategies, a
  team's own strategy (download, upload), the call and its answer, the
  errors; the calls panel.
- [Sign-in and keys](players.md): Google sign-in (tatyx's own Google
  project and client), the session, the players' own keys and the
  leaderboard's, the profile.
- [The leaderboard](leaderboard.md): the tournaments of the presets
  and the players' entries on the server, on the leaderboard key; the
  entries, the field, the schedule, an admin's and a new strategy's
  tournaments, the queue, the standings, the tab.

**Project**

- [Development environment](dev-environment.md): the multyx group, the
  server on 9710 and the index on 9700, devbox, Vite, the tests, the
  group's scripts and dev container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with
  its own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations** or **Next**,
  where it has any.
