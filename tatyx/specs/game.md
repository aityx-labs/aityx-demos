# The game

## Concept

The goal is to hack into the mainframe. It sits in the middle of the
map; three teams sit around it, each on a sector of the map, in a
triangle, each with an **origin**, its database. The map is a hidden
graph of **sites** joined by **links**: twenty-one sites where bytes
are **built**, the ones near the mainframe twice as fast as the ones
farther out, each only up to its size; every game places, sizes and
links them anew. A team knows only what its Explorer has found. Its bots
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
| The hack, built at the mainframe from 0 to done | 10 MB |
| A relay (farther out) builds | ×1, up to 0.5 to 3 MB |
| A core (near the mainframe) builds | ×2, up to 2 to 5 MB |
| The mainframe builds the hack | ×3, for any bot sent there |
| A builder builds, on a relay | 48 KB/s |
| A Tester with its team's Builder | doubles the Builder |
| An Anchor holds a site | 15 s after it arrives |
| An Anchor, on the site it holds | builds as a Builder |
| A link, from full health to gone | 15 s |
| A link counts as rotting under | 34% health |
| The Explorer runs, off the links | 110 px/s |
| The others walk, on the links | 70 px/s |
| A shortcut must save | 60 px of walking |
| Live shortcuts per team | 3 |
| One tick | 0.1 s |

### The map

The hidden graph (`buildMap` in world.ts) is drawn anew every game,
from a seed (`newWorld(seed)`; `SITE_DRAW`): in every team's sector,
three **cores** near the mainframe (×2), 89 to 163 px from it, and four
**relays** farther out (×1), 163 to 400 px from it, so some lie beyond
the origins, toward the corners of the board; anywhere across the
sector but its last 6° to either side, inside the board (clear of the
HUD and the legend); cores sized 2 to 5 MB, relays 0.5 to 3 MB, in steps
of half a megabyte; no two nodes closer than 80 px. One sector is drawn
and turned a third and two thirds of the way round for the other two,
so the three sectors are the same on every map, and no seat is luckier
than another.

The links are the map's neighbours: two nodes are joined when no
other node lies inside the circle they span (the Gabriel graph), so a
site is joined to the sites around it, across the sectors' edges too,
and the mainframe to the cores around it; never an origin straight to
another origin or to the mainframe. An origin with only one neighbour
is joined to its nearest sites besides, so every origin has two ways
out at least. Some forty-eight links in all, every node reaching the
mainframe by several ways. The same seed draws the same map, so a match
can be replayed; the app draws a new one for every match.

### Finding

A team starts knowing its origin and nothing else. When its Explorer
reaches a site, the site joins the team's map, with every link from it:
the map's own links from that site, which become live at full health if
they weren't, and every live link there already, shortcuts included,
with the nodes at their far ends. Only the Explorer moves off the
links; the other bots walk the links the team knows, by the shortest
way, and stand still with no way to where they want to be.

### Rotting and renewing

Every live link loses health, from 100 to 0 in 15 s; at 0 it is gone,
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
- an **Anchor**, on the site it holds, while it holds it (never
  doubled);
- a **Tester**, on a site its team's Anchor holds and with no Builder
  of its team there (with one, it doubles the Builder instead).

Explorers build nothing on a site, nor does an Anchor on a site another
team's Anchor holds, or one whose hold is over. A site's label shows
its richness and the bytes built there over its size. **Holding**: the
first Anchor to stand on a site holds it for its team for 15 s
(`holdSeconds`), and meanwhile only its team builds there; then its
hold is over, the next Anchor standing there (of any team) holds it in
turn for what is left of its own 15 s, and the first moves on to hold
another site it knows (the same one only when there is no other, and
then only after leaving and coming back). On a site nobody holds, any
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
  sits on a ring around the centre (296 px), at the middle of its
  sector, all three as far from the mainframe: Vice Cyan up (−90°), Neon
  Purple lower right (30°), Sunset Pink lower left (150°); the three make
  a triangle with one vertex up, drawn in neon.
- **An origin** per team: a hexagon in the team's colour with a smaller
  one inside, with its name (to the right of the top one, under the
  lower ones); no bytes and no percentage.
- **The sites**: small dim hexagons with a question mark until a team
  finds them; then orange, the computer's, as big as the site is (the
  bigger its size, the bigger the hexagon), with a diamond (bigger for a
  core) and under it the site's richness and its bytes built over its
  size (`×2 · 1.4/4.5 MB`), a thin hexagon in the colour of every team
  that knows the site, and a fill in a team's colour while that team's
  Anchor holds it; dim again once spent (`×2 · spent · 4.5 MB`).
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
match takes just under a minute and some thirty decisions. The tests
play on fixed seeds, and check the drawing of the map on two hundred.
The server plays the same matches for the [leaderboard](leaderboard.md).
A tick takes well under a millisecond: the ways a team has from a node
are searched once per state of the world and kept (`route`).

## Balance

No strategy should win every match, neither a preset nor a one-line
table a player uploads. Measured headless, with the tables decided
locally, on tournaments of five hundred to six hundred matches, each
trio's three turns on one map. Every strategy wins about a third of its
matches when the field is even. Before: the nine-site map and the
rules as they were (the probes, a strategy each against the five
presets: the old rules on the new map); now: the rules above.

| | Wins, before | Wins, now |
|---|---|---|
| The Farmer | 42% | 41% |
| The Sprinter | 63% | 40% |
| The Doubler | 28% | 35% |
| The Fortress | 7% | 26% |
| The Swarm | 27% | 25% |
| "Hack every megabyte", against the presets | 98% | 27% |
| "Builders until four, then hack" | 93% | 30% |
| "A second Explorer, then hack" | 94% | 31% |
| "Two Builders, two Testers, then hack" | 69% | 44% |
| "Anchors until four, then hack" | | 23% |
| The top seat (cyan) | 53% | 32% |

What changed, and why:

- **The origins as far from the mainframe, the sectors alike.** On the
  oval the top origin was nearer the mainframe; one sector drawn and
  turned for the others keeps a random map fair to every seat.
- **More sites, smaller.** Twenty-one sites hold about fifty megabytes,
  about what nine held: room enough to spread, not enough for every
  team everywhere, so holding a site still counts.
- **Links rot in 15 s, not 45.** A hacker builds only while its team's
  origin reaches the mainframe; a rush with nothing left to keep the
  links up loses its way in, so Testers, and the bytes for them, pay.
- **The hack costs 10 MB, not 6.** Early hackers no longer finish
  before an economy pays back.
- **An Anchor builds on the site it holds.** Holding no longer costs a
  team its income: the Fortress, all Anchors, was last by far.
- **An Anchor holds a site for 15 s, then moves on** (`holdSeconds`),
  so it doesn't keep a site to itself all match. The hold's length moves
  the presets by a few points at most; 15 s keeps every probe under
  45% ("two pairs, then hack" 44%), where 10 s lets it reach 49% and
  30 s or no limit 46% to 47%.

## Next

1. Balance the presets further by playing; the Farmer and the Sprinter
   lead, the Swarm trails.
2. A strategy editor in the app, beside the upload.
3. The world's rules as an aityx model too, readable in the app.
