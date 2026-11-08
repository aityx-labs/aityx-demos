# The tour

What Poker Tour adds to PokerFace's table: the sign-in, the leaderboard
the server plays, and the players' strategies and aliases. The server is
[pokertour_api](../pokertour_api) (its API in
[lib/routes.dart](../pokertour_api/lib/routes.dart), served by
`bin/server.dart` on a laptop and by `bin/lambda.dart` on AWS, see [On
AWS](aws.md)); the app's side is [lib/tour/](../pokertour_app/lib/tour)
and [lib/auth/](../pokertour_app/lib/auth). Each player plays on their
own aityx key; the host's keys are the leaderboard's alone.

## The page before the table

The app opens on the welcome
([sign_in_screen.dart](../pokertour_app/lib/screens/sign_in_screen.dart)):
behind, the table as the game shows it, seated with the five presets
(Rocky, Max, Sunny, Ada, Finn), with its controls, under a dark veil
that takes every click: nothing on it can be pressed, focused or read
out until the player signs in, and it never plays (its presets come from
the app's assets; it has no key to decide with). On the veil: what the
tour is, the state of the sign-in, and the leaderboard as it stands
(below). It asks the server how to sign in (`GET /api/config`:
the Google client id, the allowed domains, aityx's URL; never a key),
again with a growing pause while the server doesn't answer, and
then:

- **Not set up** (no client id): "The host hasn't set the tour up yet",
  and the leaderboard still shows.
- **Sign in**: Google's own button
  ([google_sign_in](https://pub.dev/packages/google_sign_in), as in
  HealthHub). The ID token is kept in the tab's session storage, so a
  reload stays signed in until it expires.
- **Not allowed**: an account outside the tour's domains (the server's
  `POKERTOUR_ALLOWED_DOMAINS`; `*`, any Google account, by default, so
  only a narrowed setting turns anyone away) is told so,
  with a sign-out button. The app checks the email's domain; the server
  checks it again on every call that needs a player.
- Signed in and allowed: the table, at once, with the sidebar of
  [the leaderboard, the aityx calls and the profile](profile.md). Without
  a key of the player's own, or with one aityx rejects, the Profile tab
  opens and asks for one, and **Play** and **Step** wait.

Signing out (in Profile) closes the table, its players and custom
strategies with it; the player's own key stays in the browser until they
forget it.

## The keys

Players bring their own aityx keys, set in Profile and kept in their
browser ([The sidebar and the profile](profile.md)); the app has no
other, and the server never hands one out. The host's keys are the
leaderboard's: they play the tournaments and check entries on the
server, and never reach a browser.

| | On a laptop (aityx staging) | Deployed (production) |
|---|---|---|
| The leaderboard's key | the server's `POKERTOUR_LEADERBOARD_KEY` (else `AITYX_API_KEY`), from `.env` | the S3 object `pokertour/leaderboard.key`, which only the functions' role can read, from `POKERTOUR_PROD_LEADERBOARD_KEY` ([On AWS](aws.md)) |
| A player's key | their own | their own |

## The leaderboard

`GET /api/leaderboard` is open to all and holds no emails: the
standings (every strategy in the tour: the five presets as the house's,
and the players' entries; points, wins, tournaments played, best and
latest place, and why one is left out; each with its owner's alias, else
the name they entered it under, or "the house"), the tournament being
played
(its number, hand, aityx calls so far, each seat's stack or finishing
place), the latest twenty results, and the runner (`enabled`; its state,
playing, waiting, idle or error, with a line of detail; the schedule's
hours, UTC, and `nextRunAt`; and `queue`, the tournaments waiting their
turn, oldest first, each by its `source` and `at`, never who asked). A tournament nobody has heard from for
sixteen minutes is reported as cut short, with no current tournament.

The app shows it on the welcome page and in the sidebar's
**Leaderboard** tab, compact ([leaderboard_panel.dart](../pokertour_app/lib/tour/leaderboard_panel.dart)),
refreshed every ten seconds while shown. Each row has the strategy's name
with its owner beneath ("template strategy" for a preset, whatever the
API calls it), then the wins (the ranking is still by points; they
aren't shown). The latest results aren't listed. The line at the top says what
the leaderboard is doing and the tournaments waiting their turn ("the
schedule's, a new strategy's"); the line under it counts down to the
next scheduled tournament by the second, with when it is in local time
("Next tournament in 2 h 14 min, today at 18:00"; "12 min 05 s" under
an hour; "any moment now" once the time has passed and the board hasn't
caught up). Only an admin (`GET /api/me` says
`admin`: an `aletyx.com` or `aletyx.ai` account, whatever
`POKERTOUR_ALLOWED_DOMAINS` lets play; no setting widens it) has **Play
a tournament now** beside it, disabled while an admin's is waiting; it
calls `POST /api/tournaments` and says "A tournament is starting", "A
tournament is queued: it starts when the one being played ends" or "A
tournament you asked for is waiting its turn already". Rows of yours say
"yours" (matched by an owner id, a short hash of the email the server
gives `GET /api/me`). Per row: **Download as JSON** (the rules; a preset's from
the table's own, an entry's from `GET /api/strategies`) and, for yours,
**Withdraw**.

### Aliases

The leaderboard names a player by their alias, else their Google name
(else the email's part before the @). **Your name on the leaderboard**
in Profile sets it: `PUT /api/me` with `{"alias": "..."}`, up to 32
characters on one line (`400` otherwise), trimmed; empty goes back to
the name. `GET /api/me` answers the alias (null for none) with the rest;
the standings and `GET /api/strategies` show it for every strategy of
theirs, old ones too.

### Entering a strategy

Four ways in, all through `POST /api/strategies` with the ID token:
**Upload a strategy** (a JSON file, as **Download** gives: `name`,
`tagline`, `decisions`) in Profile or in the Players view, **Enter it in
the tour** in the strategy editor (which saves the rules as yours
first), and the trophy button on a strategy of yours in the players
panel. Profile lists **Your strategies in the tour**, each with a remove
button. The server checks it
is a strategy (a name of up to 60 characters, `decisions.action` and
`decisions.raise_to`), that the name isn't a preset's, that the player
has fewer than three (`POKERTOUR_MAX_ENTRIES`; an entry of the same name
is replaced, with a fresh record), then runs it on aityx on the sample
situation (A♥ K♦ on K♠ 7♣ 2♦; `422` with aityx's reason when it refuses
the rules), enters it, and asks for a tournament (below), where it sits
first, having played none; the answer's `tournament` says what asking
did (`started`, `queued`, `waiting`; null when the leaderboard is off),
and the app's message after an upload says so. `DELETE
/api/strategies/{id}` withdraws one of yours.

Every call that enters or reads strategies, or starts a tournament,
needs a bearer token Google issued for the server's client id
([auth.dart](../pokertour_api/lib/auth.dart), verified with openid_client
against Google's keys, remembered until it expires), for a verified
email in an allowed domain: `401` without one, `403` for another domain,
`503` while the server has no client id. `POST /api/tournaments` wants an
admin's besides (`403` otherwise) and answers `202` with `started`,
`queued` (behind the tournament being played) or `waiting` (an admin's
is queued already); `503` when the leaderboard is off.

### The runner

[runner.dart](../pokertour_api/lib/runner.dart) plays one tournament
when asked (`POKERTOUR_RUN=on` and a key), by three sources:

- the **schedule** ([schedule.dart](../pokertour_api/lib/schedule.dart):
  `POKERTOUR_SCHEDULE_HOURS`, `0,6,12,18` UTC, four times a day, every
  six hours; a timer in the server, an EventBridge schedule on AWS);
- an **admin**'s **Play a tournament now**;
- a player's **new strategy**, every entry (a replacement too).

Never two at once: a tournament asked for is **queued**
([queue.dart](../pokertour_api/lib/queue.dart)) in the tour's table
and played when the one being played ends, the oldest first. At most one
waits per source: asking again while one from the same source waits
answers `waiting`, and that one stands for both (a second new strategy
plays in the tournament the first asked for, since the fewest
tournaments sit first). The queue is played by whoever holds the
runner's **lock**, an item of the same table taken with a conditional
write (free, its holder's, or lapsed): the laptop's server, or on AWS
the runner function, one tournament per invocation, which invokes
itself again while more wait. A lock lapses sixteen minutes after it
was taken, longer than a tournament may run, so a holder that died (a
function out of time, a server killed) holds nothing for long; a
laptop's server, its table's only player, also lets its last process's
lock go when it starts, and plays what that one left in the queue.

- How many sit is drawn at random each tournament, from three to nine
  (all of them when fewer can play), none twice: the ones with the
  fewest tournaments first, ties at random; fewer than two that can
  play, and it idles.
- The game is PokerFace's ([poker_core](../poker_core)): 1000 chips
  each, blinds up every ten hands, no rebuys. Every decision is one aityx
  call on the leaderboard's key, as the app's
  ([aityx.dart](../pokertour_api/lib/aityx.dart)). A tournament runs until
  one player has every chip, or `POKERTOUR_MAX_HANDS` (300), or the
  time is up (fourteen minutes, a Lambda function's limit, on a laptop
  too): then the chips decide the places of those still in. Out of time
  before a hand is played, nothing is recorded.
- A strategy aityx refuses (a 4xx about the model, or no action in the
  answer) is marked broken with the reason, folds for the rest of that
  tournament, and sits out until it is replaced by a new entry of the
  same name; a preset plays again after a restart. aityx not answering
  is retried after 30 s, doubling to five minutes, while there is time,
  with the runner's state saying so; a rejected key ends the tournament
  at once, unrecorded, with "the leaderboard cannot play until the host
  sets a working key".
- At the end, places become points: the winner of a table of n gets
  n − 1, the last 0; wins, best and latest place are kept. The standings
  are by points, then wins, then fewer tournaments, then name. The
  runner's state then says the result, until the next tournament.

The state is in two places, on AWS and, on a laptop, in Floci, the local
AWS ([Development environment](dev-environment.md)):

- **The tour's table** ([tour_db.dart](../pokertour_api/lib/tour_db.dart),
  DynamoDB): the players' strategies (`pk` `STRATEGY`, `sk` the entry's
  id), with their owners' emails (never served), and the players
  (`pk` `PLAYER`, `sk` the owner id), their name and alias; each item's
  rest as JSON in `data`. Also the queue (`pk` `QUEUE`, `sk` the source:
  `schedule`, `admin` or `strategy`; when it was asked for and the
  owner id of who asked), put only if absent, and the runner's lock
  (`pk` `RUNNER`, `sk` `LOCK`; `holder` and `until`, in ms).
- **The store** ([store.dart](../pokertour_api/lib/store.dart), S3):
  `leaderboard.json`, every record, the history and a revision, and
  `live.json`, the runner's state and the tournament being played,
  written at most every five seconds.

Every look reads both. A change reads both, writes `leaderboard.json`
back only if nobody wrote in between (S3's ETag with `If-Match`; the
revision makes every change a new file), the change being redone on a
fresh read otherwise, then puts and deletes the strategies it touched.
A `leaderboard.json` from before the table, with its entries in it,
moves them to the table at its next change. The presets are in neither:
they are always in the tour.

## Settings

See [.env.example](../.env.example): the leaderboard's key and aityx's
URL (`POKERTOUR_LEADERBOARD_KEY`, else `AITYX_API_KEY`; `AITYX_URL`), the
sign-in (`OIDC_CLIENT_ID`, `OIDC_ISSUER`, `POKERTOUR_ALLOWED_DOMAINS`; the admins are aletyx.com's
and aletyx.ai's, no setting), the runner (`POKERTOUR_RUN`,
`_SCHEDULE_HOURS`, `_MAX_HANDS`, `_MAX_ENTRIES`), Floci
(`POKERTOUR_AWS_ENDPOINT`, default `http://localhost:9811`, never AWS's;
`POKERTOUR_DATA_BUCKET` and `POKERTOUR_TABLE`, both `pokertour-local`
by default), where the server listens (`POKERTOUR_BIND_HOST`,
`FLUTTER_WEB_PORT`, `API_PORT`, one port), and the deployment's ([On
AWS](aws.md)).

## Tests

[test/tour_test.dart](../pokertour_app/test/tour_test.dart): the server's
answers read (the admin, the schedule, starting a tournament), and the
welcome page without a sign-in set up (no "now" button; the table and
its controls behind the veil, out of reach);
[test/profile_test.dart](../pokertour_app/test/profile_test.dart): the
player's key alone (never another), **Play** disabled until it works,
and Profile setting the alias the leaderboard shows and removing a
strategy of yours.
[pokertour_api/test/](../pokertour_api/test): the leaderboard (entering,
limits, points, the store and the table, a lost race redone, conditional
writes), the runner on a fake aityx (a whole tournament with the store
told, who sits, a broken strategy, the deadline, a rejected key), the
routes and their gates (the admin's, the runner's state, a tournament
cut short, the config without a key, aliases), the schedule, and
`floci_test.dart`, the table and the bucket on Floci (skipped when it
isn't running). [aws_lite/test](../aws_lite/test): the signer.

## Known limitations

- A player's key is used from the browser, as PokerFace's: anything
  running on the origin could read it, hence Profile's advice to use a
  key made for demos. The build takes CanvasKit from its own origin;
  Google's sign-in SDK is the one third-party script.
- A server restart, or a function out of time, ends the tournament in
  progress unrecorded; the leaderboard says it was cut short until the
  next one. Entries changed during a tournament take effect at the next.
- The admins' domains are the server's setting, checked on every `POST
  /api/tournaments`.
- An alias isn't unique: two players may choose the same one.
- No pagination: the leaderboard answers every entry; fine for a team.
- Strategies written in the app are lost on a reload, as in PokerFace,
  unless entered in the tour or downloaded.
