# Robots

## A robot is an aityx model

[Robot.toModel](../roborules_app/lib/battle/model.dart):

- `inputs`: the 12 sensors, each with its type and meaning (see
  [The battle](battle.md#the-world-model)).
- `decisions.action`: a FIRST decision table. Its columns are the sensors
  its rules test, then `=> drive: ahead|back|stop`,
  `=> turn: left|right|none|toward_enemy|away_from_enemy|perpendicular`,
  `=> gun: aim|sweep_left|sweep_right|hold`, `=> fire: number [0..3]` and
  `# why`. A condition is an aityx test (`true`, `< 200`, `[0..30]`), `-`
  for any value.

It runs alone in aityx too, given the sensors as its state. Rules may also
be written as `{"when": {...}, "then": {...}, "why": "..."}`. The app refuses
an unknown sensor, a missing command, a command value it doesn't know and a
fire power outside 0 to 3 before calling aityx
([lib/aityx/battle.dart](../roborules_app/lib/aityx/battle.dart)),
since aityx takes any word in an output column as a value.

## Predefined robots

[predefined_robots.dart](../roborules_app/lib/battle/predefined_robots.dart):
`robotKinds`, what a battle is made of: a **Random robot** (below),
Robocode's sample robots written as rules, and robots of our own, each with a name, a color, a
sentence on what it does, and its rules:

- **SittingDuck**: sits still, a target.
- **Fire**: sits still spinning its gun; fires at what it sees, hard (3)
  when point blank with energy to spare, else a cheap shot; moves across
  the line of fire when hit.
- **SpinBot**: drives in circles sweeping its gun; fires hard at whatever
  crosses its sight; turns in place at walls.
- **Walls**: stops and turns right at walls, so it follows them; drives on
  with the gun on the enemy, firing 2 in sight.
- **Tracker**: closes in to 150 px, fires hard in sight, backs off under
  60 px.
- **RamFire**: drives straight at the enemy; once on it (under 40 px),
  fires hard, or just 0.5 when the enemy is under 5 energy.
- **TrackFire**: sits still, gun on the enemy; fires 3 under 60 px, 2
  under 200, else 1, with energy to spare.
- **MyFirstRobot**: drives ahead sweeping its gun, cheap shots in sight,
  turns left at walls and across the line of fire when hit.
- **Crazy**: loops left, swerves when hit, reverses off walls and keeps
  reversing (`speed < 0`) until it bumps into something.

Then robots of our own, with more involved tactics (seven to ten rules):

- **Orbiter**: circles the nearest enemy across its line of fire
  (`perpendicular`), closing in beyond 400 px; reverses its orbit off a
  wall and keeps going backward (`speed < 0`) until it backs into the
  next; jinks backward when hit; fires 2.5 under 250 px, else 1. The
  strongest of the lot in trial battles.
- **Sniper**: falls back to 250 px when there is room behind it, else
  slips sideways; moves to a new spot when hit; settles (`speed > 2`:
  stop) before firing 2, or 0.5 under 20 energy.
- **Vulture**: while more than one enemy is left, keeps 250 px away
  (circling instead near a wall) and pecks with 0.5 shots; swoops on an
  enemy under 20 energy, firing 3; once one enemy is left, fights it.
- **Berserker**: calm above 60 energy (sidesteps when hit, careful 1-power
  shots within 300 px); under 60 closes in firing 2; under 30 charges
  firing 3.

And robots just for fun:

- **Matador**: stands facing the bull, strutting toward it beyond 350 px
  and flicking 1-power shots within it; when it comes under 120 px, steps
  aside (`perpendicular`) firing 3. Olé!
- **Chicken**: runs from anyone within 300 px, firing 0.5 over its
  shoulder; panics off walls and flaps about when hit; charges, firing 3,
  once the enemy is under 15 energy.
- **Tipsy**: staggers toward the enemy, lurching left and right as the
  distance to the walls changes (`wall_distance` 100–150 and 190–240),
  hiccupping 0.5 shots roughly that way and firing 2 when close; spins
  round when hit.
- **Pacifist**: never fires; keeps out of everyone's way and out of the
  line of fire, gun idly spinning.
- **BumperCar**: drives into the nearest enemy, says sorry with a 0.1
  shot, backs off and does it again.

`RobotKind.make` makes a fresh robot of a kind, named and colored apart
from the battle's others: a second Walls is "Walls 2", with the next free
color. Each robot's rules are its own: customizing one leaves the kind,
and the other robots, alone. Every kind's rules pass the battle's checks
and end with a rule that always matches.

## Random robots

[RobotFactory](../roborules_app/lib/battle/random_robots.dart): a name and a
color not yet taken (24 names, 10 colors), and rules: usually "a wall ahead:
back off and turn" first, then two to five tactics in random order, each
with random numbers (fire when the enemy is in sight; stand and fire hard
when closer than 150–350 px; dodge across the line of fire when hit; run
under 20–50 energy; finish an enemy under 10–30; ram when closer than
80–150 px; cheap long shots beyond 300–500 px), then a fallback that always
matches (circle and sweep, head for the enemy, or circle it).

## The rules editor

Selecting a robot (or **Edit rules…** in New Battle) pauses a running battle and opens
[RulesEditor](../roborules_app/lib/ui/rules_editor.dart): the robot's
name and color, and three tabs:

- **Rules**: a card per rule: its conditions (**When**, a sensor and its
  test; **+ condition** adds one; true/false for yes/no sensors), its
  commands (**Then**: drive, turn, gun, fire), and **Why**; move a rule up
  or down, delete it, **Add rule** (before the fallback), and **Rules
  from…**, which replaces the rules with a predefined robot's or random
  ones (the name and color stay).
- **aityx model (JSON)**: the robot's model, one rule per line, editable;
  **Apply** reads it back, checking it as the battle would: the four
  command columns, each command one of its values, a fire power from 0 to
  3, known sensors; an error says what's wrong. **Copy**.
- **Sensors**: what each sensor means and how to write conditions.

**OK** keeps the changes; the battle uses them from its next batch of turns.
**Download** saves the robot as it stands in the editor as a
[file](#robot-files) (applying the JSON first on that tab), and
**Remove**, between battles, takes it out of the battle (from the battle
window; New Battle has its own **← Remove**).

## Robot files

[robot_files.dart](../roborules_app/lib/battle/robot_files.dart), saved
and picked with the browser's downloads and file picker
([lib/files/](../roborules_app/lib/files/); nothing outside a browser):

- **Download**: a robot is saved as its aityx model (above: it runs on
  aityx alone) with its `color` (`#rrggbb`) added, as `Name.robot.json`
  (**Download** in its rules);
  **Robot › Download all robots** saves the battle's robots as one file,
  `roborules-robots.json`, `{"robots": [...]}`.
- **Upload** (**Robot › Upload robots…**, or **Upload robots…** under the
  robots, between battles): one or more `.json` files, each a robot's
  model, a list of them or `{"robots": [...]}`, are added to the battle,
  up to ten robots. Each robot is checked as the rules editor's **Apply**
  checks it, has at most 100 rules, and is named and colored apart from
  the battle's others (a second Walls is "Walls 2"; its file's color when
  free, else the next free one; a name is cut to 40 characters). A file
  larger than 1 MB, one that isn't JSON or a robot, and robots beyond ten
  are left out, and a dialog says which and why; the robots that could be
  read are added.

