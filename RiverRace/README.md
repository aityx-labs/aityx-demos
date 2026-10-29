# RiverRace

The 1982 Atari river shooter, remade, with three planes up the same river
at once. Two are flown by [aityx.ai](https://aityx.ai), each by its own
**strategy**, a decision table of rules; the yellow one is yours. Who
scores more, the careful pilot or the daredevil, or you?

Everything of the original is there: a river with banks that widen and
narrow, islands, a bridge at the end of every section, tankers and
helicopters that start to patrol as you near them, jets that cross the
screen, fuel that runs out and depots to fill up over (or to shoot, for
80 points), one missile at a time that follows the plane, three planes in
reserve and one more every 10,000 points. Your plane is drawn solid, the
aityx pilots' mostly see-through (35% opaque), in cyan and magenta.

Every few frames, one call to aityx decides what both aityx pilots do:
the app sends what each plane senses (fuel, land ahead, where the open
water is, threats, depots, the next bridge...) and each pilot's rules,
and aityx answers each one's steer, throttle and fire, with the rule that
fired. Under the river, a card per pilot shows its score, fuel and rules,
the rule that just fired outlined; add, edit, move and remove rules, or
swap the whole strategy (Careful, Daredevil, Sharpshooter, Rookie), while
they fly. The panel on the right shows every call, the request sent and
the response received.

**← →** steer, **↑ ↓** faster and slower, **space** fires, **P** pauses.

## Technology

| Part | Technology |
|---|---|
| App ([riverrace_app/](riverrace_app)) | [Flutter](https://flutter.dev) (Dart): web, Android, iOS and Linux from one codebase |
| API ([riverrace_api/](riverrace_api)) | Dart (`dart:io`): holds the [aityx](https://aityx.ai) key and asks aityx what the pilots do |
| Rules | Each aityx pilot's strategy, a FIRST decision table built by [riverrace_api/lib/strategy.dart](riverrace_api/lib/strategy.dart) on the types in [riverrace_api/models/river.json](riverrace_api/models/river.json) |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/), process-compose for the services either way; or [Docker Compose](compose.yaml) |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl. It is the same
lock as the other aityx demos', so they share one Nix store.

## Run it locally with devbox

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/).
2. Put your [aityx](https://aityx.ai) key in `.env` (copy
   [.env.example](.env.example)): the same `AITYX_API_KEY` as Mortgage
   Hub's and Contact Hub's, for instance
   `grep '^AITYX_' ../ContactHub/.env > .env`. Without it the game runs,
   but the aityx pilots fly straight on.
3. From this folder:

   ```bash
   devbox services up           # add --pcflags "--tui=false" when not in a terminal
   ```

That starts, from [process-compose.yaml](process-compose.yaml):

| URL | What |
|---|---|
| http://localhost:8940/app/ | The app's release build, served by a small native web server ([scripts/flutter-web.sh](scripts/flutter-web.sh)). The first start builds it (about 20 s on a laptop, a minute or two on a 4-core codespace); later starts reuse it until the app changes |
| http://localhost:8941/api/health | The API, compiled to a native executable ([scripts/api.sh](scripts/api.sh)); the web app reaches it as `/api/` on its own origin, through the web server's proxy |

That's what Docker Compose serves too, and it keeps the machine free:
the two servers hold about 35 MB between them. For hot reload while
working on the app, run the Flutter dev server instead, with
`WEB_MODE=debug devbox services up`, or on its own with `devbox run web`
(press `r` in its terminal). `devbox run build` builds the web build and
the executables ahead of time ([scripts/build.sh](scripts/build.sh)),
only what changed.

The ports are 8940 and 8941, so RiverRace runs alongside the other
demos (Mortgage Hub 8880, Contact Hub 8890, PokerFace 8910, RoboRules
8920, Cellfie 8930). Press **Start** and fly; see [Game](specs/game.md)
for the rules of play, [Strategies](specs/strategies.md) for the sensors,
commands and rule editor, [Decisions](specs/decisions.md) for how aityx
flies the pilots (in real time, or as a **Fair race** where the game
waits for aityx), and [Calls panel](specs/calls-panel.md).

Once both are ready, the `health-check` monitor prints where to open the
app (in a codespace, its forwarded URL too), waits 5 s
(`HEALTH_CHECK_DELAY`), then logs one line every 15 s
(`HEALTH_CHECK_INTERVAL`); 🤖 [aityx](https://aityx.ai) is ⚪ when the API
has no key:

```
RiverRace is up. Open the app at:
  http://localhost:8940/app/
Health checks start in 5 s, then every 15 s.
2026-10-23 12:07:31 🌐 Web ✅ · 🔌 API ✅ · 🤖 aityx ✅
```

Stop everything with `devbox services stop`. To run only the app, use
`devbox run web`, the dev server with hot reload (set `FLUTTER_WEB_PORT`
to change the port, `WEB_MODE=release` for the release build); only the
API, `devbox run api` (`API_PORT`).

### The model

[riverrace_api/models/river.json](riverrace_api/models/river.json)
holds the types (`Sense`, what a plane senses, and `Act`, what it does).
For each decision the API adds, per aityx pilot, an input with what its
plane senses, a function `strategy_p1` or `strategy_p2` with its rules as
a FIRST decision table (with an else row, straight on, when the
strategy has none), and a decision calling it, and sends that as the
`decision` of `POST /v1/systemone`. After changing it, `bash
scripts/model-test.sh` runs strategies on aityx. See
[Decisions](specs/decisions.md).

### Building the binaries

The [Makefile](Makefile) builds release binaries through
[scripts/make.sh](scripts/make.sh):

```bash
make            # every platform this host can build
make web        # riverrace_app/build/web/
make android    # riverrace_app/build/app/outputs/flutter-apk/app-release.apk
make ios        # riverrace_app/build/ios/iphoneos/Runner.app (macOS, unsigned)
make linux      # riverrace_app/build/linux/<arch>/release/bundle/ (Linux only)
make clean
```

Pass `MODE=profile` or `MODE=debug` for other build modes, and
`IOS_CODESIGN=1` to sign the iOS build (this needs a signing team in Xcode).
The version is `X.Y.Z`: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time (see
[scripts/version.sh](scripts/version.sh)).
The artifact's group and artifact IDs, `aityx:riverrace`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

## Run it with Docker Compose

With only [Docker](https://docs.docker.com/get-docker/) installed (no
devbox, no Flutter), from this folder:

```bash
docker compose up --build
```

and open http://localhost:8940/app/. [compose.yaml](compose.yaml) builds
and starts two services:

| Service | What |
|---|---|
| `web` | The app's release web build ([docker/web.Dockerfile](docker/web.Dockerfile)), served by nginx under `/app/`, with `/api/` proxied to the API ([docker/nginx.conf](docker/nginx.conf)) |
| `api` | The API compiled to a native executable ([riverrace_api/Dockerfile](riverrace_api/Dockerfile)); not published, reached only through `web` |

For the key, copy [.env.example](.env.example) to `.env` and fill in
`AITYX_API_KEY` (or export it); optionally set `AITYX_URL` for another
HTTPS endpoint. Both values go to the API only, never the web app. The first build
takes a few minutes (it downloads Flutter); later ones
reuse Docker's cache. Set `FLUTTER_WEB_PORT` to change the port; the app
is bound to 127.0.0.1 unless you set `RIVERRACE_BIND_HOST=0.0.0.0`. Stop
it with `docker compose down`. Both services have health checks, so
`docker compose up --wait` returns once they are healthy. There is no hot
reload: rebuild after a change.

## Run it in a codespace

[![Open RiverRace and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens this repository's **aityx demos** dev container on a
4-core machine (16 GB RAM), which is what the Flutter builds want. It
starts RiverRace with the rest of its group, the aityx demos (Mortgage
Hub, Contact Hub, Cellfie, PokerFace and RoboRules), and the index page
that links them. To choose for yourself instead, use *Code → Codespaces
→ New with options* and pick **aityx demos** as the dev container
configuration — the repository holds two groups of demos, each with its
own, so the configuration matters.

The codespace uses your [aityx](https://aityx.ai) key, the same
`AITYX_API_KEY` Codespaces secret as Mortgage Hub's and Contact Hub's.
The optional `AITYX_URL` secret selects a non-default HTTPS endpoint;
otherwise the API uses `https://api.aityx.ai`. Both settings are passed
only to the API process, never to Flutter or the web service.
GitHub keeps Codespaces secrets per user and grants them per repository,
so if your key already reaches this repository, there is nothing to do.
Otherwise add it at
[github.com/settings/codespaces](https://github.com/settings/codespaces)
(**New secret**, name `AITYX_API_KEY`, access to
`aityx-labs/aityx-demos`), or enter it when GitHub asks on the creation
page. Without it the game runs, but the aityx pilots fly straight on.

When the codespace is created,
[on-create.sh](../.devcontainer/on-create.sh) copies the group's
release web builds from the [published image](../image/) into the
workspace (a demo that changed since the image was made builds itself
instead, a minute or two),
[update-content.sh](../.devcontainer/update-content.sh) compiles each
API and web server (a few seconds each) and
[post-create.sh](../.devcontainer/post-create.sh) says whether your key
arrived. Then, on that and every later start,
[post-start.sh](../.devcontainer/post-start.sh) starts the index page
and the aityx group in the background with `./start-all.sh` and makes
their ports public, RiverRace's **8940** among them. There is nothing to
run: the codespace is available about three minutes after you ask for
it and the apps answer within a minute after that; open port 8940
from the **Ports** panel, or RiverRace's card on the index page (port
8800, which Codespaces opens in a browser tab for you). Its bare URL
redirects to the app at `/app/`.

Watch RiverRace's services with `process-compose attach -U -u
/tmp/aityx-demos-RiverRace.sock`. Stop the group with `./stop-all.sh`
from the repository root and start it again with `./start-all.sh`: in
the codespace both act on the aityx group only (`DEMOS_GROUP=aityx`).
There is no devbox in a codespace: the demos run on the image's own
Flutter and process-compose (`DEMOS_TOOLCHAIN=image`, see
[demos-toolchain.sh](../demos-toolchain.sh)); `devbox services` is for a
laptop.

**If the app doesn't start, send us `startup.log` from the root of the
repository.** Every step of the codespace's start goes there,
timestamped, including a line saying when each demo's web app and API
first answered. It holds no secrets.

**Check the port's visibility.** In the **Ports** panel, the
*Visibility* column for 8940 should say **Public**. If it says
**Private**, right-click the port, choose **Port Visibility → Public**
and reload the app.

## Run it in a dev container locally

Open the repository root in VS Code and choose **Reopen in Container**,
then **aityx demos**. The dev containers live at the root of the
repository, in [.devcontainer/](../.devcontainer), because that is
where GitHub looks for them: one per demo group, RiverRace's in
[.devcontainer/aityx/](../.devcontainer/aityx), with the scripts both
share beside them. It runs the aityx group's
[published image](../image/), `docker.io/aletyxcode/samples-and-demos-aityx`,
built from the [Containerfile](../image/Containerfile) by
`bash image/build-image.sh aityx`: Microsoft's `ubuntu-24.04` base with
pinned, checksum-verified Flutter, process-compose and the GitHub CLI,
and the six aityx demos' release web builds.

## Contributing

1. Create a branch from an up-to-date `main`.
2. Make one change per pull request, with its tests. Run `flutter analyze`
   and `flutter test` in `riverrace_app/`, and `dart analyze` and
   `dart test` in `riverrace_api/`. After changing the model or
   `riverrace_api/lib/strategy.dart`, `bash scripts/model-test.sh` runs
   strategies on aityx.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
