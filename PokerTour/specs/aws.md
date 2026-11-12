# On AWS

Poker Tour runs serverless on AWS, from the same code as the laptop's
server: [deploy/](../deploy) holds the CloudFormation template and the
script that builds and deploys it. The stack, named `pokertour`
(`POKERTOUR_STACK`), in the CLI's account and region:

## The parts

- **The app**: the release web build (base href `/app/`, CanvasKit from
  its own origin) in a private bucket, `pokertour-web-<account>`, under
  `app/`, served by **CloudFront** through an origin access control. A
  CloudFront function on every request sends `/` and `/app` to `/app/`,
  gives a folder its `index.html`, and an extension-less path under
  `/app/` the app. The default caching policy applies; `deploy.sh`
  uploads with `max-age=300` and invalidates `/*`, and gives `.wasm`
  its type, which the CLI doesn't know.
- **The API**: the function `pokertour-api` (`provided.al2023`, arm64,
  512 MB, 60 s), `pokertour_api/bin/lambda.dart` as `bootstrap` with
  `POKERTOUR_ROLE=api`, reserved concurrency 20 (its URL answers anyone,
  so a flood can't take the account's concurrency, which other apps
  share), behind a Lambda function URL (no auth of its
  own: the API verifies the tokens), which CloudFront fronts at `/api/*`
  with a cache policy of its own (TTL 0, `Authorization` in the key, so
  it reaches the function) and the managed all-viewer-except-host origin
  request policy. The function URL event (payload 2.0) becomes a call of
  `route()`; the answer, a JSON body with `cache-control: no-store`.
- **The runner**: the function `pokertour-runner` (same code,
  `POKERTOUR_ROLE=runner`, 900 s, reserved concurrency 1): the
  queue's oldest tournament per invocation, under the table's lock
  ([The tour](tour.md#the-runner)) held until five seconds past the
  function's own deadline, with the tournament's deadline 90 s before
  it (room for a last aityx call and the writes), and the result in the response (`played`, `number`,
  `hands`, `calls`, the state, `more`); while more wait it invokes
  itself again (`POKERTOUR_RUNNER_FUNCTION`, its own name), so each
  tournament gets a function of its own. Invoked by the **EventBridge
  schedule** `pokertour-tournaments`, `cron(0 0,6,12,18 * * ? *)` UTC
  (`ScheduleHours`), which queues the schedule's first, and by the API
  asynchronously once it has queued an admin's or a new strategy's
  (`POST /api/tournaments`, `POST /api/strategies` →
  `lambda:InvokeFunction` with `X-Amz-Invocation-Type: Event`). An
  invocation that finds the lock taken, or nothing queued, plays
  nothing. A second invocation while one runs is throttled by the
  concurrency limit and retried by Lambda for up to an hour; function
  errors are not retried.
- **The tour's table**, `pokertour-tour` (DynamoDB, on demand,
  point-in-time recovery, encrypted, kept if the stack goes): the
  players' strategies and aliases ([The tour](tour.md)), named to the
  functions as `POKERTOUR_TABLE`.
- **The data bucket**, `pokertour-data-<account>` (private, versioned,
  old versions expire after 30 days, no CORS, kept if the stack goes;
  its policy denies reading any `*.key` object to every principal but
  the functions' role, an administrator too, and anything without
  TLS): `tour/leaderboard.json` and
  `tour/live.json` (the store of [The tour](tour.md), with S3's
  `If-Match` and `If-None-Match` as the version check), and the
  leaderboard's key, `pokertour/leaderboard.key`, production's, which
  `deploy.sh` writes from `POKERTOUR_PROD_LEADERBOARD_KEY` through a pipe
  when a listing of the bucket doesn't show it (or with `--key`), read
  from `.env` only then: `scripts/env.sh` exports no production key, and
  `deploy.sh` unsets the local ones, so no build or CLI process inherits
  a key. The functions read it (and again
  after ten minutes) with their role, and nothing else can: no secret in
  the environment or the template, and none for the players, who bring
  their own. Their aityx is `AITYX_PROD_URL` (`https://api.aityx.ai`);
  `deploy.sh` refuses a staging address there.
- **IAM**: the functions' role (logs; the tour's files; `GetItem`,
  `PutItem`, `DeleteItem` and `Query` on the table; `s3:GetObject` on
  the leaderboard's key object; and the runner to invoke, by name); the
  scheduler's role. No role for players. The log groups keep fourteen
  days.
- **Headers**: every answer through CloudFront carries HSTS (a year),
  `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` (the page
  holds the player's key) and `Referrer-Policy:
  strict-origin-when-cross-origin`, by a response headers policy.

The functions are built in Docker ([lambda.Dockerfile](../docker/lambda.Dockerfile),
the official Dart 3.13 image for `linux/arm64`; `LAMBDA_ARCH=x86_64`
for the other architecture) into `deploy/out/lambda/`, zipped with the
models, and uploaded to `pokertour-code-<account>-<region>` under
`lambda/<hash>.zip`, so an unchanged build redeploys nothing.

## The script

`bash deploy/deploy.sh [--key] [--no-build]`, from the PokerTour
folder, with the AWS CLI's credentials, Docker and `zip`: builds, uploads
the code, deploys the stack (`aws cloudformation deploy`, the sign-in's
client id, aityx's URL, the domains, the schedule and the limits from
`.env`), syncs the app, writes the leaderboard's key when missing, and
prints the address and the origin to authorize in the Google client.
`bash deploy/destroy.sh` empties the web bucket and deletes the stack;
the table and the data and code buckets stay.

## The sign-in

Poker Tour's Google client is its own: the project `aletyxcode-pokertour`
(aletyx.com organization), an *Internal* consent screen, and the web
client `pokertour-web` with the origins `https://d2qns5tf435v11.cloudfront.net`
and `http://localhost:9810`. `deploy.sh` passes its id,
`POKERTOUR_OIDC_CLIENT_ID` from `.env`, to the stack, which publishes it
in `GET /api/config`; the API verifies the tokens against it. The
client's downloaded JSON stays in `PokerTour/.secrets/` (git- and
docker-ignored, mode 600). AWS never sees the players' tokens.

## Known limitations

- The Google client's authorized origins can't be set from here: a new
  CloudFront address (another stack, a custom domain) must be added by
  hand in Google Cloud, or the sign-in popup answers `origin_mismatch`.
- The consent screen is *Internal* to the aletyx.com organization:
  aletyx.ai accounts sign in only if that domain belongs to the same
  Google Workspace; otherwise the audience must be *External*, with them
  as test users or the app published.
- A tournament is fifteen minutes at most: a table of nine slow
  strategies may end on chips.
- One region, one stack name; a second deployment needs another
  `POKERTOUR_STACK`.
- CloudFront's default certificate and domain: no custom domain yet.
- No Content-Security-Policy yet: the Flutter build (CanvasKit, its
  wasm) and Google's sign-in script need one written and tested for
  them.
- The function URL is public: CloudFront doesn't sign its calls (an
  origin access control for a function URL wants the body's hash from
  the browser), so the API's reserved concurrency is what bounds direct
  calls.
- The tour's table and `leaderboard.json` are written in turn, not
  together: two changes at the same moment can leave the table a step
  behind the file until the next change.
