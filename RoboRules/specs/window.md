# The window

[BattleScreen](../roborules_app/lib/ui/battle_screen.dart), in the look of
Robocode's Java Swing window ([classic.dart](../roborules_app/lib/ui/classic.dart)):
light gray panels, beveled buttons, a blue gradient title bar, "RoboRules:
Robocode-style battles, every turn played by aityx".

- **aityx light**, top right over the title bar on every screen
  ([aityx_status.dart](../roborules_app/lib/aityx/aityx_status.dart)): an
  8 px dot, grey while checking, green when aityx accepts the API's key,
  red otherwise; its tooltip says why ("aityx: ready — accepts the key
  (url)", "aityx: no key — AITYX_API_KEY is not set", "aityx: not
  working — …", "aityx: the API did not answer"). It asks the API's
  `GET /api/aityx` at start and every minute; the API posts an empty
  request to aityx's `/v1/systemone` at most once a minute (a working key
  gets 400 `invalid_request`, without running a model) and never returns
  the key ([aityx_check.dart](../roborules_api/lib/aityx_check.dart)).
- **Menu bar**: **Battle** (New…, Start, Pause/Resume, Stop, Results…),
  **Robot** (Add a robot…, each robot's rules, Remove each robot; adding
  and removing only between battles), **Options** (speeds), **Help** (the
  last aityx call, About).
- **Battlefield** ([painter.dart](../roborules_app/lib/battle/painter.dart)),
  800 × 600 scaled to fit: dark ground with a faint speckle and grid;
  tanks with two treads (moving with the tank), a body in the robot's color
  turned to its heading, a turret and barrel turned to the gun, a radar
  dish sweeping; energy above, name and the rule it follows below; glowing
  bullets sized by power; orange explosions for hits and bigger ones for
  robots lost. Positions and angles ease between turns. Messages over it: how
  to start, "aityx is playing the next turns…", "Round n is over: aityx is
  scoring it…".
- **Robots**, on the right (below on a narrow window): round and turn, and
  a button per robot: color, name (struck through when lost), energy and a
  green, amber or red bar, and the rule it follows now with its reason, or
  its rule count and score. Its tooltip lists its rules; selecting it opens
  the [rules editor](robots.md#the-rules-editor). Between battles each
  button has an **×** that removes the robot, and **Add robot…** below
  them opens [Add a robot](#dialogs); both restart the battle from setup.
  At least two robots fight, at most ten. A lost robot is "lost", never
  "dead".
- **Events**, below the robots: the battle log, newest at the bottom,
  everything that happened since the battle started: the robots and rounds
  of the battle, each round's start, every rule a robot switches to (with
  its reason), every hit (by whom, the damage, the energy left), every
  robot lost, each round's end (who is left), its scores, the winner, any
  failed call, and every call to aityx (what turns it played, how long it
  took, its number). The last ten calls keep what was sent and answered:
  their lines are links that open them in the viewer; older lines stay,
  grayed.
- **Controls**: Start/Pause/Resume, Next turn, Stop, Restart, New battle…,
  **Speed** (1 to 60 turns a second, or Max), aityx's measured turns a
  second, **aityx call**, and any error (a failed call pauses the battle
  until Resume; a round aityx fails to score waits with **Retry scoring**,
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
    call n** from the event log: Contact Hub's viewer in aityx's dark theme
    with each robot's rules, the turn's steps, the world and the frames
    labeled.
