# The bots

The five characters are the letters of aityx, the robots of the concept
art ([art/reference/](../art/reference/)): ivory shells with orange
panels and dark joints, two glowing orange bars for eyes. Each has a part
on the map ([bots.ts](../tatyx_app/src/game/bots.ts)), and the rules
that make the parts real are the world's ([The game](game.md)). Every
team starts with one of each, and buys more of whichever kind its
strategy chooses, a megabyte each ([Deciding on aityx](aityx.md)).

| Letter | Name | Part on the map |
|---|---|---|
| A | **Anchor** | Walks the links to the best site it knows and stays. While it stands there, the site is its team's alone: only its team builds on it. |
| I | **Builder** | Walks the links to a site and builds bytes there for its team; twice as fast with a Tester of its team beside it. |
| T | **Tester** | Renews every link it crosses. On a site with its team's Builder, it doubles the Builder; on a site its team's Anchor holds, it builds itself. |
| Y | **Combinator** | Where two links it knows meet, makes a direct link between their far ends, a shortcut; with none to make, builds on a site like a Builder, though no Tester doubles it. |
| X | **Explorer** | The only one that moves off the links: runs anywhere on the map, and every site it reaches, with the links from it, joins the team's map. |

The names are the game's, not the concept art's: the art labels the
five Scout, Builder, Analyzer, Monitor and Connector, with a line each
about information work. The roster on the title shows each bot's
letter, its name on the line below, and its part in a line (`motto` in
bots.ts); `part`, the full sentence, is the hint on hover on the map.

## Behaviour

Nobody steers a bot: each kind has one behaviour, so buying a bot is
choosing what will happen ([world.ts](../tatyx_app/src/game/world.ts),
`wantOf`). "The best site" is the richest one it can reach (a core
before a relay), then the nearest, among the sites its team knows that
are not spent and no other team holds; a bot on a spent site leaves it.

Any bot can be sent to the mainframe, by a strategy's `hack` answer
([The game](game.md#buying-and-hacking)): from then on it is a
**hacker**, goes to the mainframe as soon as its team knows a way there,
and builds the hack there for the rest of the match, whatever its kind;
the Explorer, sent last, runs there. Until there is a way, it does its
usual work.

- **Anchor**: the best site where its team's Builders work, else the
  best site, that no other Anchor of its team holds or heads for; it
  stays.
- **Builder**: the best site its team holds, else the best site, that
  no other Builder of its team works or heads for; it stays and builds.
- **Tester**: the weakest link it knows, when one is rotting (under
  a third of its health), crossed from the nearer end. Else a site with
  its team's Builder, or one its team holds, that no other Tester of
  its team works; else the weakest link, and on to the next.
- **Combinator**: wherever a shortcut can be made, the best first; with
  none to make (or the team's three shortcuts standing), the best site
  no other Combinator of its team works, to build.
- **Explorer**: the nearest site not yet found; then any site whose map
  link has rotted away, to find it again; then the farthest known site,
  to keep moving. It builds nothing.

Bots never die and never fight: the only contest is for a site, and an
Anchor settles it. The first Anchor to arrive holds the site; another
team's Anchor arriving later holds nothing there, and leaves.

## Teams and tags

Three teams, each on a sector of the map, each with a colour tag
([teams.ts](../tatyx_app/src/game/teams.ts)), a palette out of Miami
Vice:

| Team (id) | Tag | Strategy to begin with |
|---|---|---|
| Vice Cyan (`cyan`) | `#00F0FF` | The Farmer |
| Neon Purple (`magenta`) | `#BC6CFF` | The Sprinter |
| Sunset Pink (`green`) | `#FF5CA8` | The Swarm |

The ids are the first palette's, kept so the tournaments already
recorded (whose results name the teams by id) still count.

Each team's strategy is the player's to choose on the title: a preset,
or the team's own, uploaded ([Deciding on aityx](aityx.md#a-teams-own-strategy)).

The list is [teams.json](../tatyx_app/src/game/teams.json), read by
the app and by the tool that paints the portraits; change a colour
there and run `npm run recolor`. The lineup is `LINEUP` in
[play.ts](../tatyx_app/src/game/play.ts).

**Orange** (`#E36742`, aityx's colour) is never a team's: it tags what
the computer defines, the mainframe and the sites nobody holds, so a player can always tell its own from the system's. A
tag shows on the bots themselves (their panels and the glow of their
eyes, in the team's colour instead of the art's orange), as the ring
under each, as the colour of a team's origin, sector and HUD chip, of
the thin line beside every link the team knows and the ring around
every site it has found, of the fill of a site its Anchor holds, and of
its shortcuts. The test suite checks that no team's colour is orange.

## Art

- [art/reference/](../art/reference/): the concept art, copied as
  reference (the lineup of the five, a hero shot of each, turnarounds
  and reference sheets); never served by the app.
- [tatyx_app/public/bots/](../tatyx_app/public/bots/): the five hero
  shots, downscaled to 384 px, transparent, in the art's orange, named
  by letter and part (`a-anchor.png`, `i-builder.png`, `t-tester.png`,
  `y-combinator.png`, `x-explorer.png`): what the title's roster shows.
  Under it, one folder per team (`cyan/`, `magenta/`, `green/`) with
  the same five painted in the team's colour by
  [tool/recolor.mjs](../tatyx_app/tool/recolor.mjs) (`npm run
  recolor`): every pixel in the art's orange hue band (5° to 50°) that
  is saturated enough to be a panel or the eyes' glow, and bright enough
  not to be a joint, takes the team's hue and keeps its own saturation
  and brightness, with the edge pixels blended so there is no halo; the
  ivory shells and the dark joints stay as they are. Generated once and
  committed; what the map shows.

## Next

- Sprite sheets and animations from the turnarounds (walk, work).
- A bot's numbers per kind (speed, rates) are the world's rules, the
  same for every team; a strategy that could tune them is an idea.
