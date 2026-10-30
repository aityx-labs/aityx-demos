# Index

The aityx demos on one origin: the index page, in the aityx palette,
with a card for each of the six (Mortgage Hub, Contact Hub, Cellfie,
RoboRules, PokerFace, RiverRace: what it shows, its technology, **Open**,
**Source** on GitHub, and **Codespace**), the six apps themselves, each
under its own path, and "Your aityx key". The datyx group has its own
index, [../datyx-index/](../datyx-index/).

Every demo is a Flutter web app that calls aityx from the browser, with
the key the user sets once on this page: the page and the apps share one
origin, so they share the browser's storage.

## What it serves

| Path | What |
|---|---|
| `/` (and `/app/`) | the page, [www/](www/) |
| `/mortgagehub/` | `MortgageHub/mortgagehub_app/build/web` |
| `/contacthub/` | `ContactHub/contacthub_app/build/web` |
| `/pokerface/` | `PokerFace/pokerface_app/build/web` |
| `/roborules/` | `RoboRules/roborules_app/build/web` |
| `/cellfie/` | `Cellfie/cellfie_app/build/web` |
| `/riverrace/` | `RiverRace/riverrace_app/build/web` |
| `GET /aityx/config` | dev mode: whether this server holds a key |
| `POST /aityx/v1/systemone` | dev mode: aityx, with that key |
| `GET /api/health` | `{"ok": true}` |
| `GET /api/demos` | each demo: whether its build is there and made for its path |

[bin/server.dart](bin/server.dart) is plain Dart, no packages. A demo is
every folder beside this one whose `group.id.txt` says `aityx`
(`INDEX_GROUP`) with a `<slug>_app/` package, the slug being the folder's
name in lower case. Its release build (each demo's `scripts/build.sh`:
`flutter build web --release --base-href /<slug>/ --no-web-resources-cdn`)
is served with `Cache-Control: no-cache`, and any path that isn't a file
gets its `index.html` (the app routes it); a path that tries to leave the
build is refused. A demo that isn't built answers 503 with a page that
says to run `./build-all.sh`.

## The key

The page's **Your aityx key** section (`/#aityx-key`, which each app's
status light opens) takes the user's key, checks it with one empty call
to `<url>/v1/systemone` from the browser (aityx answers 400
`invalid_request` once it accepts the key, so no model runs) and only
then saves it: in `localStorage` ("Remember on this device") or
`sessionStorage` ("Only this session"), as `aityx.key`, with `aityx.url`
(by default `https://api.aityx.ai`, under **Advanced**). **Forget key**
removes it. Once saved, the key is not shown again, only its last four
characters. Every app reads it from there
([packages/aityx_web](../packages/aityx_web/)) and calls aityx itself.

Without a user key, an app asks this server's `GET /aityx/config`. When
the server has a key, `AITYX_API_KEY` in its environment (a Codespaces
secret) or in the repository's `.env`, re-read at most every 10 s, it
answers `{"available": true, "url": ..., "source": "environment" | ".env"}`
(never the key), and the app sends its calls to `POST
/aityx/v1/systemone` here, which forwards them to
`<AITYX_URL>/v1/systemone` with that key: the dev mode, for development
and for a codespace whose owner lends their key to its visitors. The
proxy:

- answers only this origin's pages: `Sec-Fetch-Site: same-origin` or,
  from a browser that doesn't send it, no `Origin` or one naming this
  host; anything else gets 403 `proxy_cross_site`, and so does, while
  the server listens on the loopback only (the default), a request whose
  `Host` isn't this machine (`localhost`, `127.0.0.1`, `[::1]`): a page
  that reached it through DNS rebinding;
- takes up to 2 MB and waits up to 120 s for aityx;
- passes aityx's status and body back unchanged, except a redirect (502
  `proxy_redirect`: `AITYX_URL` may be behind a login) and no answer (502
  `proxy_unreachable`);
- never logs the key or the bodies.

Without a key it answers `{"available": false}`, and so does a static
host, which has no `/aityx/config` at all. Then each app's light is red
until the user sets a key on this page.

The page has a strict content security policy (its script is
[www/index.js](www/index.js), and it may connect only to this origin and
`https://*.aityx.ai`), sent as a header too, so it can't be framed.

## Run it

Port **8800** (`INDEX_PORT`), bound to 127.0.0.1 (`INDEX_BIND_HOST`).
[group.id.txt](group.id.txt) says `aityx`. From the root of the
repository, `./start-aityx.sh` builds every demo whose build is missing
or stale, starts this server, and prints each demo's link,
`http://localhost:8800/<slug>/` (`./start-all.sh` too, with everything);
`./stop-aityx.sh` stops it. From this folder, with
[Devbox](https://www.jetify.com/devbox):

```bash
devbox services up            # the index on http://localhost:8800/
devbox run serve              # the same, in the foreground
```

or, with Dart on the PATH, `dart bin/server.dart`.
