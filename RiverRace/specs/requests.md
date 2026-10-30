# Requests

The requests that shaped RiverRace, oldest first, each with what changed.
The feature files hold the current specification; see the
[index](README.md).

## 2026-10-28

1. **Build a new aityx demo with Cellfie's structure, other ports and
   content: a remake of the Atari 2600 River Raid, as in the original, but
   with two planes on screen at once, in different colors, each flying by
   a different strategy (a set of rules), to see which strategy wins; the
   user explores each plane's strategy, adding and removing rules, and a
   sidebar shows every event sent to and received from aityx.** Added
   `RiverRace/` (group `aityx`, ports 8940 and 8941), copied from Cellfie's
   scaffolding (scripts, process-compose, Docker Compose, dev container,
   Makefile, the calls panel's JSON view): the [game](game.md) in the app,
   the [strategies](strategies.md) with their pilot cards and rule editor,
   the [decisions](decisions.md) asked of aityx through the
   [API](api.md)'s `POST /api/decide`, and the [calls panel](calls-panel.md).
   Named RiverRace, not after the original. Added to the Index page, the
   root README, the default dev container's ports and the aityx group's
   scripts.
2. **Make it three planes: two automated with different strategies, and
   one the user flies; the user's plane opaque, the computer ones more
   transparent.** The yellow plane is the player's (arrow keys and space),
   drawn solid; the aityx pilots' cyan and magenta planes are drawn at
   half opacity. **You fly** lets the two aityx pilots race alone. Since a
   person plays in real time, the game doesn't wait for aityx unless
   **Fair race** is on (see [Decisions](decisions.md)).
3. **Make the GIF, and add RiverRace to the Index page, the Dockerfile
   and the blog post.** Recorded `riverrace.gif` for the aityx launch post
   in the docs repo, and added RiverRace to it beside the other demos. The
   Index page already had its card. Docker Compose (`docker compose up
   --build`) was run: both images build and answer; the published dev
   container image carries RiverRace's web build once its app is
   committed, as it does every demo's, with no change to the
   `Containerfile`.
4. **Wait for a keypress to start.** Any key starts the race, goes on
   after a pause, or starts another race once one is over (see
   [Game](game.md#playing)).
5. **Make the computer planes a little more transparent.** The aityx
   pilots' planes are drawn at 35% opacity, down from half.
6. **Don't say how many planes on the start screen, just "Press any key
   to play", and make that work: there are two or three planes depending
   on whether the user plays.** The start screen says only *Press any key
   to play*. The game's keys are read app-wide, so a key plays even when
   a control just clicked has the focus (space used to toggle it); not
   while a dialog or menu is open. Recorded the GIF again for the blog
   post.
7. **Fix the review's findings on the pull request.** The API refuses a
   call from another site's page (403) and a body that isn't JSON (415)
   before it calls aityx, so no website can spend the key; the app's own
   calls, same-origin through the proxy, still go through (see
   [API](api.md)). The player's keys are read as held every frame and
   count only while no dialog is open (see [Game](game.md#playing)). A
   decision that arrives after its plane was lost is dropped (see
   [Decisions](decisions.md)). A native app without `API_BASE_URL` calls
   `http://localhost:8941` instead of a `file:` address. The Android
   finding (the Kotlin plugin not applied) didn't reproduce: Flutter's
   template builds, `MainActivity` included, so the Gradle files stay as
   Flutter generates them.

## 2026-10-29

8. **Separate the dev containers, images and Codespaces configurations by
   demo group.** RiverRace now opens in the aityx group's dev container,
   **aityx demos** (`.devcontainer/aityx/`), on the group's image
   `docker.io/aletyxcode/samples-and-demos-aityx` (`bash
   image/build-image.sh aityx`), which starts it with the other aityx
   demos and the index page. Its own dev container,
   `.devcontainer/RiverRace/`, was removed. The start-up log is
   `startup.log` at the repository root. The README's codespace link
   points at the group's container. See [Development
   environment](dev-environment.md).
9. **Make the computer planes a little more transparent, and the default
   speed a bit slower.** The aityx pilots' planes are drawn at 25% opacity,
   down from 35% (see [Theme](theme.md)). **Speed** gains a ¾× choice,
   which the game starts at, instead of 1× (see [Game](game.md#playing)).
10. **Start even slower, and speed up a little every 30 seconds.** The
    game starts at ½×; every 30 seconds of play it speeds up by 10
    percent, up to 1×, showing how fast it runs beside **Speed**, which
    is now the starting speed (see [Game](game.md#playing)).
11. **Slow down a little over the fuel strip, as in River Raid; a retro
    recharging beep over it and a retro explosion when enemies are hit;
    double the lives, since a plane sometimes doesn't come back after a
    crash; then, slow down clearly while over the strip.** A plane over
    a depot drops at once to half its throttle's speed and holds it (a
    first try, easing to 70%, was hardly visible). A
    **Sound** chip (on) plays a square-wave beep while refueling, rising
    with the tank, and a noise burst when a missile hits something,
    made with Web Audio (see [Game](game.md#playing)). Planes start with
    eight lives, up from four. The plane that didn't come back: it did,
    but now and then (1 respawn in 18) at a spot it couldn't fly out of,
    an island or the bank just ahead, and was lost again within a few
    frames; it now comes back where it can fly straight on for 40 rows
    (see [Game](game.md#the-planes)). The aityx pilots' planes are 25%
    opaque in the planes section too, as in [Theme](theme.md).
12. **Save space in the top row, so the game shows better: the title on
    the left and all the buttons on the right; no Finish at selector,
    bridge 10 is enough.** The controls moved into the top bar, right of
    the title and the status; Restart and New river are icons. The race
    always ends at bridge 10 (see [Game](game.md#playing)).
14. **Make the current speed 1× and the others relative to it; remove
    aityx decides every, using the rate that suits the game speed; remove
    Fair race.** **Speed** reads ½×, 1× (the default, the pace that was
    ½×), 1½× and 2× (the old 1×, the game's top speed); the speed-up goes
    by 0.2× up to 2×. aityx is asked about every 0.2 s of real time,
    every 6 frames at 1× and proportionally more often in frames as the
    game speeds up. Fair race, which held the game for aityx's answers,
    is gone (see [Game](game.md#playing) and [Decisions](decisions.md)).

## 2026-10-30

15. **Add a discreet health indicator, top right in every demo, saying
    whether the aityx key is set and aityx is reachable and answering,
    with a tooltip.** A small light sits in the top right corner over
    every screen: green when the API has its key and aityx accepts it,
    red when not, grey while it checks, with the reason on hover. The
    [API](api.md) answers it at `GET /api/aityx`, checking aityx at most
    once a minute (see [aityx status](aityx-status.md)).
