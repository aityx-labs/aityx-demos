# The leaderboard

The preset strategies and the ones players enter play each other on the
server, on the tour's leaderboard key, and the standings show in the
sidebar's first tab.

## The players' strategies

A signed-in player enters a strategy in the tour by uploading it: on
the title (a team's **Upload**, which sets the team's strategy in the
browser as before and, signed in, enters it too; signed out, the card
says to sign in for that), or with **Enter a strategy** in the
leaderboard tab, under **Your strategies in the tour**, which lists
the player's entries, each with **Withdraw**
([ui/tour.ts](../tatyx_app/src/ui/tour.ts)).

- `POST /api/strategies` (signed in, this origin's pages): the strategy
  file's JSON, checked on the server as the title checks an upload (the
  game's `parseStrategy`, from the runner bundle): `400` with what to
  fix; a preset's name is refused; a player has at most
  `TATYX_MAX_ENTRIES` (3) in the tour, `409` past that; one of the same
  name replaces theirs, as a new strategy with a fresh record. `201`
  with the entry and `tournament`: what asking for one did (below).
- `GET /api/strategies` (signed in): every entry, its rules, whose it is
  (the owner's alias, never an email) and whether it is the caller's.
- `DELETE /api/strategies/<id>` (signed in, this origin's pages): the
  caller's entry withdrawn (`404` for another's); it leaves the
  standings.

The entries are kept in the store's `strategies.json`
(`tatyx/data/` on a laptop, mode 600; the data bucket deployed), with
their owners' emails, which no answer holds. A tour with none yet
starts with the strategies kept in the repository,
[strategies/](../strategies) ([Deployment](deploy.md#the-strategies-kept-in-the-repository)).

## A tournament

A **field** of five strategies plays it: of the presets and the
entries, the fewest matches played in the tournaments kept first, so a
new entry plays at once; on a tie a player's before a preset, then at
random (`pickField`). Every trio of the field, each trio three times,
turned a seat each time: thirty matches, in which every strategy plays every sector
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

Asked for by three sources:

- the **schedule**: every `TATYX_LEADERBOARD_EVERY_HOURS` hours (6), on
  the hour in UTC: 0, 6, 12 and 18 o'clock. 0: none;
- an **admin** pressing **Play a tournament now** in the tab
  (`POST /api/leaderboard/run`: a signed-in `aletyx.com` or `aletyx.ai`
  player, from the game's own pages; `403` for anyone else). `202`
  with `status`: `started`, `queued` or `waiting`; `503` when the
  leaderboard is off;
- a player entering a **strategy** (above).

Never two at once: a tournament asked for is **queued**, and played
when the one being played ends, the oldest first. At most one waits per
source: asking again while one from the same source waits answers
`waiting`, and that one stands for both (a second new strategy plays in
the tournament the first asked for, since the fewest matches played sit
first). On a laptop the server is one process: its drain of the queue
is the only player, and the queue is kept in `leaderboard.json`, so a
restart plays what was left in it. Deployed, the runner function plays
each tournament asked for, one at a time, and the others wait in
Lambda's queue ([Deployment](deploy.md)). Never with
`TATYX_LEADERBOARD=off`, or without a key.

## What is kept, and shown

The store's `leaderboard.json` (`tatyx/data/`, `TATYX_DATA_DIR`, ignored
by git, mode 600; deployed, the data bucket) keeps the last 20 tournaments, each with who asked for it, its
field (the ids, the names, the owners) and its matches (the lineup, the
winner, the time, each team's progress and bots, the decisions), and the
queue. `GET /api/leaderboard`, open to all, answers the standings over
the tournaments kept (the presets and the entries in the tour), the
latest tournament (with its field's names), what the leaderboard is
doing (the match being played, the calls so far, who asked), the
`queue` (each waiting tournament's source and when it was asked for)
and when the next scheduled one is; no key, no email.

The tab ([ui/leaderboard.ts](../tatyx_app/src/ui/leaderboard.ts)),
refreshed every 8 s while it shows (every 2 s while a tournament plays):

- what it is doing, or when the next tournament is, or why it doesn't
  play, and what waits its turn ("the schedule's, a new strategy's");
  the last failure, in red;
- **Play a tournament now**, for admins only, disabled while an admin's
  waits;
- the standings: the place, the strategy with whose it is under it
  (its owner's alias; **template strategy** for a preset) and the
  number of matches it won; the most wins per match played first (an
  entry plays fewer tournaments than the presets), then the most wins,
  then the most mean progress into the hack, then the fastest wins
  (which rank but aren't shown);
- signed in, **Your strategies in the tour** (above);
- the latest tournament: each match's lineup in its seats' colours,
  the winner in bold, the time and the calls.

## Known limitations

- The queue is the server's, in one process: two tatyx servers on one
  data folder would each play theirs.
- The seats are not equal: the origins sit on an oval, so the top one
  (cyan's sector) is nearer the mainframe than the other two, and in
  local tournaments that seat wins most matches. The tournament's
  turning of the seats keeps the standings fair; the map's balance is
  [The game](game.md)'s next step.
- The schedule is the server's timer: a server that isn't running plays
  nothing, and doesn't catch up.
