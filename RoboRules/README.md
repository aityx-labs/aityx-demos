# RoboRules

A web take on the old [Robocode](https://robocode.sourceforge.io/): tanks
fight on a dark battlefield until one is left. Here every robot's behavior
is an [aityx](https://aityx.ai) decision model, its rules a decision table
you can edit, and **the whole battle is played by aityx**: what each robot
senses, which of its rules fires, how it moves, turns, aims and fires,
where the bullets fly, who is hit or rams whom, damage, energy, who is lost,
and each round's score. The app only draws it.

Start with two random robots, or pick Robocode's sample robots (Walls,
SpinBot, Tracker, RamFire, Crazy…) written as rules: add and remove them,
select a robot to change its rules, and see which rules win, every event
and every aityx call in the log.

## How it works

- **A robot** is an aityx model: the 12 sensors (`enemy_distance`,
  `enemy_bearing`, `gun_bearing`, `enemy_in_sight`, `my_energy`,
  `enemy_energy`, `near_wall`, `wall_distance`, `gun_ready`, `was_hit`,
  `speed`, `enemies_left`) as inputs, and one decision, `action`, a FIRST
  table whose rules set four commands: `drive` (ahead, back, stop), `turn`
  (left, right, none, toward_enemy, away_from_enemy, perpendicular), `gun`
  (aim, sweep_left, sweep_right, hold) and `fire` (a power, 0 to 3). It runs
  on its own in aityx too. See [Robots](specs/robots.md).
- **The battle** is one more aityx model,
  [assets/models/world.json](roborules_app/assets/models/world.json), with each robot's
  table added as a function: every turn it computes each robot's sensors,
  calls its rules, and applies Robocode's physics. One call to aityx's
  `/v1/systemone` plays up to 50 turns and returns the world after each.
  See [The battle on aityx](specs/battle.md).
- **The score** of each round is a third model,
  [assets/models/scoring.json](roborules_app/assets/models/scoring.json), Robocode's way:
  50 for every robot you outlive, a last-survivor bonus, and your bullet
  damage. See [Scoring](specs/scoring.md).

The app calls aityx itself, from the browser: there is no API of its own.
It builds the battle's model from the world model and each robot's rules
([lib/aityx/battle.dart](roborules_app/lib/aityx/battle.dart)), sends it to
aityx's `/v1/systemone`, and draws the frames that come back, through the
repository's shared [aityx_web](../packages/aityx_web) package, which finds
the key and draws the aityx light.

| Part | Technology |
|---|---|
| App ([roborules_app/](roborules_app)) | [Flutter](https://flutter.dev) for the web, styled like Robocode's Swing window; calls aityx itself |
| Rules and physics | [aityx.ai](https://aityx.ai) decision models, the app's assets |
| Serving | The repository's index server ([Index/](../Index)), at `/roborules/` beside the other aityx demos |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/) |

## Your aityx key

Every battle runs on aityx, on your key: open the index page
(http://localhost:8800/), paste it in **Your aityx key** and choose **Check
and save**. Every demo on that origin uses it, RoboRules among them; the
app sends it straight to aityx and nowhere else. To get one, sign up at
[aityx.ai](https://aityx.ai), then create a key on the API keys page of
[console.aityx.ai](https://console.aityx.ai).

Without one, the index server's **dev key** works too: an `AITYX_API_KEY`
in the repository's `.env` (copy [../.env.example](../.env.example)), or
in its environment. The app then calls aityx through the index server's
`/aityx/` proxy, which adds the key, so it never reaches the browser.

The light at the top right of the window says which it is: green when
aityx accepts the key (yours, or the dev key), red with why otherwise, and
a tap on it opens the index page's key section.

## Run it locally

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/).
2. From the repository's root:

   ```bash
   ./start-aityx.sh RoboRules   # or ./start-aityx.sh for all six aityx demos
   ```

and open http://localhost:8800/roborules/ (set your key on
http://localhost:8800/ first, unless `.env` has a dev key). That builds
the app's release web build if it changed ([scripts/build.sh](scripts/build.sh),
about 25 s on a laptop, a minute or two on a 4-core codespace; nothing when
it's up to date) and starts the index server, which serves it. Stop it
with `./stop-aityx.sh`.

`bash scripts/build.sh` (or `devbox run build`) builds it ahead of time,
only when it changed: `flutter build web --release --base-href /roborules/
--no-web-resources-cdn`, which keeps CanvasKit on our own origin. `make`
builds it too ([scripts/make.sh](scripts/make.sh)); served anywhere but the
index server (a static host, or `flutter run`), there's no dev proxy, and
no key until one is saved on that origin.

`bash scripts/model-test.sh` plays scripted battles on aityx and checks
the physics against Robocode's rules, with the dev key from the root
`.env`; run it after changing the world model
([tool/build_world.py](roborules_app/tool/build_world.py) writes it).

## Run it in a codespace

[![Open RoboRules and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens the **aityx demos** dev container
([.devcontainer/aityx/](../.devcontainer/aityx)), which builds RoboRules
with the rest of the aityx group and starts the index page that serves
them all. It runs the aityx group's [published image](../image/),
`docker.io/aletyxcode/samples-and-demos-aityx`, which carries the
group's release web builds, so the codespace is available about three
minutes after you ask for it (a demo that changed since the image was made
builds itself, a minute or two). Once it has started, open port **8800**
from the **Ports** panel, paste your key in **Your aityx key**, and open
RoboRules' card (`/roborules/`). An `AITYX_API_KEY` Codespaces secret is
optional: it becomes the dev key every visitor of your codespace uses.
Stop the group with `./stop-all.sh` from the repository root and start it
again with `./start-all.sh`. If it doesn't start, send `startup.log` from
the root of the repository.

## Playing

- **Battle › New…** (or **New battle…**): how many robots (2 to 10, two by
  default) and rounds (1 to 10); the robots get random rules.
- **Start**, **Pause**/**Resume**, **Next turn** (while paused), **Stop**,
  **Restart**.
- **Speed**: how many turns a second to show, from 1 to 60, or **Max**, as
  fast as aityx plays them; the bar shows how fast that is.
- **Select a robot** on the right (or **Robot › Edit …'s rules**) to change
  its name, color and rules, as cards or as its aityx model's JSON.
- **aityx call** shows the last call: the battle model with every robot's
  rules, and the turns aityx played.
- When the last round ends, **Results** ranks the robots as Robocode did.

## Contributing

1. Create a branch from an up-to-date `main`.
2. Make one change per pull request, with its tests: `flutter analyze` and
   `flutter test` in `roborules_app/`, `bash scripts/build.sh`, and
   `bash scripts/model-test.sh` after changing a model.
3. Update the matching spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

*Robocode is an open-source project by Mathew Nelson and Flemming N.
Larsen; RoboRules borrows its look and its rules of motion and damage, not
its code.*
