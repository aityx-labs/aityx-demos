# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this project that means `npm
  test` and `npm run typecheck` in `tatyx_app/` and in
  `../packages/aityx_js/`, and `bash scripts/build.sh` builds the web app
  the server serves at `/tatyx/`. Then open it (`bash scripts/serve.sh`,
  http://localhost:9710/tatyx/) and look: the title, the field, the light,
  the key dialog.
- **Secrets**, as in Poker Tour: every player brings their own aityx
  key, kept in their browser (the key form saves it, with its URL); the
  server's keys are the leaderboard's alone (`TATYX_LEADERBOARD_KEY`,
  staging's, and `TATYX_PROD_LEADERBOARD_KEY`, production's, a different
  key), in the repository's `.env`, and never lent: never give a player,
  a page or an API answer a server key. The relay at `/aityx/` passes the
  player's Authorization header on and must never log it, store it, or
  add a key of its own. Never compile a key into the app, serve it from
  the API, print it, log it, show it in the calls panel (it shows the
  request's body, never its headers), or put it on a command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, third-party scripts on the app's origin, and
  unnecessarily broad permissions or exposed ports. The relay answers
  this origin's pages only, forwards to an https URL only, and never
  follows a redirect. Never commit credentials, even placeholders that
  look real.

Do not commit or push code that has not passed both checks.

## Project notes

- tatyx is a [Phaser 4](https://phaser.io) game in TypeScript, built
  with Vite ([tatyx_app/](tatyx_app)), served by a plain Node server
  ([tatyx_server/server.mjs](tatyx_server/server.mjs)) on port 9710:
  the app at `/tatyx/`, `/api/health`, and aityx for the app at `/aityx/`.
  It calls aityx from the browser through the shared
  [aityx-js](../packages/aityx_js/README.md) package, the TypeScript twin
  of the Flutter demos' aityx_web.
- The game logic lives in [tatyx_app/src/game/](tatyx_app/src/game):
  plain data and pure functions, no Phaser, so it can run headless (tests,
  a server runner later). The scenes only draw it.
- Toolchain is managed by [devbox.json](devbox.json) (Node 22); enter it
  with `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- The group: `group.id.txt` says `multyx`, shared with Poker Tour.
  `./start-multyx.sh` and `./stop-multyx.sh` at the repository's root
  take it with the group, apart from the aityx and datyx groups; so does
  the multyx dev container (`.devcontainer/multyx/`).
