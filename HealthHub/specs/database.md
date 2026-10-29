# Database

HealthHub's data lives in PostgreSQL 17, the `postgres` service of
[compose.yaml](../compose.yaml), the official `postgres:17` image with
its data in the `postgres-data` Docker volume. It is the same container
in every way of running the demo:

- `docker compose up` runs it with the API and the web app, on the
  compose network, where the API reaches it as `postgres:5432`.
- `devbox services up` ([process-compose.yaml](../process-compose.yaml))
  runs it alone from the same file, `docker compose up postgres` attached
  through [scripts/infra.sh](../scripts/infra.sh) (`1-postgres`), and the
  API on the host reaches it on the published port, 127.0.0.1:9803
  (`HEALTHHUB_DB_PORT`). The process's readiness probe is the container's
  health, and its shutdown is `docker compose stop postgres`, so the
  container and its data outlive the services. `bash scripts/infra.sh
  down -v` removes the container and the volume; `bash scripts/infra.sh
  psql` opens a prompt as the `healthhub` user.
- A dev container adds Docker with the `docker-in-docker` feature and
  does the same as a laptop.

On the first start of an empty volume the image runs
[docker/postgres-init.sh](../docker/postgres-init.sh), which creates the
`healthhub` user, with `HEALTHHUB_DB_PASSWORD` (`healthhub` by default,
a development password), and the `healthhub` database it owns. The
superuser's password is `HEALTHHUB_DB_ADMIN_PASSWORD` (`postgres`). The
container is healthy once `pg_isready` sees the `healthhub` database.

The schema is the API's ([API](api.md),
[lib/db.dart](../healthhub_api/lib/db.dart)): at start it creates what is
missing, so a fresh database works without a separate migration step:

| Table | Columns | What |
|---|---|---|
| `greetings` | `id SERIAL PRIMARY KEY`, `message TEXT NOT NULL`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()` | The greeting the app shows. One row, "Hello, world", inserted when the table is empty; `GET /api/hello` reads the first by `id` |

## Known limitations

- A development password, and no TLS between the API and the database:
  fine on a laptop, a codespace or the compose network, not anywhere
  shared.
- No migration tool yet: the API's `CREATE TABLE IF NOT EXISTS` is the
  whole schema management. A real schema will want one.
