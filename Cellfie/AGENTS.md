# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this project that means
  `flutter analyze` and `flutter test` pass in `cellfie_app/`, and
  `bash scripts/build.sh` builds the web app (served by the index server
  at `/cellfie/`). After changing `cellfie_app/assets/models/life.json`,
  also run `bash scripts/model-test.sh`, which runs its rules on aityx.
- **Secrets**, such as the aityx key: users set their own on the index
  page, kept in their browser; the optional dev key (`AITYX_API_KEY`)
  lives only in the repository's `.env` or the index server's
  environment, and `scripts/model-test.sh` exports it to the tests only.
  Never compile a key into the app (`--dart-define`), print it, log it,
  show it in the calls panel (the request shown is the body, never the
  headers), or put it on a command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and unnecessarily broad permissions or exposed
  ports. Never commit credentials, even placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- There are no services of Cellfie's own: the app calls aityx from the
  browser through the shared package
  [packages/aityx_web](../packages/aityx_web/README.md), and the
  repository's index server serves the build. Run it with
  `./start-aityx.sh` from the repository root and open
  http://localhost:8800/cellfie/.
- The devcontainer build is documented in the [README](README.md).
