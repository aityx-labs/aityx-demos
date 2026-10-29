# Strategies

Each aityx pilot flies by a **strategy**, a list of rules: the first
whose tests all pass decides what the plane does
([strategy.dart](../riverrace_app/lib/strategy/strategy.dart)). On aityx
it is a FIRST decision table (see [Decisions](decisions.md)).

## Sensors

What a plane senses, the table's input columns; computed by the game
(`Race.sense`).

| Sensor | Kind | Meaning |
|---|---|---|
| `fuel` | number | Fuel left, 0 to 100 |
| `speed` | slow, normal, fast | How fast it flies |
| `land_ahead` | true/false | Land straight ahead within 48 rows |
| `land_distance` | number | Rows to land straight ahead (999 when none within 160) |
| `channel` | left, right, ahead | Where the open water is, 48 rows ahead |
| `room_left`, `room_right` | number | Water to either side, in pixels |
| `enemy_ahead` | true/false | A ship, helicopter or jet in the line of fire within 120 rows |
| `enemy_distance` | number | Rows to it (999 when none) |
| `threat` | none, left, right, ahead | An enemy about to collide, within 40 rows, and on which side |
| `fuel_ahead` | true/false | A fuel depot in the line of fire within 120 rows |
| `fuel_side` | none, left, right, ahead | Where the nearest depot ahead is, within 120 rows |
| `bridge_ahead` | true/false | The next bridge still stands, within 120 rows |
| `leading` | true/false | The plane is the furthest up |
| `missile_ready` | true/false | No missile of its own in the air |

## Commands

Each rule sets three, the table's outputs:

- `steer`: `to_channel` (toward the middle of the corridor of water it can
  follow ahead, leaning toward where the river bends), `to_fuel` (toward
  the nearest depot ahead, else as `to_channel`), `dodge` (away from the
  threat, toward the side with room, else as `to_channel`), `left`,
  `right`, `straight`. The game works out the direction every frame from
  the latest decision.
- `throttle`: `slow`, `normal`, `fast`.
- `fire`: true or false.

A rule without tests always matches. With no rule matching, the plane
flies straight on at normal speed without firing (the else row the API
adds).

## The strategies to pick

| Strategy | What it does |
|---|---|
| **Careful** (pilot 1 at the start) | Slow and steady: turns early for land, dodges and shoots threats, refuels below 45, shoots bridges and enemies ahead |
| **Daredevil** (pilot 2 at the start) | Full throttle: turns at 50 rows from land, swerves fast, refuels only below 25, shoots fuel depots for points |
| **Sharpshooter** | Fires whenever the missile is ready, but spares the depots |
| **Rookie** | One rule: straight ahead, firing. A start for writing your own |

## The pilot cards

Under the river, one card per aityx pilot, in its plane's color:

- The strategy's name (tap to rename), and **Strategy** to replace its
  rules with one of the above.
- The plane's score, planes left, bridges passed, times lost and what it
  is doing (flying slow/normal/fast, refueling, or lost and why), and its
  fuel gauge.
- The rules, numbered, each as `when fuel < 45 · fuel_side is left,
  right, ahead → to_fuel · slow · hold fire` with its why. The rule that
  fired in the last decision is outlined in the plane's color; *No rule
  matched* when none did.
- Each rule can be moved up or down, removed, or tapped to edit; **Add
  rule** adds one at the end (up to 40).

The rule editor has a test per sensor, blank for any: a number test (`<
40`, `>= 10`, `= 0` or `[10..50]`, checked as typed), *any/yes/no* for
true/false sensors, and word chips (none or all selected is any); then
`steer`, `throttle`, `fire`, and the why. Changes reach aityx with the
next decision, while the race goes on.

## Known limitations

- Strategies aren't saved: a reload starts with Careful and Daredevil.
- The tests are those a FIRST table cell takes; there is no `or` across
  sensors within one rule (write two rules).
