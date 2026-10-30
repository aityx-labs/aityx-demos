# PokerFace

PokerFace is a poker simulator, a no-limit Texas hold'em tournament at
a table of up to nine, where every player is a set of rules. The rules are a decision
model run on [aityx.ai](https://aityx.ai), called from the browser: at
each turn the app works out
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
| App ([pokerface_app/](pokerface_app)) | [Flutter](https://flutter.dev) (Dart): web, Android, iOS and Linux from one codebase. The table itself (the deal, the betting rounds, side pots, the showdown) runs in the app, and so does every call to aityx: there is no server of its own |
| aityx from the browser ([packages/aityx_web](../packages/aityx_web/README.md)) | The repository's shared package: finds the key (the one you set on the index page, else the index server's dev key), calls aityx's `/v1/systemone`, and draws the aityx light |
| Rules ([pokerface_app/assets/models/](pokerface_app/assets/models)) | [table.json](pokerface_app/assets/models/table.json), the situation a player sees, and one [strategy](pokerface_app/assets/models/strategies) per file: the decisions of the model, an action table and a raise expression |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/) |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl. It is the same
lock as Mortgage Hub's and Contact Hub's, so they share one Nix store.

## Run it locally

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/).
2. From the repository root:

   ```bash
   ./start-aityx.sh PokerFace
   ```

   That builds the app's release web build if it's missing or stale
   ([scripts/build.sh](scripts/build.sh): about 30 s on a laptop, a
   minute or two on a 4-core codespace) and starts the index server,
   which serves it at **http://localhost:8800/pokerface/**, with the index
   page and the other aityx demos on the same origin.
3. Set your [aityx](https://aityx.ai) key once, in **Your aityx key** on
   the index page (http://localhost:8800/#aityx-key): sign up at
   aityx.ai, then create a key under API keys in console.aityx.ai. Every
   aityx demo on that origin uses it. Or, for development, put
   `AITYX_API_KEY` in the repository's root `.env` (see
   [../.env.example](../.env.example)): the index server then adds it to
   the app's calls through its dev proxy, and the key never reaches the
   browser.

Without a key the app opens, but nobody can act: the light at the top
right is red, and each decision says "aityx is not set up: set your key
on the index page". The table opens with five players, one per strategy.
Press **Play** and watch; the slider sets the pace, **Step** plays one
step at a time while paused, a tap on a seat shows and edits that
player's rules, **Players** adds and removes players and shows the
strategies (see [The table](specs/table.md) and [Players and
strategies](specs/players.md)). The sidebar lists every call to aityx;
tap one for the whole request and response (see [The aityx
calls](specs/calls.md)).

`bash scripts/build.sh` (or `devbox run build`) builds the web app ahead
of time, only when it changed. `flutter run -d chrome` in
`pokerface_app/` gives hot reload, but on an origin of its own: it sees
neither the key set on the index page nor the dev proxy, so decisions
need a key saved in that origin's storage (`aityx.key` in
`localStorage`).

### Testing

In `pokerface_app/`, `flutter analyze` and `flutter test`: the table's
engine (hand ranks, side pots, the betting rounds), the screens, the
table logic and every aityx call path against a mock (see [Deciding on
aityx](specs/aityx.md)).

`bash scripts/model-test.sh` runs every strategy on aityx with fixed
situations (a premium hand before the flop, a flush draw facing a bet, a
free flop in the big blind, ...) and checks that each plays in character:
[model_scenarios_test.dart](pokerface_app/test/model_scenarios_test.dart),
tagged `aityx`, which `flutter test` skips. It reads `AITYX_API_KEY` from
the environment, else the repository's root `.env`. Run it after changing
a model.

### Building the binaries

The [Makefile](Makefile) builds release binaries through
[scripts/make.sh](scripts/make.sh):

```bash
make            # every platform this host can build
make web        # pokerface_app/build/web/ (base href /pokerface/)
make android    # pokerface_app/build/app/outputs/flutter-apk/app-release.apk
make ios        # pokerface_app/build/ios/iphoneos/Runner.app (macOS, unsigned)
make linux      # pokerface_app/build/linux/<arch>/release/bundle/ (Linux only)
make clean
```

Pass `MODE=profile` or `MODE=debug` for other build modes, and
`IOS_CODESIGN=1` to sign the iOS build (this needs a signing team in Xcode).
The native builds have no dev proxy and only an in-memory key store,
empty at start, so they can't call aityx yet.
The version is `X.Y.Z`: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time (see
[scripts/version.sh](scripts/version.sh)).
The artifact's group and artifact IDs, `aityx:pokerface`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

## Run it in a codespace

[![Open PokerFace and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens this repository's **aityx demos** dev container on a
4-core machine (16 GB RAM), which is what the Flutter builds want. It
serves PokerFace with the rest of its group, the aityx demos (Mortgage
Hub, Contact Hub, Cellfie, RoboRules and RiverRace), and the index page
that links them, all on the index's port, 8800. To choose for yourself
instead, use *Code → Codespaces → New with options* and pick **aityx
demos** as the dev container configuration — the repository holds two
groups of demos, each with its own, so the configuration matters.

When the codespace is created,
[on-create.sh](../.devcontainer/on-create.sh) copies the group's release
web builds from the [published image](../image/) into the workspace (a
demo that changed since the image was made builds itself instead, a
minute or two). Then, on that and every later start,
[post-start.sh](../.devcontainer/post-start.sh) starts the index server
with `./start-all.sh`. Open port 8800 (Codespaces opens it in a browser
tab for you), set your aityx key in **Your aityx key**, and open
PokerFace's card, `/pokerface/`.

An `AITYX_API_KEY` Codespaces secret is optional: it becomes a dev key
that every visitor of your codespace uses, through the index server's
proxy, so nobody has to set one. Add it at
[github.com/settings/codespaces](https://github.com/settings/codespaces)
(**New secret**, name `AITYX_API_KEY`, access to
`aityx-labs/aityx-demos`).

Stop the group with `./stop-all.sh` from the repository root and start it
again with `./start-all.sh`. There is no devbox in a codespace: the demos
build on the image's own Flutter (`DEMOS_TOOLCHAIN=image`, see
[demos-toolchain.sh](../demos-toolchain.sh)).

**If the app doesn't start, send us `startup.log` from the root of the
repository.** Every step of the codespace's start goes there,
timestamped. It holds no secrets.

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
   and `flutter test` in `pokerface_app/`, `bash scripts/build.sh`, and
   `bash scripts/model-test.sh` after changing a model.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
- [Strategies](specs/strategies.md): what a strategy sees and how its
  rules are written.
- [Deciding on aityx](specs/aityx.md): whose key, the call, and its
  errors.
