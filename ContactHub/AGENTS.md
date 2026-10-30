# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path (build, script, or service), not just a syntax check. For this
  project that means `flutter analyze` and `flutter test` pass in
  `contacthub_app/`, and `bash scripts/build.sh` builds the web app (with
  `<base href="/contacthub/">` in `contacthub_app/build/web/index.html`).
  After changing `contacthub_app/assets/models/routing.json`, also run
  `bash scripts/model-test.sh`, which runs its rules on aityx.
- **Secrets**, such as the aityx key: users set theirs on the index page,
  in their browser; the dev key (`AITYX_API_KEY`) lives only in the
  repository's `.env`, which the index server reads. Never compile a key
  into the app, show it on screen (the aityx call shown is the request
  body, never its headers), print it, or put it on a command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and unnecessarily broad permissions or exposed
  ports. Never commit credentials, even placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- There's no API or service of its own: the app calls aityx itself
  (package `aityx_web`, `../packages/aityx_web`), and the repository's
  index server (`Index/`) serves the web build at `/contacthub/`. Start it
  with `./start-all.sh ContactHub` from the repository root.
- The devcontainer build is documented in the [README](README.md).
