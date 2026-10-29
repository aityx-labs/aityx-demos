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
  [models/world.json](roborules_api/models/world.json), with each robot's
  table added as a function: every turn it computes each robot's sensors,
  calls its rules, and applies Robocode's physics. One call to aityx's
  `/v1/systemone` plays up to 50 turns and returns the world after each.
  See [The battle on aityx](specs/battle.md).
- **The score** of each round is a third model,
  [models/scoring.json](roborules_api/models/scoring.json), Robocode's way:
  50 for every robot you outlive, a last-survivor bonus, and your bullet
  damage. See [Scoring](specs/scoring.md).

| Part | Technology |
|---|---|
| App ([roborules_app/](roborules_app)) | [Flutter](https://flutter.dev) for the web, styled like Robocode's Swing window |
| API ([roborules_api/](roborules_api)) | Dart (`dart:io`): holds the [aityx](https://aityx.ai) key, builds the battle model and plays turns on aityx |
| Rules and physics | [aityx.ai](https://aityx.ai) decision models |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) on a laptop, or a [Dev Container](https://containers.dev/) from the [published image](../image/), process-compose for the services either way; or [Docker Compose](compose.yaml) |

## Run it locally with devbox

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/).
2. Put your [aityx](https://aityx.ai) key in `.env` (copy
   [.env.example](.env.example)), the same `AITYX_API_KEY` as the other
   samples': `grep '^AITYX_' ../MortgageHub/.env > .env`. Every battle runs
   on aityx, so it's required.
3. From this folder:

   ```bash
   devbox services up           # add --pcflags "--tui=false" when not in a terminal
   ```

and open http://localhost:8920/app/. The API answers on
http://localhost:8921. The ports are RoboRules' own, so it runs alongside
the other samples (Mortgage Hub 8880/8881, Contact Hub 8890/8891).

That serves the app's release build with a small native web server
([scripts/flutter-web.sh](scripts/flutter-web.sh)) and the API compiled to
a native executable ([scripts/api.sh](scripts/api.sh)), what Docker
Compose serves too, and it keeps the machine free: the two servers hold
about 27 MB between them. The first start builds them (about 25 s on a
laptop, a minute or two on a 4-core codespace); later starts reuse the
builds until something changes, and are up in a second or two. For hot
reload while working on the app, run the Flutter dev server instead, with
`WEB_MODE=debug devbox services up`, or on its own with `devbox run web`
(press `r` in its terminal). `devbox run build` builds the web build and
the executables ahead of time ([scripts/build.sh](scripts/build.sh)), only
what changed. Stop everything with `devbox services stop`.

`bash scripts/model-test.sh` plays scripted battles on aityx and checks
the physics against Robocode's rules; run it after changing the world
model ([tool/build_world.py](roborules_api/tool/build_world.py) writes
it).

## Run it with Docker Compose

```bash
docker compose up --build
```

and open http://localhost:8920/app/; set `FLUTTER_WEB_PORT` for another
port. The key comes from your environment or `.env`.

## Run it in a codespace

[![Open RoboRules and the other aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens the **aityx demos** dev container
([.devcontainer/aityx/](../.devcontainer/aityx)), which starts RoboRules
with the rest of the aityx group and the index page that links them.
The codespace uses your `AITYX_API_KEY` Codespaces secret, the same as the
other samples'. It runs the aityx group's [published image](../image/),
`docker.io/aletyxcode/samples-and-demos-aityx`, which carries the
group's release web builds, so the codespace is available about three
minutes after you ask for it and the apps answer within a minute after
that (a demo that changed since the image was made builds itself, a
minute or two). Once it has started, open port **8920** from the
**Ports** panel, or RoboRules' card on the index page (port 8800).
Watch the services with `process-compose attach -U -u
/tmp/aityx-demos-RoboRules.sock`, stop the group with `./stop-all.sh`
from the repository root and start it again with `./start-all.sh` (in
the codespace both act on the aityx group only); there is no devbox in
a codespace. If it doesn't start, send `startup.log` from the root of
the repository.

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
   `flutter test` in `roborules_app/`, `dart analyze` and `dart test` in
   `roborules_api/`, and `bash scripts/model-test.sh` after changing a
   model.
3. Update the matching spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

*Robocode is an open-source project by Mathew Nelson and Flemming N.
Larsen; RoboRules borrows its look and its rules of motion and damage, not
its code.*
