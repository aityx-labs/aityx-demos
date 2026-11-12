# Development environment

- **Toolchain**: [devbox.json](../devbox.json), Node 22 and curl, locked
  in [devbox.lock](../devbox.lock) (the same as tatyx's).
- **Build**: [scripts/build.sh](../scripts/build.sh), run by the
  repository's `build-all.sh` and `start-all.sh` (a folder of the index's
  group with a `scripts/build.sh` is one the index serves, see
  `demos-toolchain.sh`), or by hand (`devbox run build`). It runs `npm ci`
  when the packages are missing or older than the lock file, then `vite
  build` into `holidaysplit_app/build/web/` with the base
  `/demos/holidaysplit/`, only when the build is missing, was made with
  other settings (`build/web/.aityx-services`) or is older than the app,
  `packages/aityx_js` or the version files.
- **Serving**: the index server ([Index/bin/server.dart](../../Index/bin/server.dart))
  serves every folder of its group with a `<slug>_app/` that has a
  `pubspec.yaml` (the Flutter demos) or a `package.json` (this one), from
  `<slug>_app/build/web`. The `<base href>` in the build's `index.html`
  tells it the build was made for its path. The trip reader's worker and
  prompt (`public/reader/`) are copied into the build as they are, not
  bundled.
- **Dev server**: `devbox run dev` serves the sources with Vite on
  http://localhost:18811/demos/holidaysplit/ and proxies the rest of
  `/demos/` to the index on `INDEX_PORT` (8800), for the key page and the
  dev proxy.
- **Tests**: `npm test` in `holidaysplit_app/` (vitest), the trip reader's
  answer turned into the lists and held to the chat.
- **In a codespace**: the aityx group's image has Flutter but no Node, so
  `build-all.sh` and `start-all.sh` skip Holiday Split there (see
  `image_lacks` in `demos-toolchain.sh`) until the image carries Node.
