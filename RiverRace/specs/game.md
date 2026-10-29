# Game

The 1982 Atari river shooter, remade for three planes at once
([lib/game/](../riverrace_app/lib/game/)): the river and its contents in
[river.dart](../riverrace_app/lib/game/river.dart), the rules of play in
[race.dart](../riverrace_app/lib/game/race.dart), the drawing in
[race_painter.dart](../riverrace_app/lib/game/race_painter.dart). The
game runs in the app; aityx decides only what the two aityx pilots do
(see [Decisions](decisions.md)).

## The river

- A playfield 160 pixels across and 160 rows high, drawn with the
  Atari's wide pixels (1.6 times as wide as tall), scrolling up the river.
- Made from a seed, section by section, so the same seed is the same
  river: **Restart** keeps it, **New river** picks another.
- Mirror-symmetric about its middle, as in the original: green banks that
  widen and narrow in steps, with slanted edges between, and islands in
  the middle. Houses with a tree stand on the banks.
- Every section is 40 blocks of 16 rows (640 rows) and ends at a
  **bridge** across a narrow neck (32 pixels of water), with its road
  across the banks. Bridge 1 ends the first section.
- Later sections are narrower, with more islands and enemies.
- Every channel goes on into the next stretch with at least 16 pixels in
  common (`River.flowsInto`), so no channel is a dead end; no island is
  within 7 blocks of a bridge.

## Things on the river

| Thing | Size | Points | Behavior |
|---|---|---|---|
| Tanker (ship) | 16 × 6 | 30 | Still, or patrols side to side once on screen, at ½ pixel a frame |
| Helicopter | 8 × 7 | 60 | Still, or patrols once on screen, at 0.8 a frame; its rotor turns |
| Fuel depot | 7 × 22 | 80 | Still; flying over it fills the tank, shooting it scores |
| Jet | 8 × 5 | 100 | From the second half of the first section on, every 3 to 9 seconds, crosses the screen at 2 a frame, over land too |
| Bridge | the neck | 500 | Blocks the river until shot down; its road stays |

Patrolling things turn back at the banks. What a plane shoots is gone for
every plane.

## The planes

Three planes fly up the same river: **You** (the original's yellow,
drawn solid), and the two aityx pilots (cyan and magenta, drawn 25%
opaque). **You fly** off leaves the race to the two aityx pilots.
Planes don't collide with each other.

- **Speed**: slow, normal or fast, 0.75, 1.5 or 2.5 rows a frame, eased
  toward over a few frames. Sideways, 1.25 pixels a frame.
- **Missile**: one in the air at a time per plane; it flies 5 rows a frame
  faster than the plane and follows the plane sideways, as in the
  original. It passes over land and stops at the first thing or standing
  bridge it hits, scoring for its plane.
- **Fuel**: a full tank lasts about 24 seconds (0.07 a frame); over a
  depot it fills at 0.9 a frame, and the plane drops at once to half its
  throttle's speed and holds it until past the depot, as in the
  original, so it fills more (slowing down fills more still); past it,
  it eases back up. Below a quarter the gauge turns red.
- **Lost**: crashing into land, a ship, helicopter or jet, or a standing
  bridge, or running out of fuel. The plane explodes; after 50 frames it
  comes back with a full tank, low on the screen, mid-channel where it
  can fly straight on for 40 rows without meeting the bank, an island or
  a standing bridge (over the widest water if there's no such place),
  blinking for 2 seconds during which enemies pass through it.
- **Lives**: eight (one flying, seven in reserve), and one more every
  10,000 points. A plane with none left is out of the race.
- **The screen** follows the plane furthest up, 48 rows above its bottom.
  A plane left behind is pushed along by the bottom edge, 12 rows up.

The race ends when a plane passes bridge 10. The winner has
the most points, then went furthest; a banner says who, with each plane's
score, bridge and losses, and **Race again** starts on a new river.

## Playing

- **← →** (or A, D) steer, **↑** (W) faster, **↓** (S) slower, **space**
  fires (held, it fires again as soon as it can), **P** or **Enter**
  pauses and plays. The keys work whatever has the focus (a control just
  clicked included), except while a dialog or menu is open. The flying
  keys count while held, read every frame: a key held when a dialog
  opens, or let go inside it, stops counting, so the plane doesn't keep
  steering or firing.
- Before the race the river shows only *Press any key to play*: whether
  two or three planes race depends on **You fly**.
- Any key starts the race, goes on after a pause, and, once the race is
  over (after a second and a half, so the banner can be read), starts
  another on a new river; not Tab, Esc or a modifier alone, nor a
  shortcut with Cmd, Ctrl or Alt.
- The controls sit in the top bar, right of the title and of the status
  (the frame, and how long aityx took to answer), so the game starts
  right under it: **Start**/**Pause**, **Restart** (same river) and
  **New river** (icons, named on hover), **You fly**, **Sound**, **Fair
  race** (see [Decisions](decisions.md)), **Speed** (¼×, ½× by default,
  ¾×, 1×) and **aityx decides every** (3, 6, 12 or 30 frames). In a
  window narrower than 1,300 pixels they wrap in a row above the game
  instead.
- The game runs at 60 frames a second of game time, in fixed steps.
- **Speed** is where a race starts: every 30 seconds of play the game
  speeds up by 10 percent, up to 1× (from ½×, in two and a half
  minutes), and *now 0.6×* beside the choice says how fast it runs. A
  restart, or a new river, starts it again from the choice.
- **Sound** (on by default), made in the browser, Atari-like: a short
  square-wave beep every 6 frames while a plane refuels, higher the
  fuller its tank, and a burst of coarse noise, falling in pitch, when a
  missile hits a ship, helicopter, jet, depot or bridge. One beep and one
  explosion at most a frame, whichever planes made them. None outside a
  browser.
- Under the river, a gray band, as on the Atari: each plane's name,
  score, fuel gauge and planes left.
- The **Race log** lists the last 8 events: planes lost and why, bridges
  blown up, depots shot, extra planes, planes out.

## Known limitations

- No sound.
- Keyboard only: no on-screen controls for touch screens, so on a phone
  you can only watch the aityx pilots.
- A lost plane comes back where the screen is, not at the last bridge as
  in the original, since the other planes fly on.
- The original's balloons, and its tanks on the roads, aren't there.
