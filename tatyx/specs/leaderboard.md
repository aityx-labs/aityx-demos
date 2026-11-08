# The leaderboard

The preset strategies and the players' entries play each other on the
server, on the tour's leaderboard key, and the standings show in the
sidebar's first tab.

## A tournament

The five presets and up to two of the players' entries (those that have
played the fewest matches in the tournaments kept, ties at random; see
[Entering a strategy](#entering-a-strategy)). Every trio of them, each
trio three times, turned a seat each time: thirty matches for the five
presets alone, 105 with two entries, in which every strategy plays every
sector against every pair of the others
([tournament.ts](../tatyx_app/src/game/tournament.ts), whose
`playTournament` takes the strategies to seat, the presets by default). A trio's three
matches play on the same map, drawn for that trio, so the seats are
compared on equal ground; each result keeps its map's seed, and
`playTournament` takes a seed to replay a whole tournament. Each match is
headless, the game's own world and rules, and waits for its decisions
after every tick (`Match.settle`), so how fast aityx answers never
changes how it ends; a match with no winner after 600 simulated seconds
is a draw. Every decision is one systemone call on the leaderboard key:
a tournament of the presets is some nine hundred calls, four or five
minutes; with two entries, some three thousand, a quarter of an hour. A tournament
whose first questions all fail (a rejected key, say) stops there, and
says why.

The server runs the game's runner, bundled for Node by `npm run build`
([vite.runner.config.ts](../tatyx_app/vite.runner.config.ts),
[runner.ts](../tatyx_app/src/game/runner.ts)) into
`tatyx_app/dist-runner/runner.mjs`, and calls aityx itself
([tatyx_server/leaderboard.mjs](../tatyx_server/leaderboard.mjs)) with
the key no answer holds and no log prints.

## When

- Every `TATYX_LEADERBOARD_EVERY_HOURS` hours (6), on the hour in UTC:
  0, 6, 12 and 18 o'clock. 0: only on demand.
- When an admin presses **Play a tournament now** in the tab
  (`POST /api/leaderboard/run`: a signed-in admin, from the game's own
  pages), unless one is being played, or one started less than
  `TATYX_LEADERBOARD_COOLDOWN_MINUTES` (10) ago.
- Never with `TATYX_LEADERBOARD=off`, or without a key.

## Entering a strategy

A signed-in player enters a strategy file (what **Download** on the
title gives: `name`, `tagline`, `decisions`) with `POST /api/strategies`,
from the game's own pages, with their session
([tatyx_server/server.mjs](../tatyx_server/server.mjs),
[leaderboard.mjs](../tatyx_server/leaderboard.mjs)):

- It is checked as the title checks an upload (`parseStrategy` in
  [lineup.ts](../tatyx_app/src/game/lineup.ts): JSON, a name of 1 to 60
  characters, a build table on the team model's inputs, 64 KB at most;
  `400` with what to fix), its name must not be a preset's (`400`), and
  a player has three entries at most (`409`); an entry of the same name
  as one of theirs replaces it, with a new id, so its record starts
  afresh.
- Then aityx is asked its question once, on the leaderboard's key, on a
  team's situation at the start of a match (`check` in
  [runner.ts](../tatyx_app/src/game/runner.ts)): `422` with aityx's
  reason when it refuses the rules, `503` when it can't be asked (no
  leaderboard key, the key rejected, no answer).
- Entered (`201`, the entry with its id), it plays from the next
  tournament it is seated in.

`GET /api/strategies` answers the player's own entries, and `DELETE
/api/strategies/{id}` withdraws one of theirs (`204`; `404` for none of
theirs by that id), which leaves the standings with it. Signed out,
`401`; from another site, `403`. The entries are kept in
`<TATYX_DATA_DIR>/entries.json` (mode 600) with their owners' emails,
which no answer holds.

## What is kept, and shown

`tatyx/data/leaderboard.json` (`TATYX_DATA_DIR`; ignored by git, mode
600) keeps the last 20 tournaments, each with its matches (the lineup,
the winner, the time, each team's progress and bots, the decisions) and
the names of the entries it seated. `GET /api/leaderboard`, open to all,
answers the standings over the tournaments kept (the presets and every
entry in the tour, one not yet seated with no match played), the latest
tournament (with its entries' names, for the lineups), what the
leaderboard is doing (the match being played, the calls so far) and when
the next one is; no key, no email.

The tab ([ui/leaderboard.ts](../tatyx_app/src/ui/leaderboard.ts)),
refreshed every 8 s while it shows (every 2 s while a tournament plays):

- what it is doing, or when the next tournament is, or why it doesn't
  play; the last failure, in red;
- **Play a tournament now**, for admins;
- the standings: the place, the strategy with whose it is under it
  (its owner's alias, else the part of their email before the @;
  **template strategy** for a preset) and the
  number of matches it won; most wins first, then the most mean
  progress into the hack, then the fastest wins (which rank but aren't
  shown);
- the latest tournament: each match's lineup in its seats' colours,
  the winner in bold, the time and the calls.

## Known limitations

- The app has no button to enter a strategy yet: an upload on the
  title plays in that browser only, and an entry goes in through `POST
  /api/strategies` with a session (from the page's console, say).
- Two entries a tournament keeps it to a quarter of an hour: with many
  entries, each plays every few tournaments, and the standings, over
  the 20 kept, compare strategies on different numbers of matches (the
  wins are a count, not a rate).
- The seats are not equal: the origins sit on an oval, so the top one
  (cyan's sector) is nearer the mainframe than the other two, and in
  local tournaments that seat wins most matches. The tournament's
  turning of the seats keeps the standings fair; the map's balance is
  [The game](game.md)'s next step.
- The schedule is the server's timer: a server that isn't running plays
  nothing, and doesn't catch up.
