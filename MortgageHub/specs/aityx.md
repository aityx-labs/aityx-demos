# aityx.ai integration

[aityx.ai](https://stage.aityx.ai/docs) runs decision models: `POST
/v1/systemone` executes a model on known facts, `POST
/v1/systemtwo/decisions` interprets raw input and executes it, and `POST
/v1/systemtwo/models` writes or revises a model. Calls send
`Authorization: Bearer <key>` and JSON `{decision, state}`, and return
`answers`, a `receipt` and `usage`.

The [regulatory check](regulatory-check.md) uses it, from the browser:
the app calls aityx itself, through the shared
[aityx_web](../../packages/aityx_web) package. There is no API of its own.

- **Where the key comes from**, in this order (`AityxSettings.resolve`):
  1. **The user's key**, set once on the index page's **Your aityx key**
     (`/#aityx-key`) and kept in the browser: `sessionStorage['aityx.key']`
     ("Only this session") or `localStorage['aityx.key']` ("Remember on
     this device"), the session's first, with `aityx.url` beside it
     (default `https://api.aityx.ai`). The index and every aityx demo are
     served from one origin (the index server, port 8800; this app at
     `/mortgagehub/`), so they share it. The app posts to
     `<url>/v1/systemone` with `Authorization: Bearer <key>`; aityx allows
     CORS from any origin.
  2. **The dev key**: without a user key, the app asks `/aityx/config` at
     the origin's root. When the index server has a key
     (`AITYX_API_KEY` in its environment, or the repository's `.env`), it
     answers `{"available": true, "url", "source"}`, never the key, and
     the app posts to `/aityx/v1/systemone` on its own origin, with no
     Authorization header: the server adds the key, which never reaches
     the browser.
  3. **None**: the check says *aityx is not set up: set your key on the
     index page* and sends nothing.

  The key is never compiled into the app (no `--dart-define`), never in a
  URL or a log, and never in what the app shows: the request under **Show
  aityx request and response** is the body, the key is a header. The web
  build loads no third-party script (`--no-web-resources-cdn`), since its
  origin holds the key. Native builds (Android, iOS, Linux) keep the key
  in memory only and have no dev proxy: their check says aityx is not set
  up.
- **Base URL:** the user's, set under **Advanced** on the index page, or,
  for the dev key, `AITYX_URL` (default `https://api.aityx.ai`, the one
  the docs name). Stage (`api-stage.aityx.ai`) is behind Cloudflare
  Access and can't be called from a browser.
- **Check:** [scripts/aityx-check.sh](../scripts/aityx-check.sh) runs the
  docs' cancellation example on System One (deterministic, the cheapest
  call) with the repository's `.env` key and checks the answers match the
  docs' (`cancel_refund`, eligible, \$20, 2026-10-28). It prints only the
  status and the answers; the key goes to curl on stdin, never on a
  command line. Needs `jq`.
- **Status light:** a small dot in the top right corner of every screen,
  aityx_web's `AityxStatusLight`, mounted once through `MaterialApp.builder`
  (`withAityxStatus`): grey while it checks, green when aityx accepts the
  key, red otherwise. Its tooltip, also its screen reader label, says why:
  `aityx: ready — the key works with <url>`,
  `aityx: no key — set yours on the index page`, `aityx: key
  rejected — ...`, `aityx: not reachable — ...` or `aityx: not working —
  ...`. A tap opens the index page's key section in the same tab. The
  check posts `{}` to `/v1/systemone`, which aityx answers 400
  `invalid_request` when it accepts the key and 401 when it doesn't,
  without running a model. It checks on start, when the key changes (the
  index page, in another tab, saves or forgets it) and when the window
  regains focus, at most once every 30 s for focus; there is no polling
  timer, since each check spends a request of the user's quota.
- **What aityx returns:** each answer typed (`choice`, `number`,
  `value` for strings and table structs, `noul` for booleans as `1.0` /
  `0.0`), and a receipt with the rule each table matched. Strict mode
  requires a type on every decision and a `# why` on every table row.
- Verified on 2026-10-13: the check script passed against stage (since
  replaced by production in the repository's `.env`).

## Known limitations

- `jq` comes from the host, not devbox.
- A key saved for "Only this session" lives in that tab's
  `sessionStorage`: a demo opened in a new tab may not see it.
