# API

[cellfie_api](../cellfie_api/bin/server.dart), a Dart server that holds
the aityx key, which must never reach the app, and runs the generations
on aityx ([Generation](generation.md)). Routes in
[lib/routes.dart](../cellfie_api/lib/routes.dart) and
[bin/server.dart](../cellfie_api/bin/server.dart):

| Request | Answer |
|---|---|
| `GET /` | 302 to `/app/`, so a forwarded port's bare URL opens the app |
| `GET /api/health` | `{"ok": true, "aityx": <whether the API has its key>}` |
| `GET /api/aityx` | `{"key": <whether the API has its key>, "ok": <whether aityx accepts it>, "url": "https://<aityx host>", "detail": "<why>"}`, for the [status light](aityx-status.md) |
| `POST /api/step` | `{"generation": 12, "rules": {...}, "situations": [...], "clusters": [...]}` → `{"generation": {...}, "aityx": {"request", "response", "took_ms"}}` |
| `OPTIONS` anything | 204 |
| anything else | 404 `{"error": "not found"}` |

The API reads `AITYX_API_KEY` and `AITYX_URL` (default
`https://api.aityx.ai`, which must be https) from its environment;
`scripts/api.sh` falls back to `.env`.

`GET /api/aityx` ([lib/aityx_check.dart](../cellfie_api/lib/aityx_check.dart))
posts an empty request to aityx's `/v1/systemone` with the key: aityx
checks the key first, so a working one gets 400 `invalid_request`
(`ok: true`, "aityx accepts the key") without running a model. Any other
answer is `ok: false` with why: no key ("AITYX_API_KEY is not set", and
no call), a URL that isn't https, `aityx answered HTTP <code>` with
aityx's detail, a redirect, named with where it leads ("AITYX_URL may be
behind a login"), or `aityx did not answer` after 10 s. The answer is
kept for a minute and checks asked meanwhile share it; neither the answer
nor the log holds the key.

`POST /api/step` ([lib/life.dart](../cellfie_api/lib/life.dart)) refuses,
with 400 and `{"error": ...}`, a body over 64 KB, invalid JSON, a
`generation` that isn't a whole number, a `rules` that isn't an object of
booleans keyed `conway`, `highlife` and `no_death` (any left out is as by
default: Conway's on, the others off), more than 18 situations or a
repeated one, a situation with `neighbours` outside 0–8 or `cells` under
1, more than 24 clusters, a cluster wider or taller than 64, or whose
`shape` isn't `height` rows of `width` `o` or `.` with `cells` `o`;
without a key it answers 503. It sends the model with the state to aityx
with a 30 s timeout (504 when it runs out) and answers 502 when aityx
answers an error, a `decision_error`, or lists of the wrong length.
`generation` holds `generation`, `rules`, `next_generation`, `population`,
`population_next`, `births`, `deaths`, `survivors`, `situations` (each as
sent, with `fate`, `alive_next`, `rule` and `why`), `clusters` (each as
sent, with `pattern`, `kind`, `rule`, `why` and `about`) and
`recognized`. `aityx` is left out if aityx's answer contains the key. The
Docker image carries the model in `/app/models`.

CORS allows `ALLOWED_ORIGINS` (by default the dev server's,
`http://localhost:8930` and `http://127.0.0.1:8930`). `server
healthcheck` asks a running server's `/api/health` and exits 0 when it
answers ok; it's the Docker health check.

The app reaches the API at `API_BASE_URL` (a dart-define; empty means
the app's own origin, through the dev server's or nginx's `/api/`
proxy).

## Known limitations

- One call per generation; nothing is cached or stored.
