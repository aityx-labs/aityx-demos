# multyx index

The index of the multyx group, the multiplayer games on aityx: one
page, in the aityx palette, with a card per demo (what it is, its
technology, **Open** for it on its port here or, in a codespace, its
forwarded URL, **Source** on GitHub, and **Codespace** for the multyx
group's dev container): the tatyx game and Poker Tour. The six aityx
demos have their own index, [../Index/](../Index/), and the datyx group
[../datyx-index/](../datyx-index/); this one is in Node, as tatyx is.

- [www/index.html](www/index.html): the page. The cards' text is in it;
  the port of each demo comes from the server ([Settings](#settings)),
  so the same page is right on a local run, on the cluster and in a
  codespace. It does not say which ones are up.
- [bin/server.mjs](bin/server.mjs): a plain Node server (no packages).
  `GET /` is the page (`/app/` too, so `start-all.sh` checks it like a
  demo); `GET /api/demos` lists every folder beside this one with a
  `process-compose.yaml` whose `group.id.txt` says `multyx`, the web and
  API ports it defaults to, and whether its web app answers right now,
  for scripts. `GET /api/settings` answers the ports the page links to
  and names, and whether this copy runs on the cluster
  ([Settings](#settings)). `GET /api/health` answers `{"ok": true}`.
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

On the local Kubernetes cluster (`k8s/` at the root), `bash
k8s/deploy.sh multyx-index` builds [docker/multyx-index.Dockerfile](docker/multyx-index.Dockerfile),
deploys [k8s/](k8s/) in the namespace `multyx`, and checks it
([k8s/verify.sh](k8s/verify.sh)): the index is on
http://localhost:19700/. [k8s/deployment.yaml](k8s/deployment.yaml) sets
the ports below to the ones the cluster publishes on this host, each
demo's usual port plus 10000 (tatyx on 19710, Poker Tour on 19810), and
`INDEX_ON_CLUSTER`, so the cards open the cluster's copies and the footer
names the cluster's scripts. The image has no folders beside it, so
`INDEX_DEMOS` names the demos `/api/demos` checks, as
`<folder>=<URL>,...`.

## Settings

All from the server's environment; a local run needs none of them. The
page reads the ports and `INDEX_ON_CLUSTER` from `GET /api/settings`
(`{"cluster": false, "ports": {"TATYX_PORT": 9710, ...}}`, the ports by
these names) and builds its links, the ports in its text and its footer
from them: it never looks at its own port. In a codespace the same ports
go in the forwarded host names. A value that is not a port (or, for
`INDEX_ON_CLUSTER`, not `true`, `1`, `false` or `0`) stops the server at
start.

| Variable | Default | On the cluster | What |
|---|---|---|---|
| `INDEX_PORT` | 9700 | 9700 | The port the server listens on |
| `INDEX_BIND_HOST` | 127.0.0.1 | 0.0.0.0 | The address it binds |
| `INDEX_GROUP` | multyx | multyx | The group `/api/demos` lists |
| `INDEX_DEMOS` | unset | the two Services | `<folder>=<URL to check>,...` for `/api/demos`, where no folders are beside the server |
| `INDEX_ON_CLUSTER` | false | true | This copy runs on the local Kubernetes cluster: the footer says so and how to deploy and delete it |
| `TATYX_PORT` | 9710 | 19710 | tatyx, as its own server names it |
| `POKERTOUR_WEB_PORT` | 9810 | 19810 | Poker Tour (its own `FLUTTER_WEB_PORT`) |
| `AITYX_INDEX_PORT` | 8800 | 18800 | The aityx demos' index, which the footer names |
| `DATYX_INDEX_PORT` | 9800 | 19800 | The datyx group's index, which the footer names |

Poker Tour's web port is `FLUTTER_WEB_PORT` in its folder, as every
Flutter demo's, so here it has a name of its own. The index reads only
its own environment, not the other folders' `.env`: move a demo to
another port and its variable here has to say so too.
