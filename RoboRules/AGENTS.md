# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this project that means
  `flutter analyze` and `flutter test` pass in `roborules_app/`, and
  `bash scripts/build.sh` builds the web app the index serves at
  `/roborules/`. After changing `assets/models/world.json` or the world
  builder (`roborules_app/tool/build_world.py`), also run
  `bash scripts/model-test.sh`, which plays turns on aityx and checks the
  physics.
- **Secrets**, such as the aityx key (`AITYX_API_KEY`), live only in the
  repository's `.env` (the index server's dev key, and the model tests) or
  in the user's browser, where the index page saves the user's own. Never
  compile one into the app, print it, log it, show it in the aityx call
  viewer (it shows the request's body, never its headers), or put it on a
  command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and unnecessarily broad permissions or exposed
  ports. Never commit credentials, even placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- RoboRules runs entirely in the browser: the app calls aityx itself
  through the shared [aityx_web](../packages/aityx_web) package, and the
  index server (`Index/bin/server.dart`) serves its build at `/roborules/`.
  There is no API and no service of its own.
- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- The devcontainer build is documented in the [README](README.md).
