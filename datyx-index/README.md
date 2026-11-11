# datyx index

The index of the datyx group: one page, in the aityx palette, with a
card per system (what it is, its technology, **Open** for it on its port
here or, in a codespace, its forwarded URL, more links on that port where
a card has them (the dashboard's **Training** and **Inference** tabs), **Source** on GitHub, and
**Codespace** for the datyx group's dev container): the datyx dashboard, the datyx API
(whose health check covers OpenMetadata) and HealthHub. The six aityx demos have their own index,
[../Index/](../Index/).

- [www/index.html](www/index.html): the page. The cards' text is in it;
  the port of each system comes from the server ([Settings](#settings)),
  so the same page is right on a local run, on the cluster and in a
  codespace. It does not say which ones are up.
- [bin/server.dart](bin/server.dart): a plain Dart server (no packages).
  `GET /` is the page (`/app/` too, so `start-all.sh` checks it like a
  demo); `GET /api/demos` lists every folder beside this one with a
  `process-compose.yaml` whose `group.id.txt` says `datyx`, the web and
  API ports it defaults to, and whether its web app (or its API, for the
  datyx API, which has no app) answers right now, for scripts; or, with
  `INDEX_DEMOS` set (`<folder>=<URL to check>,...`, for a container,
  which has no folders beside it), exactly the folders it names.
  `GET /api/settings` answers the ports the page links to and names,
  and whether this copy runs on the cluster ([Settings](#settings)).
  `GET /api/health` answers `{"ok": true}`.
- Port **9800** (`INDEX_PORT`), the first of the datyx group's ports,
  bound to 127.0.0.1 (`INDEX_BIND_HOST`).
- [group.id.txt](group.id.txt) says `datyx`: `./start-datyx.sh` and
  `./stop-datyx.sh` at the repository's root take it with the group.

## Run it

From this folder, with [Devbox](https://www.jetify.com/devbox):

```bash
devbox services up            # the index on http://localhost:9800/
devbox run serve              # the same, in the foreground
```

or, with Dart on the PATH, `dart bin/server.dart`. From the root of the
repository, `./start-datyx.sh` starts it with the group and prints its
link last; `./stop-datyx.sh` stops it.

On the local Kubernetes cluster (`bash k8s/deploy.sh datyx-index` at the
root; [k8s/](k8s/), image [docker/datyx-index.Dockerfile](docker/datyx-index.Dockerfile))
it's on http://localhost:19800/. [k8s/deployment.yaml](k8s/deployment.yaml)
sets the ports below to the ones the cluster publishes on this host, each
system's usual port plus 10000, and `INDEX_ON_CLUSTER`, so the cards open
the cluster's copies and the footer names the cluster's scripts.
[k8s/verify.sh](k8s/verify.sh) checks it.

## Settings

All from the server's environment; a local run needs none of them. The
page reads the ports and `INDEX_ON_CLUSTER` from `GET /api/settings`
(`{"cluster": false, "ports": {"DATYX_API_PORT": 9900, ...}}`, the ports
by these names) and builds its links, the ports in its text and its
footer from them: it never looks at its own port. In a codespace the
same ports go in the forwarded host names. A value that is not a port
(or, for `INDEX_ON_CLUSTER`, not `true`, `1`, `false` or `0`) stops the
server at start.

| Variable | Default | On the cluster | What |
|---|---|---|---|
| `INDEX_PORT` | 9800 | 9800 | The port the server listens on |
| `INDEX_BIND_HOST` | 127.0.0.1 | 0.0.0.0 | The address it binds |
| `INDEX_GROUP` | datyx | datyx | The group `/api/demos` lists |
| `INDEX_DEMOS` | unset | the three Services | `<folder>=<URL to check>,...` for `/api/demos`, where no folders are beside the server |
| `INDEX_ON_CLUSTER` | false | true | This copy runs on the local Kubernetes cluster: the footer says so and how to deploy and delete it, and each card names the ports the cluster publishes (the datyx API's and OpenMetadata's, HealthHub's and Flink's) and not the whole range of a local run |
| `DATYX_INDEX_PORT` | `INDEX_PORT` | 19800 | Where a browser reaches this index: the first port of the footer's range |
| `DATYX_DASHBOARD_WEB_PORT` | 9906 | 19906 | The datyx dashboard (its own `FLUTTER_WEB_PORT`) |
| `DATYX_API_PORT` | 9900 | 19900 | The datyx API, as in [datyx/.env.example](../datyx/.env.example) |
| `DATYX_OPENMETADATA_PORT` | 9902 | 19902 | OpenMetadata's UI, as in datyx/.env.example |
| `DATYX_DEBUG_PORT` | 9905 | not set | The last of the datyx API's ports in a local run, its debugger's, for the card's "Ports 9900 to 9905"; the cluster publishes none, and its page does not name it |
| `HEALTHHUB_WEB_PORT` | 9801 | 19801 | HealthHub's app (its own `FLUTTER_WEB_PORT`) |
| `HEALTHHUB_FLINK_PORT` | 9806 | 19806 | Flink's web UI, the last of HealthHub's ports, as in [HealthHub/.env.example](../HealthHub/.env.example) |
| `AITYX_INDEX_PORT` | 8800 | 18800 | The aityx demos' index, which the footer names |
| `MULTYX_INDEX_PORT` | 9700 | 19700 | The multyx group's index, which the footer names |

The dashboard's and HealthHub's web port is `FLUTTER_WEB_PORT` in each
of their folders, so here each has a name of its own. The index reads
only its own environment, not the other folders' `.env`: move a system
to another port and its variable here has to say so too.
