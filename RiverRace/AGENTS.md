# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this project that means
  `flutter analyze` and `flutter test` pass in `riverrace_app/`, and
  `bash scripts/build.sh` builds the web app (its `build/web/index.html`
  has `<base href="/riverrace/">` and no `gstatic` script URL). After
  changing `riverrace_app/assets/models/river.json` or
  `riverrace_app/lib/aityx/decision_request.dart`, also run
  `bash scripts/model-test.sh`, which runs strategies on aityx.
- **Secrets**, such as the aityx key (`AITYX_API_KEY`), live only in the
  repository's `.env` (the index server's dev key, and the model tests)
  or in the user's browser (the key set on the index page). Never compile
  them into the app, print them, log them, or put them on a command line.
  The calls panel shows the request body, never the headers.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, third-party scripts on the app's origin (the
  web build uses `--no-web-resources-cdn`), and unnecessarily broad
  permissions or exposed ports. Never commit credentials, even
  placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- There is no API and there are no services here: the index server
  (`Index/bin/server.dart`) serves the web build at `/riverrace/`, started
  with `./start-all.sh` from the repository root. The app calls aityx
  itself through `packages/aityx_web`.
- The devcontainer build is documented in the [README](README.md).
