# The demos on Kubernetes

Every demo also runs on a local Kubernetes cluster, made with
[kind](https://kind.sigs.k8s.io): one node in Docker, with the demos' images
in a local registry. The cluster runs beside the demos that
`./start-all.sh` runs, on the same ports plus 10000.

## Quick start

```bash
brew install kind          # kubectl comes with Docker Desktop
bash k8s/up.sh             # the registry, the cluster, the namespaces and the settings
bash k8s/deploy.sh         # build, push, deploy and check every demo (a first run takes a while)
bash k8s/verify.sh         # check them again
bash k8s/down.sh           # delete the cluster and its data (the registry and its images stay)
```

`bash k8s/deploy.sh tatyx PokerTour` deploys only those. `BUILD=0` applies
the manifests and restarts without building (after `bash k8s/secrets.sh`,
for instance).

Running every demo takes about 7 GB of Docker's memory, on top of what the
local demos use. Docker Desktop needs 14 GB or more to run both (Settings,
Resources, Memory).

## Where to open them

Each demo is on its usual port plus 10000, on this host only (127.0.0.1):
the six aityx demos at http://localhost:18800/demos/, the multyx index at
http://localhost:19700/ and the datyx index at http://localhost:19800/,
which link to the rest. The root [README](../README.md#ports) lists every
port, local and on the cluster. The stores (PostgreSQL, Kafka,
Elasticsearch, Floci) are reachable in the cluster only; reach one from
here with `kubectl --context kind-aityx-demos -n <group> port-forward`.

## How it fits together

- **The cluster**: [kind/cluster.yaml](kind/cluster.yaml), one node named
  `aityx-demos`, context `kind-aityx-demos`. Every script names the
  context, so nothing reaches another cluster. Each demo's Service is a
  NodePort at its usual port plus 22000, which kind publishes on the host.
- **The registry**: `kind-registry`, on `localhost:5001`. Each demo's
  `k8s/build.sh` builds its images and pushes them there, as
  `localhost:5001/aityx-demos/<name>:dev`. At most two builds run at once
  (`K8S_BUILD_SLOTS`): a Flutter web build takes a gigabyte or two.
- **The namespaces**: one per group, `aityx`, `multyx` and `datyx`, as in
  each folder's `group.id.txt`.
- **The settings**: [secrets.sh](secrets.sh) copies the root `.env` into the
  Secret `demo-env` in each namespace, without the production settings
  (`*_PROD_*`). Like a local run, the cluster runs on aityx staging, and
  without an `AITYX_URL` the staging keys stay out. Run it again after
  changing the `.env`, then `BUILD=0 bash k8s/deploy.sh` the demos that read
  it.
- **Each demo**: its `k8s/` folder holds its manifests (`kustomization.yaml`),
  `build.sh` and `verify.sh`. [deploy.sh](deploy.sh) builds, applies,
  restarts the demo's own workloads on the new images and waits for them;
  once every demo named is up, it runs each one's `verify.sh`.

## Google sign-in

On the cluster, each demo signs in with the Google OAuth client below,
which lists its cluster origins as authorized JavaScript origins, next to
the local ones (Google Cloud console, Google Auth Platform, Clients). The
datyx API and its dashboard ask for no sign-in on the cluster, as in a
local run without a `datyx/.env`: every call there is the Local profile,
which owns the development data (HealthHub's sources, their catalogue and
models). A signed-in user would get a new, empty profile, since datyx
seeds that data only into the profiles there at its start
([datyx/k8s/api.yaml](../datyx/k8s/api.yaml)).

| Client (Google project) | Demos | Cluster origins |
|---|---|---|
| `healthhub` (aletyxcode-healthhub) | HealthHub | `http://localhost:19800`, `:19801` and `:19906`, and the same on `http://127.0.0.1` |
| `pokertour-web` (aletyxcode-pokertour) | Poker Tour | `http://localhost:19810` |
| `tatyx-web` (aletyxcode-tatyx) | tatyx | `http://localhost:19710` |

Serve a demo from another address and that address must be added too, or
Google refuses the sign-in with `origin_mismatch`.
