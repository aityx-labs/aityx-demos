# Mortgage Hub

Mortgage Hub brings a home buyer's mortgage, from application to closing,
into one place. For now the app is a welcome page with a form to request
a mortgage proposal, and a regulatory check that says whether a lender can
process it under current US rules, run by [aityx.ai](https://aityx.ai).

## Technology

| Part | Technology |
|---|---|
| App ([mortgagehub_app/](mortgagehub_app)) | [Flutter](https://flutter.dev) (Dart): web, Android, iOS and Linux from one codebase |
| API ([mortgagehub_api/](mortgagehub_api)) | Dart (`dart:io`): holds the [aityx](https://aityx.ai) key and runs the regulatory check |
| Rules | An [aityx.ai](https://aityx.ai) decision model ([proposal-check.json](mortgagehub_api/models/proposal-check.json)) |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/), process-compose for the services either way; or [Docker Compose](compose.yaml) |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl.

## Run it with Docker Compose

With only [Docker](https://docs.docker.com/get-docker/) installed (no
devbox, no Flutter), from this folder:

```bash
docker compose up --build
```

and open http://localhost:8880/app/. [compose.yaml](compose.yaml) builds
and starts two services:

| Service | What |
|---|---|
| `web` | The app's release web build ([docker/web.Dockerfile](docker/web.Dockerfile)), served by nginx under `/app/`, with `/api/` proxied to the API ([docker/nginx.conf](docker/nginx.conf)) |
| `api` | The API compiled to a native executable ([mortgagehub_api/Dockerfile](mortgagehub_api/Dockerfile)); not published, reached only through `web` |

For the regulatory check, copy [.env.example](.env.example) to `.env`
and fill in your [aityx](https://aityx.ai) key, `AITYX_API_KEY` (or
export it). The settings come from your environment, else `.env`, and go
to the API only. The first build takes a few minutes
(it downloads Flutter); later ones reuse Docker's cache. Set
`FLUTTER_WEB_PORT` to change the port; the app is bound to 127.0.0.1
unless you set `MORTGAGEHUB_BIND_HOST=0.0.0.0`. Stop it with
`docker compose down`. Both services have health checks, so
`docker compose ps` shows them `healthy`, and `docker compose up --wait`
returns once they are. Unlike [devbox](#run-it-locally-with-devbox), there is no hot
reload: rebuild after a change.

## Run it locally with devbox

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/).
2. For the regulatory check, put your own [aityx](https://aityx.ai) settings in `.env` (see
   [.env.example](.env.example)): `AITYX_API_KEY`, and
   `AITYX_URL=https://api-stage.aityx.ai` for a stage key. In a
   codespace GitHub asks for the key instead; see
   [Run it in a codespace](#run-it-in-a-codespace). Check them
   with `bash scripts/aityx-check.sh`, and the mortgage rules with
   `bash scripts/model-test.sh`.
3. From this folder:

   ```bash
   devbox services up           # add --pcflags "--tui=false" when not in a terminal
   ```

That starts, from [process-compose.yaml](process-compose.yaml):

| URL | What |
|---|---|
| http://localhost:8880/app/ | The app's release build, served by a small native web server ([scripts/flutter-web.sh](scripts/flutter-web.sh)). The first start builds it (about 20 s on a laptop, a minute or two on a 4-core codespace); later starts reuse it until the app changes |
| http://localhost:8881/api/health | The API, compiled to a native executable ([scripts/api.sh](scripts/api.sh)); the web app reaches it as `/api/` on its own origin, through the web server's proxy |

That's what Docker Compose serves too, and it keeps the machine free:
the two servers hold about 35 MB between them. For hot reload while
working on the app, run the Flutter dev server instead, with
`WEB_MODE=debug devbox services up`, or on its own with `devbox run web`
(press `r` in its terminal). `devbox run build` builds the web build and
the executables ahead of time ([scripts/build.sh](scripts/build.sh)),
only what changed.

A `health-check` monitor logs one line every 15 s (set
`HEALTH_CHECK_INTERVAL` to change it): the time, then each check as its
emoji, a short label and ✅ ok / ❌ failed (🤖 [aityx](https://aityx.ai) is ⚪ when the API
has no key):

```
2026-10-13 12:35:54 🌐 Web ✅ · 🔌 API ✅ · 🤖 aityx ✅
```

Stop everything with `devbox services stop`. To run only the app, use
`devbox run web`, the dev server with hot reload (set `FLUTTER_WEB_PORT`
to change the port, `WEB_MODE=release` for the release build); only the
API, `devbox run api` (`API_PORT`).

### Building the binaries

The [Makefile](Makefile) builds release binaries through
[scripts/make.sh](scripts/make.sh):

```bash
make            # every platform this host can build
make web        # mortgagehub_app/build/web/
make android    # mortgagehub_app/build/app/outputs/flutter-apk/app-release.apk
make ios        # mortgagehub_app/build/ios/iphoneos/Runner.app (macOS, unsigned)
make linux      # mortgagehub_app/build/linux/<arch>/release/bundle/ (Linux only)
make clean
```

Pass `MODE=profile` or `MODE=debug` for other build modes, and
`IOS_CODESIGN=1` to sign the iOS build (this needs a signing team in Xcode).
The version is `X.Y.Z`: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time (see
[scripts/version.sh](scripts/version.sh)).
The artifact's group and artifact IDs, `aityx:mortgagehub`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

## Run it in a codespace

### 1. Set your [aityx](https://aityx.ai) key — required

The regulatory check runs on [aityx.ai](https://aityx.ai), and it needs an
API key. The key is always **yours**: none ships with this repository and
none is built into the container. Without it the codespace still starts and
the app still opens, but the regulatory check — what this demo exists to
show — cannot run.

Set it once, before launching:

1. Open your [aityx](https://aityx.ai) console's **API keys** page and copy a key.
2. Go to
   [github.com/settings/codespaces](https://github.com/settings/codespaces).
3. Under **Codespaces secrets**, choose **New secret**.
4. Name it exactly `AITYX_API_KEY`, paste the key as the value, and give
   it access to the `aityx-labs/aityx-demos` repository.
5. For a non-default endpoint, add an optional `AITYX_URL` Codespaces
   secret and give it access to the same repository. For a stage key, set
   it to `https://api-stage.aityx.ai`; otherwise leave it unset to use
   `https://api.aityx.ai`.

![The New secret form: name AITYX_API_KEY, the key as the value, and access to aityx-labs/aityx-demos](docs/images/codespaces-new-secret.png)

If you skip this, GitHub asks for the key on the codespace creation page,
because [devcontainer.json](../.devcontainer/aityx/devcontainer.json)
lists it as a required secret. Either way GitHub keeps it against your
account and passes it to the container as an environment variable: it is
never written to disk there, never committed, and never reaches the Flutter
app.

The API URL defaults to `https://api.aityx.ai` and the payment estimate's
rate to 6.5%. To change either locally, put `AITYX_URL` or `ASSUMED_RATE`
in `.env` (see [.env.example](.env.example)). In Codespaces, set
`AITYX_URL` as described above. A stage key works only against
`https://api-stage.aityx.ai`.

### 2. Launch it

[![Open Mortgage Hub and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens this repository's **aityx demos** dev container on a
4-core machine (16 GB RAM): Mortgage Hub starts with the rest of its
group, the aityx demos (Contact Hub, Cellfie, PokerFace, RoboRules and
RiverRace), and the index page that links them, from
[start-all.sh](../start-all.sh). To choose for yourself instead, use
*Code → Codespaces → New with options* and pick **aityx demos** as the
dev container configuration; the repository holds two groups of demos,
each with its own, and the other one, **datyx demos**, doesn't include
Mortgage Hub. Mortgage Hub's own dev container, the one the group's
were copied from, is kept in
[.devcontainer/archive/MortgageHub/](../.devcontainer/archive/MortgageHub).

The creation page should look like this, with **aityx demos** as the dev
container configuration (the screenshot still shows the former
**Mortgage Hub** one), a 4-core machine, and `AITYX_API_KEY` under
*Recommended secrets*, ticked as associated with the repository. If it is
not ticked, the secret does not reach this repository; go back to step 1.

![The Create a new codespace page, with Mortgage Hub, 4-core and AITYX_API_KEY associated with the repository](docs/images/create-codespace.png)

### 3. Run the app

When the codespace is created,
[on-create.sh](../.devcontainer/on-create.sh) copies the group's
release web builds from the [published image](../image/) into the
workspace (a demo that changed since the image was made builds itself,
a minute or two, while the others are already up),
[update-content.sh](../.devcontainer/update-content.sh) compiles the
APIs and web servers (a few seconds each) and
[post-create.sh](../.devcontainer/post-create.sh) says whether your key
arrived. Then, on that and every later start,
[post-start.sh](../.devcontainer/post-start.sh) starts the index page
and the aityx group in the background with `./start-all.sh` and makes
port **8880** public, with the other demos' ports. There is nothing to run: the codespace is available about three
minutes after you ask for it and the demos answer within a minute after
that; open port 8880 from the **Ports** panel, or from the Mortgage Hub
card on the index page (port 8800, which Codespaces opens in a browser
tab for you). Its bare URL redirects to the app at `/app/`.

Watch Mortgage Hub's services with `process-compose attach -U -u
/tmp/aityx-demos-MortgageHub.sock`. Stop the group with `./stop-all.sh`
from the repository root and start it again with `./start-all.sh`: in
the codespace both act on the aityx group only (`DEMOS_GROUP=aityx`).
There is no devbox in a codespace: the demos run on the
image's own Flutter and process-compose (`DEMOS_TOOLCHAIN=image`, see
[demos-toolchain.sh](../demos-toolchain.sh)); `devbox services` is for
a laptop.

**If the app doesn't start, send us `startup.log` from the root of the
repository.** Every step of the codespace's start goes there,
timestamped: the builds, what `start-all.sh` says as each demo answers
(or, after 15 minutes without, that it didn't), and the ports'
visibility. Open it from the Explorer, or right-click it and choose
**Download**. It holds no secrets: your key and token appear only as
*set* or *not set*.

**Check the port's visibility.** In the **Ports** panel, the
*Visibility* column for 8880 should say **Public**. The codespace sets
it when it starts and again when VS Code attaches, but GitHub does not
always apply it, and an organization can forbid public ports. If it says
**Private**, right-click the port, choose **Port Visibility → Public**
and reload the app. The panel can also lag behind the real setting; from
a terminal, `gh codespace ports -c "$CODESPACE_NAME"` shows it, and
`startup.log` says whether the automatic change worked.

A public port opens for anyone you share the link with — and they run
regulatory checks on your [aityx](https://aityx.ai) key. Set it back to
private in the **Ports** panel if you don't want that.

## Run it in a dev container locally

Open the repository root in VS Code and choose **Reopen in Container**,
then **aityx demos**. The dev containers live at the root of the
repository, in [.devcontainer/](../.devcontainer), because that is where
GitHub looks for them: one per demo group, Mortgage Hub's in
[.devcontainer/aityx/](../.devcontainer/aityx). It starts the aityx
group and the index page, this demo among them.

It runs the aityx group's [published image](../image/),
`docker.io/aletyxcode/samples-and-demos-aityx`, built from the
[Containerfile](../image/Containerfile) by
`bash image/build-image.sh aityx`: Microsoft's `ubuntu-24.04`
devcontainer base image with pinned, checksum-verified releases of
Flutter, process-compose and the GitHub CLI, and the six aityx demos'
release web builds.

Codespaces secrets are a GitHub feature, so set the key here by copying
[.env.example](.env.example) to `.env` and filling in `AITYX_API_KEY`. The
scripts read the environment first and fall back to `.env`, so the same
commands work either way.

## Contributing

1. Create a branch from an up-to-date `main`.
2. Make one change per pull request, with its tests. Run `flutter analyze`
   and `flutter test` in `mortgagehub_app/`, and `dart analyze` and
   `dart test` in `mortgagehub_api/`.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
