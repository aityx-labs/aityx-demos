# Development environment

tatyx is one folder with the app, the server and the scripts, in the
**tatyx** group of the aityx demos, which it starts and stops with.

- [tatyx_app](../tatyx_app): the Phaser 4 app, TypeScript, built
  with Vite. `src/main.ts` mounts the shell and starts the game;
  `src/scenes/` the three scenes; `src/game/` the world as plain data and
  pure functions (no Phaser, so it runs under Node); `src/ui/` the shell.
  `public/` holds the portraits (the orange originals and, under
  `bots/<team>/`, each team's, painted by `tool/recolor.mjs` with
  [pngjs](https://www.npmjs.com/package/pngjs); `npm run recolor`
  regenerates them, and they are committed) and the favicon. It depends
  on the shared
  package by path: `"aityx-js": "file:../../packages/aityx_js"`, which
  npm links; Vite compiles the package's TypeScript as the app's own
  (`server.fs.allow` lets the dev server read it).
- [packages/aityx_js](../../packages/aityx_js/README.md): the shared
  TypeScript package, no build, its own tests (`npm test`, vitest) and
  type check.
- [tatyx_server/server.mjs](../tatyx_server/server.mjs): plain Node,
  no packages. One process on one port, **9710** (the multyx group's
  range: 9700 is the index): the build under `/tatyx/`, to share a server with other apps (`/`, `/tatyx` and `/app...`
  redirect there, keeping the query, since the page's relative paths,
  the bots' portraits among them, resolve only under `/tatyx/`; a path
  that isn't a file gets `index.html`; Vite's hashed `assets/` are cached for a year,
  the page never), `/api/health`, `/api/config`, `/api/session`
  ([auth.mjs](../tatyx_server/auth.mjs), [Sign-in and keys](players.md)),
  `/api/leaderboard` ([leaderboard.mjs](../tatyx_server/leaderboard.mjs),
  [The leaderboard](leaderboard.md)) and the relay at
  `/aityx/v1/systemone`. Every setting is in
  [.env.example](../.env.example). Settings:
  `FLUTTER_WEB_PORT` (the name every demo's `start-all.sh` reads, Flutter
  or not; also `TATYX_PORT`), `TATYX_BIND_HOST`, `WEB_ROOT`,
  `AITYX_API_KEY`, `AITYX_URL`; the key from the environment, a
  Codespaces secret, else this folder's or the repository's `.env`, read
  again at most every 10 s.
- [devbox.json](../devbox.json) manages the toolchain: Node 22 and curl;
  [devbox.lock](../devbox.lock) is committed. `devbox run serve` builds
  and serves; `devbox run dev` runs Vite's dev server on **9711** at
  `/tatyx/`, with `/api/` and `/aityx/` proxied to the server on 9710;
  `devbox run test` runs the tests and the type check.
- **The group**: `group.id.txt` says `multyx`, the group of the
  multiplayer games on aityx, shared with [Poker Tour](../../PokerTour/),
  so `./start-multyx.sh`, `./stop-multyx.sh` (`DEMOS_GROUP=multyx` into
  `start-all.sh` and `stop-all.sh`), `./build-all.sh` and the multyx dev
  container take it with the group, and `start-all.sh` links this
  folder's `.env` to the repository's root one (its `.env.example` names
  `AITYX_API_KEY`). `./start-multyx.sh tatyx` starts it alone. The
  group's index, [multyx-index](../../multyx-index/README.md), on
  **9700**, has a card for it and one for Poker Tour.
- **The build** ([scripts/build.sh](../scripts/build.sh), run by
  `scripts/serve.sh`, the repository's `build-all.sh` and `start-all.sh`,
  or by hand): `npm ci` when the packages are missing or older than the
  lock file, then `npm run build` (the type check, then Vite) into
  `tatyx_app/dist/`, recorded in `dist/.tatyx-services`; only when
  the build is missing or older than its sources (the app, the shared
  package, the version files).
- **Running it** ([scripts/serve.sh](../scripts/serve.sh), what
  [process-compose.yaml](../process-compose.yaml) runs): builds what's
  stale, then `node tatyx_server/server.mjs` with `WEB_ROOT` set and
  the settings from the environment, else `.env`
  ([scripts/env.sh](../scripts/env.sh), see
  [.env.example](../.env.example)): the key reaches the server's
  environment only. `/api/health` is the readiness probe.
- **The tests**: `npm test` in `tatyx_app/` (the bots, the map, each
  mechanic, the strategies, and a whole match played headless)
  and in `packages/aityx_js/` (the store, the connection, the check, the
  resolution and the client, with a fake fetch); `npm run typecheck` in
  each. `make test` runs all four.
- **The dev container** ([.devcontainer/multyx/](../../.devcontainer/multyx/devcontainer.json)):
  the multyx group's published image (`bash image/build-image.sh
  multyx`: Flutter for Poker Tour, Node 22, the version
  [devbox.lock](../devbox.lock) pins, and process-compose;
  `DEMOS_TOOLCHAIN=image`, `DEMOS_GROUP=multyx`), with the shared
  scripts in `.devcontainer/`: `on-create.sh` restores the image's
  builds (Poker Tour's; this game has no Flutter build for the image to
  carry), `update-content.sh` builds (here `npm ci` and Vite, a minute),
  `post-start.sh` starts the group with the index first and makes 9700,
  9710 and 9810 public.

- **On Kubernetes** ([k8s/](../k8s), the repository's local kind
  cluster, `bash k8s/up.sh` then `bash k8s/deploy.sh tatyx` at its
  root): one image, [docker/tatyx.Dockerfile](../docker/tatyx.Dockerfile),
  built from this folder with the shared packages as a second context
  (`npm ci` and `npm run build` in a Node 22 stage; the server, the
  build, the runner and [strategies/](../strategies) on `node:22-alpine`,
  as the image's `node` user, no packages); its allowlist,
  `tatyx.Dockerfile.dockerignore`, keeps the `.env`, the builds and
  `data/` out. A Deployment `tatyx` (one replica, `Recreate`) in the
  namespace `multyx`, with the tour's files (`TATYX_DATA_DIR=/data`) on
  the volume `tatyx-data`, and the Service `tatyx` on 9710, a node port
  published at **http://localhost:19710/tatyx/**. Like a local run it is
  on aityx staging: `AITYX_URL`, `AITYX_API_KEY`,
  `TATYX_LEADERBOARD_KEY` and `TATYX_OIDC_CLIENT_ID` from the Secret
  `demo-env` the root `.env` makes (`k8s/secrets.sh`). The `tatyx-web`
  client lists `http://localhost:19710` among its authorized JavaScript
  origins, so Google sign-in works on the cluster as it does on 9710
  (Google can take a while to apply a change to a client's origins).
  `k8s/verify.sh` checks it from the host: the app, a real decision
  through the relay on a player's key, the leaderboard's key in the pod,
  the volume, and the signed-in API refusing a caller who isn't.

## Known limitations

- The dev container image doesn't carry this game's build or its
  packages: a codespace runs `npm ci` and the Vite build when created
  (a minute). The image itself is built and pushed by hand; until
  `bash image/build-image.sh multyx` is pushed once, the multyx dev
  container has no image to pull.
