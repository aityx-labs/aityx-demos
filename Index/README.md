# Index

The aityx demos on one origin, under `/demos/`: the index page, in the
aityx palette, with a card for each of the six, in two groups, Games
(Cellfie, PokerFace, RoboRules, RiverRace) and Apps (Mortgage Hub,
Contact Hub): an animation of the app, what it shows, its technology,
**Open**, **Source** on GitHub, and **Codespace**; the six apps
themselves, each under its own path; and "Your aityx key". The datyx
group has its own index, [../datyx-index/](../datyx-index/), and so has
the multyx group, [../multyx-index/](../multyx-index/).

Every demo is a Flutter web app that calls aityx from the browser, with
the key the user sets once on this page: the page and the apps share one
origin, so they share the browser's storage. A card's picture and **Open**
open the app in a new tab that keeps its opener (`rel="opener"`), so a
key kept "only this session" (sessionStorage) is copied into it; with
noopener the new tab would start empty. Every other link on the page
(aityx.ai, the console, GitHub, Codespaces) opens a new tab too.

## What it serves

| Path | What |
|---|---|
| `/` and `/demos` | 301 to `/demos/` |
| `/demos/` | the page, [www/](www/), with `/demos/index.js` beside it |
| `/demos/<slug>.gif` | a card's animation, `www/<slug>.gif`: a recording of the app, 720 px wide |
| `/demos/mortgagehub/` | `MortgageHub/mortgagehub_app/build/web` |
| `/demos/contacthub/` | `ContactHub/contacthub_app/build/web` |
| `/demos/pokerface/` | `PokerFace/pokerface_app/build/web` |
| `/demos/roborules/` | `RoboRules/roborules_app/build/web` |
| `/demos/cellfie/` | `Cellfie/cellfie_app/build/web` |
| `/demos/riverrace/` | `RiverRace/riverrace_app/build/web` |
| `GET /demos/aityx/config` | dev mode: whether this server holds a key |
| `POST /demos/aityx/v1/systemone` | dev mode: aityx, with that key |
| `GET /demos/api/health` | `{"ok": true}` |
| `GET /demos/api/demos` | each demo: whether its build is there and made for its path |

Everything is under `/demos/` because the page and the apps use only
paths relative to it (the page's own files, each app's base href, the
key page and the dev proxy as the
[aityx_web](../packages/aityx_web/) package resolves them), so the same
files, copied as they are, serve from a static host at `/demos/` (the
aityx website), where there is no dev proxy or API and the page and the
apps fall back to the user's key.

[bin/server.dart](bin/server.dart) is plain Dart, no packages. A demo is
every folder beside this one whose `group.id.txt` says `aityx`
(`INDEX_GROUP`) with a `<slug>_app/` package, the slug being the folder's
name in lower case. Its release build (each demo's `scripts/build.sh`:
`flutter build web --release --base-href /demos/<slug>/
--no-web-resources-cdn`)
is served with `Cache-Control: no-cache`, and any path that isn't a file
gets its `index.html` (the app routes it); a path that tries to leave the
build is refused. A demo that isn't built answers 503 with a page that
says to run `./build-all.sh`.

## The key

The page's **Your aityx key** section (`/demos/#aityx-key`, which each app's
status light opens) takes the user's key, checks it with one empty call
to `<url>/v1/systemone` from the browser (aityx answers 400
`invalid_request` once it accepts the key, so no model runs) and only
then saves it: in `localStorage` ("Remember on this device") or
`sessionStorage` ("Only this session"), as `aityx.key`, with `aityx.url`
(by default `https://api.aityx.ai`, under **Advanced**). **Forget key**
removes it. Once saved, the key is not shown again, only its last four
characters. Every app reads it from there
([packages/aityx_web](../packages/aityx_web/)) and calls aityx itself.

A link can carry the key, in the fragment only:
`/demos/#AITYX_API_KEY=<key>`, with `AITYX_URL` beside it if the key is
for another aityx. The browser never sends a fragment to a server, so the
key reaches no access log. The page takes them off the address bar at
once, checks the key with aityx like a pasted one and saves it on the
device, replacing any key set before, for every demo; a key aityx rejects
is not saved, and the section says so. A key in the query string
(`/demos/?AITYX_API_KEY=<key>`) has already reached the server's logs: the
page takes it off the address bar, refuses it and says so. This is the
page's own script, so it works on a static host too.

Without a user key, an app asks this server's `GET /demos/aityx/config`.
When the server has a key, `AITYX_API_KEY` in its environment (a
Codespaces secret) or in the repository's `.env`, re-read at most every
10 s, it
answers `{"available": true, "url": ..., "source": "environment" | ".env"}`
(never the key), and the app sends its calls to `POST
/demos/aityx/v1/systemone` here, which forwards them to
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
host, which has no `/demos/aityx/config` at all. Then each app's light
is red until the user sets a key on this page.

The page has a strict content security policy (its script is
[www/index.js](www/index.js), and it may connect only to this origin and
`https://*.aityx.ai`), sent as a header too, so it can't be framed.

## Run it

Port **8800** (`INDEX_PORT`), bound to 127.0.0.1 (`INDEX_BIND_HOST`).
[group.id.txt](group.id.txt) says `aityx`. From the root of the
repository, `./start-aityx.sh` builds every demo whose build is missing
or stale, starts this server, and prints each demo's link,
`http://localhost:8800/demos/<slug>/` (`./start-all.sh` too, with
everything); `./stop-aityx.sh` stops it. From this folder, with
[Devbox](https://www.jetify.com/devbox):

```bash
devbox services up            # the index on http://localhost:8800/demos/
devbox run serve              # the same, in the foreground
```

or, with Dart on the PATH, `dart bin/server.dart`.
