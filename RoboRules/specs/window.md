# The window

[BattleScreen](../roborules_app/lib/ui/battle_screen.dart), in the look of
Robocode's Java Swing window ([classic.dart](../roborules_app/lib/ui/classic.dart)):
light gray panels, beveled buttons, a blue gradient title bar, "RoboRules:
Robocode-style battles, every turn played by aityx".

- **aityx light**, top right over the title bar on every screen
  (`withAityxStatus` from the shared
  [aityx_web](../../packages/aityx_web) package, in `MaterialApp.builder`):
  an 8 px dot, grey while checking, green when aityx accepts the key the
  app calls it with, red otherwise; its tooltip says why ("aityx: ready — the key works with
  https://api.aityx.ai", "aityx: no key — set yours on the index page", "aityx: key
  rejected — …", "aityx: not reachable — …", "aityx: not working — …").
  The key is the user's, saved on the index page, else the index server's
  dev key (see [Development environment](dev-environment.md#the-aityx-key)).
  It checks by posting an empty request to aityx's `/v1/systemone` (a
  working key gets 400 `invalid_request`, without running a model) at
  start, when the key is saved or forgotten on the index page, and when the
  window regains focus, at most once every 30 s there; no timer polling,
  since each check spends a request of the user's quota. A tap opens the
  index page's key section (`/demos/#aityx-key`) in the same tab.
- **Menu bar**: **Battle** (New…, Start, Pause/Resume, Stop, Results…),
  **Robot** (Add a robot…, Upload robots…, Download all robots; adding and
  uploading only between battles; see [Robot files](robots.md#robot-files);
  each robot's own actions, edit, download and remove, are in its
  [rules](robots.md#the-rules-editor)), **Options** (speeds: 2, 5, 10, 20 or
  30 turns a second, or as fast as aityx; and **Sound: on (turn it off)**
  or **Sound: off (turn it on)**), **Help** (the last aityx call, About).
- **Battlefield** ([painter.dart](../roborules_app/lib/battle/painter.dart)),
  800 × 600 scaled to fit: dark ground with a faint speckle and grid;
  tanks with two treads (moving with the tank), a body in the robot's color
  turned to its heading, a turret and barrel turned to the gun, a radar
  dish sweeping; energy above, name and the rule it follows below; each
  gun's line of sight, Robocode's radar beam: a cone in the robot's color
  10° either side of the gun (where `enemy_in_sight` looks), fading with
  distance and brighter while the nearest enemy is in it; glowing bullets
  sized by power; vintage, arcade-sprite explosions that step through
  their frames (a flash, a ragged fireball cooling from yellow to red,
  square sparks), small for hits and, for a robot lost, bigger, with a
  shock ring and rising smoke, leaving a dark scorch mark for the rest of
  the round. Positions and angles ease between turns. Messages over it: how
  to start, "aityx is playing the next turns…", "Round n is over: aityx is
  scoring it…", then, once aityx has scored it, the round's winner for 3
  seconds before the next round (and after the last, until a new battle):
  a trophy and "Name wins round n!" in the winner's color, with its
  points ("Round n: no winner" when aityx names none).
- **Sound** ([lib/sound/](../roborules_app/lib/sound/), Web Audio, made
  in the browser; none outside one, nor in tests): short and quiet, played
  as each turn is shown. A **soft thud** (a low sine falling from 140 to
  50 Hz, 0.15 s) when a robot runs into a wall or rams another; a **small
  pop** (a few hundredths of a second of noise around 1.8 kHz) when a
  bullet hits a robot; a **bigger boom** (noise falling in pitch over a low
  rumble, 0.6 s) when a robot is lost, which drowns out the rest of its
  turn. The frames say so: a hit is a robot's `hit`, a loss `alive` turning
  false; a collision is a robot that was moving and now stands still
  (`v` 0), at a wall (18 px from it) or, rammed, where it was with
  another robot within 52 px; a robot stuck against a wall or another
  robot doesn't sound again. Each kind sounds at most once every 100 ms,
  so turns played fast don't make a wall of noise. Sound is on by default;
  turning it off or on is remembered in the browser (localStorage
  `roborules.sound`; without storage, until the page closes). The browser
  allows audio only after a click or key press, and a battle starts with
  one: the audio is made on the first sound and resumed if the browser
  suspended it.
- **Robots**, on the right (below on a narrow window): round and turn, and
  a button per robot: color, name (struck through when lost), energy and a
  green, amber or red bar, and the rule it follows now with its reason, or
  its rule count and score. Its tooltip lists its rules; selecting it opens
  the [rules editor](robots.md#the-rules-editor). Between battles each
  button has an **×** that removes the robot, **Add robot…** below
  them opens [Add a robot](#dialogs), and **Upload robots…** adds robots
  from files ([Robot files](robots.md#robot-files)); all restart the
  battle from setup.
  At least two robots fight, at most ten. A lost robot is "lost", never
  "dead".
- **Events**, below the robots: the battle log, newest at the bottom,
  its lines on alternating white and light gray backgrounds (by their
  place in the log, so a line keeps its shade as more arrive), and shots
  in a red tone (light red, with dark red text),
  everything that happened since the battle started: the robots and rounds
  of the battle, each round's start, every rule a robot switches to (with
  its reason), every shot fired ("Name fires a shot of power p", from
  the turn's `fired`), every hit (by whom, the damage, the energy left), every
  robot lost, each round's end (who is left), its scores, its winner
  ("Name wins round n, with p points"), the battle's winner, and any
  failed call. The calls to aityx themselves aren't lines (see **Last
  aityx call**). Every line is clickable (a pointer, a tap or Enter)
  and opens [the aityx call viewer](#dialogs) as the **aityx call** button
  does, with the line on top and the call behind it: a rule switch, shot,
  hit or loss the call that played that turn; a round's end the call that
  played its last turn; a round's winner its score; the battle's end the
  last round's score. The app's own lines (the battle and its rounds
  starting, rule changes, failed calls) open the same dialog, which says no
  aityx call is behind them. Each line's tooltip says which call it opens.
  The last ten calls keep what was sent and answered; an older call opens
  saying only the last ten are kept.
- **Last aityx call**, always at the bottom, below the events: the latest
  call ("Call 9: turns 161–180 of round 1, in 406 ms"; a score call also
  lists the round's scores), a link that opens it in the viewer; "None
  yet" before the first.
- **Controls**: Start/Pause/Resume, Next turn, Stop, Restart, New battle…,
  **Speed** (1 to 60 turns a second, or Max; 10 to start), where a
  battle starts: every 15 seconds of play (pauses don't count) it speeds
  up by 5 turns a second, up to 40, with *now n* beside the choice;
  choosing a speed, or a new battle, starts again from the choice, and Max
  stays Max, **Sound on** /
  **Sound off** (a speaker icon; it turns the sound off and on, as the
  Options menu does), aityx's measured turns a second, **aityx call**, and
  any error (a failed call pauses the battle
  until Resume, and says why: "aityx is not set up: set your key on the
  index page", "aityx rejected the key", "aityx did not answer", "aityx
  answered HTTP n: …" with aityx's reasons, or a robot's rules the app
  refuses before calling aityx; a round aityx fails to score waits with **Retry scoring**,
  since moving on would leave it out of the totals).
- **Dialogs**:
  - **New Battle**, as Robocode's: **Available robots** on the left (the
    [predefined robots](robots.md#predefined-robots): a random one, then
    Robocode's samples), **Selected robots** on the right (opening with the
    battle's current robots, customizations and all), and between them
    **Add →** (or double-click an available robot), **← Remove**, **← Remove
    all** and **Edit rules…** (the [rules editor](robots.md#the-rules-editor)
    for the highlighted selected robot). Below, what the highlighted robot
    does (an available one's description, or a selected one's rules), and
    the number of rounds (1–10, three by default). **Start Battle** needs
    two robots; the same kind can be added more than once.
  - **Add a robot** (from the robots panel or the Robot menu): the same
    list; **Add** (or a double-click) adds the highlighted one to the
    current battle.
  - **Results** (Rank, Robot Name, Total Score, Survival, Surv Bonus,
    Bullet Dmg, 1sts, the winner highlighted).
  - **The last aityx call** (the aityx call button, Help), or **aityx
    call n** from a line of the event log, with the line above the viewer
    (**A battle event** for a line with no call behind it): Contact Hub's
    viewer in aityx's dark theme with each robot's rules, the turn's steps,
    the world and the frames labeled.
