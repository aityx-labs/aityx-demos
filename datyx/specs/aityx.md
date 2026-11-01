# aityx

datyx routes calls to aityx ([aityx.ai](https://aityx.ai/docs)): a
gateway in front of aityx's `POST /v1/systemone` that adds datyx's own
aityx key, keeps an account of every call (who, why, which model and
decision, how long, how many input tokens, what it cost, the request and
the answer), and is where calls will be personalized per profile. The
dashboard's aityx tab shows the account. Code in
`datyx-api/src/main/java/datyx/aityx/` (`AityxResource`, `AityxGateway`,
`AityxCall`, `AityxPersonalizer`, `NoPersonalization`, `ServiceToken`,
`AityxGatewayPolicy`).

## The gateway

`POST /api/aityx/v1/systemone` takes the body aityx's
`/v1/systemone` takes (a JSON object: `model`, `questions`, `decision`,
`state`, ...), at most 1 MB (a 413 `{"error":"a request is 1 MB at most"}`
over it, a 400 `{"error":"the body isn't a JSON object"}` when it isn't
one), and:

1. hands it to the personalization hook (below), which answers the body
   to send;
2. posts that to `${datyx.aityx.url}/v1/systemone` (`DATYX_AITYX_URL`,
   `https://api.aityx.ai` by default) with `Authorization: Bearer` and
   datyx's aityx key (`AITYX_API_KEY` in datyx's environment), JSON in
   and out, within 60 seconds; nothing else of the caller's request is
   passed on (not its headers, not its token);
3. answers aityx's status, body and `X-aityx-Mode` header as they came
   (and its `Content-Type`).

The caller's body is sent byte for byte when the hook leaves it as it is.
Without a key datyx answers 503 `{"error":"datyx has no aityx key"}` and
calls nothing. aityx unreachable is a 502 `{"error":"aityx can't be
reached"}`, no answer within 60 s a 504 `{"error":"aityx didn't answer
within 60 s"}`. datyx's key is never logged, stored, answered or put in
an error (it is also blanked out of any body or error recorded, should
one ever carry it).

`GET /api/aityx/v1/status` answers `{"configured": <whether datyx has an
aityx key>}`, to the same callers as the gateway (the service token, or
a signed-in user), calling and recording nothing: what a service without
a key of its own (HealthHub) asks before counting on aityx, so the
service token alone never passes for a key.

Optional headers of the call:

- `X-Datyx-Purpose`: why the call is made (`triage`), at most 64
  characters, recorded.
- `X-Datyx-Caller`: a service's name (below).

### Who may call

- **A signed-in user**: the bearer token, as on the rest of `/api`
  ([auth.md](auth.md)). The call is recorded in their profile, the
  caller being their email (else subject); `local` (the local profile)
  while authentication is off.
- **A service**: header `X-Datyx-Service-Token` equal to
  `DATYX_SERVICE_TOKEN` (datyx's environment), compared in constant
  time (SHA-256 digests, `MessageDigest.isEqual`). Unset, every service
  call is refused; a wrong token is a 401. The caller recorded is
  `X-Datyx-Caller` (letters, digits, space, `.`, `_`, `-`; the rest
  dropped, at most 64 characters), `HealthHub` when absent.

A service's calls belong to no profile: they are the **services'
bucket** (`profile_id` null), shown to every profile when
`datyx.aityx.share-service-calls` (`DATYX_AITYX_SHARE_SERVICE_CALLS`) is
true: the default in dev mode, where the datyx group's HealthHub is
every profile's; false otherwise, where they are kept and shown to no
profile (set it to true for a single-tenant deployment). Empty counts as
unset, so the profile decides (`datyx.aityx.share-service-calls-by-default`,
true only in `%dev`): `compose.yaml` passes it through empty, so a
Compose image built with the prod profile shares nothing, the requests
holding health data (HealthHub's complaints). A profile never sees
another profile's calls.

`AityxGatewayPolicy` (an `HttpSecurityPolicy` named `aityx-gateway`,
for `/api/aityx/v1/*`) lets a call with the right service token through
without a sign-in, refuses one with a wrong or unconfigured token (a
401, a 403 when it also carries a signed-in user's token), and otherwise
wants a signed-in user, as the secured paths do (open while
authentication is off, as every path is). The token opens the gateway
alone: `/api/aityx` and `/api/aityx/calls/{id}` are secured paths like
the data sources, a 401 without a sign-in whatever the token.

## The personalization hook

`AityxPersonalizer.personalize(caller, body)` answers the body to send
aityx, given the caller (`profileId`, null for a service; `caller`;
`service`; `purpose`). Today's, `NoPersonalization`, answers the body
as it came, and the account says personalization isn't active. This is
where personalization per profile will go: a profile's preferred Jev
model, extra context in the state, variants of a decision. A call whose
body the hook changed is recorded as `personalized`.

## The account

Every call the gateway answers is recorded (`AityxCall`, table
`aityx_call`, migration `V9__aityx_calls.sql`): the profile (null for a
service), the caller and whether it is a service, the purpose, when,
how long (`millis`), aityx's HTTP status, its mode (`X-aityx-Mode`),
the body's `model`, `decision.name` and number of `questions`, the
answer's `usage.input_tokens` and the cost (input tokens × $0.042 per
million, `AityxCall.USD_PER_MILLION_INPUT_TOKENS`, aityx's price), a
short error (aityx's `error.code` or `error.message`, or why aityx
wasn't reached), and the request sent and answer received, each
truncated to 64 KB (never headers). A call refused before reaching aityx
(no key, too large, not JSON, not allowed) isn't recorded. The latest
2,000 calls of each profile, and of the services' bucket, are kept: older
ones are deleted as each call is recorded.

A call failed when its status isn't 2xx.

### GET /api/aityx

`?days=7` (1 to 30): the caller's calls over the last `days`, with the
services' bucket when shared, secured like the data sources:

```json
{"since":"2026-10-25T10:12:00Z","days":7,
 "configured":true,"sharesServiceCalls":true,"pricePerMillionInputTokens":0.042,
 "personalization":{"active":false,"name":"none",
  "note":"Coming: per-profile Jev models, extra context and decision variants. Calls go to aityx as they come."},
 "totals":{"calls":12,"failed":1,"inputTokens":48210,"costUsd":0.00202482,"avgMillis":2310.5,
  "p50Millis":2100,"p95Millis":4800,"lastCalledAt":"2026-11-01T10:11:58.120Z"},
 "lastHour":3,
 "perHour":[{"hour":"2026-10-31T11:00:00Z","calls":0,"failed":0,"inputTokens":0,"p50Millis":null},
  {"hour":"2026-11-01T10:00:00Z","calls":3,"failed":0,"inputTokens":12051,"p50Millis":2100}],
 "byPurpose":[{"name":"triage","calls":11,"failed":1,"inputTokens":44190},{"name":null,"calls":1,"failed":0,"inputTokens":4020}],
 "byModel":[{"name":"jev-latest","calls":12,"failed":1,"inputTokens":48210}],
 "byDecision":[{"name":"HealthHub · Triage at the desk","calls":12,"failed":1,"inputTokens":48210}],
 "calls":[{"id":51,"at":"2026-11-01T10:11:58.120Z","caller":"HealthHub","service":true,"purpose":"triage",
   "model":"jev-latest","decision":"HealthHub · Triage at the desk","questions":12,"millis":2100,"status":200,
   "mode":"live","inputTokens":4017,"costUsd":0.000168714,"error":null,"personalized":false}]}
```

- `configured`: datyx has an aityx key (never the key).
- `totals`: `calls`, `failed`, `inputTokens` (summed), `costUsd`
  (summed), `avgMillis`, `p50Millis`, `p95Millis` (nearest rank),
  `lastCalledAt`; the averages and percentiles null, and the sums 0,
  without calls.
- `lastHour`: the calls of the last hour.
- `perHour`: always 24, the last 24 hours, each `hour` (its start, UTC)
  with its `calls`, `failed`, `inputTokens` and `p50Millis` (null
  without calls), the current hour last.
- `byPurpose`, `byModel`, `byDecision`: each value (null when the call
  had none) with its `calls`, `failed` and `inputTokens`, the most
  called first.
- `calls`: the latest 50, newest first, without their bodies.
  `inputTokens` and `costUsd` are null when the answer had no usage.

### GET /api/aityx/calls/{id}

One call, with what was sent and answered, when it is the caller's
profile's (or the shared services' bucket's); a 404
`{"error":"no aityx call 51"}` otherwise:

```json
{"id":51,"at":"2026-11-01T10:11:58.120Z","caller":"HealthHub","service":true,"purpose":"triage",
 "model":"jev-latest","decision":"HealthHub · Triage at the desk","questions":12,"millis":2100,"status":200,
 "mode":"live","inputTokens":4017,"costUsd":0.000168714,"error":null,"personalized":false,
 "request":{"model":"jev-latest","questions":{},"decision":{},"state":{"complaint":"...","age":54}},
 "requestTruncated":false,
 "response":{"answers":{},"decisions":{},"usage":{"input_tokens":4017}},
 "responseTruncated":false}
```

`request` and `response` are the JSON recorded, or its text as a string
when it was truncated or isn't JSON (null when there was none, such as
aityx unreachable).

## Settings

- `AITYX_API_KEY`: datyx's aityx key, a secret (`datyx.aityx.key`).
  Without it the gateway answers 503.
- `DATYX_AITYX_URL`: aityx's base URL, `https://api.aityx.ai` by
  default (`datyx.aityx.url`); the scripts fall back to `AITYX_URL`.
- `DATYX_SERVICE_TOKEN`: the token services present, a secret
  (`datyx.service-token`); unset, service calls are refused. Make one
  with `openssl rand -hex 32`; HealthHub reads the same one.
- `DATYX_AITYX_SHARE_SERVICE_CALLS`: whether every profile sees the
  services' calls (empty or unset: true in dev mode, false otherwise,
  also in Docker Compose with the prod profile).

In development `scripts/env.sh` reads `AITYX_API_KEY`, `AITYX_URL` and
`DATYX_SERVICE_TOKEN` from datyx's `.env`, else from the repository
root's `.env`, which HealthHub reads too.

## Tests

`AityxGatewayTest` (authentication off, aityx a local stub server,
`AityxStub`, at `datyx.aityx.url`): the body is forwarded byte for byte
to `/v1/systemone` and aityx's status, body and mode answered as they
came; datyx's key reaches aityx and never the answer, its headers, the
record or the logs, and neither the caller's headers nor the service
token reach aityx; an error answer is answered as it came and recorded
as failed with aityx's code; over 1 MB a 413, not a JSON object a 400,
neither reaching aityx; the record's fields (caller, purpose cleaned,
model, decision, questions, status, mode, tokens, cost, bodies) and the
detail's request and response, a body over 64 KB kept truncated; a
service's calls with its token, named by `X-Datyx-Caller` cleaned or
`HealthHub`, a wrong or empty token a 401; the token compared as
digests; the personalization hook (a test personalizer) gets the caller
and its body is what aityx gets, recorded as personalized; the account's
totals, cost, last hour, hours, breakdowns, newest first and window;
the latest 2,000 of a profile kept as a call is recorded, the services'
untouched, and trimmed alike; aityx unreachable a 502, too slow a 504,
without the key in the error. `AityxAuthTest` (authentication on): the
gateway, the account and a call want a sign-in (401), the service token
opens the gateway alone, a wrong one is a 401 (403 with a user's token);
a signed-in user's call goes with datyx's key, not their token, and is
recorded under their email; another profile sees neither it in the
account nor its detail (404), and both see the services' calls.
`AityxNoKeyTest`: without a key a 503, nothing called and the account
says so, as does the status; without a service token configured, every
token refused. `AityxAuthTest` also: the status wants the token or a
sign-in and calls and records nothing.
`AityxShareConfigTest`: the services' calls shared in dev mode only,
also when the setting comes empty (as `compose.yaml` passes it), an
explicit value winning.

## Known limitations

- Personalization isn't there yet: the hook passes the body on as it is.
- The price is a constant, aityx's for input tokens at the time of
  writing; output isn't counted.
- The answer is read whole before it is passed on (no streaming).
- While authentication is off the gateway is open, as every path is,
  and spends datyx's key for whoever reaches the API (bound to
  127.0.0.1 in development).
