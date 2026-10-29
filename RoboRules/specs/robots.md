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
be written as `{"when": {...}, "then": {...}, "why": "..."}`. The API refuses
an unknown sensor, a missing command, a command value it doesn't know and a
fire power outside 0 to 3 ([lib/battle.dart](../roborules_api/lib/battle.dart)),
since aityx takes any word in an output column as a value.

## Predefined robots

[predefined_robots.dart](../roborules_app/lib/battle/predefined_robots.dart):
`robotKinds`, what a battle is made of: a **Random robot** (below) and
Robocode's sample robots written as rules, each with a name, a color, a
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

Selecting a robot (or **Robot › Edit …'s rules**, or **Edit rules…** in
New Battle) pauses a running battle and opens
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
