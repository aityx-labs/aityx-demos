# multyx index

The index of the multyx group, the multiplayer games on aityx: one
page, in the aityx palette, with a card per demo (what it is, its
technology, **Open** for it on its port here or, in a codespace, its
forwarded URL, **Source** on GitHub, and **Codespace** for the multyx
group's dev container): the tatyx game and Poker Tour. The six aityx
demos have their own index, [../Index/](../Index/), and the datyx group
[../datyx-index/](../datyx-index/); this one is in Node, as tatyx is.

- [www/index.html](www/index.html): the page. The cards' text and each
  demo's port are in it; it does not say which ones are up.
- [bin/server.mjs](bin/server.mjs): a plain Node server (no packages).
  `GET /` is the page (`/app/` too, so `start-all.sh` checks it like a
  demo); `GET /api/demos` lists every folder beside this one with a
  `process-compose.yaml` whose `group.id.txt` says `multyx`, the web and
  API ports it defaults to, and whether its web app answers right now,
  for scripts. `GET /api/health` answers `{"ok": true}`.
- Port **9700** (`INDEX_PORT`), the first of the multyx group's ports,
  bound to 127.0.0.1 (`INDEX_BIND_HOST`). tatyx is on 9710; Poker Tour
  keeps 9810, the origin its Google sign-in client allows.
- [group.id.txt](group.id.txt) says `multyx`: `./start-multyx.sh` and
  `./stop-multyx.sh` at the repository's root take it with the group.

## Run it

From this folder, with [Devbox](https://www.jetify.com/devbox):

```bash
devbox services up            # the index on http://localhost:9700/
devbox run serve              # the same, in the foreground
```

or, with Node on the PATH, `node bin/server.mjs`. From the root of the
repository, `./start-multyx.sh` starts it with the group and prints its
link last; `./stop-multyx.sh` stops it.
