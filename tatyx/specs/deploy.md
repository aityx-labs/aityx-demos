# Deployment

tatyx runs serverless on AWS, in the account and region of the AWS CLI's
credentials, as the CloudFormation stack `tatyx`
([deploy/template.yaml](../deploy/template.yaml)), deployed by
`bash deploy/deploy.sh` (`--key` to put the leaderboard's key again,
`--no-build` to deploy the build there is).

Every resource is tagged for cost allocation with the account's standard,
`project=tatyx` and `tenancy` (`TATYX_TENANCY`: `GA`, the default, `RC` or
`shared`): the deploy passes them as the stack's tags, which CloudFormation
copies to every resource that takes tags, and puts them on the code bucket
it makes outside the stack.

## What runs where

- **CloudFront**, one address (`https://<id>.cloudfront.net`):
  `/tatyx/` is the app, from a private web bucket (under `tatyx/`; `/`,
  `/tatyx` and the old `/app` paths redirect there, a path without an
  extension gets the page); `/api/` and `/aityx/` go to the API
  function's URL, uncached, with the cookies, the player's
  Authorization header and the body, and the page's host in
  `x-tatyx-host` (set by CloudFront, so a POST's Origin is checked
  against the page's host, not the function URL's).
- **The API function** (`tatyx-api`, Node 22): the server's own routes
  ([tatyx_server/lambda.mjs](../tatyx_server/lambda.mjs) makes a
  function URL event the server's request): the config, the sign-in and
  its session cookie, the aliases, the entries, the leaderboard, and the
  relay of the player's calls (on their own key) to production's aityx,
  `AITYX_PROD_URL`, never staging.
- **The runner function** (`tatyx-runner`): one tournament per
  invocation, within 15 minutes, on the leaderboard's own key; one at a
  time (reserved concurrency 1: the others wait in Lambda's queue, up to
  six hours). Invoked by the schedule (`tatyx-tournaments`, at 0, 6, 12
  and 18 UTC), by an admin's **Play a tournament now**, and by every
  strategy a player enters. Its progress is in `live.json`, which the
  API shows.
- **The data bucket** (`tatyx-data-<account>`, versioned, kept when the
  stack goes): under `tour/`, `leaderboard.json`, `strategies.json`
  (the entries), `players.json` (the aliases), `live.json` and
  `session-secret` (made by the first function to need it, once);
  and `tatyx/leaderboard.key`, `TATYX_PROD_LEADERBOARD_KEY`, which only
  the functions' role reads. The players' keys stay in their browsers.

## The strategies kept in the repository

[strategies/](../strategies) holds the players' strategies kept with the
game, one file each (an entry: id, owner, name, tagline, decisions,
when entered). A tour with no entries yet, a laptop's or the deployed
one, starts with them (`strategies.json` is written from them once);
after that the tour's own file is the truth, and a withdrawn one stays
withdrawn.

## Sign-in

The Google OAuth client (`TATYX_OIDC_CLIENT_ID`) must list the
CloudFront origin the deploy prints among its authorized JavaScript
origins, or Google's button answers "origin not allowed".

## Known limitations

- An admin's or an entry's tournament asked for while one is played is
  queued in Lambda, not shown in the leaderboard's queue.
- The default CloudFront address; no custom domain yet.
