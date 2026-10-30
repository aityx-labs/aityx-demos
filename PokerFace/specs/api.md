# API

[pokerface_api](../pokerface_api/bin/server.dart), a Dart server that
holds the aityx key, which must never reach the app, and runs each
player's strategy on aityx ([Strategies](strategies.md)). Routes in
[lib/routes.dart](../pokerface_api/lib/routes.dart) and
[bin/server.dart](../pokerface_api/bin/server.dart):

| Request | Answer |
|---|---|
| `GET /` | 302 to `/app/`, so a forwarded port's bare URL opens the app |
| `GET /api/health` | `{"ok": true, "aityx": <whether the API has its key>}` |
| `GET /api/aityx` | `{"key", "ok", "url", "detail"}`: whether the API has its key and aityx accepts it, for [the aityx light](aityx-status.md). It posts an empty request to aityx's `/v1/systemone`, which checks the key first: 400 `invalid_request` means the key works, without running a model; a redirect (a login page in front of `AITYX_URL`), another status or no answer says why in `detail`. Kept for a minute; never includes the key ([lib/aityx_check.dart](../pokerface_api/lib/aityx_check.dart)) |
| `GET /api/strategies` | `{"strategies": [{"id", "name", "tagline", "decisions"}, ...]}`: the presets, in file order |
| `POST /api/act` | `{"strategy": "shark" \| {"name", "tagline", "decisions"}, "situation": {...}}` → `{"action": {...}, "aityx": {"request", "response", "took_ms"}}` |
| `OPTIONS` anything | 204 |
| anything else | 404 `{"error": "not found"}` |

The API reads `AITYX_API_KEY` and `AITYX_URL` (default
`https://api.aityx.ai`, which must be https) from its environment;
`scripts/api.sh` falls back to `.env`. At start it loads
`models/table.json` and `models/strategies/*.json`
([lib/table.dart](../pokerface_api/lib/table.dart)); the Docker image
carries them in `/app/models`.

`POST /api/act` refuses, with 400 and `{"error": ...}`, a body over
64 KB, invalid JSON, an unknown strategy id, a strategy object without a
name or without `decisions.action` and `decisions.raise_to`, and a
situation that misses an input of the table model, has one of the wrong
type or out of range, or cards not written like `Ah`; without a key it
answers 503. It sends aityx `{"decision": {name, types, inputs,
decisions}, "state": situation}` with a 30 s timeout (504 when it runs
out) and answers 502 when aityx answers an error (with aityx's code,
detail and first error paths in the message, so a custom strategy's
mistake reaches the editor), a `decision_error` or no action. `action`
holds `action` (fold, check, call, raise, all_in), `raise_to`, `rule`
(the 1-based row of the action table that fired, from the receipt) and
its `why` (the row's annotation), and `decisions`, the strategy's other
answers by name. `aityx` is left out if aityx's answer contains the key.

CORS allows `ALLOWED_ORIGINS` (by default the dev server's,
`http://localhost:8910` and `http://127.0.0.1:8910`). `server
healthcheck` asks a running server's `/api/health` and exits 0 when it
answers ok; it's the Docker health check.

The app reaches the API at `API_BASE_URL` (a dart-define; empty means
the app's own origin, through the dev server's or nginx's `/api/`
proxy).

## Known limitations

- One aityx call per decision; nothing is cached, and nothing is stored.
- The API trusts the situation the app sends beyond its shape: the
  table runs in the app.
