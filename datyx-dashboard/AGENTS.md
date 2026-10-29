# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims: run the relevant
  code path (build, script, or service), not just a syntax check. For this
  project that typically means `flutter analyze` and `flutter test` pass in
  `datyx_dashboard/`, and `devbox services up` still serves the dashboard
  and the health check cleanly, with the datyx API running from
  `../datyx/` (start the group: `./start-datyx.sh` at the
  repository root). A change to `compose.yaml` or
  `docker/` also gets a `docker compose up --wait`.
- **Secrets**: the dashboard holds none. Settings live in `.env` and the
  processes' environment (see `.env.example`); never print them or put
  them on a command line.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, and unnecessarily broad permissions or exposed
  ports. The published port binds to `127.0.0.1` unless `DATYX_BIND_HOST`
  says otherwise. Never commit credentials, even placeholders that look
  real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json): Flutter, make and
  curl, the same lock as the demos'. Enter it with `devbox shell` and keep
  [devbox.lock](devbox.lock) committed.
- `devbox services up` starts the processes in
  [process-compose.yaml](process-compose.yaml) plus the health monitor
  ([scripts/health-check.sh](scripts/health-check.sh)); stop with
  `devbox services stop`. In non-interactive contexts pass
  `--pcflags "--tui=false"`.
- Ports: 9906 the dashboard; the API it calls is datyx's, 9900. Never
  take an 88xx or 89xx port, which the demos use, nor 98xx, HealthHub's.
- No em dashes in prose. Never write "deterministic": say "predictable",
  or "the same inputs always produce the same result".
