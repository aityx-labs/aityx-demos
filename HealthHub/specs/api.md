# API

[healthhub_api](../healthhub_api/bin/server.dart), a Dart server that
holds the aityx key, which must never reach the app, and talks to
PostgreSQL ([Database](database.md), [lib/db.dart](../healthhub_api/lib/db.dart)).
Routes in [lib/routes.dart](../healthhub_api/lib/routes.dart), which
decides the answers without a server or a database so it can be tested,
and [bin/server.dart](../healthhub_api/bin/server.dart), which asks the
database for the routes that need it, Kafka's REST proxy for the health
check, and the people feed for `/api/people` and `/api/events`:

| Request | Answer |
|---|---|
| `GET /` | 302 to `/app/`, so a forwarded port's bare URL opens the app |
| `GET /api/health` | `{"ok": true, "db": <whether the database answers SELECT 1>, "aityx": <whether the API has its key>, "auth": <whether authentication is on>, "kafka": <whether Kafka's REST proxy answers GET /topics with 200>, "simulation": <whether the people simulation runs>}`; `ok` is true whether or not the database or Kafka answer |
| `GET /api/hello` | `{"message": "Hello, world", "since": <when the row was written, ISO 8601 UTC>, "postgres": <the server's version()>, "user": <the signed-in user's subject, email, name and picture, or null>}`, the first row of `greetings`; with a signed-in user the message is `Hello, <name>`; 503 `{"error": "the database is not answering"}` when it can't be read |
| `GET /api/care-centers?bbox=west,south,east,north` | `{"centers": [...], "truncated": <whether there were more>}`, the care centers with a location in the area, hospitals first, at most 500 ([Care centers](care-centers.md)); open to everyone; 400 for a bbox that isn't one, 503 when the database doesn't answer |
| `GET /api/people?bbox=west,south,east,north` | The simulated people ([Simulation](simulation.md)): `{"enabled": <dev mode>, "simTime": "HH:MM", "day": <from 1>, "people": [{"id", "name", "age", "city", "lat", "lon", "homeLat", "homeLon", "state", "mode", "hospitalName", "conditionName", "conditionType"}]}`, each person's latest move as read back from Kafka, only those who are, or whose home is, in the bbox when one is given (400 for a bbox that isn't one), and the time and day of the newest move of all; `simTime` and `day` are null until the first move arrives; in prod mode `{"enabled": false, "simTime": null, "day": null, "people": []}`; open to everyone |
| `GET /api/events?limit=20&type=admission` | The latest moves and admissions the API read from the streams, merged newest first by arrival ([Simulation](simulation.md#the-stream)): `{"enabled": <dev mode>, "topic": "healthhub.people.moves", "topics": ["healthhub.people.moves", "healthhub.admissions"], "events": [...]}`. A move is `{"type": "move", "id", "name", "age", "city", "state", "mode", "conditionName", "conditionType", "hospitalName", "simTime", "day", "turn", "lat", "lon", "partition", "offset"}`; an admission is `{"type": "admission", "eventId", "personId", "id" (the person's id again, as a move has it), "name", "age", "sex", "occupation", "city", "conditionCode", "conditionName", "conditionType", "visit", "visitNumber", "complaint", "hospitalId", "hospitalName", "simTime", "day", "turn", "partition", "offset"}`. `type` (`admission` or `move`, else 400) keeps one kind; `limit` of them (20 unless asked, at most 100; 400 when not a positive number). The feed keeps the latest 100 of each kind apart, so admissions stay among the events however many moves follow. In prod mode `"enabled": false` and no events; open to everyone |
| `GET /api/admissions?limit=20` | `{"admissions": [{"id", "eventId", "personId", "name", "age", "sex", "occupation", "city", "conditionCode", "conditionName", "conditionType", "visit", "visitNumber", "complaint", "hospitalId", "hospitalName", "day", "simTime", "recordedAt"}]}`: the latest admissions recorded in the database's `admissions` table, newest first, `limit` of them (20 unless asked, at most 200; 400 when not a positive number); in prod mode too, whatever a dev run recorded; open to everyone; 503 when the database doesn't answer |
| `GET /api/auth/config` | How to sign in: `{"enabled": <whether OIDC_CLIENT_ID is set>, "issuer": "https://accounts.google.com", "clientId": <the id, or null>}`; the app reads it at start |
| `GET /api/me` | Who the bearer token says is calling: `{"authenticated": true, "subject", "email", "name", "picture"}`; 401 `{"error": "sign in first"}` without a valid token once authentication is on; `{"authenticated": false}` while it's off |
| `GET /api/datyx/me`, `GET /api/datyx/datasources` | The datyx API's `/api/me` and `/api/datasources`, asked with the user's own token, so datyx sees the same person; the answer and its status pass through; 401 without a user once authentication is on, 502 `{"error": "the datyx API is not answering"}` when datyx doesn't answer |
| `OPTIONS` anything | 204 |
| anything else | 404 `{"error": "not found"}` |

The API reads from its environment `AITYX_API_KEY` and `AITYX_URL`
(default `https://api.aityx.ai`, which must be https; nothing calls it
yet), `API_PORT` (9802), `HEALTHHUB_BIND_HOST` (127.0.0.1),
`ALLOWED_ORIGINS` and the database settings `HEALTHHUB_DB_HOST`
(127.0.0.1), `HEALTHHUB_DB_PORT` (9803), `HEALTHHUB_DB_NAME`,
`HEALTHHUB_DB_USER` (both `healthhub`) and `HEALTHHUB_DB_PASSWORD`,
`OIDC_ISSUER` (default `https://accounts.google.com`), `OIDC_CLIENT_ID`
(empty: authentication off) and `DATYX_API_URL` (default
`http://127.0.0.1:9900`; Compose points it at the host's port 9900
through `host.docker.internal`, or, with `compose.datyx.yaml` as a second
`-f` file, at the `api` service of the datyx stack's network, which is
what works on Linux), `HEALTHHUB_MODE` (`dev`, the default, or `prod`;
anything else stops the server), `HEALTHHUB_KAFKA_REST_URL` (default
`http://127.0.0.1:9805`; Compose sets `http://kafka-rest:8082`) and the
simulation's `HEALTHHUB_SIM_PEOPLE`, `HEALTHHUB_SIM_TURN_MS` and
`HEALTHHUB_SIM_MINUTES_PER_TURN`; `scripts/api.sh` falls back to `.env`
for the key, the database's port and password and these, and Compose
sets the host to the `postgres` service.

## Authentication

OpenID Connect, Google first ([lib/auth.dart](../healthhub_api/lib/auth.dart)).
The app signs in with the client id this API publishes (the Google Cloud
project `healthhub`, its Web application client `healthhub`, with the
app's origin `http://localhost:9801` among its authorized JavaScript
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
database, opened when first needed and dropped after a failure of the
connection so the next call opens a new one (an error the server answers,
such as a refused value, leaves it open; connect timeout 5 s, query
timeout 10 s, no TLS). The driver sends one statement at a time on it;
only the migration holds every other call back until it is done, so a
health check's ping or a read never waits behind an admission being
retried. At start it runs the migration in the background, retrying every
3 s until the database answers: `CREATE TABLE IF NOT EXISTS greetings`
and the hello row if the table is empty, and the care centers' table and
seed. Until then `/api/health` says `"db": false` and `/api/hello`
answers 503. In dev mode, once the migration succeeded, the server reads
the care centers and starts the [simulation](simulation.md) and the feed
that reads it back; neither waits for Kafka, and in prod neither runs. Every statement with a value
takes it as a parameter. Logs name the database as
`user@host:port/name`, never the password.

CORS allows `ALLOWED_ORIGINS` (by default the web app's,
`http://localhost:9801` and `http://127.0.0.1:9801`). `server
healthcheck` asks a running server's `/api/health` and exits 0 when it
answers ok (whether or not the database does); it's the Docker health
check.

The app reaches the API at `API_BASE_URL` (a dart-define; empty means
the app's own origin, through the web server's or nginx's `/api/`
proxy).

## Kafka

The API reaches Kafka only through its REST proxy (Karapace, the
`kafka-rest` service of [compose.yaml](../compose.yaml), the Confluent
REST Proxy v2 API), with
[lib/kafka_rest.dart](../healthhub_api/lib/kafka_rest.dart): plain HTTP
from `dart:io`, so there is no Kafka client library and the API stays a
single native executable. It produces JSON records (`POST
/topics/{topic}`, `application/vnd.kafka.json.v2+json`; a record the
proxy reports as failed throws too) and consumes them through a consumer
instance (`POST /consumers/{group}` with `"format": "json"`,
`"auto.offset.reset"` `"latest"` or, for a group that must not miss
records, `"earliest"`, and `"auto.commit.enable": "true"`, `POST
.../subscription`, `GET .../records`, `DELETE` the instance on close):
the feed has two, the moves' and the admissions'
([Simulation](simulation.md#the-stream)). The instance's path is
built from the API's own proxy URL, not the `base_uri` the proxy answers,
which names a host the API may not resolve. Every failure throws; the
callers retry. The proxy doesn't create topics: the `kafka` service's
health check makes `healthhub.people.moves`, `healthhub.admissions` (and
`healthhub.test`). A
call that times out is aborted, so a proxy that never answers doesn't
keep sockets open. `/api/health`'s `"kafka"` is the result of the last
ping, every 5 s in the background, so the health check never waits on
the proxy.

## Known limitations

- Nothing calls aityx yet; the key is only reported as set or not.
- Only the two datyx paths are forwarded; a general proxy isn't wanted.
- One connection, no pool: enough for the hello world.
- Every person publishes its own record each turn, one HTTP call each
  (70 a second with the defaults, and one more for each admission), over
  the client's pooled connections: fine for a demo, not a way to load
  Kafka.
- The consumer instances are left on the proxy when the API is killed
  without a chance to stop (`kill -9`, a crash); the proxy drops each
  once it has been idle for 5 minutes.
