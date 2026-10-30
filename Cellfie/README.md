# Cellfie

Every generation, the cells take a picture of themselves, and aityx says
who's in it. Cellfie plays Conway's Game of Life on an infinite board, with the rules
of the game as a decision model on [aityx.ai](https://aityx.ai). Every
generation is one call to aityx: the app counts what is on the board
(every distinct situation a cell is in, and every cluster of live cells
with its shape), aityx decides what lives, what dies and what is born, and
names the well-known patterns among the clusters (still lifes, oscillators,
spaceships and methuselahs, as [Wikipedia](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life)
lists them), and the app draws the next board, labels the patterns,
notifies when one appears, and shows every call, request and response,
in a side panel. Conway's rules are on at the start; HighLife's birth with
six neighbours and Life without death can be switched on from **Rules**.
Pick a **Random start** (a sparse, medium or dense soup, islands, a glider
fleet, a zoo with one of each pattern, or a methuselah), press **Play**,
and set the **Acceleration** from half a generation a second to as fast
as aityx answers.

## Technology

| Part | Technology |
|---|---|
| App ([cellfie_app/](cellfie_app)) | [Flutter](https://flutter.dev) (Dart): web, Android, iOS and Linux from one codebase. It calls [aityx](https://aityx.ai) itself, from the browser, through the repository's shared package [aityx_web](../packages/aityx_web/README.md): there's no Cellfie API |
| Rules | The Life model, [cellfie_app/assets/models/life.json](cellfie_app/assets/models/life.json): a decision table with a why on every row, and the pattern catalogue |
| Serving | The repository's index server ([Index/](../Index)) serves the release web build at `/cellfie/`, beside the index page and the other aityx demos, on one origin |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/) |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl. It is the same
lock as Mortgage Hub's and Contact Hub's, so they share one Nix store.

## The aityx key

Every generation is a call to aityx on a key:

1. **Yours**: open the index page, http://localhost:8800/, and paste your
   key in **Your aityx key** (sign up at [aityx.ai](https://aityx.ai),
   then **API keys** in [console.aityx.ai](https://console.aityx.ai)). It
   stays in your browser, and every aityx demo uses it: the app calls
   aityx directly with it.
2. **A dev key**: with none of yours, if the repository's `.env` (see
   [../.env.example](../.env.example)) or the index server's environment
   has `AITYX_API_KEY`, the index server adds it to the calls through its
   own proxy. It never reaches the browser.

Without either, the board works, but a generation says
`aityx is not set up: set your key on the index page.` The dot at the top
right says which key is in use and whether aityx accepts it; tap it to
open the index page's key section.

## Run it locally

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/),
   or have Flutter (Dart 3.13 or newer) on your path.
2. From the repository root:

   ```bash
   ./start-aityx.sh Cellfie     # builds the app if it changed, starts the index server
   ```

3. Open http://localhost:8800/cellfie/ (and set your key on
   http://localhost:8800/ if you haven't).

`bash scripts/build.sh` (or `devbox run build`) builds the app's release
web build, `cellfie_app/build/web/`, only when it changed:
`flutter build web --release --base-href /cellfie/ --no-web-resources-cdn`
(CanvasKit from the app's own origin, so no third-party script runs where
your key is kept). The first build takes about 25 s on a laptop, a minute
or two on a 4-core codespace; the index server serves a new build on the
next reload.

Pick a **Random start** over the cells in view (soups of three
densities, islands, a glider fleet, a zoo with one of each pattern, the
R-pentomino or the acorn), or tap cells to draw; drag to move around the
infinite board and scroll to zoom. **Play** runs generations at the
**Acceleration** you set, **Step** runs one. Each generation is a call
to aityx, shown in the panel on the right with what it decided and the
JSON both ways (see [Calls panel](specs/calls-panel.md)); patterns aityx
recognizes are named on the board, and a notice says when one appears
(see [Patterns](specs/patterns.md)). **Rules** switches rules on and off
(see [Rules](specs/rules.md)).

### The model

[cellfie_app/assets/models/life.json](cellfie_app/assets/models/life.json)
is sent with every generation as the `decision` of `POST /v1/systemone`,
with the board as the `state`. Its `fate` function is the rules, a
decision table where each rule's rows fire only when its switch in
`state.rules` is on; its `identify` function is the pattern catalogue,
one row per phase of each pattern, generated from seeds by
`dart run tool/catalogue.dart` in `cellfie_app/` (`--check` says if it's
out of date); its `kind_of` function says what each pattern is. After
changing it, `bash scripts/model-test.sh` runs it on aityx with the key
from the repository's `.env`: all 18 situations against Conway's rules,
the other rules, every shape of the catalogue, and an empty board. See
[Generation](specs/generation.md).

### Building the binaries

The [Makefile](Makefile) builds release binaries through
[scripts/make.sh](scripts/make.sh):

```bash
make            # every platform this host can build
make web        # cellfie_app/build/web/, under /cellfie/
make android    # cellfie_app/build/app/outputs/flutter-apk/app-release.apk
make ios        # cellfie_app/build/ios/iphoneos/Runner.app (macOS, unsigned)
make linux      # cellfie_app/build/linux/<arch>/release/bundle/ (Linux only)
make clean
```

Pass `MODE=profile` or `MODE=debug` for other build modes,
`WEB_BASE_HREF` to serve the web build elsewhere, and `IOS_CODESIGN=1` to
sign the iOS build (this needs a signing team in Xcode). The native
builds have no index page and no dev proxy, and keep a key only in
memory: they run, but no generation can. The version is `X.Y.Z`: X and Y
from [version.X.txt](version.X.txt) and [version.Y.txt](version.Y.txt),
Z the build time (see [scripts/version.sh](scripts/version.sh)). The
artifact's group and artifact IDs, `aityx:cellfie`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

## Run it in a codespace

[![Open Cellfie and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens this repository's **aityx demos** dev container on a
4-core machine (16 GB RAM), which is what the Flutter builds want. It
starts Cellfie with the rest of its group, the aityx demos (Mortgage
Hub, Contact Hub, PokerFace, RoboRules and RiverRace), and the index
page that links them. To choose for yourself instead, use *Code →
Codespaces → New with options* and pick **aityx demos** as the dev
container configuration — the repository holds two groups of demos, each
with its own, so the configuration matters.

When the codespace is created,
[on-create.sh](../.devcontainer/on-create.sh) copies the group's
release web builds from the [published image](../image/) into the
workspace (a demo that changed since the image was made builds itself
instead, a minute or two). Then, on that and every later start,
[post-start.sh](../.devcontainer/post-start.sh) starts the index server,
which serves the index page and every aityx demo on port **8800**, the
only port, made public so the link can be shared. When the index page
opens, paste your [aityx](https://aityx.ai) key in **Your aityx key**,
then open Cellfie from its card, at `/cellfie/` on the same address.
Anyone you share the link with sets their own key.

Optionally, an `AITYX_API_KEY` Codespaces secret (at
[github.com/settings/codespaces](https://github.com/settings/codespaces),
**New secret**, with access to `aityx-labs/aityx-demos`) is a dev key
every visitor of your codespace uses unless they set their own: the index
server adds it to the calls through its own proxy, and it never reaches
a browser. `AITYX_URL` optionally selects another aityx endpoint for it.

Stop the group with `./stop-all.sh` from the repository root and start
it again with `./start-all.sh`: in the codespace both act on the aityx
group only (`DEMOS_GROUP=aityx`). There is no devbox in a codespace: the
demos are built with the image's own Flutter (`DEMOS_TOOLCHAIN=image`,
see [demos-toolchain.sh](../demos-toolchain.sh)).

**If the app doesn't start, send us `startup.log` from the root of the
repository.** Every step of the codespace's start goes there,
timestamped. It holds no secrets.

**Check the port's visibility.** In the **Ports** panel, the
*Visibility* column for 8800 should say **Public**. If it says
**Private**, right-click the port, choose **Port Visibility → Public**
and reload the page.

## Run it in a dev container locally

Open the repository root in VS Code and choose **Reopen in Container**,
then **aityx demos**. The dev containers live at the root of the
repository, in [.devcontainer/](../.devcontainer), because that is
where GitHub looks for them: one per demo group, Cellfie's in
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
   and `flutter test` in `cellfie_app/`, then `bash scripts/build.sh`.
   After changing the model, `bash scripts/model-test.sh` runs it on
   aityx; after changing the pattern seeds, `dart run tool/catalogue.dart`
   in `cellfie_app/` rewrites the catalogue.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
