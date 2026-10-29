# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path (build, script, or service), not just a syntax check. For this
  project that typically means `flutter analyze` and `flutter test` pass in
  `mortgagehub_app/`, `dart analyze` and `dart test` in `mortgagehub_api/`,
  and `devbox services up` still starts the web server, the API and the
  health check cleanly.
- **The aityx key** (`AITYX_API_KEY`) lives only in `.env` and the API's
  environment. Never pass it to Flutter, print it, or put it on a command
  line; never send it anywhere but the configured `AITYX_URL`.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and unnecessarily broad permissions or exposed
  ports. Never commit credentials, even placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- `devbox services up` starts the processes in
  [process-compose.yaml](process-compose.yaml) plus the health monitor
  ([scripts/health-check.sh](scripts/health-check.sh)); stop with
  `devbox services stop`. In non-interactive contexts pass
  `--pcflags "--tui=false"`.
- The devcontainer build is documented in the [README](README.md).
