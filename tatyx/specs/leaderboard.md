# The leaderboard

The preset strategies play each other on the server, on the tour's
leaderboard key, and the standings show in the sidebar's first tab.

## A tournament

Every trio of the five presets, each trio three times, turned a seat
each time: thirty matches, in which every strategy plays every sector
against every pair of the others, six times a seat
([tournament.ts](../tatyx_app/src/game/tournament.ts)). A trio's three
matches play on the same map, drawn for that trio, so the seats are
compared on equal ground; each result keeps its map's seed, and
`playTournament` takes a seed to replay a whole tournament. Each match is
headless, the game's own world and rules, and waits for its decisions
after every tick (`Match.settle`), so how fast aityx answers never
changes how it ends; a match with no winner after 600 simulated seconds
is a draw. Every decision is one systemone call on the leaderboard key:
a tournament is some nine hundred calls, four or five minutes. A tournament
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

## What is kept, and shown

`tatyx/data/leaderboard.json` (`TATYX_DATA_DIR`; ignored by git, mode
600) keeps the last 20 tournaments, each with its matches (the lineup,
the winner, the time, each team's progress and bots, the decisions).
`GET /api/leaderboard`, open to all, answers the standings over the
tournaments kept, the latest tournament, what the leaderboard is doing
(the match being played, the calls so far) and when the next one is; no
key, no email.

The tab ([ui/leaderboard.ts](../tatyx_app/src/ui/leaderboard.ts)),
refreshed every 8 s while it shows (every 2 s while a tournament plays):

- what it is doing, or when the next tournament is, or why it doesn't
  play; the last failure, in red;
- **Play a tournament now**, for admins;
- the standings: the place, the strategy with whose it is under it
  (its owner's alias; **template strategy** for a preset) and the
  number of matches it won; most wins first, then the most mean
  progress into the hack, then the fastest wins (which rank but aren't
  shown);
- the latest tournament: each match's lineup in its seats' colours,
  the winner in bold, the time and the calls.

## Known limitations

- Only the presets play: a team's own strategy, uploaded on the title,
  plays in that browser only.
- The seats are not equal: the origins sit on an oval, so the top one
  (cyan's sector) is nearer the mainframe than the other two, and in
  local tournaments that seat wins most matches. The tournament's
  turning of the seats keeps the standings fair; the map's balance is
  [The game](game.md)'s next step.
- The schedule is the server's timer: a server that isn't running plays
  nothing, and doesn't catch up.
