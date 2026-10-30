# Contact Hub

Contact Hub lets someone ask anything and gets the question to the right
department or person, with the checks it needs run on the way. For now the
welcome page takes the request, typed, dictated (speech is recognized in
the browser, so no audio leaves the device) or picked from a sample, and
the routing screen says where it went: [Jev](https://aityx.ai/docs/coming-from-jev)
classifies and checks the message and a decision model on
[aityx.ai](https://aityx.ai) picks the department, the person and the
priority. For a request about an order, it applies the store's policy to
the order's dates and amounts (refund within 30 days, store credit within
60, warranty, restocking fee, price drops, cancellations...) and says how
much is paid back, and by when. It shows why, and the aityx call itself,
with links that jump to exactly the JSON behind each item.

## Technology

| Part | Technology |
|---|---|
| App ([contacthub_app/](contacthub_app)) | [Flutter](https://flutter.dev) (Dart): web, Android, iOS and Linux from one codebase. It calls [aityx](https://aityx.ai) itself, from the browser, through the aityx demos' shared package, [packages/aityx_web](../packages/aityx_web/README.md) |
| Serving | The repository's index server ([Index/](../Index)) serves the release web build at `/contacthub/`, on one origin with the index page and the other aityx demos. There's no Contact Hub API |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/) |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl. It is the same
lock as Mortgage Hub's, so the two share one Nix store.

## Run it locally

From the repository root:

```bash
./start-all.sh ContactHub       # or ./start-all.sh for every demo
```

That builds the web app if it changed ([scripts/build.sh](scripts/build.sh):
`flutter build web --release --base-href /contacthub/ --no-web-resources-cdn`,
about 20 to 40 s on a laptop, nothing when it's up to date) and starts the
index server. Open the index page, http://localhost:8800/, paste your
[aityx](https://aityx.ai) key in **Your aityx key** (sign up at aityx.ai,
then **API keys** in console.aityx.ai), and open Contact Hub's card, or
http://localhost:8800/contacthub/. The key stays in your browser, and
every demo on that page uses it. With no key of yours, the index server
lends its dev key, `AITYX_API_KEY` in the repository's `.env` (see
[../.env.example](../.env.example)), through its own proxy: the key never
reaches the browser. Without either, the app runs, but **Send** says to
set your key.

Type a request, or press the microphone beside the field and say it: the
browser asks for the microphone the first time, and Chrome or Edge install
their on-device English pack, while other browsers download a small
speech model (see [Request box](specs/request.md)). Or pick one from
**Try a sample**: one for each department, and two for the checks.
**Send** routes it, with one aityx call from the app (see
[Routing](specs/routing.md)). The dot at the top right says whether aityx
accepts the key (see [aityx status light](specs/aityx-status.md)).

`bash scripts/build.sh` (or `devbox run build`) builds the web app on its
own, only if it changed.

### Building the binaries

The [Makefile](Makefile) builds release binaries through
[scripts/make.sh](scripts/make.sh):

```bash
make            # every platform this host can build
make web        # contacthub_app/build/web/
make android    # contacthub_app/build/app/outputs/flutter-apk/app-release.apk
make ios        # contacthub_app/build/ios/iphoneos/Runner.app (macOS, unsigned)
make linux      # contacthub_app/build/linux/<arch>/release/bundle/ (Linux only)
make clean
```

Pass `MODE=profile` or `MODE=debug` for other build modes, and
`IOS_CODESIGN=1` to sign the iOS build (this needs a signing team in Xcode).
The native apps have no index page and no dev proxy: their key store is in
memory only, so they start without a key and can't route yet.
The version is `X.Y.Z`: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time (see
[scripts/version.sh](scripts/version.sh)).
The artifact's group and artifact IDs, `aityx:contacthub`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

## Run it in a codespace

[![Open Contact Hub and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens this repository's **aityx demos** dev container on a
4-core machine (16 GB RAM), which is what the Flutter builds want. It
starts Contact Hub with the rest of its group, the aityx demos (Mortgage
Hub, Cellfie, PokerFace, RoboRules and RiverRace), and the index page
that links them. To choose for yourself instead, use *Code → Codespaces
→ New with options* and pick **aityx demos** as the dev container
configuration — the repository holds two groups of demos, each with its
own, so the configuration matters.

Once it's up, open the index page (port 8800, which Codespaces opens in
a browser tab for you), paste your [aityx](https://aityx.ai) key in **Your
aityx key**, and open Contact Hub's card: the app is at `/contacthub/` on
the same port. The `AITYX_API_KEY` Codespaces secret is optional: when set
(at [github.com/settings/codespaces](https://github.com/settings/codespaces),
with access to `aityx-labs/aityx-demos`), it's a dev key every visitor of
your codespace uses, with no key of their own.

When the codespace is created,
[on-create.sh](../.devcontainer/on-create.sh) copies the group's release
web builds from the [published image](../image/) into the workspace (a
demo that changed since the image was made builds itself instead, a
minute or so), and [post-start.sh](../.devcontainer/post-start.sh)
starts the index server with `./start-all.sh` on that and every later
start. Stop it with `./stop-all.sh` from the repository root and start
it again with `./start-all.sh`. There is no devbox in a codespace: the
demos build on the image's own Flutter (`DEMOS_TOOLCHAIN=image`, see
[demos-toolchain.sh](../demos-toolchain.sh)).

**If the app doesn't start, send us `startup.log` from the root of the
repository.** Every step of the codespace's start goes there,
timestamped. It holds no secrets.

## Run it in a dev container locally

Open the repository root in VS Code and choose **Reopen in Container**,
then **aityx demos**. The dev containers live at the root of the
repository, in [.devcontainer/](../.devcontainer), because that is
where GitHub looks for them: one per demo group, Contact Hub's in
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
   and `flutter test` in `contacthub_app/`, and `bash scripts/build.sh`.
   After changing the model (`contacthub_app/assets/models/routing.json`),
   `bash scripts/model-test.sh` runs its rules on aityx, and `dart run
   tool/route_samples.dart` in `contacthub_app/` routes every sample on
   aityx; both use the key in the repository's `.env`.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
