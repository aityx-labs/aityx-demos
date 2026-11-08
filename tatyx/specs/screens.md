# Screens

One page, [index.html](../tatyx_app/index.html), at `/app/`: a shell in
plain DOM around a Phaser canvas, in the aityx dark palette (near-black
with a violet tint, light grey text, an orange accent;
[style.css](../tatyx_app/src/style.css)); on the canvas, the neon of
Tron and synthwave: cyan lines, a neon purple sun, scanlines.

## The shell

[ui/shell.ts](../tatyx_app/src/ui/shell.ts).

- **The bar**, across the top: the logo (the board in small: the
  mainframe, an orange hexagon on black with a smaller one and a site's
  diamond inside, and the three origins on its corners in the teams'
  colours, Vice Cyan up, Neon Purple lower right, Sunset Pink lower left, each linked
  to the core; [public/favicon.svg](../tatyx_app/public/favicon.svg),
  the tab's icon too) and the
  name, a link home: a click goes to the title, every time, from the
  map (ending the match, as **Title** does) or from the title itself
  (anew); on the map, the match's controls: **Start**
  (then **Pause**, **Resume**, **Play again**; Space does the same) and
  the **speed**, ½×, 1×, 2×, 4× or 8×; on the right, **music**, which
  turns the soundtrack off and on, with the volume slider beside it
  ([Sound](sound.md)), and the **aityx light**.
- **The light**: an 8 px dot, grey while it checks, green when aityx
  accepts the key, red otherwise, with why on hover and for screen
  readers ([Deciding on aityx](aityx.md)). A click opens Profile.
- **The sidebar**, always shown, on the right, 320 px (under the canvas on a narrow
  window), the window's height, three tabs as Poker Tour's:
  **Leaderboard** ([The leaderboard](leaderboard.md)), **aityx calls
  (n)** ([Deciding on aityx](aityx.md#the-calls-panel)) and **Profile**
  ([Sign-in and keys](players.md#profile)). It opens on Leaderboard, or
  on Profile when there is no key to play on; a match's **Start** turns
  it to the calls.
- **The call viewer**: a dialog with a call's request and answer, in
  full.
- **The game pane**: the canvas, a 16:9 stage of 1280 × 720 scaled to
  fit and centred.

## The game

Three Phaser scenes ([scenes/](../tatyx_app/src/scenes)); what they
share (the palette, the button, the synthwave backdrop, the scanlines)
is in [look.ts](../tatyx_app/src/scenes/look.ts).

- **Boot**: loads the five portraits behind a bar, then the title (or
  the map, when the URL ends in `#map`).
- **The title**: the synthwave backdrop, a starfield over a sun of
  purple-to-orange bands setting behind a neon horizon, with a purple
  grid running from the bottom of the stage to the vanishing point;
  "tatyx" in glowing orange (a click on it draws a new lineup: every
  team a preset at random, no two the same) and the line "Build the
  sites, hack the mainframe"; the roster: the five bots in a row, each bobbing, with its
  letter, its name on the line below and its part; under them a card
  per team, in its colour: its strategy's name and tagline, **◀ ▶**
  through the presets, **Download** and **Upload**
  ([Deciding on aityx](aityx.md#a-teams-own-strategy)). **Play** (or
  **Sign in to play**, which opens Profile) starts the music and leads
  to the map; greyed out with no key to play on.
- **The map** ([map.ts](../tatyx_app/src/scenes/map.ts)): the board as
  [The game](game.md#the-map-on-screen) describes it, and the match
  playing on it: the neon hexagonal grid, the three tinted sectors with their
  edges and names, the triangle and the ring the origins sit on, the
  mainframe with its turning rings, the origins, the sites (dim until
  found), the links as they are found, rot and are renewed, the bots
  walking them (and bought at the origins), the HUD with the teams'
  strategies, bytes, bots and progress, the clock, the legend of the
  tags and the hint line; **Title** goes back; before the match, the
  lineup and **Start**; while paused, "PAUSED"; at the end, the winner
  and **Play again** ([The game](game.md#playing-a-match)). The links and the bots are drawn each frame; a
  site, whenever its bytes, its finders or its holder change.

## Known limitations

- The portraits are static images; no animations yet: a bot slides
  along a link.
- The glow is layered alpha, not a shader: Phaser 4's FX pipeline is
  left for later.
