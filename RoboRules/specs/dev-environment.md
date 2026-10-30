# Development environment

RoboRules runs entirely in the browser: the app calls aityx itself, and
there is no API, web server or service of its own. The repository's index
server ([Index/bin/server.dart](../../Index/bin/server.dart), port 8800)
serves its release web build at **`/roborules/`**, beside the index page
and the other five aityx demos, all on one origin, so a key set once on
the index page works in every demo.

## The aityx key

The shared [aityx_web](../../packages/aityx_web) package finds it, in this
order:

1. **The user's key**, saved by the index page's **Your aityx key**
   section in the browser (`sessionStorage`, else `localStorage`, under
   `aityx.key`, with `aityx.url`, by default `https://api.aityx.ai`). The
   app calls `<url>/v1/systemone` directly, with `Authorization: Bearer
   <key>`.
2. **The dev key**: with no user key, the app asks `/aityx/config` at the
   origin's root. When the index server has a key (`AITYX_API_KEY` in its
   environment or the repository's `.env`), the app POSTs to
   `/aityx/v1/systemone` on the same origin, with no key, and the index
   server forwards it to aityx with its key, which never reaches the
   browser.
3. **None**: the [light](window.md) is red and a battle says "aityx is not
   set up: set your key on the index page".

The aityx call viewer shows the request's body, never its headers, which
carry the key.

## Running it

- `./start-aityx.sh RoboRules` from the repository's root (or
  `./start-aityx.sh` for the whole aityx group) builds the app if it's
  stale and starts the index server: http://localhost:8800/roborules/.
  `./stop-aityx.sh` stops it.
- **The build** ([scripts/build.sh](../scripts/build.sh), `devbox run
  build`, also run by the repository's `build-all.sh` and `start-all.sh`):
  `scripts/make.sh web` with `WEB_BASE_HREF=/roborules/`, which runs
  `flutter build web --release --base-href /roborules/
  --no-web-resources-cdn` (CanvasKit from our own origin, so no
  third-party script runs on the origin that holds the key) with the
  version's dart-defines. It builds only when `roborules_app/build/web` is
  missing or older than the app's `lib/`, `web/`, `assets/`, pubspecs, the
  shared package's `lib/` and pubspec, or the version files, and also when
  the build doesn't record its settings (`build/web/.aityx-services`:
  `base_href=/roborules/ web_resources_cdn=no`, written once a build
  succeeds and required to be newer than the build, so a `make web` by
  hand with other settings isn't reused). A start after no change builds
  nothing; a first start, or one after a change, takes the build (about
  25 s on a laptop, a minute or two on a 4-core codespace). One Flutter web
  build runs at a time across the repository's demos, through a lock
  directory in the system's temp folder
  (`aityx-demos-flutter-web-build.lock`, holding the builder's PID; a lock
  whose process is gone, or that never got its PID and is a minute old, is
  taken over), so starting every demo at once doesn't thrash a small
  machine; the checks run inside the lock, so two starts that overlap
  build once. `build/` is git-ignored.
- `make` (or `make web`) builds the app through
  [scripts/make.sh](../scripts/make.sh) (`MODE`, `WEB_BASE_HREF`); `make
  clean`. The app is web only. Served anywhere but the index server (a
  static host, or `flutter run`), it has no dev proxy, and no key until one
  is saved on that origin's index page.
- Toolchain: [devbox.json](../devbox.json) (Flutter, make, curl).

## Tests

- `flutter analyze` and `flutter test` in `roborules_app/`: the battle's
  model ([test/battle_test.dart](../roborules_app/test/battle_test.dart)),
  the calls to aityx against a mock client
  ([test/api_test.dart](../roborules_app/test/api_test.dart)), the
  controller, the window and the robots.
- `bash scripts/model-test.sh` (`devbox run model-test`) runs the tests
  tagged `aityx`
  ([test/model_scenarios_test.dart](../roborules_app/test/model_scenarios_test.dart)),
  skipped by a plain `flutter test` (`dart_test.yaml`): scripted battles
  played on aityx with `AITYX_API_KEY` and `AITYX_URL` from the
  environment, else the repository's `.env`, exported to the test only.
- `python3 tool/build_world.py assets/models/world.json`, from
  `roborules_app/`, rewrites the world model.

## Dev container

The aityx group's ([.devcontainer/aityx/](../../.devcontainer/aityx)),
named **aityx demos**, shared with the other five aityx demos (there is no
per-demo one), forwarding the index's port 8800, the only one. An
`AITYX_API_KEY` Codespaces secret is optional: it becomes the index
server's dev key. It uses the group's published image
(`docker.io/aletyxcode/samples-and-demos-aityx`, built by
`bash image/build-image.sh aityx`, see [image/](../../image/)), which
carries the six aityx demos' release web builds: `on-create.sh` copies
them into the workspace (unless a demo's folder changed since the image
was made: then that app builds itself), `update-content.sh` runs
`build-all.sh` for the group and `post-start.sh` starts the index, which
serves them all. Every step goes to `startup.log` at the root of the
repository (see [startup-log.sh](../../.devcontainer/startup-log.sh)).
