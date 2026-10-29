# PokerFace

PokerFace is a poker simulator, a no-limit Texas hold'em tournament at
a table of up to nine, where every player is a set of rules. The rules are a decision
model run on [aityx.ai](https://aityx.ai): at each turn the app works out
the player's situation (cards, hand, equity, the pot, what it costs to
call, position, who is still to act, and a random number for strategies
that mix their play), and one aityx call runs the player's strategy on it
and answers with the action, the amount, and the rule that decided it,
with its reason. The table shows the hand like an online poker room,
avatars, chips and all; the blinds go up every ten hands, there are no
rebuys, and when one player has every chip the winner and their strategy
are announced. A sidebar shows every call to aityx (the request and the
response, with the key parts marked) and the hand log, where every action
expands into the rule that fired and the situation behind it. A slider
sets the pace, from one step at a time to as fast as aityx answers.

Five strategies come with it, each a file of rules: the Rock, the Maniac,
the Calling Station, the Mathematician and the Shark. Add players with
any of them, tap a player to read their rules and add, remove or reorder
them for that player, or write a strategy of your own from one and seat
it at the table.

## Technology

| Part | Technology |
|---|---|
| App ([pokerface_app/](pokerface_app)) | [Flutter](https://flutter.dev) (Dart): web, Android, iOS and Linux from one codebase. The table itself (the deal, the betting rounds, side pots, the showdown) runs in the app |
| API ([pokerface_api/](pokerface_api)) | Dart (`dart:io`): holds the [aityx](https://aityx.ai) key, serves the strategies and runs each decision on aityx |
| Rules ([pokerface_api/models/](pokerface_api/models)) | [table.json](pokerface_api/models/table.json), the situation a player sees, and one [strategy](pokerface_api/models/strategies) per file: the decisions of the model, an action table and a raise expression |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/), process-compose for the services either way; or [Docker Compose](compose.yaml) |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl. It is the same
lock as Mortgage Hub's and Contact Hub's, so they share one Nix store.

## Run it locally with devbox

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/).
2. Put your [aityx](https://aityx.ai) key in `.env` (copy
   [.env.example](.env.example)): the same `AITYX_API_KEY` as Mortgage
   Hub's, for instance `grep '^AITYX_' ../MortgageHub/.env > .env`.
   Without it the app opens, but nobody can act.
3. From this folder:

   ```bash
   devbox services up           # add --pcflags "--tui=false" when not in a terminal
   ```

That starts, from [process-compose.yaml](process-compose.yaml):

| URL | What |
|---|---|
| http://localhost:8910/app/ | The app's release build, served by a small native web server ([scripts/flutter-web.sh](scripts/flutter-web.sh)). The first start builds it (about 25 s on a laptop, a minute or two on a 4-core codespace); later starts reuse it until the app changes |
| http://localhost:8911/api/health | The API, compiled to a native executable ([scripts/api.sh](scripts/api.sh)); the web app reaches it as `/api/` on its own origin, through the web server's proxy |

That's what Docker Compose serves too, and it keeps the machine free:
the two servers hold about 30 MB between them. For hot reload while
working on the app, run the Flutter dev server instead, with
`WEB_MODE=debug devbox services up`, or on its own with `devbox run web`
(press `r` in its terminal). `devbox run build` builds the web build and
the executables ahead of time ([scripts/build.sh](scripts/build.sh)),
only what changed.

The ports are 8910 and 8911, so PokerFace runs alongside Mortgage Hub
(8880) and Contact Hub (8890). The table opens with five players, one per
strategy. Press **Play** and watch; the slider sets the pace, **Step**
plays one step at a time while paused, a tap on a seat shows and edits
that player's rules, **Players** adds and removes players and shows the
strategies (see [The table](specs/table.md) and [Players and
strategies](specs/players.md)). The sidebar lists every
call to aityx; tap one for the whole request and response (see
[The aityx calls](specs/calls.md)).

Once both are ready, the `health-check` monitor prints where to open the
app (in a codespace, its forwarded URL too), waits 5 s
(`HEALTH_CHECK_DELAY`), then logs one line every 15 s
(`HEALTH_CHECK_INTERVAL`); 🤖 [aityx](https://aityx.ai) is ⚪ when the API
has no key:

```
PokerFace is up. Open the app at:
  http://localhost:8910/app/
Health checks start in 5 s, then every 15 s.
2026-10-23 14:02:10 🌐 Web ✅ · 🔌 API ✅ · 🤖 aityx ✅
```

Stop everything with `devbox services stop`. To run only the app, use
`devbox run web`, the dev server with hot reload (set `FLUTTER_WEB_PORT`
to change the port, `WEB_MODE=release` for the release build); only the
API, `devbox run api` (`API_PORT`).

### Testing the strategies on aityx

`bash scripts/model-test.sh` runs every strategy on aityx with fixed
situations (a premium hand before the flop, a flush draw facing a bet, a
free flop in the big blind, ...) and checks that each plays in character:
[model_scenarios_test.dart](pokerface_api/test/model_scenarios_test.dart).
Run it after changing a model. `dart test` in `pokerface_api/` skips it,
and checks the API's own logic; `flutter test` in `pokerface_app/` runs
the table's engine through its paces (hand ranks, side pots, the betting
rounds) and the screens.

### Building the binaries

The [Makefile](Makefile) builds release binaries through
[scripts/make.sh](scripts/make.sh):

```bash
make            # every platform this host can build
make web        # pokerface_app/build/web/
make android    # pokerface_app/build/app/outputs/flutter-apk/app-release.apk
make ios        # pokerface_app/build/ios/iphoneos/Runner.app (macOS, unsigned)
make linux      # pokerface_app/build/linux/<arch>/release/bundle/ (Linux only)
make clean
```

Pass `MODE=profile` or `MODE=debug` for other build modes, and
`IOS_CODESIGN=1` to sign the iOS build (this needs a signing team in Xcode).
The version is `X.Y.Z`: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time (see
[scripts/version.sh](scripts/version.sh)).
The artifact's group and artifact IDs, `aityx:pokerface`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

## Run it with Docker Compose

With only [Docker](https://docs.docker.com/get-docker/) installed (no
devbox, no Flutter), from this folder:

```bash
docker compose up --build
```

and open http://localhost:8910/app/. [compose.yaml](compose.yaml) builds
and starts two services:

| Service | What |
|---|---|
| `web` | The app's release web build ([docker/web.Dockerfile](docker/web.Dockerfile)), served by nginx under `/app/`, with `/api/` proxied to the API ([docker/nginx.conf](docker/nginx.conf)) |
| `api` | The API compiled to a native executable ([pokerface_api/Dockerfile](pokerface_api/Dockerfile)), with the models; not published, reached only through `web` |

For the key, copy [.env.example](.env.example) to `.env` and fill in
`AITYX_API_KEY` (or export it); it goes to the API only. The first build
takes a few minutes (it downloads Flutter); later ones reuse Docker's
cache. Set `FLUTTER_WEB_PORT` to change the port; the app is bound to
127.0.0.1 unless you set `POKERFACE_BIND_HOST=0.0.0.0`. Stop it with
`docker compose down`. Both services have health checks, so
`docker compose up --wait` returns once they are healthy. There is no hot
reload: rebuild after a change.

## Run it in a codespace

[![Open PokerFace and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens this repository's **aityx demos** dev container on a
4-core machine (16 GB RAM), which is what the Flutter builds want. It
starts PokerFace with the rest of its group, the aityx demos (Mortgage
Hub, Contact Hub, Cellfie, RoboRules and RiverRace), and the index page
that links them. To choose for yourself instead, use *Code → Codespaces
→ New with options* and pick **aityx demos** as the dev container
configuration — the repository holds two groups of demos, each with its
own, so the configuration matters.

The codespace uses your [aityx](https://aityx.ai) key, the same
`AITYX_API_KEY` Codespaces secret as Mortgage Hub's and Contact Hub's.
GitHub keeps Codespaces secrets per user and grants them per repository,
so if your key already reaches this repository, there is nothing to do.
Otherwise add it at
[github.com/settings/codespaces](https://github.com/settings/codespaces)
(**New secret**, name `AITYX_API_KEY`, access to
`aityx-labs/aityx-demos`), or enter it when GitHub asks on the creation
page. Without it the app opens, but nobody can act.

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
their ports public, PokerFace's **8910** among them. There is nothing to
run: the codespace is available about three minutes after you ask for
it and the apps answer within a minute after that; open port 8910
from the **Ports** panel, or PokerFace's card on the index page (port
8800, which Codespaces opens in a browser tab for you). Its bare URL
redirects to the app at `/app/`.

Watch PokerFace's services with `process-compose attach -U -u
/tmp/aityx-demos-PokerFace.sock`. Stop the group with `./stop-all.sh`
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
*Visibility* column for 8910 should say **Public**. If it says
**Private**, right-click the port, choose **Port Visibility → Public**
and reload the app.

## Run it in a dev container locally

Open the repository root in VS Code and choose **Reopen in Container**,
then **aityx demos**. The dev containers live at the root of the
repository, in [.devcontainer/](../.devcontainer), because that is
where GitHub looks for them: one per demo group, PokerFace's in
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
   and `flutter test` in `pokerface_app/`, `dart analyze` and `dart test`
   in `pokerface_api/`, and `bash scripts/model-test.sh` after changing a
   model.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
- [Strategies](specs/strategies.md): what a strategy sees and how its
  rules are written.
