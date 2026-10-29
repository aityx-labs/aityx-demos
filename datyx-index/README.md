# datyx index

The index of the datyx group: one page, in the aityx palette, with a
card per system (what it is, its technology, **Open** for it on its port
here or, in a codespace, its forwarded URL, **Source** on GitHub, and
**Codespace** for the datyx group's dev container): the datyx dashboard, the datyx API,
HealthHub and OpenMetadata. The six aityx demos have their own index,
[../Index/](../Index/).

- [www/index.html](www/index.html): the page. The cards' text and each
  system's port are in it; it does not say which ones are up.
- [bin/server.dart](bin/server.dart): a plain Dart server (no packages).
  `GET /` is the page (`/app/` too, so `start-all.sh` checks it like a
  demo); `GET /api/demos` lists every folder beside this one with a
  `process-compose.yaml` whose `group.id.txt` says `datyx`, the web and
  API ports it defaults to, and whether its web app (or its API, for the
  datyx API, which has no app) answers right now, for scripts.
  `GET /api/health` answers `{"ok": true}`.
- Port **9907** (`INDEX_PORT`), the datyx group's range, bound to
  127.0.0.1 (`INDEX_BIND_HOST`).
- [group.id.txt](group.id.txt) says `datyx`: `./start-datyx.sh` and
  `./stop-datyx.sh` at the repository's root take it with the group.

## Run it

From this folder, with [Devbox](https://www.jetify.com/devbox):

```bash
devbox services up            # the index on http://localhost:9907/
devbox run serve              # the same, in the foreground
```

or, with Dart on the PATH, `dart bin/server.dart`. From the root of the
repository, `./start-datyx.sh` starts it with the group and prints its
link last; `./stop-datyx.sh` stops it.
