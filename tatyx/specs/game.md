# The game

## Concept

The goal is to hack into the mainframe. It sits in the middle of the
map; three teams sit around it, each on a sector of the map, in a
triangle, each with an **origin**, its database. The map is a hidden
graph of **sites** joined by **links**: nine sites where bytes are
**built**, the ones near the mainframe twice as fast as the ones near
the origins, each only up to its size; every game places and sizes
them anew. A team knows only what its Explorer has found. Its bots
build bytes on the sites it has found, as long as the site is connected
to the origin by links the team knows, and the more a team builds, the
more bots it deploys: every megabyte is one decision, a bot of one of
the five kinds, or one of its bots sent to the mainframe to hack it.
At the mainframe any bot builds, and what it builds is its team's
hack: the first team to build the hack's price there wins.

Every team has a **colour tag**: cyan, magenta or green. Orange, the
aityx colour, is never a team's: it tags what the computer defines, the
mainframe and the sites nobody holds ([The bots](characters.md)).

Nobody plays it by hand. Each team's **strategy** is an aityx decision
model, asked what the team's next megabyte buys; the world's rules are
the browser's simulation, plain data and pure functions
([world.ts](../tatyx_app/src/game/world.ts)). Each team plays a preset
or its own strategy, and the game plays itself from them: the browser
keeps the clock and draws, ten ticks a second times the chosen speed,
and the calls panel shows every decision as it is made ([Deciding on
aityx](aityx.md)).

## The rules

`RULES` in world.ts, to be balanced by playing:

| Rule | Value |
|---|---|
| A bot, or sending one to the mainframe | 1 MB |
| The hack, built at the mainframe from 0 to done | 6 MB |
| A relay (near an origin) builds | ×1, up to 1.5 to 5 MB |
| A core (near the mainframe) builds | ×2, up to 5 to 10 MB |
| The mainframe builds the hack | ×3, for any bot sent there |
| A builder builds, on a relay | 48 KB/s |
| A Tester with its team's Builder | doubles the Builder |
| A link, from full health to gone | 45 s |
| A link counts as rotting under | 34% health |
| The Explorer runs, off the links | 110 px/s |
| The others walk, on the links | 70 px/s |
| A shortcut must save | 60 px of walking |
| Live shortcuts per team | 3 |
| One tick | 0.1 s |

### The map

The hidden graph (`buildMap`): each team's origin is joined to two
**relays**, one to either side of it, toward the mainframe; each relay
to the **core** on its side (the cores sit near the sector boundaries,
close to the mainframe) and to the relay across the boundary, the other
team's; each core to the mainframe. From an origin it is relay, core,
mainframe, and every core lies between two teams. The graph is the same
every game; the links are not there until found.

Where the sites sit, and how big they are, is drawn anew every game,
from a seed (`newWorld(seed)`; `SITE_DRAW` in world.ts): a relay 28° to
50° to its side of its origin, 62% to 86% of the way out on the
origins' ellipse, sized 1.5 to 5 MB; a core within 14° of its sector
boundary, 135 to 195 px from the mainframe, sized 5 to 10 MB; sizes in
steps of half a megabyte, and no two nodes closer than 100 px. The same
seed draws the same map, so a match can be replayed; the app draws a new
one for every match.

### Finding

A team starts knowing its origin and nothing else. When its Explorer
reaches a site, the site joins the team's map, with every link from it:
the map's own links from that site, which become live at full health if
they weren't, and every live link there already, shortcuts included,
with the nodes at their far ends. Only the Explorer moves off the
links; the other bots walk the links the team knows, by the shortest
way, and stand still with no way to where they want to be.

### Rotting and renewing

Every live link loses health, from 100 to 0 in 45 s; at 0 it is gone,
every team forgets it, and a bot that was on it steps back to the end
it came from. A Tester crossing a link brings it back to 100 the moment
it arrives at the far end. A gone link can be found again by an
Explorer visiting an end of it, or, for a shortcut, made again.

### Building bytes

Bytes are built on a site up to its **size**, all teams together: then
the site is **spent**, builds nothing more, and the bots leave it for a
site with room (the last tick builds only what is left). On a site its
team can build on (not spent, connected to the team's origin over links
the team knows, and not held by another team's Anchor), each of these
builds bytes for its team at 48 KB/s times the site's richness (×1 for
a relay, ×2 for a core), every tick (`buildRate` in world.ts):

- a **Builder**, twice that with a Tester of its team on the site;
- a **Combinator**, never doubled;
- a **Tester**, on a site its team's Anchor holds and with no Builder
  of its team there (with one, it doubles the Builder instead).

Anchors and Explorers build nothing on a site. A site's label shows its
richness and the bytes built there over its size. **Holding**: the
first Anchor to stand on a site holds it for its team, and while it
stands there only its team builds there; on a site nobody holds, any
number of bots of any team build, each at its rate.

### Buying and hacking

When a team has a megabyte, its strategy is asked, and the answer is
applied at once: a bot of the chosen kind appears at the origin, for a
megabyte; or, for `hack`, a megabyte sends one of the team's bots to
the mainframe for good, the nearest to it (an Explorer only when no
other is left, since the team needs it to keep its way there; with
every bot already sent, the team saves); or the team saves, and is
asked again in 5 s. A bot sent in (a **hacker**) leaves its work and
walks to the mainframe as soon as the team knows a way there (an
Explorer runs there), and until then does its usual work. At the
mainframe, a hacker of any kind builds its team's hack at 48 KB/s times
the mainframe's richness, ×3, as long as the mainframe is connected to
the team's origin over links it knows; a bot not sent there, passing
through or with nowhere to go, builds nothing; nobody holds the
mainframe. A
team's progress into the hack is the bytes it has built there over the
hack's price; at the price, it has won, the world stops, and the map
says so.

## The map on screen

Tron's look: a neon hexagonal grid on black (pointy-top cells, as the
sites, every fifth cell of every other row brighter), glowing lines, scanlines over
everything, the synthwave sun on the title. In stage pixels (1280 ×
720):

- **The mainframe** at the centre, (640, 404): an orange hexagonal core
  with two rings turning around it, its name, and over it each team's
  progress into the hack, a percentage in the team's colour.
- **The sectors**: three wedges of 120°, one per team, tinted with the
  team's colour, their edges drawn from the centre. The team's origin
  sits on an ellipse around the centre (540 by 296), at the middle of
  its sector: Cyan up (−90°), Magenta lower right (30°), Green lower
  left (150°); the three make a triangle with one vertex up, drawn in
  neon.
- **An origin** per team: a hexagon in the team's colour with a smaller
  one inside, with its name (to the right of the top one, under the
  lower ones); no bytes and no percentage.
- **The sites**: small dim hexagons with a question mark until a team
  finds them; then orange, the computer's, as big as the site is (the
  bigger its size, the bigger the hexagon), with a diamond (bigger for a
  core) and under it the site's richness and its bytes built over its
  size (`×2 · 1.4/8.0 MB`), a thin hexagon in the colour of every team
  that knows the site, and a fill in a team's colour while that team's
  Anchor holds it; dim again once spent (`×2 · spent · 8.0 MB`).
- **The links**, drawn each frame: an ivory line that fades as the
  link rots, a thicker one in the maker's colour for a shortcut, and a
  thin line in each team's colour beside every link that team knows.
- **The bots**: each team's portraits painted in its colour over a ring
  in that colour, the tag, with the letter under each; the ones
  standing at one site spread around it, the Explorer runs straight
  across the map, the others along the links. Hovering one says who it
  is and what it does, or that it was sent to the mainframe.
- **The HUD**: along the top, "HACK THE MAINFRAME" in orange, a chip per team
  with its strategy, its bytes, how many bots it has and its progress,
  the clock, and **Title**; along the bottom, the legend of the tags on
  one line, with the hint line over it; each sector's name in its far
  corner; "PAUSED" under the HUD while paused. At the end, the winner's
  name across the map, its strategy, the time and the number of
  decisions, and **Play again**.

## Playing a match

The map opens with the board set and the match waiting: a card in the
middle with the lineup (which strategy each team plays) and **Start**.
The bar holds the match's controls ([Screens](screens.md)): **Start**,
then **Pause** and **Resume**, then **Play again**, also on Space; and
the **speed**, ½× to 8× (kept in this browser). Paused, the world stands
still, so the calls can be read; an answer arriving meanwhile is
applied, and the next questions wait. Starting needs a signed-in player
and a key to play on ([Sign-in and keys](players.md)): without a key,
**Start** (in the bar and in the middle) is greyed out and takes no
clicks; signed out with a key, it opens Profile and says so.

`/app/#map` opens on the map, skipping the title: for development and
screenshots.

## Headless

The world and the match run under Node, without Phaser: the tests play
a whole match with the strategies' tables decided locally
([test/world.test.ts](../tatyx_app/test/world.test.ts), "a match"), and
print the winner, the time and the decisions. With the rules above a
match takes about a minute and some twenty decisions. The tests play
on fixed seeds, and check the drawing of the map on two hundred. The
server plays the same matches for the [leaderboard](leaderboard.md).

## Next

1. Balance the rules and the presets by playing: the sites' sizes, the
   rot, the rates. Since bots are sent in to hack, the presets that send
   theirs early win: in a local tournament the Sprinter won 13 of 18,
   the Fortress 2; and the seats are unequal: the top origin (cyan's) is
   nearer the mainframe on the oval map, and that seat won 16 of 30.
2. A strategy editor in the app, beside the upload.
3. The world's rules as an aityx model too, readable in the app.
