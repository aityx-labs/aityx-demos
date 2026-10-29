# aityx.ai integration

[aityx.ai](https://stage.aityx.ai/docs) runs decision models: `POST
/v1/systemone` executes a model on known facts, `POST
/v1/systemtwo/decisions` interprets raw input and executes it, and `POST
/v1/systemtwo/models` writes or revises a model. Calls send
`Authorization: Bearer <key>` and JSON `{decision, state}`, and return
`answers`, a `receipt` and `usage`.

The [regulatory check](regulatory-check.md) uses it, through the API
([mortgagehub_api/](../mortgagehub_api)), which holds the key.

- **Key:** `AITYX_API_KEY`, always the user's own; none ships with the
  repository. It arrives either from the environment or from `.env`
  (git-ignored, mode 600), and the scripts prefer the environment. In a
  codespace it comes from the environment: `devcontainer.json` declares it
  under `secrets`, so GitHub asks the person creating the codespace for
  it, keeps it against their account, and passes it in without writing it
  to disk. It's a secret: it's never passed to Flutter (no
  `--dart-define`), since anything compiled in is readable in the web
  bundle. When the app needs aityx, the calls go through the API
  (`scripts/api.sh` exports it to the server's own environment only).
- **Base URL:** `AITYX_URL`, by default `https://api.aityx.ai`, the one
  the docs name. The stage key works only on stage: `.env` sets
  `AITYX_URL=https://api-stage.aityx.ai`, the API endpoint for stage
  console itself calls (production answers 401 to it).
- **Check:** [scripts/aityx-check.sh](../scripts/aityx-check.sh) runs the
  docs' cancellation example on System One (deterministic, the cheapest
  call) and checks the answers match the docs' (`cancel_refund`, eligible,
  \$20, 2026-10-28). It prints only the status and the answers; the key
  goes to curl on stdin, never on a command line. Needs `jq`.

- **What aityx returns:** each answer typed (`choice`, `number`,
  `value` for strings and table structs, `noul` for booleans as `1.0` /
  `0.0`), and a receipt with the rule each table matched. Strict mode
  requires a type on every decision and a `# why` on every table row.
- Verified on 2026-10-13: the check script passes against stage.

## Known limitations

- `jq` comes from the host, not devbox.
