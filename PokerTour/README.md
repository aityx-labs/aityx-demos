# Poker Tour

Poker Tour is [PokerFace](../PokerFace/) for a team: the same no-limit
Texas hold'em table where every player is a set of rules run on
[aityx.ai](https://aityx.ai), with the host's sign-in and leaderboard
around it:

- **Your own key.** Each player sets their aityx key in Profile (a key
  made for demos, never a production one); the table calls aityx with it
  from the browser as PokerFace does, and **Play** waits until aityx
  accepts it. Players never get the host's key: the leaderboard plays on
  a key of its own, on the server.
- **Sign in to play.** Any Google account may play (the domains are a
  setting, `POKERTOUR_ALLOWED_DOMAINS`, to narrow it). Signed out, one
  sees the leaderboard and nothing more.
- **A leaderboard.** Besides the five presets (the Rock, the Maniac, the
  Calling Station, the Mathematician and the Shark), players download
  strategies to start from and enter their own: a tournament among the
  strategies in the tour is played on the leaderboard's key four times a day,
  every six hours, whenever an admin (an aletyx.com or aletyx.ai
  account) presses **Play a tournament now** on the leaderboard, and
  whenever a player enters a strategy; one at a time, the others queued
  until it ends. The standings follow.
  The app shows them, each strategy over its owner's alias (set in
  Profile; the Google name by default), the tournament being played,
  when the next one is, and the latest results.

It is in the **multyx** group (`group.id.txt`), with tatyx, on port **9810**. On a
laptop or in the container it is one Dart server that serves the app
under `/pokertour/`, answers the API under `/api/` and plays the tournaments
on a timer, keeping the tour in [Floci](https://floci.io/), the local
AWS (its DynamoDB and S3, in Docker). On AWS it is serverless
([deploy/](deploy)): the app in S3 behind CloudFront, the API and the
tournament runner as Lambda functions on the same code, the players'
strategies and aliases in a DynamoDB table, the leaderboard's files and
key in one bucket, and an EventBridge schedule for the four daily
tournaments.

## Technology

| Part | Technology |
|---|---|
| App ([pokertour_app/](pokertour_app)) | [Flutter](https://flutter.dev) (Dart): PokerFace's table, sidebar and editor; Google sign-in ([google_sign_in](https://pub.dev/packages/google_sign_in)); the player's own key; the leaderboard, Profile (alias, key, your strategies) and uploads and downloads of strategy files |
| Engine ([poker_core/](poker_core)) | Pure Dart, shared by the app and the server: cards, hands, the game, and one decision's request to aityx and the action in its answer (PokerFace's, moved out of the app) |
| Server ([pokertour_api/](pokertour_api)) | Dart (`dart:io`): the static files, the API, Google ID tokens verified with [openid_client](https://pub.dev/packages/openid_client), the players' strategies and aliases in DynamoDB, the leaderboard's records in S3 with conditional writes, the runner that plays one tournament on aityx with the leaderboard's key, and a Lambda custom runtime (`bin/lambda.dart`) that serves the API and the runner on AWS |
| AWS ([aws_lite/](aws_lite), [deploy/](deploy), [floci/](floci)) | Signature Version 4 in pure Dart, for the server's S3, DynamoDB and Lambda calls; a CloudFormation template for S3, CloudFront, DynamoDB, Lambda (`provided.al2023`, arm64), IAM and EventBridge Scheduler, and the script that builds and deploys it; Floci, the local AWS, in Docker |
| aityx from the browser ([packages/aityx_web](../packages/aityx_web/README.md)) | The repository's shared package: the systemone call and the aityx light, on the player's key |
| Rules ([pokertour_app/assets/models/](pokertour_app/assets/models)) | PokerFace's: [table.json](pokertour_app/assets/models/table.json), what a player sees, and one [strategy](pokertour_app/assets/models/strategies) per file |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or the multyx group's [dev container](../.devcontainer/multyx/devcontainer.json); Docker for Floci; [Docker Compose](compose.yaml) for the container; Docker and the AWS CLI for the deployment |

## Set it up

Two things, both the host's, neither in the repository:

1. **A Google OAuth client.** Poker Tour has its own Google Cloud
   project, `aletyxcode-pokertour` in the aletyx.com organization, with
   an *External* consent screen ("Poker Tour", in production) and a *Web application*
   client, `pokertour-web`, whose authorized JavaScript origins are
   `http://localhost:9810` and the CloudFront address; add any other
   address it is served from (*Google Auth Platform > Clients*). Its id
   goes in `.env` as `POKERTOUR_OIDC_CLIENT_ID`, which wins over
   `OIDC_CLIENT_ID`: the repository's root `.env` is shared with
   HealthHub, whose client is in its own project. The client's JSON, as
   Google downloads it (with the secret, which nothing here needs), is
   kept in `.secrets/google-oauth-client.json`, mode 600: `.secrets/`
   and `client_secret*.json` are in the root `.gitignore`, and
   `sync-dockerignore.sh` copies them into every `.dockerignore`. The
   *External* consent screen lets any Google account sign in; the
   app and the server check the account's domain against
   `POKERTOUR_ALLOWED_DOMAINS` (`*`, any, by default).
2. **The leaderboard's keys**: `POKERTOUR_LEADERBOARD_KEY` in `.env`,
   aityx staging's, for a laptop's server (else `AITYX_API_KEY`; the
   repository's root `.env`, linked by `start-all.sh`, or this
   folder's), and `POKERTOUR_PROD_LEADERBOARD_KEY`, production's, which
   `deploy/deploy.sh` puts in S3 for the functions alone. They play the
   tournaments and check entries, and stay on the server: players never
   get them, and set their own in Profile.

Without the first the app shows the leaderboard and says the host
hasn't set the tour up; without the second the leaderboard doesn't play.
The tour's admins, who can start a tournament from the leaderboard, are
the aletyx.com and aletyx.ai accounts, whatever the playing domains. See [.env.example](.env.example) for every setting.

## Run it locally

From the repository root, with [Devbox](https://www.jetify.com/devbox):

```bash
./start-multyx.sh PokerTour
```

starts Floci, the local AWS ([floci/compose.yaml](floci/compose.yaml):
the container `pokertour-floci` on port 9811, its state in the Docker
volume `pokertour-floci`, the bucket and the table `pokertour-local`
made on the first start), builds the app's release web build and the
server if they're stale ([scripts/build.sh](scripts/build.sh)) and
starts the server
([scripts/serve.sh](scripts/serve.sh)) at
**http://localhost:9810/pokertour/**, with its API at `/api/` (`/api/health`,
`/api/config`, `/api/leaderboard`). Stop it with `./stop-datyx.sh`. Or
`devbox services up` in this folder.

The server keeps the tour in Floci as the functions keep it in AWS: the
players' strategies and aliases in its DynamoDB, `leaderboard.json` and
`live.json` in its S3 (`POKERTOUR_AWS_ENDPOINT`, never an AWS address).
A tournament is played at the hours of `POKERTOUR_SCHEDULE_HOURS`
(`0,6,12,18` UTC: four a day, every six hours), when an admin asks and
when a player enters a strategy, never two at once: queued in the
tour's DynamoDB table and played in turn;
every decision is one aityx call on the leaderboard's key, a few hundred
a tournament. `POKERTOUR_RUN=off` stops them.

## Run it with Docker Compose

```bash
docker compose up        # from this folder; the first build takes a few minutes
```

builds the image ([Dockerfile](Dockerfile): the app and the server, from
this folder and the repository's `packages/`) and runs it on port 9810,
with Floci beside it, the tour in the `pokertour-floci` volume. The
settings come from the environment or this folder's `.env`.

## Run it on AWS

```bash
bash deploy/deploy.sh    # from this folder; the first run takes a few minutes
```

builds the app and the functions' executable (in Docker, for Linux
arm64), creates or updates the CloudFormation stack `pokertour`
([deploy/template.yaml](deploy/template.yaml)) in the CLI's account and
region, uploads the app, and puts the leaderboard's key,
`POKERTOUR_PROD_LEADERBOARD_KEY`, in the bucket as
`pokertour/leaderboard.key` when it isn't there yet (`--key` writes it
again), through a pipe; only the functions can read it. Production runs
on `AITYX_PROD_URL` (`https://api.aityx.ai`). Local runs use staging,
`AITYX_URL=https://api-stage.aityx.ai`, with `POKERTOUR_LEADERBOARD_KEY`
on the server; production never reads `AITYX_URL`, `AITYX_API_KEY` or
the staging key. It prints the app's
address, `https://<distribution>.cloudfront.net/pokertour/`, whose origin
(the address without the path) must be among the Google client's
authorized origins. The stack:

- **S3 and CloudFront**: the web build in a private bucket, served by
  CloudFront at `/pokertour/` (a CloudFront function sends `/` and the
  old `/app/` there and
  resolves folders); `/api/*` goes to the API function's URL, uncached,
  the bearer token passed on.
- **Two Lambda functions** on one executable (`pokertour_api/bin/lambda.dart`,
  a custom runtime): `pokertour-api` answers the API and, when an admin
  asks for a tournament or a player enters a strategy, queues one in the
  table and invokes `pokertour-runner` asynchronously;
  `pokertour-runner` plays the queue's oldest per invocation within its
  fifteen minutes (the chips decide if the time runs out), under the
  table's lock, and invokes itself again while more wait (reserved
  concurrency 1 besides; a second call waits). Both read the
  leaderboard's key from the bucket with their role; nothing secret is
  in the environment.
- **The tour's table** (`pokertour-tour`, DynamoDB, kept if the stack
  goes): the players' strategies and aliases.
- **The data bucket** (`pokertour-data-<account>`, kept if the stack
  goes): `tour/leaderboard.json` and `tour/live.json`, written with
  S3's conditional writes so the API and the runner never lose each
  other's change, and the leaderboard's key object.
- **An EventBridge schedule**, `cron(0 0,6,12,18 * * ? *)` UTC, that
  invokes the runner four times a day.

`aws logs tail /aws/lambda/pokertour-runner --follow` shows a
tournament's log; `bash deploy/destroy.sh` removes the stack (the table
and the data and code buckets stay). Settings: `POKERTOUR_STACK`,
`LAMBDA_ARCH`, and the server's, from `.env`.

## Play

Open the app, sign in with Google, and the table opens, as PokerFace's:
play, step, the pace, the players and their rules. Beside it, the
sidebar's tabs: **Leaderboard** (the standings, each strategy over its
owner, the tournament being played, when the next is, and for an admin
**Play a tournament now**), **aityx calls** (every call, and the hand
log), and **Profile** (the account, your name on the leaderboard, your
aityx key, and your strategies in the tour). The table runs on your own
key, set in Profile with an optional URL, and on no other: without one
that aityx accepts, Profile opens and **Play** waits. On a laptop the
default URL is aityx staging's, deployed production's. The leaderboard
plays on the server, on its own key. The tour's strategies are among
the ones you can seat. **Upload a strategy** (a JSON file like the ones
**Download** gives), in Profile or the Players view, enters one; so does
**Enter it in the tour** on a strategy of your own, written in the
editor or at a seat: the server checks it on aityx (on the sample
situation) and seats it from the next tournament. Up to three a player;
one of yours can be removed in Profile or withdrawn from the
leaderboard.

Each tournament seats a random number of the strategies in the tour,
three to nine (all of them when there are fewer), none twice, the ones
with the fewest tournaments first, and runs until one has every chip (or
300 hands, or fourteen minutes: then the chips decide). The winner of a
table of n gets n − 1 points, the last 0; the standings are by points,
then wins. A strategy aityx refuses is left out with the reason shown,
until it is replaced. The leaderboard counts down to the next scheduled
tournament; an admin sees **Play a tournament now** beside it.

### Testing

- `poker_core/`: `dart test` (the engine, the table logic).
- `pokertour_app/`: `flutter analyze` and `flutter test` (the screens,
  the decision paths against a mock, the player's key and **Play**
  waiting for it, Profile's alias and strategies).
- `aws_lite/`: `dart test` (the signer against AWS's published examples).
- `pokertour_api/`: `dart test` (the leaderboard, its store and table,
  the runner with a fake aityx, the deadline, the routes and their gates,
  aliases, the schedule; `test/floci_test.dart` runs the table and the
  bucket on Floci, and is skipped unless Floci is running).
- `bash scripts/model-test.sh` runs the presets on the real aityx, as
  PokerFace's.

## Learn more

- [specs/](specs/README.md): the specification of every feature,
  [The tour](specs/tour.md) for the sign-in, the keys and the leaderboard,
  and [On AWS](specs/aws.md) for the serverless deployment.
- [PokerFace](../PokerFace/README.md): the table, the strategies and the
  aityx calls, which are the same here.
