# Requests

The requests that shaped tatyx, oldest first, each with what changed.
The feature files hold the current specification; see the
[index](README.md).

## 2026-11-07

1. **A game in the style of Kingdom Rush (resource exploration, different
   kinds of characters, a simulation) that can be entirely automated with
   aityx; which engine?** Phaser 4 with TypeScript and Vite, web only (the
   user needs the web alone, and the game needn't be Flutter): the web's
   native 2D engine, with the UI around the canvas as plain DOM; the
   simulation as plain TypeScript with no Phaser in it, so it can run
   headless; the decisions on aityx. Flame (the Flutter engine) was the
   pick only for the repository's uniformity; Godot's web export and
   Defold were weighed and set aside ([The game](game.md)).
2. **Go ahead with Phaser. A separate folder for the game and a separate
   group, tatyx, so neither the aityx nor the datyx group is affected;
   the basics: the scaffolding, the library, an initial screen, the
   descriptors to start the servers; in the style of Idle Horizons: Dawn
   of Heroes. The characters are the five robots of the concept art;
   copy it to the project as reference.** Added `BotRush/` (group
   `tatyx`, port 9710): a Phaser 4 app with three scenes (boot, the
   title with the five bots' roster, and the field with the bots at
   their posts, the lane and the base), the shell around it (the bar,
   the aityx light, the key dialog, the calls panel), the world as data
   in `src/game/`, a plain Node server for the build and the aityx dev
   proxy, scripts, devbox, process-compose, a Makefile and these specs
   ([Screens](screens.md), [The bots](characters.md), [Development
   environment](dev-environment.md)). Added `packages/aityx_js/`, the
   TypeScript twin of aityx_web: the key store, the connection, the
   client, the check, the status light and the key form, with tests
   ([Deciding on aityx](aityx.md)). Added the group: `tatyx-index/` (a
   Node index page on 9700, a card per demo), `start-tatyx.sh` and
   `stop-tatyx.sh`, the tatyx dev container (`.devcontainer/tatyx/`,
   devbox-based, no Flutter), and a line each in `start-all.sh` and the
   dev container's `post-start.sh` so the group's index is found; the
   aityx and datyx groups' files are otherwise untouched. The concept
   art is in `art/reference/`, and the five portraits, downscaled, in
   `botrush_app/public/bots/`. The game's name, BotRush, was a working
   title.
3. **The game's name is tatyx.** Renamed BotRush to tatyx everywhere:
   the folder (`BotRush/` to `tatyx/`, beside `tatyx-index/`, as the
   datyx group has `datyx/` and `datyx-index/`), the app
   (`botrush_app/` to `tatyx_app/`), the server (`botrush_server/` to
   `tatyx_server/`), the settings (`BOTRUSH_PORT` and
   `BOTRUSH_BIND_HOST` to `TATYX_PORT` and `TATYX_BIND_HOST`), the
   build's stamp, the page's title, the title screen, the bar (now
   "tatyx", then "the aityx demos"), the group's index card, the scripts'
   comments and these specs. The port stays 9710 and the group `tatyx`.
4. **The game map: the goal is to hack into the mainframe, in the
   middle of the map; each team on a sector of the map, in a triangle,
   with a colour tag of its own, orange being only for the computer's
   bots; the map in the style of Tron and other tech references;
   synthwave in the visuals and the soundtrack; each player with a
   database, its base, where it collects bytes from the data sources it
   finds around the map, to hack the mainframe with. The map, the
   visuals and the bare scheme of the game first; the mechanics and the
   aityx calls later.** The field became the map ([The game](game.md),
   [Screens](screens.md)): a neon grid on black, three 120° sectors
   tinted cyan, magenta and lime with a database each on an ellipse
   around the centre, the mainframe as an orange hexagonal core with
   turning rings, nine data sources scattered by a seeded generator,
   fifteen bots (every team fields the five) over rings in their team's
   colour, three orange sentinels circling the mainframe, a HUD with
   each team's bytes and progress, a legend of the tags, scanlines. The
   title got the synthwave backdrop (stars, a banded sun, a neon
   horizon, the grid to the vanishing point). The world module holds
   the scheme ([world.ts](../tatyx_app/src/game/world.ts): Mainframe,
   Database, DataSource, BotState with a team, Sentinel) and
   [teams.ts](../tatyx_app/src/game/teams.ts) the teams and tags, with
   tests that no team is orange. A synthwave loop synthesized with Web
   Audio plays from **Play**, with a **music** button in the bar
   ([Sound](sound.md)). The lane, the waves and the bricks are gone.
5. **Make the volume controllable, and by default a little quieter.** A
   volume slider in the bar beside the music button, 0 to 100%, kept in
   localStorage (`tatyx.volume`), starting at 50%; the loop's master
   gain is 0.28 at full volume, so the default (0.14) is quieter than
   before (0.22) ([Sound](sound.md), [Screens](screens.md)).
6. **Have each team's robots reflect the team's colour, instead of the
   reference's orange, generated statically from a static list of
   colours; keep cyan and magenta, change lime.** Lime became green
   (`#39FF7A`); the three colours now live in
   [teams.json](../tatyx_app/src/game/teams.json), which the app reads.
   A tool, [tool/recolor.mjs](../tatyx_app/tool/recolor.mjs) (`npm run
   recolor`, with pngjs), paints the five portraits for each team: the
   art's orange hue band (the panels, the eyes' glow, their shading)
   takes the team's hue and keeps its own saturation and brightness,
   the ivory shells and dark joints untouched, the edges blended; the
   results, `public/bots/<team>/`, are committed. The map shows each
   squad in its team's portraits; the title keeps the orange originals
   and the sentinels stay orange ([The bots](characters.md)).
7. **Make the bytes orange instead of cyan, so they don't read as a
   team's; and when captured, make them turn their owner's colour.** A
   data source now has an owner, none to begin with, and `capture`
   gives it to a team; the map draws a source orange, the computer's,
   until it has an owner, then in the owner's colour, redrawing it when
   its owner or its bytes change ([The game](game.md)).
8. **A darker green; a bigger map; sites grouping the bytes; the goal
   to connect to and exploit each site from home until reaching the
   mainframe, only a few sites being connected to it at the start;
   then hack it, and at 100% hacked the game is won.** Green is now
   `#22D468`, and the recolor tool scales a portrait's brightness down
   a little for a darker tag. The homes' ellipse grew from 420 × 270 to
   480 × 290, with the centre at (640, 400), the sector names moved to
   the far corners and the mainframe's name over it. The scattered
   data sources became nine sites in a network (`buildNetwork`): three
   cores on a circle around the mainframe, on the sector boundaries,
   linked to it; six relays, two per team, linked to the home, to the
   core on their side and to the neighbouring team's relay across the
   boundary; each site a ring around its diamonds, orange until
   exploited. The world module got the scheme as pure functions,
   tested: `connect` (a site linked to something the team holds),
   `exploit` (the site and its bytes become the team's, the bytes go
   home), `canHack` (holding a core), `hack` (512 bytes from 0 to
   100%; at 100%, the winner) and `connectable`; the map draws links
   and sites again whenever they change, in the colours of the teams
   that connected or exploited them, and the winner's name across the
   map ([The game](game.md), [Screens](screens.md)).
5. **The characters: keep the idea of the five roles but name them by
   their letters; after thinking it over, A is the Anchor, I the
   Builder, T the Tester, Y the Combinator, X the Explorer. The game:
   the Explorer runs freely and finds assets, sites (the origin, the
   sites with bytes, the mainframe) and links between them; the others
   follow the links; links rot with time and the Tester renews the ones
   it passes; the Builder grows a site's bytes; the Combinator connects
   existing links into shortcuts; the Anchor keeps a site's bytes from
   being taken by other teams; each team starts with one of each and
   buys one for a megabyte taken from sites; balance later. The key
   part is that decision, run by aityx: each team's strategy for
   creating robots, then the game simulates and shows the winner. No
   sentinels; real bytes, fewer near the origin and more near the
   mainframe; the art captions changed everywhere.** The roster is
   Anchor, Builder, Tester, Combinator and Explorer, in the module, the
   title, the hover hints, the portraits' file names, the READMEs and
   the index card, with captions of the game's own instead of the
   art's ([The bots](characters.md)). The world was rewritten
   ([The game](game.md), [world.ts](../tatyx_app/src/game/world.ts)):
   a hidden graph of nine sites (relays of 1.5 MB near the origins,
   cores of 3 MB near the mainframe) that each team's Explorer finds,
   links with health that rot away in 45 s and that a Tester renews by
   crossing, bots that walk the known links by the shortest way, bytes
   that flow home from a site while a bot stands there and the links
   hold and no other team's Anchor is there, Builders growing sites,
   Combinators making up to three shortcuts, a megabyte buying a bot at
   the origin or going into the hack that Testers spend at the
   mainframe, and a winner at 6 MB; the sentinels are gone. The one
   decision on aityx ([Deciding on aityx](aityx.md)): the team model
   (`models/team.json`, nineteen inputs), three preset strategies as
   decision tables (`strategies/`: the Farmer, the Sprinter, the Swarm,
   one per team), the match (`play.ts`) that asks a team's strategy
   whenever it has a megabyte and applies the answer, the aityx decider
   (`aityx.ts`) shown in the calls panel, and a local decider for the
   tests. The map draws it all each frame and ends with the winner and
   **Play again**. The tests cover each mechanic and play a whole match
   headless.

## 2026-11-08

6. **A pause button, to read the calls; each call a line, the full JSON
   on a click; the simulation's speed configurable; a bigger map with
   smaller sites; the game waiting for Start; and, as Poker Tour, a
   players' key for the game and a leaderboard key for a leaderboard,
   never exposed: Poker Tour's keys copied, staging and production.** The
   bar holds **Start**, **Pause**, **Resume**, **Play again** (Space too)
   and the speed, ½× to 8× ([The game](game.md#playing-a-match)); the map
   opens waiting, with the lineup and **Start**; the board is wider
   (origins on a 540 × 296 oval) with smaller sites and bots; the calls
   are one line each and open a viewer with the request and the answer
   ([Deciding on aityx](aityx.md#the-calls-panel)). Poker Tour's four
   keys were copied to the repository's root `.env` as
   `TATYX_PLAYER_KEY`, `TATYX_LEADERBOARD_KEY`, `TATYX_PROD_PLAYER_KEY`
   and `TATYX_PROD_LEADERBOARD_KEY`, each checked against its aityx; the
   proxy lends the players' key, and the server plays the
   [leaderboard](leaderboard.md) on the other: tournaments of the
   presets, every six hours and on an admin's word, in a runner the
   build bundles for Node.
7. **An Anchor on a site makes it its player's alone; any number of bots
   of any team on a site nobody holds, each at its rate.** The first
   Anchor to arrive holds the site; another team's arriving later holds
   nothing and moves on ([The bots](characters.md#behaviour)).
8. **On the opening screen, a card per team under the robots, each team
   customizing its strategy by downloading or uploading its JSON.** The
   title's team cards, with **◀ ▶** through the presets, **Download** and
   **Upload**, checked, kept in the browser
   ([Deciding on aityx](aityx.md#a-teams-own-strategy)).
9. **As Poker Tour, the sidebar's three panels, the leaderboard, the
   aityx calls and the profile, in that order; the profile by default
   when the player has no key; signed in to play; the Google OpenID
   Connect resources created and kept safely.** The sidebar's tabs
   ([Screens](screens.md)); Google sign-in, verified by the server,
   with a session cookie; the game and the proxy for signed-in players
   only ([Sign-in and keys](players.md)). Created in Google Cloud: the
   project `aletyxcode-tatyx` in aletyx.com, its *Internal* consent
   screen "tatyx" (Google's API Services User Data Policy accepted), and
   the web client `tatyx-web` for `http://localhost:9710` and `:9711`;
   its id is `TATYX_OIDC_CLIENT_ID` in the root `.env`, and its secret,
   which nothing needs, was never downloaded.
10. **The title orange, the subtitle "Build the sites, hack the
    mainframe"; bytes built on sites, not drawn from them, the more
    built the more robots deployed; the Tester's two modes, building on
    a site its Anchor holds and doubling a Builder beside it; the
    Combinator building like a Builder, without the Tester's doubling;
    each robot's name on a line under its letter.** The economy is
    building ([The game](game.md#building-bytes)): Builders, Combinators
    and Testers on held sites build at 48 KB/s, twice on a core, a
    Builder twice again with a Tester; sites never run out; the three
    presets retuned to it. The title and the roster as asked
    ([Screens](screens.md)).
11. **Two more strategies.** The Doubler (a Tester beside every Builder)
    and the Fortress (Anchors first); a tournament is now every trio of
    the five, each turned through the three seats: thirty matches
    ([The leaderboard](leaderboard.md)).
12. **Set the group on Poker Tour and tatyx to a new one, multyx: three
    groups, each with its scripts, ids, builds and dev container: aityx
    for the six demos, datyx for the datyx API, its dashboard and
    HealthHub, multyx for Poker Tour and tatyx.** The tatyx group became
    multyx, shared with Poker Tour: `group.id.txt` says `multyx`;
    `./start-multyx.sh` and `./stop-multyx.sh` replace the tatyx
    scripts; the index, `tatyx-index/` before, is `multyx-index/` on
    9700, with a card for Poker Tour too; the dev container is
    `.devcontainer/multyx/`, on a published image of its own (`bash
    image/build-image.sh multyx`: Flutter and Node 22) instead of a
    devbox-built one, with Docker for Poker Tour's Floci. The game, its
    port (9710) and its build are unchanged ([Development
    environment](dev-environment.md)).
13. **Make sure the player's key, URL and alias are persisted; tatyx
    exactly like Poker Tour in its keys: each player their own, the
    leaderboard a separate key, different for staging and production,
    never exposed to a user.** The server lends no key any more:
    `TATYX_PLAYER_KEY` and `TATYX_PROD_PLAYER_KEY` are gone, and so is
    `/aityx/config`; `/api/config` says where its aityx is and the path
    that relays to it. `/aityx/v1/systemone` became a relay, as Poker
    Tour's: the player's own Authorization header passed on, never one
    of the server's (none: 401), since aityx staging takes no calls from
    browsers. The key stays in the browser with the URL it was saved
    with, production's too; the alias on the server, as before. The
    leaderboard's keys, staging's `TATYX_LEADERBOARD_KEY` and
    production's `TATYX_PROD_LEADERBOARD_KEY`, are each their own and
    never leave the server ([Sign-in and keys](players.md), [Deciding on
    aityx](aityx.md)).
14. **The background hexagonal as well.** The map's grid is hexagonal,
    pointy-top cells as the sites, every fifth cell of every other row
    brighter ([The game](game.md#the-map-on-screen)).
15. **The robots are not showing, green boxes instead.** The game opened
    at `/app` (no slash) asked for the portraits at `/bots/...`, which
    don't exist, and Phaser drew its missing-texture boxes; `/app` now
    redirects to `/app/` ([Development
    environment](dev-environment.md)).
16. **By default, three different strategies, one per team.** The
    default lineup already is (cyan the Farmer, magenta the Sprinter,
    green the Swarm); a lineup set on the title is kept in the browser
    and wins over it.
17. **Remove "the aityx demos" from the title.** Gone from the title
    screen's corner and from the bar beside the name
    ([Screens](screens.md)).
18. **Remove the "In" column from the leaderboard, and the "Win" one;
    the wins as a single number.** The standings show the place, the
    strategy and its wins; the mean progress and the time of the wins
    still break ties ([The leaderboard](leaderboard.md)).
19. **What is the Tester's "works the hack"? Let all robots hack the
    mainframe; the origin with no percentage or bytes, the sites with
    their bytes built, the mainframe with an amount of bytes, shown as
    the hack's percentage, built up to a threshold.** The hack reserve
    is gone: a strategy's `hack` now spends a megabyte to send the
    team's nearest bot (an Explorer last) to the mainframe for good,
    where any bot builds its team's hack, ×3, until one team has built
    6 MB there. The team model's `reserve_mb` became `hackers`, and the
    counts by kind leave the hackers out; the Tester no longer hacks. The
    origins show only their names; the mainframe shows each team's
    percentage in its colour ([The game](game.md#buying-and-hacking),
    [The bots](characters.md), [Deciding on aityx](aityx.md)).
20. **The "HACK THE MAINFRAME" title orange; the synthwave loop longer
    and less repetitive.** The map's HUD title is orange. The eight-bar
    loop became a 48-bar song in sections (intro, verse, verse with a
    lead, chorus, breakdown, chorus up an octave, outro), going round
    from the verse with the arpeggios moved on each time ([Sound](sound.md)).
21. **Each site has a limit to what can be built on it, after which
    building there is useless; sites of varied sizes.** A site builds up
    to its size, all teams together, then is spent: nothing more is
    built there, its bots leave for a site with room, and its label
    says so. The team model has `room_mb`, what is left to build on the
    sites the team knows ([The game](game.md#building-bytes)).
22. **Randomize the position and size of the sites every game.** The map
    is drawn from a seed for every match: where each relay and core sits,
    within its region, and its size (relays 1.5 to 5 MB, cores 5 to 10
    MB), the graph unchanged and no two nodes closer than 100 px; a found
    site is drawn as big as it is. A tournament plays each trio's three
    matches on one map, and a seed replays a match or a tournament
    ([The game](game.md#the-map), [The leaderboard](leaderboard.md)).
23. **In the profile view, no "Empty: <name>" on the alias field: the
    name as its default, or what the player saves; a single button to
    save the profile, not one for the name and another for the key.**
    The alias field starts with the player's name (their alias once
    they have one) and has no hint line under it. Its **Save** and the
    key form's **Check and save** became one **Save profile**, which
    saves the name when it changed and the key when it or its URL
    changed (an unchanged key is not checked again), with one line
    saying what was saved; **Forget** stays. The shared key form
    (`packages/aityx_js`) takes the button's label and the page's own
    fields to save with the key (`submitLabel`, `alsoSave`). Poker
    Tour's Profile got the same ([Sign-in and keys](players.md#profile)).
24. **Only admins (aletyx.com or aletyx.ai accounts) can play a
    tournament now; tournaments also on the schedule (every six hours)
    and every time a player uploads a new strategy, which goes to the
    server and enters the leaderboard. A tournament asked for while one
    is being played waits for it to end: never in parallel, a queue.**
    The admins are the `aletyx.com` and `aletyx.ai` players, fixed:
    `TATYX_ADMIN_DOMAINS` is gone. Uploads go to the server, signed in
    (the title's **Upload**, and **Enter a strategy** in the leaderboard
    tab, with the player's entries and **Withdraw**): `GET`, `POST` and
    `DELETE /api/strategies`, kept in `data/strategies.json`, at most
    `TATYX_MAX_ENTRIES` (3) a player. A tournament's field is five of
    the presets and the entries, the fewest matches played first; the
    standings rank by wins per match played. Every tournament asked for
    (the schedule's, an admin's, a new strategy's) is queued, one
    waiting per source, kept in `leaderboard.json`, and played in turn;
    the admin's cooldown (`TATYX_LEADERBOARD_COOLDOWN_MINUTES`) went with
    it. Poker Tour, which keeps its tour in DynamoDB, queues its
    tournaments there; tatyx, one process with JSON files, in its file.
    Tests: the field and the standings (`test/tour.test.ts`), and the
    queue and the entries on a fake runner
    (`tatyx_server/test/leaderboard.test.mjs`, in `npm test`). See [The
    leaderboard](leaderboard.md) and [Sign-in and keys](players.md).
25. **Change the team colors to this palette: the cyan named "vice
    cyan", #00F0FF; the magenta "neon purple", #BC6CFF; the green
    "miami peach", #FFB86B.** Miami peach falls in the orange band
    reserved for aityx's own pieces (#E36742), so the user chose
    "sunset pink", #FF5CA8, instead. The teams are now Vice Cyan
    (#00F0FF), Neon Purple (#BC6CFF) and Sunset Pink (#FF5CA8), in
    `teams.json`; their ids stay `cyan`, `magenta` and `green`, so
    the tournaments already recorded still count. The portraits were
    painted again (`npm run recolor`), the leaderboard takes the
    seats' colours from the teams' list instead of a copy, and the
    look's neon and sun accents follow the first two colours, so the
    title's sun is purple ([The bots](characters.md#teams-and-tags)).
26. **Four more music loops, synthwave, soft, repeatable, played in a
    random order.** The soundtrack is five songs: Neon Drive, as it was,
    and Night Drive, Palm Shadows, Pastel Horizon and Afterglow,
    slower and quieter, with triangle voices and a light kit. Each
    plays through once, then the next is drawn at random from the
    others (never the same twice in a row) and starts on the next bar
    ([Sound](sound.md#the-soundtrack)).
27. **"The Doubler" dominates and wins all: a bigger board, with more
    sites, more random, and rules that keep any strategy from
    dominating, while keeping the game simple.** Measured headless on
    tournaments of hundreds of matches, with the presets and with
    one-line probe strategies a player could upload ("hack every
    megabyte"), which won 98% of their matches. The map
    is twenty-one sites (three cores and four relays per sector, some
    beyond the origins), placed and sized anew and linked as
    neighbours (the Gabriel graph) every game, one sector drawn and
    turned for the others, the origins on a ring as far from the
    mainframe; the sites smaller (relays 0.5 to 3 MB, cores 2 to 5 MB).
    The rules: links rot in 15 s (not 45), the hack costs 10 MB (not
    6), and an Anchor builds on the site it holds. Now every preset wins
    27% to 40% of its matches, each probe 28% to 44%, every seat a
    third; the ways a team has are searched once per world state, a
    tick twenty times faster ([The game](game.md#balance)).
28. **The tatyx logo at the top goes home, every time.** The logo and
    the name in the bar are a link to the title, from the map (the
    match ends, as with **Title**) and from the title itself
    ([Screens](screens.md#the-shell)).
29. **On the title, a click on the title draws the teams' strategies
    anew, at random, no two the same.** `shuffleLineup` in lineup.ts
    picks three different presets and keeps them, like ◀ ▶ do
    ([Screens](screens.md#the-game)).
30. **Nerf the Anchor a little: it holds a site only for a limited time,
    configurable; recheck the balance.** An Anchor holds the site it
    arrives at for `RULES.holdSeconds`, 15 s, building there and keeping
    other teams off; then its hold is over, it builds nothing there, and
    it moves on to hold another site it knows (the same one only when
    there is no other); a later Anchor standing there holds the site in
    turn. The map fills a held site only while the hold lasts. Measured
    against hold times of 10 s, 15 s, 30 s and none: the presets win 25%
    to 41%, every probe (an Anchor-heavy one too, 23%) under 45%, at 15 s
    ([The game](game.md#balance), [The bots](characters.md)).
31. **The app logo a hexagonal pattern, more in line with the game's
    look.** The logo, in the bar and as the tab's icon, is the board in
    small: an orange hexagon on black, the mainframe, with a smaller one
    and a site's diamond inside, and the three origins on its corners in
    the teams' colours, each linked to the core. One file,
    `public/favicon.svg`, serves both ([Screens](screens.md#the-shell)).
32. **Make sure the sign-in and the aityx key are remembered.** The
    session was signed with a random secret per start and lasted 12
    hours, so every restart of the server signed everyone out. Without
    `TATYX_SESSION_SECRET`, the server now keeps its secret in
    `<data>/session-secret` (made once, mode 600), and a session lasts
    30 days since the player's last visit, renewed at most once a day.
    The key already stayed in the browser's localStorage until
    **Forget**, through sign-outs and restarts; that's now in the spec
    ([Players](players.md)).
33. **Add a zoom control to the map, and more sites outside the
    origins.** Every sector has three **outer** relays beyond the
    origins (1 to 3.5 MB), so the board reaches past the stage; the
    map's camera shows it all at first and zooms (**−**, **Fit**, **+**,
    the wheel, the keys + − 0) and pans (a drag), while a second camera
    keeps the HUD and the cards still ([The game](game.md#the-map-on-screen)).
34. **The winner's card is too small: break the line between the team's
    name and "hacked the mainframe".** The card is bigger, the name on
    one line, "HACKED THE MAINFRAME" on the next.
35. **The Explorers a little slower, the sites a little more sparse.**
    The Explorer runs at 90 px/s (was 110); no two nodes closer than
    120 px (was 80). A site with no room left starts its sector's
    drawing over, so every map has all its sites.
36. **At the top, only each team's name and progress; its stats under
    its origin.** The HUD's chips say "Vice Cyan · 12%"; the strategy,
    the bytes and the bots are under each origin, under its name.
37. **The mainframe's name sits off its base; the board is too
    cluttered: larger, sparser.** The name is just under the mainframe,
    the progress under it, the hackers on its upper arc (and the bots at
    an origin on its upper arc, clear of its name); the board is larger
    (the ring 340 px, was 296), the cores and relays farther out, and
    the fonts and bots bigger, for the zoomed-out view. Balance measured
    again: the Sprinter leads (56%), noted in [The game](game.md#balance).
38. **tatyx at `/tatyx` instead of `/app`, to share a server with other
    apps.** The build's base, the server's routes (`/`, `/tatyx` and the
    old `/app` paths redirect to `/tatyx/`), the scripts, the docs,
    `start-all.sh` and the multyx index.
39. **Save the strategies to this repo, in the game project, as well as
    server side.** The players' strategies of the laptop's tour (The
    Homesteader and The Raider) are in [strategies/](../strategies), one
    file each; a tour with no entries yet starts with them, locally and
    deployed. The server keeps its files in a store
    (`tatyx_server/store.mjs`): a folder on a laptop, an S3 bucket
    deployed. The old `entries.json` is read when there is no
    `strategies.json`.
40. **Deploy tatyx to AWS.** Serverless, as Poker Tour: CloudFront at
    `/tatyx/`, the API and the relay as a Lambda function (the server's
    own routes through `tatyx_server/lambda.mjs`), the runner as another
    (one tournament at a time), the tour in an S3 bucket, the schedule
    four times a day ([Deployment](deploy.md); `bash deploy/deploy.sh`).
41. **Only show the win count on the leaderboard to admins, so it
    does not influence players.** `GET /api/leaderboard` leaves out the
    wins and what tells them (the progress, the winning times, each
    match's winner) unless an admin is signed in; the tab shows the
    **Wins** column and the bold winners only when they come, and asks
    again on signing in or out ([The leaderboard](leaderboard.md)).
