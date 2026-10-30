# Requests

The requests that shaped PokerFace, oldest first, each with what changed.
The feature files hold the current specification; see the
[index](README.md).

## 2026-10-23

1. **Another sample, a poker simulator much like PokerStars or online
   poker, but with the player rules defined by aityx. As in the others,
   show the requests and responses in a sidebar, let the user accelerate
   or slow the game, and add players with different strategies defined
   as rules. Call it PokerFace.** Added `PokerFace/`, built like Contact
   Hub and Life Hub: a Flutter app (`pokerface_app`, web, Android, iOS
   and Linux) and a Dart API (`pokerface_api`), devbox, process-compose
   and the health monitor, the Makefile, Docker Compose, and the dev
   container in `.devcontainer/PokerFace/`, on ports 8910 and 8911 (see
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
   (`pokerface_api/bin/web_server.dart`: `/app/` from `build/web`, `/api/`
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
   demo group.** PokerFace now opens in the aityx group's dev container,
   **aityx demos** (`.devcontainer/aityx/`), on the group's image
   `docker.io/aletyxcode/samples-and-demos-aityx` (`bash
   image/build-image.sh aityx`), which starts it with the other aityx
   demos and the index page. Its own dev container,
   `.devcontainer/PokerFace/`, was removed. The start-up log is
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
    every demo.** `pokerface_api` is gone, with `scripts/api.sh`,
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
    builds only the web app, `--base-href /pokerface/
    --no-web-resources-cdn`, which the index server serves at
    `/pokerface/`. See [Deciding on aityx](aityx.md) and [Development
    environment](dev-environment.md).
