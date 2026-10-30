# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this project that means
  `flutter analyze` and `flutter test` pass in `pokerface_app/`, and
  `bash scripts/build.sh` builds the web app (base href `/pokerface/`, no
  CDN). After changing anything in `pokerface_app/assets/models/`, also
  run `bash scripts/model-test.sh`, which runs every strategy's rules on
  aityx.
- **Secrets**, such as the aityx key: a user's key lives only in their
  browser (set on the index page); the dev key (`AITYX_API_KEY`) only in
  the repository's root `.env`, read by the index server and by
  `scripts/model-test.sh`. Never compile a key into the app, print it,
  log it, show it in the calls sidebar, or put it on a command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, third-party scripts on the app's origin, and
  unnecessarily broad permissions or exposed ports. Never commit
  credentials, even placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- There are no services: the repository's index server serves the web
  build at `/pokerface/` (`./start-aityx.sh PokerFace` at the root). The
  app depends on the shared package `../packages/aityx_web` by path.
- The devcontainer build is documented in the [README](README.md).
