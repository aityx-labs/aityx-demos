# Requests

The requests that shaped Poker Tour, oldest first, each with what changed. Up to 2026-11-06 they are PokerFace's, which Poker Tour was copied from.
The feature files hold the current specification; see the
[index](README.md).

## 2026-11-09

21. **"In the index of poker tour show the leaderboard more
    prominently, without played and best, only wins, and the welcome
    message to the side with the sign-in button; also pop the Google one
    click sign-in on the top as usual."** The welcome page puts the
    leaderboard first, large, in a card of its own, with the welcome and
    the sign-in in a card beside it on the right (above it on a narrow
    screen). Its standings show the wins alone, ranked by them, with
    medals for the first three; the sidebar's are unchanged. Google's One
    Tap prompt, already asked for as the page opens, is asked for again
    after a sign-out ([The tour](tour.md)).

## 2026-11-08

20. **"Access blocked: Poker Tour can only be used within its
    organization": make it available to external accounts as well.**
    The Google project's consent screen is *External* now, in
    production, and the tour's domains default to `*`, any Google
    account (`POKERTOUR_ALLOWED_DOMAINS` still narrows it); the sign-in
    asks for "your Google account". The admins are still the aletyx.com
    and aletyx.ai accounts alone ([The tour](tour.md)).

19. **Found checking the deploy: a random tournament seated a preset
    twice.** The table's list held each preset twice, the app's own and
    the copy the server returns with the tour's strategies (`tour-shark`
    beside `shark`), so clicking the title could seat The Shark twice.
    The tour's copies of the presets are no longer added
    ([Players and strategies](players.md)).

18. **Fixes from a review of the above before deploying.** A new
    tournament (the title, or **New tournament**) while aityx is deciding
    for the old table no longer throws when the answer comes back or
    leaves **Play** stuck: the late answer is dropped and a **Play**
    pressed meanwhile waits for it ([The table](table.md)). The music
    stops on sign-out, and starts at its defaults when the browser blocks
    storage instead of breaking the table ([Music](music.md)). The Rock
    keeps premium cards with a pair only when the pair is likely best
    (50% equity), so ace-king on a paired board is no longer bet and
    called at any price; the Shark's short-table rule says what it does,
    re-raise a loose opener ([Strategies](strategies.md)). `make.sh
    android` prints the APK's real path again.

17. **In the index view of the poker app (before login), show a table
    and controls like the game, with an overlay on top so nothing is
    clickable until login.** The welcome page shows the game's table,
    seated with the presets, and its controls, under a veil that takes
    every click, focus and screen-reader visit; the welcome, the sign-in
    and the leaderboard sit on the veil ([The tour](tour.md)).

16. **Make the path to Poker Tour /pokertour instead of /app, so that it
    can live in the same server as other apps.** The web build's base
    href is `/pokertour/`; the server serves it there and sends `/`,
    `/pokertour` and the old `/app/` paths to it, and so does the
    CloudFront function; `deploy.sh` uploads it under `pokertour/` in
    the web bucket. The API stays at `/api/`. The multyx index opens
    Poker Tour at `/pokertour/` and takes a redirect for an answer
    ([On AWS](aws.md), [Development environment](dev-environment.md)).

15. **In Poker Tour, "the Mathematician" seems to dominate: make sure no
    template strategy dominates; balance them. Save the strategies to the
    repository as well as server side.** The five presets were tuned
    against each other by simulating thousands of tournaments locally:
    the Rock sees cheap flops, goes all in short-stacked and can't fold a
    premium pair; the Maniac holds back junk at a full table, bluffs
    when few are left and folds calls that would cost its stack; the
    Station folds weak cards over four big blinds and calls that risk a
    fifth of its stack; the Mathematician bets only on a 30-point edge;
    the Shark steals more and plays wider at a short table
    ([Strategies](strategies.md)). They are the app's assets, which the
    server reads (a laptop's straight from the app, the Lambda functions
    from the models deploy.sh bundles with them): no S3 or DynamoDB copy
    is needed.

14. **In each tournament on the leaderboard, pick a random number of
    strategies, non repeated.** The runner draws the table's size at
    random, three to nine (all of them when fewer can play), and seats
    that many distinct strategies, the fewest tournaments first
    ([The tour](tour.md)).

13. **Make it have a jazz soundtrack, five songs, randomly played in
    loop, soft and easy, with volume and mute control.** Five original
    tracks (a ballad, a medium swing, a bossa nova, a minor blues and a
    waltz), synthesized by `scripts/jazz.dart`, play at the table in a
    random order, round and round, never one twice in a row; a note
    button mutes them, a slider sets the volume, and the browser
    remembers both ([Music](music.md)).

12. **Show the time to the next tournament on the leaderboard.** A line
    under the leaderboard's status counts down to the next scheduled
    tournament by the second, with its local time ([The tour](tour.md)).

11. **When the title is clicked, create a new tournament with random
    strategies without repetition.** The app bar's title starts a new
    tournament at the player's table with three to nine distinct
    strategies drawn at random from the table's list ([The
    table](table.md)).

10. **Remove the "seat at my table" button column.** The leaderboard's
    rows lost **Seat it at my table**; **Download as JSON** and, for
    yours, **Withdraw** stay ([The tour](tour.md)).

9. **Make sure the player's key, URL and alias are persisted.** The key
   and the alias already were: the key in the browser (localStorage,
   or sessionStorage for one session), the alias on the server, in the
   tour's table. The URL was kept only when it wasn't this
   environment's, so a key saved for staging on a laptop followed the
   server's URL, and would have gone to production had the server's
   changed; now the URL the key was saved with is always kept
   ([Profile](profile.md)).

8. **Set the group on Poker Tour and tatyx to a new one, multyx: three
   groups, each with its scripts, ids, builds and dev container: aityx
   for the six demos, datyx for the datyx API, its dashboard and
   HealthHub, multyx for Poker Tour and tatyx.** Poker Tour left the
   datyx group for multyx (`group.id.txt`): `./start-multyx.sh
   PokerTour` starts it; its card moved from the datyx index to the
   multyx index (`multyx-index/`, port 9700); the datyx dev container no
   longer forwards 9810, the multyx one does (`.devcontainer/multyx/`,
   with Docker for Floci, on the image `bash image/build-image.sh
   multyx` publishes, which carries the app's web build). The port stays
   9810, the origin the Google sign-in client allows ([Development
   environment](dev-environment.md)).

7. **The leaderboard's GA and staging keys, used safely and never
   exposed to users; players set their own key to play and never use
   the host's; clean up the Profile view (no closing paragraph, no URL
   description, the current URL shown) with a disclaimer to use a key
   made for demos only; disable Play while the key is missing or not
   working; show each strategy's owner under its name on the
   leaderboard, by an alias the player sets in Profile (their name by
   default); upload strategies from the Players and Profile views, and
   add or remove them in Profile; store every strategy in DynamoDB;
   use Floci for all local emulation of AWS services.** The
   leaderboard plays, and checks entries, on keys of its own:
   `POKERTOUR_LEADERBOARD_KEY` (staging) in the laptop server's
   environment, and `POKERTOUR_PROD_LEADERBOARD_KEY` (production),
   which `deploy.sh` pipes to `pokertour/leaderboard.key`, an object
   only the functions' role can read. The tour's key for players went
   with everything that served it: the key objects
   `pokertour/aityx.key` and `pokertour/aityx-local.key`, the players'
   role, the app's STS and S3 fetch (`lib/aws/`), the data bucket's
   CORS, the `GooglePrincipal` and `ExtraOrigins` parameters, and
   `key` in `GET /api/config` and `/api/health`. The table runs on the
   player's own key alone; **Play** and **Step** stay disabled ("Set a
   working aityx key in Profile to play") until aityx accepts it.
   Profile lost its closing paragraph and the URL's description: it
   says "Set yours to play", warns "Use a key made for demos only.
   Never reuse a production key here.", shows the current URL under
   the URL field, and gained **Your name on the leaderboard** (`PUT
   /api/me` with `alias`, up to 32 characters, empty for the Google
   name) and **Your strategies in the tour**, with **Upload a
   strategy** and a remove button for each. **Upload a strategy** left
   the leaderboard for Profile and the Players view; the leaderboard's
   rows show the owner under the strategy's name, by alias, and the
   "By" column went. The players' strategies and aliases moved to a
   DynamoDB table (`pokertour-tour` deployed, with point-in-time
   recovery; `pk` `STRATEGY` or `PLAYER`); `leaderboard.json` keeps
   the records and the history, its entries moving to the table at the
   next change. On a laptop the server keeps the tour in Floci
   ([floci/compose.yaml](../floci/compose.yaml), port 9811, the volume
   `pokertour-floci`): its S3 and DynamoDB, both `pokertour-local`; the
   `data/` folder and `POKERTOUR_DATA` went. See [The tour](tour.md),
   [On AWS](aws.md), [The sidebar and the profile](profile.md),
   [Players and strategies](players.md) and [Development
   environment](dev-environment.md).

## 2026-11-07

6. **In the Profile tab, remove the key's reachability indicator and
   the "Only for this session" checkbox; "Use my key" can be "Save
   key".** The line that said which key the table runs on, on which
   aityx, and whether aityx accepts it (with its check-again button)
   went, and so did the checkbox: a saved key always goes to
   localStorage. The button reads **Save key**. The red note when there
   is no key, or aityx rejects it, stays, and so do the sidebar tab's
   crossed-out key and the aityx light. See [The sidebar and the
   profile](profile.md).

5. **A different experience: the table and the title on the left, and
   on the right a sidebar with tabs, the leaderboard, the aityx calls
   and the profile; with no aityx key, open the profile and let the
   user set their key and optionally the URL; by default staging's URL
   and key locally, production's elsewhere; the player uses their own
   key for their bots and strategies, the leaderboard its own.** The
   app bar's **Leaderboard** button and account menu went: the sidebar
   runs the window's height beside the title and the table, with
   **Leaderboard** (compact, with **Play a tournament now** and
   **Upload a strategy**), **aityx calls** (the hand log a switch away)
   and **Profile** (the account, the key in use and whether it works,
   **Your key**, **URL (optional)**, **Only for this session**). The
   table runs on the player's own key (kept in the browser), else the
   tour's from S3 (staging's object locally, production's deployed),
   on their URL else this environment's (`GET /api/config`). Signing in
   goes straight to the table; Profile opens when there is no key or
   aityx rejects it, and on a tap of the aityx light. aityx staging
   takes no browser calls, so the local server relays the app's calls
   to it (`/aityx/v1/systemone`, with the browser's own key). See [The
   sidebar and the profile](profile.md).

4. **Make all demos use the staging address and keys locally, and the
   production aityx site and keys in production; staging is
   https://stage.aityx.ai/.** Staging's API is
   `https://api-stage.aityx.ai` (`stage.aityx.ai` is its website): the
   root `.env` has staging's key and that address, which every demo's
   local run reads (the index server's proxy, HealthHub, datyx, Poker
   Tour, the model tests); datyx's compose now falls back to
   `AITYX_URL`. New `AITYX_PROD_URL` (`https://api.aityx.ai`) and
   `AITYX_PROD_API_KEY`, read only by deploys: Poker Tour's `deploy.sh`
   gives the stack production's address (refusing a staging one) and
   writes production's key to `pokertour/aityx.key`, and staging's to a
   new local key object, `pokertour/aityx-local.key`, which a laptop's
   players fetch. The published builds carry no key or address and
   default to production. The players' role trusts the account's IAM
   OIDC provider for Google when there is one (`GooglePrincipal`), which
   took over from the built-in identity and caused the sign-in's
   `InvalidIdentityToken`. See [On AWS](aws.md).

3. **Google sign-in is not configured for this project yet: create the
   project in Google, download and store the credentials safely, and
   keep them out of Git, Docker and anything else, in their ignore
   files.** The sign-in popup answered `origin_mismatch`: the client in
   the shared `.env` was HealthHub's, in its own project. New Google
   Cloud project `aletyxcode-pokertour` (aletyx.com organization) with
   an *Internal* consent screen, "Poker Tour", and the web client
   `pokertour-web` (origins: the CloudFront address and
   `http://localhost:9810`). Its JSON is in
   `PokerTour/.secrets/google-oauth-client.json` (mode 600); the root
   `.gitignore` ignores `.secrets/` and `client_secret*.json`, and
   `sync-dockerignore.sh` carried both into every `.dockerignore`. The
   new `POKERTOUR_OIDC_CLIENT_ID` (scripts/env.sh, process-compose,
   compose, deploy.sh) wins over the shared `OIDC_CLIENT_ID`, so
   HealthHub keeps its client. The Lambda Dockerfile moved to
   `docker/lambda.Dockerfile`, the repository's place for a Dockerfile
   that builds from its parent folder. Redeployed: `GET /api/config`
   and the players' role trust the new client. See [On AWS](aws.md) and
   [The tour](tour.md).

2. **Refactor this to run serverlessly, starting with on-demand: a
   button on the leaderboard, for admins only (accounts in aletyx.ai or
   aletyx.com), and four times a day, every six hours, from the most
   adequate AWS serverless service; deploy it to my AWS account to test;
   make sure Google sign-in works.** The runner plays one tournament
   per call instead of round the clock, within a deadline (fourteen
   minutes, a Lambda function's), and reports to the store
   (`live.json`); the leaderboard and its state live in a store (a
   folder, or S3 with conditional writes, `pokertour_api/lib/store.dart`),
   so two processes share them. New `POST /api/tournaments` (an
   admin's, `POKERTOUR_ADMIN_DOMAINS`, the playing domains by default)
   and **Play a tournament now** on the leaderboard, with the next
   scheduled time shown; `GET /api/me` says `admin`. The schedule,
   `POKERTOUR_SCHEDULE_HOURS` (`0,6,12,18` UTC), replaces
   `POKERTOUR_PAUSE_S`: a timer in the server, an EventBridge schedule
   on AWS. The signer moved to the shared package `aws_lite`, which the
   server also uses to call S3 and Lambda. `pokertour_api/bin/lambda.dart`
   is a Lambda custom runtime serving the API (a function URL behind
   CloudFront at `/api/`) and the runner (one tournament per
   invocation); `deploy/template.yaml` and `deploy/deploy.sh` build
   (Docker) and deploy the stack: S3 and CloudFront for the app, the
   two functions, the data bucket with the key object and the players'
   role, the schedule. See [On AWS](aws.md), [The tour](tour.md) and
   [Development environment](dev-environment.md).

## 2026-11-06

1. **Copy the PokerFace demo to a new demo, Poker Tour. The host sets
   the key and every player plays with it; players must sign in with
   Google, and for now only aletyx.com and aletyx.ai accounts; store
   the key safely on S3, so it can be fetched without serving an API
   (the key is static); besides the simple strategies, let the user
   download them or upload their own to the leaderboard; the
   leaderboard runs the game continuously and updates server-side, a
   simple container; in the datyx group, not aityx.** Added `PokerTour/`
   (group `datyx`, port 9810, [Development environment](dev-environment.md)):
   the app copied from PokerFace with its engine and table logic moved
   to the pure-Dart `poker_core` package, shared with a new Dart server,
   `pokertour_api`, one container that serves the app, the API and the
   leaderboard. Before the table, a welcome page with Google's sign-in
   and the leaderboard; only the allowed domains get through, checked by
   the app and the server. The key is the host's S3 object: the app
   asks STS for temporary credentials with the user's Google token
   (`AssumeRoleWithWebIdentity`) and fetches the object with a presigned
   GET signed in Dart, no API of ours in between; the key stays in
   memory and the table calls aityx with it ([The tour](tour.md),
   [Deciding on aityx](aityx.md)). Every strategy can be downloaded as
   JSON; a strategy of yours can be entered in the tour from the editor,
   the players panel or an upload on the leaderboard, checked on aityx
   first ([Players and strategies](players.md)). The server plays up to
   nine strategies a tournament, round the clock, on the host's key,
   scores the places, keeps `data/leaderboard.json`, and answers the
   standings, the tournament being played and the latest results, which
   the app shows and refreshes. A card on the datyx index, the port in
   the datyx dev container, and the README.

## 2026-10-23

1. **Another sample, a poker simulator much like PokerStars or online
   poker, but with the player rules defined by aityx. As in the others,
   show the requests and responses in a sidebar, let the user accelerate
   or slow the game, and add players with different strategies defined
   as rules. Call it Poker Tour.** Added `Poker Tour/`, built like Contact
   Hub and Life Hub: a Flutter app (`pokertour_app`, web, Android, iOS
   and Linux) and a Dart API (`pokertour_api`), devbox, process-compose
   and the health monitor, the Makefile, Docker Compose, and the dev
   container in `.devcontainer/Poker Tour/`, on ports 8910 and 8911 (see
   [Development environment](dev-environment.md)). The app plays no-limit
   Texas hold'em for up to nine players, with blinds, betting rounds,
   side pots, showdowns and rebuys, and shows it on a felt with everyone's
   cards face up ([The table](table.md)). Every decision is one aityx
   call: the app computes the player's situation (cards, hand class, made
   hand, draws, equity by Monte Carlo, pot, pot odds, position, players
   to act, a random number) and the API runs the player's strategy on it
   ([Strategies](strategies.md), the API, since replaced by [Deciding on aityx](aityx.md)). Five preset strategies,
   each a file of rules with a `why` per row: the Rock, the Maniac, the
   Calling Station, the Mathematician and the Shark, verified on aityx by
   `scripts/model-test.sh`. The sidebar lists every call with the
   situation, the action, the rule that fired and its reason, and opens
   the full request and response with the key parts marked, in the same
   viewer as Contact Hub's; a second tab holds the hand log ([The aityx
   calls](calls.md)). Play, pause and step, a pace slider from 4 s
   between steps down to full speed, rebuys and reset. The players panel
   adds players by name and strategy, changes a player's strategy, removes
   players, shows every strategy's rules, and has an editor to write a
   strategy of your own from a preset, with **Try it on aityx** ([Players
   and strategies](players.md)). The [theme](theme.md) is the aityx
   palette with a green felt; the [app icon](app-icon.md) an orange ace of
   spades with a chip.

## 2026-10-23 (later)

2. **When a player name is clicked, present its strategy (rules), and
   let users add or remove them.** Tapping a seat, or a name in the
   players panel, opens the player's rules: the action table one rule a
   row with its conditions, action and why, each removable and movable;
   a form to add a rule (conditions on any input or decision, the
   action, the why); the raise expression; **Try it on aityx**; and
   **Remove <name>**. Saving gives the player a strategy of their own,
   "<Name>'s <Strategy>", so presets stay as they are. See [Players and
   strategies](players.md#a-players-rules).
3. **No rebuys; casino tournament rules; show the winner and its
   strategy when the tournament ends.** The table plays a tournament:
   everyone starts with 1000 chips, the blinds go up every 10 hands
   through 14 levels, a player out of chips is out with a place, and
   when one player has every chip a dialog announces the winner, their
   strategy and the standings, with the winner's rules a tap away and
   **New tournament**. The rebuy switch is gone; **Reset** became **New
   tournament**. See [The table](table.md).
4. **Show the chip piles as the game goes, and little avatars, like the
   popular poker sites.** Bets, the pot and each stack are piles of
   chips in casino colors, one column per denomination; each seat has an
   avatar, the strategy's face in a ring of the seat's color, lit while
   deciding, amber when winning, gray when out; the cards fan beside it
   and the name, strategy, stack and last action sit on a plate below.
   See [The table](table.md).
5. **In the hand log, when an event is clicked, expand it to explain why
   it was decided that way: the rule that fired and the game data that
   led to it.** Every action line in the hand log expands into the rule
   that fired with its why, its conditions with the situation's values,
   the whole situation, the strategy's own decisions, and a link to the
   whole call. See [The aityx calls](calls.md#the-hand-log).

## 2026-10-27

6. **Make the demos efficient enough for a 4-core codespace: serve a
   release build instead of running the Flutter dev server, and compile
   the API** (Mortgage Hub's change, ported). `devbox services up` now
   serves the app's release build with a small native web server
   (`pokertour_api/bin/web_server.dart`: `/app/` from `build/web`, `/api/`
   and `/` proxied to the API, as nginx does under Docker Compose) and
   runs the API compiled with `dart compile exe`; both come from
   `scripts/build.sh`, which builds only what changed and runs one Flutter
   web build at a time across the repository. Resident memory drops from
   about 1.2 GB to about 30 MB, and a start after no change takes a
   second. Hot reload stays with `WEB_MODE=debug` or `devbox run web`.
   See [Development environment](dev-environment.md).


## 2026-10-28

7. **Have the demos prebuilt in the dev container image, ready to boot, and
   push it where anyone can launch it.** Every dev container now runs the
   published image `docker.io/aletyxcode/samples-and-demos-devcontainer`
   (public on Docker Hub, since the organization's GHCR packages can't be
   public), built from `image/Containerfile` with Flutter, process-compose
   and every demo's release web build. A codespace restores the build,
   compiles the API in seconds and starts the services on the image's own
   tools (`DEMOS_TOOLCHAIN=image`, no devbox): every demo answers less than
   four minutes after the request, down from more than ten. See
   [Development environment](dev-environment.md) and `image/README.md`.

## 2026-10-29

8. **Separate the dev containers, images and Codespaces configurations by
   demo group.** Poker Tour now opens in the aityx group's dev container,
   **aityx demos** (`.devcontainer/aityx/`), on the group's image
   `docker.io/aletyxcode/samples-and-demos-aityx` (`bash
   image/build-image.sh aityx`), which starts it with the other aityx
   demos and the index page. Its own dev container,
   `.devcontainer/Poker Tour/`, was removed. The start-up log is
   `startup.log` at the repository root. The README's codespace link
   points at the group's container. See [Development
   environment](dev-environment.md).

## 2026-10-30

9. **Add a discreet health check indicator on top right of all demos
   indicating the API key is set and the service is reachable and
   responding, or not, with a tooltip.** A dot over the top right corner
   of every screen, grey while checking, green when aityx accepts the
   key, red otherwise, with the reason in its tooltip
   ([The aityx light](aityx-status.md)). The API answers it on the new
   `GET /api/aityx`, which checks the key against aityx at most once a
   minute (the API, since replaced by [Deciding on aityx](aityx.md)).

## 2026-10-30 (later)

10. **Run the aityx demos entirely in the browser, with no per-demo API:
    the app calls aityx itself, all the demos and the index share one
    origin, and a key the user sets once on the index page is reused by
    every demo.** `pokertour_api` is gone, with `scripts/api.sh`,
    `scripts/flutter-web.sh`, `scripts/health-check.sh`,
    `process-compose.yaml`, `compose.yaml`, `docker/`, `.dockerignore`,
    `.env.example`, `web_dev_config.yaml` and the `web` and `api` devbox
    scripts. Its table logic (the checks, the body sent to aityx, the
    action read back) is in the app, `lib/aityx/table.dart`, and the
    models are the app's assets (`assets/models/`). `AityxPokerApi`
    implements the app's `PokerApi` on `AityxClient` from the new shared
    package `packages/aityx_web`: the user's key from the index page,
    else the index server's dev key through its proxy, else "aityx is
    not set up: set your key on the index page". The API's checks and
    error wording are kept, with "aityx rejected the key" and "aityx did
    not answer" for a bad key and no answer; the calls sidebar shows the
    body the app sent, never the headers. The aityx light is the shared
    package's ([The aityx light](aityx-status.md)). The API's tests are
    ported (the table logic verbatim, the call against a MockClient, the
    scenarios on aityx still tagged `aityx`, run by
    `scripts/model-test.sh` with the root `.env`). `scripts/build.sh`
    builds only the web app, `--base-href /pokertour/
    --no-web-resources-cdn`, which the index server serves at
    `/pokertour/`. See [Deciding on aityx](aityx.md) and [Development
    environment](dev-environment.md).

11. **Don't say where the key comes from; check that it works against the
    URL and say that.** The status light's tooltip now reads `aityx: ready — the key works with
    <url>` for any key, the user's or the index server's dev key, and a
    dev key aityx refuses reads `aityx answered HTTP n`; neither names
    `.env` or the environment any more. The index page's key section does
    the same.

## 2026-11-03

12. **Separate the demos in games and apps on the index page, then serve
    the index page under /demos and each demo under its own path, such
    as /demos/riverrace, so the demos can be embedded, hidden, in the
    aityx website.** The index page moved from `/` to `/demos/` and
    lists Poker Tour under "Games"; the app moved from `/pokertour/` to
    `/demos/pokertour/`: `scripts/build.sh`, `scripts/make.sh` and the
    Makefile build it with `--base-href /demos/pokertour/`, and the
    index server serves it there (http://localhost:8800/demos/pokertour/
    locally). The aityx light's tap opens the index page's key section
    at `/demos/#aityx-key`, and the dev proxy moved to
    `/demos/aityx/config` and `/demos/aityx/v1/systemone`, both through
    `packages/aityx_web`. The dev-proxy test expects the new origin and
    proxy URL. The same prefix locally and on the website keeps one
    build. See [Deciding on aityx](aityx.md) and [Development
    environment](dev-environment.md).

13. **Remove what sits beside the title in the app bar, so the title
    stands alone, and before play show in the calls panel what the demo
    is and what aityx does in it; after play, show the calls as they
    are.** Poker Tour had no counter beside its title, only the tagline
    "every player is a set of rules, run on aityx": the tagline went,
    and the app bar says **Poker Tour** alone beside its icon (the
    version and the sidebar button stay on the right). The calls panel's
    empty state, one sentence before, became two paragraphs, in the same
    muted centered style, that scroll when the panel is short: the demo
    (no-limit hold'em at a table of up to nine, every player a set of
    rules run by aityx, five strategies or your own, the pace in your
    hands) and what aityx does (at each turn one call runs the player's
    strategy on their situation and answers the action, the amount and
    the rule; the calls show here as they happen). The entries, once
    calls arrive, are as they were. See [The table](table.md) and [The
    aityx calls](calls.md).

## 2026-11-08

14. **In the profile view, no "Empty: <name>" on the alias field: the
    name as its default, or what the player saves; a single button to
    save the profile, not one for the name and another for the key.**
    The alias field starts with the player's name (their alias once
    they have one), with no helper line; saving their own name, or an
    empty field, keeps no alias. Its **Save** and the key's **Save key**
    became one **Save profile**, which saves the name when it changed
    and the key when one is typed (or its URL changed), with one
    message for both; **Forget my key** stays. The profile tests use
    the one button. See [The sidebar and the profile](profile.md).

15. **Only admins (aletyx.com or aletyx.ai accounts) can play a
    tournament now; tournaments also on the schedule (every six hours)
    and every time a player uploads a new strategy. A tournament asked
    for while one is being played waits for it to end: never two in
    parallel, a queue, controlled in DynamoDB.** The admins are the
    `aletyx.com` and `aletyx.ai` accounts, fixed: `POKERTOUR_ADMIN_DOMAINS`
    and the template's `AdminDomains` are gone, and an account a wider
    `POKERTOUR_ALLOWED_DOMAINS` lets play is no admin. Every tournament
    asked for (the schedule's, an admin's, a new strategy's) is queued in
    the tour's table (`pk` `QUEUE`, one waiting per source) and played in
    turn by whoever holds the runner's lock (`pk` `RUNNER`, a conditional
    write that lapses after sixteen minutes): the laptop's server, or
    the runner function, which plays one per invocation and invokes
    itself while more wait. `POST /api/strategies` asks for one and says
    what asking did (`tournament`); `POST /api/tournaments` answers
    `started`, `queued` or `waiting` instead of `running`; the
    leaderboard's runner has the `queue`, which the app's line shows,
    and an admin's button stays enabled while a tournament plays. Tests:
    the queue and the lock in memory and on Floci's DynamoDB, the routes,
    the app's reading. See [The tour](tour.md#the-runner) and [On
    AWS](aws.md).

16. **Make sure all cloud resources are tagged according to their
    project, with the same tags standard as the account's other
    resources.** The account tags every resource `project=<name>` and
    `tenancy=GA|RC|shared`; Poker Tour's had none. `deploy.sh` now
    deploys the stack with `--tags project=pokertour
    tenancy=$POKERTOUR_TENANCY` (default `GA`), which CloudFormation
    passes to the stack's resources, and tags the code bucket on every
    run. The live stack and code bucket were tagged the same way. See
    [On AWS](aws.md#tags).

17. **The poker music is too bad: make it more lo-fi jazz, minimal;
    regenerate all tracks.** `scripts/jazz.dart` was rewritten and the
    five tracks made again: instead of a lounge trio playing forms with
    heads and solos, each track is one four-bar loop of extended chords
    on a mellow electric piano, a sub bass, a sparse pentatonic motif
    (nylon guitar, vibraphone or high keys) in the theme sections
    only, lazy boom-bap drums crushed to ten bits, a drumless break,
    and tape wobble with vinyl hiss and crackle over it all; 70 to 84
    BPM, new titles. The player, the controls and the file names are
    unchanged. See [Music](music.md).

## 2026-11-09

18. **Run every demo on a local Kubernetes cluster (kind), deployed, up
    and working.** Poker Tour runs on the repository's kind cluster
    (the root's `k8s/`, context `kind-aityx-demos`) in the multyx
    namespace, at http://localhost:19810/pokertour/: the server as the
    Deployment `pokertour` (the Dockerfile's image, as compose.yaml
    builds it), the tour in Floci as the StatefulSet `pokertour-floci`
    with a volume and the same init hook, from a ConfigMap that
    [floci/kustomization.yaml](../floci/kustomization.yaml) makes of
    `floci/init/ready.d/`. [k8s/](../k8s) holds the manifests,
    `build.sh` and `verify.sh`, which checks the app, the API, the tour
    in Floci, the sign-in gates and the relay from the host, and with
    `TOURNAMENT=1` plays a tournament. The `pokertour-web` client lists
    http://localhost:19810 among its origins, so the Google sign-in
    works on the cluster too. Local runs are unchanged. See
    [Development environment](dev-environment.md).
19. **Let users upload and download their own strategies, but not
    download or delete each other's; the calls panel may still show
    them, just don't make them easy to copy.** Another player's entry
    is sealed at the table: it plays, but tapping its seat says whose it
    is instead of opening its rules, and the players panel has a lock
    for it instead of **Edit**, with no download or delete. The
    leaderboard's **Download as JSON** is for the presets and the
    player's own entries alone. Withdrawing was the owner's alone
    already. `GET /api/strategies` still answers every entry's rules,
    since the table plays them in the player's browser
    ([Players and strategies](players.md#strategies), [The
    tour](tour.md)). The players panel's strategy dropdown ellipsizes a
    long name instead of overflowing.
