# API

[healthhub_api](../healthhub_api/bin/server.dart), a Dart server that
holds the aityx key, which must never reach the app, and talks to
PostgreSQL ([Database](database.md), [lib/db.dart](../healthhub_api/lib/db.dart)).
Routes in [lib/routes.dart](../healthhub_api/lib/routes.dart), which
decides the answers without a server or a database so it can be tested,
and [bin/server.dart](../healthhub_api/bin/server.dart), which asks the
database for the routes that need it, Kafka's REST proxy for the health
check, the people feed for `/api/people` and `/api/events`, the
simulation for whether it runs or is paused, and to pause and resume it,
and the [occupancy alarms](occupancy-alarms.md):

| Request | Answer |
|---|---|
| `GET /` | 302 to `/app/`, so a forwarded port's bare URL opens the app |
| `GET /api/health` | `{"ok": true, "db": <whether the database answers SELECT 1>, "aityx": <whether the API has its key>, "auth": <whether authentication is on>, "kafka": <whether Kafka's REST proxy answers GET /topics with 200>, "simulation": <whether the people simulation runs>, "paused": <whether it is paused>, "triage": <whether admissions are triaged with aityx>}`; `ok` is true whether or not the database or Kafka answer |
| `GET /api/hello` | `{"message": "Hello, world", "since": <when the row was written, ISO 8601 UTC>, "postgres": <the server's version()>, "user": <the signed-in user's subject, email, name and picture, or null>}`, the first row of `greetings`; with a signed-in user the message is `Hello, <name>`; 503 `{"error": "the database is not answering"}` when it can't be read |
| `GET /api/care-centers/nearest?lat=..&lon=..` | `{"center": {...the care center's fields..., "distance": <metres>}}`, the care center of any kind nearest the point by great-circle distance, `"center": null` when none has a location ([The map](map.md)); open to everyone; the point is used for the query only, never logged or kept; 400 for a point that isn't one, 503 when the database doesn't answer |
| `GET /api/care-centers?bbox=west,south,east,north` | `{"centers": [...], "truncated": <whether there were more>}`, the care centers with a location in the area, hospitals first, at most 500 ([Care centers](care-centers.md)); open to everyone; 400 for a bbox that isn't one, 503 when the database doesn't answer |
| `GET /api/people?bbox=west,south,east,north` | The simulated people ([Simulation](simulation.md)): `{"enabled": <dev mode>, "simTime": "HH:MM", "day": <from 1>, "people": [{"id", "name", "age", "city", "lat", "lon", "homeLat", "homeLon", "state", "mode", "monitored", "monitoredFor", "hospitalName", "careCenterKind", "conditionName", "conditionType"}]}`, each person's latest move as read back from Kafka, only those who are, or whose home is, in the bbox when one is given (400 for a bbox that isn't one), and the time and day of the newest move of all; `simTime` and `day` are null until the first move arrives; in prod mode `{"enabled": false, "simTime": null, "day": null, "people": []}`; open to everyone |
| `POST /api/simulation/people` | `{"perCity": n}`, 1 to 200: sets how many people each city of the simulation has, newcomers joining now or the last to join leaving ([Simulation](simulation.md#people)); answers `{"perCity": n}`; anyone signed in (anyone while authentication is off), 401 without a user once it is on, 409 when the simulation doesn't run, 400 for any other number |
| `GET /api/events?limit=20&type=admission` | The latest moves (a person's changes of state only) and admissions the API read from the streams, as one stream newest first by simulated time, the kinds among each other, a tie in the order read ([Simulation](simulation.md#the-stream)): `{"enabled": <dev mode>, "paused": <whether the simulation is paused>, "peoplePerCity": <the people a city now>, "busiest": <the care center with the most people in care now, {"id", "name", "kind", "inCare"}; null while nobody is>, "topic": "healthhub.people.moves", "topics": ["healthhub.people.moves", "healthhub.admissions"], "total": <every move and admission the feed read>, "perSecond": <how many a second over the last minute, to a tenth>, "events": [...]}`. A move is `{"type": "move", "id", "name", "age", "city", "state", "mode", "monitored", "monitoredFor" (why: "aged 84", "pregnant", a chronic condition; null when not), "conditionName", "conditionType", "hospitalName", "careCenterKind", "simTime", "day", "at" (the same moment as a date and time), "turn", "lat", "lon", "partition", "offset"}`; an admission is `{"type": "admission", "eventId", "personId", "id" (the person's id again, as a move has it), "name", "age", "sex", "occupation", "city", "conditionCode", "conditionName", "conditionType", "visit", "visitNumber", "complaint", "hospitalId", "hospitalName", "careCenterKind", "simTime", "day", "at", "turn", "partition", "offset", "triage" (aityx's level, "red" to "blue", once recorded; null until then or when it failed)}`. `type` (`admission` or `move`, else 400) keeps one kind; `limit` of them (20 unless asked, at most 100; 400 when not a positive number). The feed keeps the latest 100 of each kind apart, so admissions stay among the events however many moves follow; a move only when it changes the person's state (left home, arrived, going home, back home), though `total` counts them all. Whatever the type, the answer also has `"now"`, the simulated clock `{"day", "simTime", "date"}` of the newest move (`date` the day as `YYYY-MM-DD`, day 1 being 2026-01-01; null before the first move), and `"alarms"`, `{"enabled", "checkedAt", "status", "note", "stale", "active", "recent"}` as `/api/alarms` has them with the 10 latest events ([Occupancy alarms](occupancy-alarms.md#the-api)), only `enabled` and `"signIn": true` (empty lists) to a caller not signed in while sign-in is on; with the caller's token (any caller while sign-in is off) it sets an alarm check off in the background. In prod mode `"enabled": false`, `"paused": false`, `"total": 0`, `"perSecond": 0`, no events, `"now": null`, `"busiest": null` and the alarms off; open to everyone |
| `GET /api/alarms?limit=20` | The [occupancy alarms](occupancy-alarms.md#the-api): `{"enabled", "paused", "everyMs", "now", "checkedAt", "status", "note", "stale", "trainingRun", "active": [...], "recent": [...]}`, the care centers whose occupancy datyx's DeepAR forecast puts over their capacity (`expected` by the mean, `possible` by the 90th percentile), the worst and soonest first, and the latest alarm events, newest first, `limit` of them (20 unless asked, at most 100; 400 when not a positive number). Sets a check off as `/api/events` does. In prod, or with `HEALTHHUB_ALARM_EVERY_MS=0`, `"enabled": false` and nothing; with sign-in on, a signed-in user only (401 otherwise), as the forecast it is |
| `POST /api/simulation/pause`, `POST /api/simulation/resume` | Pause or resume the simulation ([Simulation](simulation.md#pausing)): 200 `{"paused": true}` or `{"paused": false}`, the state after the call; pausing a paused simulation, or resuming a running one, changes nothing and answers the same. 401 `{"error": "sign in first"}` without a user once authentication is on, checked before anything changes; 409 `{"error": "the simulation does not run"}` in prod mode or before it has started. No body is read |
| `GET /api/admissions?limit=20` | `{"admissions": [{"id", "eventId", "personId", "name", "age", "sex", "occupation", "city", "conditionCode", "conditionName", "conditionType", "visit", "visitNumber", "complaint", "hospitalId", "hospitalName", "day", "simTime", "recordedAt"}]}`: the latest admissions recorded in the database's `admissions` table, newest first, `limit` of them (20 unless asked, at most 200; 400 when not a positive number); in prod mode too, whatever a dev run recorded; open to everyone; 503 when the database doesn't answer |
| `GET /api/triage?limit=20` | `{"enabled": <whether admissions are triaged>, "summary": {"total", "failed", "compared", "matched", "withinOne", "under", "over", "nurseChecks", "inputTokens", "medianMillis", "levels": {"red", "orange", "yellow", "green", "blue"}}, "triaged": [{"eventId", "name", "age", "sex", "city", "complaint", "conditionName", "conditionType", "visit", "visitNumber", "hospitalName", "day", "simTime", "level", "waitMinutes", "area", "nurseCheck", "levelRule", "levelWhy", "areaRule", "areaWhy", "signs", "choices", "reference", "error", "inputTokens", "millis", "triagedAt"}]}`: every triage counted, against the reference levels, and the latest, newest first, `limit` of them (as `/api/admissions`) ([Triage at the desk](triage.md)); open to everyone; 503 when the database doesn't answer |
| `GET /api/care-centers/{id}` | One care center: where it is, its capacity in the simulation, who is there and on the way now, its admissions counted and the latest with their triage ([The care center view](care-center.md#the-api)); 404 for none, 503 without the database; open to everyone |
| `GET /api/people/{id}?run=` | One person of one run: facts, what they do now, admissions with their triage, days of care, counted ([The person view](person.md#the-api)); 404 when nothing is known of them, 503 without the database; open to everyone |
| `GET /api/people/{id}/prediction?run=` | datyx's XGBoost prediction of the person's hours of care over the next 30 days, asked with the user's token from their datyx source for HealthHub's database ([The person view](person.md#the-api)); datyx's own error when it refuses, 404 without such a source, 502 when datyx doesn't answer, 401 without a user once sign-in is on |
| `GET /api/care-centers/{id}/occupancy?run=&hours=72` | The people in care at the care center in each hour up to its run's end, an hour without anyone a zero, from `occupancy_hourly` ([A care center's occupancy per hour](occupancy-timeline.md#the-api)); open to everyone; 400 for hours that aren't a positive number, 503 without the database |
| `GET /api/care-centers/{id}/occupancy/forecast?run=` | datyx's DeepAR forecast of them, step by step with its percentiles, asked as the admissions' forecast is |
| `GET /api/care-centers/{id}/admissions?run=&hours=72` | The care center's admissions in each hour up to its run's end, an hour without any a zero, from `admissions_hourly` ([A care center's occupancy per hour](occupancy-timeline.md#the-api)); open to everyone; 400 for hours that aren't a positive number, 503 without the database |
| `GET /api/care-centers/{id}/admissions/forecast?run=` | datyx's DeepAR forecast of the care center's admissions per hour, step by step with its percentiles, asked with the user's token as the person's prediction is; datyx's own error when it refuses, 404 without a source or admissions, 502 when datyx doesn't answer, 401 without a user once sign-in is on |
| `GET /api/triage/{eventId}` | One admission's triage as in the list, with `receipt`, aityx's, and `rules`, the `# why` of each rule of the `level` and `area` tables in order; 404 when it has none; open to everyone |
| `GET /api/auth/config` | How to sign in: `{"enabled": <whether OIDC_CLIENT_ID is set>, "issuer": "https://accounts.google.com", "clientId": <the id, or null>}`; the app reads it at start |
| `GET /api/me` | Who the bearer token says is calling: `{"authenticated": true, "subject", "email", "name", "picture"}`; 401 `{"error": "sign in first"}` without a valid token once authentication is on; `{"authenticated": false}` while it's off |
| `GET /api/datyx/me`, `GET /api/datyx/datasources` | The datyx API's `/api/me` and `/api/datasources`, asked with the user's own token, so datyx sees the same person; the answer and its status pass through; 401 without a user once authentication is on, 502 `{"error": "the datyx API is not answering"}` when datyx doesn't answer |
| `OPTIONS` anything | 204 |
| anything else | 404 `{"error": "not found"}` |

The API reads from its environment `AITYX_API_KEY` and `AITYX_URL`
(default `https://api.aityx.ai`, which must be https), with which it
triages each admission unless `HEALTHHUB_TRIAGE` is `off` (`on` by
default; anything else stops the server; [Triage at the desk](triage.md)),
`API_PORT` (9802), `HEALTHHUB_BIND_HOST` (127.0.0.1),
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
`HEALTHHUB_SIM_MINUTES_PER_TURN`, and `HEALTHHUB_ALARM_EVERY_MS` (5000:
real milliseconds between two [occupancy alarm](occupancy-alarms.md)
checks at least; 0 turns them off; anything but a whole number from 0
stops the server); `scripts/api.sh` falls back to `.env`
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
([Simulation](simulation.md#the-stream)). The occupancy alarms' events
go to `healthhub.alarms`, keyed by the care center's id, each queued and
retried every 3 s until the proxy takes it ([Occupancy
alarms](occupancy-alarms.md#the-events)). The instance's path is
built from the API's own proxy URL, not the `base_uri` the proxy answers,
which names a host the API may not resolve. Every failure throws; the
callers retry. The proxy doesn't create topics: the `kafka` service's
health check makes `healthhub.people.moves`, `healthhub.admissions`,
`healthhub.alarms` (and `healthhub.test`). A
call that times out is aborted, so a proxy that never answers doesn't
keep sockets open. `/api/health`'s `"kafka"` is the result of the last
ping, every 5 s in the background, so the health check never waits on
the proxy.

## Known limitations

- Only the two datyx paths are forwarded; a general proxy isn't wanted.
- One connection, no pool: enough for the hello world.
- Every person publishes its own record each turn, one HTTP call each
  (560 a second with the defaults, up to 1,400 at 200 people a city, and
  one more for each admission), over
  the client's pooled connections: fine for a demo, not a way to load
  Kafka.
- The consumer instances are left on the proxy when the API is killed
  without a chance to stop (`kill -9`, a crash); the proxy drops each
  once it has been idle for 5 minutes.
