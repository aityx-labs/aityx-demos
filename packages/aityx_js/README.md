# aityx-js

aityx from the browser, for the demos written in TypeScript (the tatyx
game): the key, systemone calls, the status check, the status
light and the key form. The TypeScript twin of
[aityx_web](../aityx_web/README.md), the Dart package the Flutter demos
use, with the same storage entries and the same rules, so a key set on
one origin by either works for every page of that origin.

There's no build: the package is its TypeScript source, and the app's
bundler (Vite) compiles it. Depend on it by path, in the app's
`package.json`:

```json
"dependencies": { "aityx-js": "file:../../packages/aityx_js" }
```

## Where the key comes from

`resolveConnection()` follows this order, in the browser:

1. **The user's key**, set with the app's key form (`mountKeyForm`,
   which keeps it in `localStorage['aityx.key']` until forgotten; its URL
   field starts at `defaultUrl`, or `setDefaultUrl()` once the app knows
   its server's): `sessionStorage['aityx.key']`, else
   `localStorage['aityx.key']`. The URL comes
   from `aityx.url` in the same storage, where the form keeps the one the
   key was saved with (production's too), defaulting to
   `https://api.aityx.ai` for a key saved without one. The app calls
   `<url>/v1/systemone` directly, with `Authorization: Bearer <key>`,
   or, given a `relay` (`{url, endpoint}`, asked on each resolve) that
   relays to that URL, `<endpoint>v1/systemone` with the same header:
   the app's server passes it on, for an aityx that takes no calls from
   browsers (staging). Give the key form the same `relay`, so its check
   goes where the calls will.
2. **The dev key**, unless `lend: false` (the multyx games, where every
   player brings their own key): with no user key, the app GETs `<proxyPath>config` on
   its origin (`/aityx/config` by default; the aityx index's is
   `/demos/aityx/config`). When the app's server has a key (`AITYX_API_KEY`
   or the repository's `.env`), it answers `{"available": true, "url": ...,
   "source": ".env" | "environment"}`, never the key. Calls then go to
   `<origin><proxyPath>v1/systemone`, with no Authorization header: the
   server adds the key, so it never reaches the browser.
3. **None**: `{"available": false}`, a 404, an HTML page (a static host),
   or no answer. The light is red and calls throw `AityxNoKey`.

Each demo of the multyx group that uses it (tatyx) runs on its own origin (its own port), so
each shows the key form; the aityx demos share the aityx index's origin
and get theirs from its page instead.

## Using it in an app

```ts
import { AityxClient, mountKeyForm, mountStatusLight } from 'aityx-js';

// The light, top right on every screen; a click opens the key form.
const light = mountStatusLight(document.getElementById('light')!, {
  onClick: () => dialog.showModal(),
});
mountKeyForm(dialog, { onSaved: () => dialog.close() });

// One call: the request body in, the answer out, timed.
const client = new AityxClient();
const answer = await client.systemone({ model: ..., inputs: ... });
if (!answer.ok) console.warn(answer.problem);
```

The key form can save a page's own fields with the key, under one
button: `submitLabel` names the button (**Check and save** unless given),
and `alsoSave`, run first on each submit, saves the page's fields and
resolves to what it saved, in a sentence (null when nothing changed). With
`alsoSave` the key field may stay empty, and the key is checked with aityx
only when it or its URL changed (`keyUnchanged`), so saving the rest
spends no request. tatyx's Profile saves the player's name on the
leaderboard this way, with **Save profile**.

`checkAityx()` asks aityx whether it accepts the key without running a
model (an empty POST: a working key gets 400 `invalid_request`, a bad one
401); each check spends a request of the user's quota, so the light checks
on start, on a key change and on focus, never on a timer.

## Tests

```bash
npm install
npm test          # vitest: the store, the connection, the check, the resolution
npm run typecheck
```
