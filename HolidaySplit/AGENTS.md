# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this project that means
  `npm test` passes in `holidaysplit_app/`, and `bash scripts/build.sh`
  builds the web app (with `<base href="/demos/holidaysplit/">` in
  `holidaysplit_app/build/web/index.html`). After changing the trip
  reader's prompt (`holidaysplit_app/public/reader/trip-reader.js`), run it
  on the samples in a browser and check the lists it fills in.
- **Secrets**, such as the aityx key: users set theirs on the index page,
  in their browser; the dev key (`AITYX_API_KEY`) lives only in the
  repository's `.env`, which the index server reads. Never compile a key
  into the app, show it on screen (the aityx call shown is the request
  body, never its headers), print it, or put it on a command line. The
  trip reader's worker must never be given the key.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks (the page builds HTML from user text: escape it
  with `esc`), and unnecessarily broad permissions or exposed ports. Keep
  transformers.js pinned to an exact version. Never commit credentials,
  even placeholders that look real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- There's no API or service of its own: the app calls aityx itself
  (package `aityx-js`, `../packages/aityx_js`), and the repository's
  index server (`Index/`) serves the web build at `/demos/holidaysplit/`.
  Start it with `./start-all.sh HolidaySplit` from the repository root.
