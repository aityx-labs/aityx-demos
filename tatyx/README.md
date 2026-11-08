# tatyx

Three teams race to hack into the mainframe, and every megabyte is
decided on [aityx.ai](https://aityx.ai). A web game in the look of Tron
and the sound of synthwave: the mainframe in the middle of the map,
three teams around it in a triangle, each with an origin, its database,
on its own sector. The map is a hidden graph of sites, joined by links
that rot away with time; bytes are built on the sites, twice as fast
near the mainframe, each site only up to its size, and every game places
and sizes the sites anew. Every team fields the five bots of aityx: the
**Anchor** holds a site for its team alone, the **Builder** builds bytes
on it, the **Tester** renews the links it crosses and doubles a
Builder, the **Combinator** joins two links into a shortcut and
builds, and the **Explorer**, the only one that runs off the links,
finds the sites and the links. Every megabyte a team builds is one
question to its strategy: which bot to deploy next, or which bot to
send to the mainframe, where any bot builds its team's hack. The first
team to build the hack wins.

Nobody plays it by hand: each team's strategy is an aityx decision
model, one of five presets (the Farmer, the Sprinter, the Swarm, the
Doubler, the Fortress) or the team's own, uploaded as JSON on the title,
and the game plays itself from them, every call shown in the sidebar.
As in Poker Tour, players sign in with Google (aletyx accounts) and play
on their own aityx key, kept in their browser with its URL; and a
leaderboard plays the presets and the strategies players enter (an
upload, signed in) against each other on the server, on a key of its
own that never leaves it: every six hours, whenever a player enters a
strategy, and whenever an admin (aletyx.com or aletyx.ai) asks, one
tournament at a time, the others queued.

What's here: the title (the roster, a card per team with its strategy),
the map with the match and its controls (Start, Pause, the speed), the
sidebar (the leaderboard, the aityx calls, the profile), the world and
its rules as plain TypeScript (headless in the tests and in the
leaderboard's runner), the strategies and the team model as JSON, the
soundtrack the browser synthesizes, the shared TypeScript package that
reaches aityx, the server (sign-in, the relay to aityx, the leaderboard), and the
**multyx** group, with its index page, start scripts and dev container.
The balance of the rules and a strategy editor come next: see
[specs/](specs/README.md).

## Technology

| Part | Technology |
|---|---|
| Game ([tatyx_app/](tatyx_app)) | [Phaser 4](https://phaser.io) (TypeScript, [Vite](https://vite.dev)): three scenes, boot, the title and the map; the world, its rules, the bots' behaviours, the match and the strategies as plain data and pure functions in [src/game/](tatyx_app/src/game), with no Phaser in it; the shell around the canvas (the bar, the aityx light and key dialog, the calls panel) in plain DOM |
| aityx from the browser ([packages/aityx_js](../packages/aityx_js/README.md)) | The shared TypeScript package: the user's key and its URL, the relay to the server's aityx, the systemone call, the status check, the light and the key form; the twin of the Flutter demos' aityx_web |
| Server ([tatyx_server/](tatyx_server)) | Plain Node (`node:http`, `node:crypto`, no packages): the app at `/app/`; `/api/` for the config, the Google sign-in and its session ([auth.mjs](tatyx_server/auth.mjs)), and the leaderboard ([leaderboard.mjs](tatyx_server/leaderboard.mjs)); the relay at `/aityx/`, which passes the player's own key on to the server's aityx (staging takes no calls from browsers) and never adds one |
| Art ([art/](art/README.md)) | The concept art of the five bots, as reference; the portraits the app shows are made from it |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Node 22) on a laptop, or the multyx group's [dev container](../.devcontainer/multyx/devcontainer.json) |

## Run it

From the root of the repository:

```bash
./start-multyx.sh           # the multyx group: tatyx on http://localhost:9710/app/, Poker Tour and the index on http://localhost:9700/
./start-multyx.sh tatyx     # tatyx alone
./stop-multyx.sh
```

From this folder, with [Devbox](https://www.jetify.com/devbox):

```bash
devbox services up          # the server, detached: http://localhost:9710/app/
devbox run serve            # the same, in the foreground (builds what's stale first)
devbox run dev              # Vite's dev server, http://localhost:9711/app/, hot reload; the server on 9710 answers /api/ and /aityx/
devbox run test             # the tests and the type check
```

Or, with Node 22 on the PATH, `bash scripts/serve.sh`, or `make dev`,
`make test`, `make build` ([Makefile](Makefile)).

## Sign-in and the keys

To play, a player signs in with Google (an `aletyx.com` or `aletyx.ai`
account), in the sidebar's Profile. tatyx has its own Google project,
`aletyxcode-tatyx`, with an *Internal* consent screen and a web client,
`tatyx-web`, for `http://localhost:9710` and `:9711`; its id is
`TATYX_OIDC_CLIENT_ID` in the repository's `.env`. Serve the game from
another address and that address must be added to the client's
authorized JavaScript origins (Google Cloud console, Google Auth
Platform, Clients).

The keys, as in Poker Tour: every player brings their own, set in
Profile and kept in their browser with its URL; the server's are the
leaderboard's alone, in the repository's `.env` (see
[.env.example](.env.example)), never sent to a browser:

- `TATYX_LEADERBOARD_KEY`: staging's, for the tournaments of a laptop's
  server (with `AITYX_URL`, aityx staging).
- `TATYX_PROD_LEADERBOARD_KEY`: production's, a different key, for a
  deployment to come (with `AITYX_PROD_URL`); a local server never reads
  it.

On a laptop a player's calls to aityx staging go through the server's
relay at `/aityx/` with the player's own key, since staging takes no
calls from browsers; a key pointed at production goes there directly.
