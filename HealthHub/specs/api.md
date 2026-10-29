# API

[healthhub_api](../healthhub_api/bin/server.dart), a Dart server that
holds the aityx key, which must never reach the app, and talks to
PostgreSQL ([Database](database.md), [lib/db.dart](../healthhub_api/lib/db.dart)).
Routes in [lib/routes.dart](../healthhub_api/lib/routes.dart), which
decides the answers without a server or a database so it can be tested,
and [bin/server.dart](../healthhub_api/bin/server.dart), which asks the
database for the two routes that need it:

| Request | Answer |
|---|---|
| `GET /` | 302 to `/app/`, so a forwarded port's bare URL opens the app |
| `GET /api/health` | `{"ok": true, "db": <whether the database answers SELECT 1>, "aityx": <whether the API has its key>, "auth": <whether authentication is on>}` |
| `GET /api/hello` | `{"message": "Hello, world", "since": <when the row was written, ISO 8601 UTC>, "postgres": <the server's version()>, "user": <the signed-in user's subject, email, name and picture, or null>}`, the first row of `greetings`; with a signed-in user the message is `Hello, <name>`; 503 `{"error": "the database is not answering"}` when it can't be read |
| `GET /api/auth/config` | How to sign in: `{"enabled": <whether OIDC_CLIENT_ID is set>, "issuer": "https://accounts.google.com", "clientId": <the id, or null>}`; the app reads it at start |
| `GET /api/me` | Who the bearer token says is calling: `{"authenticated": true, "subject", "email", "name", "picture"}`; 401 `{"error": "sign in first"}` without a valid token once authentication is on; `{"authenticated": false}` while it's off |
| `GET /api/datyx/me`, `GET /api/datyx/datasources` | The datyx API's `/api/me` and `/api/datasources`, asked with the user's own token, so datyx sees the same person; the answer and its status pass through; 401 without a user once authentication is on, 502 `{"error": "the datyx API is not answering"}` when datyx doesn't answer |
| `OPTIONS` anything | 204 |
| anything else | 404 `{"error": "not found"}` |

The API reads from its environment `AITYX_API_KEY` and `AITYX_URL`
(default `https://api.aityx.ai`, which must be https; nothing calls it
yet), `API_PORT` (9801), `HEALTHHUB_BIND_HOST` (127.0.0.1),
`ALLOWED_ORIGINS` and the database settings `HEALTHHUB_DB_HOST`
(127.0.0.1), `HEALTHHUB_DB_PORT` (9802), `HEALTHHUB_DB_NAME`,
`HEALTHHUB_DB_USER` (both `healthhub`) and `HEALTHHUB_DB_PASSWORD`,
`OIDC_ISSUER` (default `https://accounts.google.com`), `OIDC_CLIENT_ID`
(empty: authentication off) and `DATYX_API_URL` (default
`http://127.0.0.1:9900`; Compose points it at the host's port 9900
through `host.docker.internal`, or, with `compose.datyx.yaml` as a second
`-f` file, at the `api` service of the datyx stack's network, which is
what works on Linux); `scripts/api.sh` falls back to `.env`
for the key, the database's port and password and these, and Compose
sets the host to the `postgres` service.

## Authentication

OpenID Connect, Google first ([lib/auth.dart](../healthhub_api/lib/auth.dart)).
The app signs in with the client id this API publishes (the Google Cloud
project `healthhub`, its Web application client `healthhub`, with the
app's origin `http://localhost:9800` among its authorized JavaScript
origins) and sends the ID token as `Authorization: Bearer`. `TokenVerifier`
(package `openid_client`) discovers the issuer's metadata and keys on the
first token, checks the signature, the issuer, the audience (the client
id) and the expiry, and remembers a verified token's identity until it
expires, so a call costs no round trip to the issuer. A refused token is
logged and treated as no token. The identity (subject, email, name,
picture) reaches the routes; the token itself goes on to the datyx API
for `/api/datyx/*` unchanged, which is why datyx lists this client id in
its `OIDC_EXTRA_AUDIENCES`: one sign-in, the same person in both APIs.
CORS allows the `Authorization` header.

The server binds its port at once and keeps one connection to the
database, opened when first needed and dropped after any failure so the
next call opens a new one (connect timeout 5 s, query timeout 10 s, no
TLS). At start it runs the migration in the background, retrying every
3 s until the database answers: `CREATE TABLE IF NOT EXISTS greetings`
and the hello row if the table is empty. Until then `/api/health` says
`"db": false` and `/api/hello` answers 503. Every statement with a value
takes it as a parameter. Logs name the database as
`user@host:port/name`, never the password.

CORS allows `ALLOWED_ORIGINS` (by default the web app's,
`http://localhost:9800` and `http://127.0.0.1:9800`). `server
healthcheck` asks a running server's `/api/health` and exits 0 when it
answers ok (whether or not the database does); it's the Docker health
check.

The app reaches the API at `API_BASE_URL` (a dart-define; empty means
the app's own origin, through the web server's or nginx's `/api/`
proxy).

## Known limitations

- Nothing calls aityx yet; the key is only reported as set or not.
- Only the two datyx paths are forwarded; a general proxy isn't wanted.
- One connection, no pool: enough for the hello world.
