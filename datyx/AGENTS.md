# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims: run the relevant
  code path (build, script, or service), not just a syntax check. For this
  project that typically means `./mvnw verify` passes in `datyx-api/`
  (the tests start a Postgres test container, so Docker must be up), and
  `devbox services up` still starts PostgreSQL, Elasticsearch,
  OpenMetadata, the API and the health check cleanly. A change to an
  endpoint the dashboard uses also gets the dashboard run against it
  (`../datyx-dashboard/`, started with the group: `./start-datyx.sh` at the
  repository root). A change to
  `compose.yaml` or `docker/` also gets a `docker compose up --wait`.
- **Secrets** and passwords live only in `.env` and the services'
  environment (see `.env.example`). Never print them or put them on a
  command line. The defaults in `.env.example` are development values.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and unnecessarily broad permissions or exposed
  ports. Every published port binds to `127.0.0.1` unless
  `DATYX_BIND_HOST` says otherwise. Never commit credentials, even
  placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json): GraalVM CE (the JDK,
  with `native-image`) and Maven. Enter it with `devbox shell` and keep
  [devbox.lock](devbox.lock) committed. `JAVA_HOME` is set by the shell's
  init hook. Flutter is the dashboard's, in its own folder.
- `devbox services up` starts the processes in
  [process-compose.yaml](process-compose.yaml) plus the health monitor
  ([scripts/health-check.sh](scripts/health-check.sh)); stop with
  `devbox services stop`. In non-interactive contexts pass
  `--pcflags "--tui=false"`.
- Ports: 9900 the API and 99xx for the rest (see [.env.example](.env.example));
  9906 is the dashboard's, in `../datyx-dashboard/`. Never take an 88xx or
  89xx port, which the demos use, nor 98xx, HealthHub's.
- The version is `${revision}` in [datyx-api/pom.xml](datyx-api/pom.xml), set by the scripts
  from the version files ([scripts/version.sh](scripts/version.sh)). Bump
  [version.X.txt](version.X.txt) or [version.Y.txt](version.Y.txt), never
  the pom.
- No em dashes in prose. Never write "deterministic": say "predictable",
  or "the same inputs always produce the same result".
