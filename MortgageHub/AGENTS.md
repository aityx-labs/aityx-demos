# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path (build, script, or the app in a browser), not just a syntax
  check. For this project that means `flutter analyze` and `flutter test`
  pass in `mortgagehub_app/`, and `bash scripts/build.sh` builds the web
  app (its `build/web/index.html` has `<base href="/mortgagehub/">` and
  loads no script from `gstatic`). After changing the model, run
  `bash scripts/model-test.sh`, which calls aityx.
- **The aityx key**: the user's key lives in their browser (set on the
  index page) and goes only to their aityx URL, as a header: never in a
  URL, a log, or what the app shows (the aityx request shown is the body,
  not the headers). The dev key (`AITYX_API_KEY`) lives only in the
  repository's `.env` or the index server's environment; never compile it
  into Flutter (no `--dart-define`), print it, or put it on a command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and third-party scripts on the app's origin
  (keep `--no-web-resources-cdn`). Never commit credentials, even
  placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- There are no services of its own: the repository's index (`Index/`)
  serves the web build at `/mortgagehub/`. Start it from the root with
  `./start-aityx.sh MortgageHub`; stop it with `./stop-aityx.sh`.
- The devcontainer build is documented in the [README](README.md).
