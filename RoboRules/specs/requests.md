# Requests

The requests that shaped RoboRules, oldest first, each with what changed.

## 2026-10-23

1. **Make a clone of the old Robocode where each robot's behavior is
   defined by rules; populate it with random robots to begin with;
   selecting a robot lets you change its rules; see which rules win the
   match; the number of robots configurable, two by default; make it look
   as much as possible like Robocode, but on the web. Robot behavior in
   aityx format and the game run by aityx, including motion and
   collisions if possible, no problem if it runs slow, with a control to
   make it slower or faster. Make sure the ports don't clash, so all the
   demos can run at once.** Added RoboRules: a Flutter web app in
   Robocode's Swing look and a Dart API. Each robot is an aityx model (its
   sensors as inputs, a FIRST table of commands), random to begin with,
   editable as cards or JSON. The battle is one aityx model
   ([The battle](battle.md)): sensing, every robot's rules, Robocode's
   motion, bullets, collisions, damage and deaths, played up to 50 turns a
   call; the score is another ([Scoring](scoring.md)). A Speed control
   from 1 to 60 turns a second, or as fast as aityx plays them. Ports
   8920/8921: Life Hub and Poker Hub in this folder already use 8900/8901
   and 8910/8911.
2. **Fix what the code review found.** A battle started after a finished
   one now plays (the round-end flag is cleared on reset); a reply still
   in flight when a battle is restarted or stopped is dropped, not applied
   to the new one; a round aityx fails to score waits with **Retry
   scoring** instead of being left out of the totals; the editor's JSON is
   checked as the battle checks robots, with an error instead of a crash;
   `make` builds only the web app, the only platform.

3. **Use custom favicons for each sample, in the same style and colors
   as aityx but related to each demo.** RoboRules had Flutter's default
   icons. It now has a tank seen from above: `web/favicon.svg`, a flat
   orange glyph with no background as aityx.ai's own favicon is drawn,
   first in `index.html`; and the tile, orange on the dark background,
   rendered from `assets/icon/icon.svg` as `favicon.png` and the
   manifest's icons. See [App icon](app-icon.md).

4. **Let the user add or remove bots, picking from the predefined ones,
   and customize them.** Added the [predefined robots](robots.md#predefined-robots):
   Robocode's sample robots (SittingDuck, Fire, SpinBot, Walls, Tracker,
   RamFire, TrackFire, MyFirstRobot, Crazy) written as rules, plus a random
   one. **New Battle** is now Robocode's: available robots on the left,
   selected on the right, Add, Remove, Remove all and Edit rules… between,
   what the highlighted robot does below; it opens with the battle's
   current robots, so customizations survive. Between battles the robots
   panel has an **×** on each robot and **Add robot…** (a picker), and the
   Robot menu Add a robot… and Remove …; the editor's **Rules from…**
   replaces a robot's rules with a predefined robot's or random ones. Two
   to ten robots; a second robot of a kind is "Walls 2" in another color.
5. **Add a view of all events, not only the last one; it can be below the
   robots' cards.** Added the **Events** log under the robots: every rule
   change, hit, loss, round start, end and score, the winner, failures,
   and every aityx call, the last ten of which open in the viewer from
   their line ([The window](window.md)).
6. **Do not use "dead"; better use "lost".** A robot out of the round is
   "lost" everywhere the app says it.

## 2026-10-27

7. **Make the demos efficient enough for a 4-core codespace: serve a
   release build instead of running the Flutter dev server, and compile
   the API.** `devbox services up` now serves the app's release build
   with a small native web server (`roborules_api/bin/web_server.dart`:
   `/app/` from `build/web`, `/api/` and `/` proxied to the API, as nginx
   does under Docker Compose) and runs the API compiled with `dart
   compile exe`, which finds `models/` beside its binary as in the Docker
   image; both come from `scripts/build.sh`, which builds only what
   changed and runs one Flutter web build at a time across the
   repository. Resident memory drops from about 1 GB to about 27 MB, and a
   start after no change takes a second. Hot reload stays with
   `WEB_MODE=debug` or `devbox run web`. See
   [Development environment](dev-environment.md).

## 2026-10-28

8. **Have the demos prebuilt in the dev container image, ready to boot, and
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

9. **Separate the dev containers, images and Codespaces configurations by
   demo group.** RoboRules now opens in the aityx group's dev container,
   **aityx demos** (`.devcontainer/aityx/`), on the group's image
   `docker.io/aletyxcode/samples-and-demos-aityx` (`bash
   image/build-image.sh aityx`), which starts it with the other aityx
   demos and the index page. Its own dev container,
   `.devcontainer/RoboRules/`, was removed. The start-up log is
   `startup.log` at the repository root. The README's codespace link
   points at the group's container. See [Development
   environment](dev-environment.md).

## 2026-10-30

10. **Add a discreet health indicator, top right in every demo, saying
    whether the aityx key is set and aityx is reachable and answering,
    with a tooltip.** The API answers `GET /api/aityx` with whether it has
    a key and whether aityx accepts it (an empty `/v1/systemone` call,
    kept for a minute; a redirect, such as a login in front of
    `AITYX_URL`, is reported as such), and the app shows it as a small
    grey, green or red dot over the top right of the window, with why in
    its tooltip. See [The window](window.md).

11. **Make the robots' line of sight visible, as Robocode draws its radar
    beams, and add a vintage explosion effect when they are done.** Each
    gun now casts a translucent cone in its robot's color, 10° either side
    of it, the arc `enemy_in_sight` checks, brighter while the nearest
    enemy is in it. A robot lost blows up in an arcade-sprite style, with
    stepped frames, a flash, a ragged fireball, square sparks, a shock ring
    and smoke, over 1.6 seconds, and leaves a scorch mark for the rest of
    the round; hits get a small burst in the same style. See [The
    window](window.md).

12. **Run the aityx demos entirely in the browser: no per-demo API, the
    Flutter app calls aityx itself, and the index and all six demos share
    one origin, so a key the user sets once on the index page is reused by
    every demo.** RoboRules' API (`roborules_api/`) is gone. The battle's
    model is built in the app ([lib/aityx/battle.dart](../roborules_app/lib/aityx/battle.dart),
    moved from the API with its tests), the world and scoring models are
    the app's assets (`assets/models/`), and `AityxBattleApi` sends each
    batch of turns and each round's score to aityx's `/v1/systemone` on
    the shared [aityx_web](../../packages/aityx_web) package, keeping the
    robot checks, the call in the viewer (its body, never the key) and the
    errors, now "aityx is not set up: set your key on the index page",
    "aityx rejected the key", "aityx did not answer" and "aityx answered
    HTTP n: …". The key is the user's, saved on the index page, else the
    index server's dev key from `.env` through its `/aityx/` proxy. The
    light is aityx_web's: it checks aityx from the browser at start, when
    the key changes and on focus (at most every 30 s), and a tap opens the
    index page's key section. The index server serves the app at
    `/roborules/` (ports 8920 and 8921 are gone); `scripts/build.sh` builds
    only the web app, with `--base-href /roborules/ --no-web-resources-cdn`.
    The API, its web server, Docker Compose, `docker/`, `process-compose.yaml`
    and `scripts/api.sh`, `flutter-web.sh` and `health-check.sh` were
    removed; `scripts/model-test.sh` runs the app's tests tagged `aityx`.
    See [Development environment](dev-environment.md), [The
    battle](battle.md#the-call) and [The window](window.md).

13. **Don't say where the key comes from; check that it works against the
    URL and say that.** The status light's tooltip now reads `aityx: ready — the key works with
    <url>` for any key, the user's or the index server's dev key, and a
    dev key aityx refuses reads `aityx answered HTTP n`; neither names
    `.env` or the environment any more. The index page's key section does
    the same.

## 2026-11-01

14. **Let the events in the event log be clickable and present them just
    like the last-call button.** Every line of the event log now opens the
    dialog the **aityx call** button opens (the same function, the same
    viewer), with the line on top and the aityx call behind it. Each event
    keeps that call: a turn's rule switches, hits and losses the call that
    played the turn (each buffered turn now remembers its call), a round's
    end the call of its last turn, the battle's end the last round's
    score, and a call's own line its call. The app's own lines (the battle
    and rounds starting, rule changes, failed calls) open the same dialog,
    saying no aityx call is behind them. Lines have a pointer and a
    tooltip naming their call; a call's own line stays a link while kept.
    See [The window](window.md).
15. **Add more, and more complicated, strategies, and funnier ones; make
    the default battle three robots; make the default speed a little
    faster.** Nine new robots to pick (see [Robots](robots.md#predefined-robots)):
    Orbiter, Sniper, Vulture and Berserker, with seven to ten rules each,
    and Matador, Chicken, Tipsy, Pacifist and BumperCar, for fun. Each was
    tried in three-robot battles on aityx, checking its rules fire and
    tuning those that trapped it against a wall. The app starts with three
    random robots, and plays 20 turns a second, from 15; the Options menu
    offers 2, 5, 10, 20 and 30 turns a second, and Max.
16. **Make a little noise when collisions happen, and explosions; let the
    user turn it off.** The battle plays short, quiet sounds made in the
    browser with Web Audio (`lib/sound/`, as RiverRace does): a soft thud
    when a robot runs into a wall or rams another, a small pop when a
    bullet hits, a bigger boom when a robot is lost. The controller reads
    them from the frames as it shows each turn, where it makes the
    explosions, at most one of each kind every 100 ms. Sound is on by
    default; **Options › Sound** and a **Sound on/off** button in the
    controls turn it off and on, and the browser remembers the choice.
    Silent outside a browser and in tests (see [The window](window.md)).
17. **When a round ends, announce the winner.** Once aityx has scored a
    round, the battlefield shows its winner for 3 seconds (from a 1.5 s
    pause) before the next round: a trophy and "Name wins round n!" in the
    winner's color, with its points; after the last round it stays until
    a new battle. The log says "Name wins round n, with p points" (see
    [The window](window.md)).
18. **Make the event log's lines alternate between white and light gray,
    so each event is clear.** Zebra stripes, by each line's place in the
    log, so a line keeps its shade as more arrive; lines are a little
    taller (see [The window](window.md)).
19. **Let a user download or upload robots.** A robot downloads as its
    aityx model with its color (`Name.robot.json`), from **Robot ›
    Download …** or the rules editor's JSON tab; **Robot › Download all
    robots** saves the battle's robots as one file. **Robot › Upload
    robots…** and **Upload robots…** under the robots add robots from one
    or more such files between battles, checked as the rules editor checks
    them, named and colored apart, up to ten; a dialog says what was left
    out and why (see [Robots](robots.md#robot-files)).
20. **No need for the long Robot menu; download, edit and remove on each
    robot's rules are enough.** The Robot menu keeps Add a robot…, Upload
    robots… and Download all robots; each robot's Edit, Download and
    Remove items are gone from it. A robot's rules (opened by selecting
    it) have **Download** (moved from the JSON tab, for either tab) and,
    between battles, **Remove** (see [Robots](robots.md#the-rules-editor)).
21. **Highlight in a red tone an event that is a fire shot.** Every shot is
    now its own line in the event log, "Turn n · Name fires a shot of
    power p" (from the turn's `fired`, after the robot's rule switch that
    turn), on a light red background with dark red text; the other lines
    keep their stripes (see [The window](window.md)).
22. **Make the simulation start slower and accelerate periodically.**
    Playback starts at 10 turns a second, from 20, and every 15 seconds of
    play (counted in the battle's 16 ms ticks while it runs, so pauses
    don't count) speeds up by 5 turns a second, up to 40, about what aityx
    plays three robots at; *now n* beside the speed says how fast it runs.
    Choosing a speed, or starting a battle, starts again from the choice;
    Max stays Max (see [The window](window.md)).
23. **Make the aityx call's return time a separate widget, always at the
    bottom: in the log it looked like an event.** The "aityx played …" and
    "aityx scored …" lines are gone from the event log; **Last aityx
    call**, below it, shows the latest call, how long aityx took, and a
    round's scores, and opens the call. Each call keeps how long it took
    and its scores (see [The window](window.md)).

## 2026-11-03

24. **Separate the demos in games and apps on the index page, then serve
    the index page under /demos and each demo under its own path, such
    as /demos/riverrace, so the demos can be embedded, hidden, in the
    aityx website.** RoboRules moved from `/roborules/` to
    `/demos/roborules/`: its release web build is now made with
    `--base-href /demos/roborules/` (`scripts/make.sh`'s default, which
    `scripts/build.sh` sets), and the index server serves it there,
    beside the index page at `/demos/` (the root redirects to it),
    where the page lists RoboRules under **Games**. The light's tap opens
    the key section at `/demos/#aityx-key`, and the dev proxy the app
    asks for the dev key moved to `/demos/aityx/config` and
    `/demos/aityx/v1/systemone` (both in the shared aityx_web package).
    The API test expects the new origin and proxy path. The same prefix
    locally and on the website keeps one build, which also works copied
    to a static host's `/demos/` (see
    [Development environment](dev-environment.md)).

