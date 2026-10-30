# API

[contacthub_api](../contacthub_api/bin/server.dart), a Dart server that
holds the aityx key, which must never reach the app, and routes requests
on aityx ([Routing](routing.md)). Routes in
[lib/routes.dart](../contacthub_api/lib/routes.dart) and
[bin/server.dart](../contacthub_api/bin/server.dart):

| Request | Answer |
|---|---|
| `GET /` | 302 to `/app/`, so a forwarded port's bare URL opens the app |
| `GET /api/health` | `{"ok": true, "aityx": <whether the API has its key>}` |
| `GET /api/aityx` | `{"key": <whether the API has its key>, "ok": <whether aityx accepts it>, "url": <aityx's origin>, "detail": "..."}`, for the [aityx status light](aityx-status.md); checked at most once a minute |
| `POST /api/route` | `{"message": "..."}` → `{"routing": {...}, "aityx": {"request", "response"}}` |
| `OPTIONS` anything | 204 |
| anything else | 404 `{"error": "not found"}` |

The API reads `AITYX_API_KEY` and `AITYX_URL` (default
`https://api.aityx.ai`, which must be https) from its environment;
`scripts/api.sh` falls back to `.env`.

`POST /api/route` refuses, with 400 and `{"error": ...}`, a body over
16 KB, invalid JSON, or a `message` that's missing, empty or over 2000
characters; without a key it answers 503. It calls aityx with a 100 s
timeout (504 when it runs out) and answers 502 when aityx answers an
error, a `decision_error` or no routing. `routing` holds the department
(`id`, `name`, `person`, `role`, `email`), `reason` and `department_rule`,
`priority`, `priority_reason` and `priority_rule`, `response_hours`,
`needs_review`, `topic` (`choice`, `confidence`, `probabilities`),
`request_kind`, `checks` (`id`, `label`, `flagged`, `probability`) and `policy`
(`request_kind`, `resolution`, `reason`, `resolution_rule`,
`refund_amount`, `amount_reason`, `amount_rule`, `refund_by`,
`days_since_order`, `days_since_delivery`, `order`, `order_number`; see
[Order policy](order-policy.md)). The state sent to aityx is the
`message`, `today` (UTC) and the `order` from the order book. `aityx` is left out
if aityx's answer contains the key. The Docker image carries the model
in `/app/models`.

CORS allows `ALLOWED_ORIGINS` (by default the dev server's,
`http://localhost:8890` and `http://127.0.0.1:8890`). `server
healthcheck` asks a running server's `/api/health` and exits 0 when it
answers ok; it's the Docker health check.

The app reaches the API at `API_BASE_URL` (a dart-define; empty means
the app's own origin, through the dev server's or nginx's `/api/`
proxy).

## Known limitations

- One call per request; nothing is cached or stored.
