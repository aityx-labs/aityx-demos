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
| App ([riverrace_app/](riverrace_app)) | [Flutter](https://flutter.dev) (Dart), on the web: it asks [aityx](https://aityx.ai) what the pilots do itself, from the browser, through the shared package [aityx_web](../packages/aityx_web/README.md). No API of its own |
| Rules | Each aityx pilot's strategy, a FIRST decision table built by [lib/aityx/decision_request.dart](riverrace_app/lib/aityx/decision_request.dart) on the types in [assets/models/river.json](riverrace_app/assets/models/river.json) |
| Served by | The [index server](../Index/), with the index page and the other aityx demos, at `/riverrace/` on one origin |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/) |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl. It is the same
lock as the other aityx demos', so they share one Nix store.

## Run it locally

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/),
   or Flutter itself.
2. From the repository root:

   ```bash
   ./start-all.sh               # or ./start-aityx.sh for the aityx demos alone
   ```

   It builds RiverRace's web app when it changed
   ([scripts/build.sh](scripts/build.sh): `flutter build web --release
   --base-href /riverrace/ --no-web-resources-cdn`, about 20 s on a
   laptop) and starts the index server, which serves it at
   **http://localhost:8800/riverrace/**, with the index page and the other
   aityx demos on the same origin.
3. Set your [aityx](https://aityx.ai) key once, in **Your aityx key** on
   the index page (http://localhost:8800/#aityx-key): sign up at aityx.ai,
   then create a key under API keys in console.aityx.ai. Every aityx demo
   uses it. Or put `AITYX_API_KEY` in the repository's `.env` (see
   [../.env.example](../.env.example)) for a dev key: the index server
   adds it to the app's calls, and it never reaches the browser.
   Without a key the game runs, but the aityx pilots fly straight on and
   the light in the top right corner is red.

Press **Start** and fly; see [Game](specs/game.md) for the rules of play,
[Strategies](specs/strategies.md) for the sensors, commands and rule
editor, [Decisions](specs/decisions.md) for how aityx flies the pilots,
[aityx calls](specs/api.md) for whose key a call uses, and
[Calls panel](specs/calls-panel.md).

`devbox run build` (or `bash scripts/build.sh`) builds the web app ahead
of time, only when it changed. There is no hot reload: rebuild and reload
the page.

### The model

[riverrace_app/assets/models/river.json](riverrace_app/assets/models/river.json)
holds the types (`Sense`, what a plane senses, and `Act`, what it does).
For each decision the app adds, per aityx pilot, an input with what its
plane senses, a function `strategy_p1` or `strategy_p2` with its rules as
a FIRST decision table (with an else row, straight on, when the
strategy has none), and a decision calling it, and sends that as the
`decision` of `POST /v1/systemone`. After changing it, `bash
scripts/model-test.sh` runs strategies on aityx, with the key from the
repository's `.env`. See [Decisions](specs/decisions.md).

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
A native build has no index page and no dev proxy, and keeps a key only in
memory, which nothing sets yet: the game runs, but its aityx pilots fly
straight on.
The version is `X.Y.Z`: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time (see
[scripts/version.sh](scripts/version.sh)).
The artifact's group and artifact IDs, `aityx:riverrace`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

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

Set your [aityx](https://aityx.ai) key in **Your aityx key** on the
index page, as when running locally. Optionally, an `AITYX_API_KEY`
Codespaces secret (at
[github.com/settings/codespaces](https://github.com/settings/codespaces),
with access to `aityx-labs/aityx-demos`) gives the index server a dev key
that every visitor of your codespace uses.

When the codespace is created,
[on-create.sh](../.devcontainer/on-create.sh) copies the group's
release web builds from the [published image](../image/) into the
workspace (a demo that changed since the image was made builds itself
instead, a minute or two). Then, on that and every later start,
[post-start.sh](../.devcontainer/post-start.sh) starts the index server,
which serves RiverRace at `/riverrace/` on port **8800**; Codespaces
opens it in a browser tab for you, or open it from the **Ports** panel and
add `/riverrace/`, or use RiverRace's card on the index page.

**If the app doesn't start, send us `startup.log` from the root of the
repository.** Every step of the codespace's start goes there,
timestamped. It holds no secrets.

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
   and `flutter test` in `riverrace_app/`, and `bash scripts/build.sh`.
   After changing the model or
   `riverrace_app/lib/aityx/decision_request.dart`, `bash
   scripts/model-test.sh` runs strategies on aityx.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
