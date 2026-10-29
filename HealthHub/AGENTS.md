# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path (build, script, or service), not just a syntax check. For this
  project that typically means `flutter analyze` and `flutter test` pass in
  `healthhub_app/`, `dart analyze` and `dart test` in `healthhub_api/`,
  and `devbox services up` still starts PostgreSQL, the web server, the
  API and the health check cleanly, with `/api/hello` answering from the
  database.
- **Secrets**, such as the aityx key (`AITYX_API_KEY`) and the database
  password (`HEALTHHUB_DB_PASSWORD`), live only in `.env` and the API's
  environment. Never pass them to Flutter, print them, or put them on a
  command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks (every SQL statement takes its values as
  parameters), and unnecessarily broad permissions or exposed ports.
  Never commit credentials, even placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed. PostgreSQL
  is not in it: it runs as the `postgres` container of
  [compose.yaml](compose.yaml), so Docker is needed too.
- `devbox services up` starts the processes in
  [process-compose.yaml](process-compose.yaml) plus the health monitor
  ([scripts/health-check.sh](scripts/health-check.sh)); stop with
  `devbox services stop`. In non-interactive contexts pass
  `--pcflags "--tui=false"`.
- The devcontainer build is documented in the [README](README.md).
