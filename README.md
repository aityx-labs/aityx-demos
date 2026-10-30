# aityx demos

Working examples of business automation with aityx: processes, decision
models, and applications built around them. Each folder is a self-contained
sample with its own documentation.

## aityx demos

The demos call [aityx.ai](https://aityx.ai) with your own API key, which
the codespace reads from a Codespaces secret. Set it up once, before
launching:

1. Sign up at [aityx.ai](https://aityx.ai).
2. In the [aityx console](https://console.aityx.ai), open the **API keys**
   page and copy a key.
3. Go to [github.com/settings/codespaces](https://github.com/settings/codespaces)
   and, under **Codespaces secrets**, choose **New secret**.
4. Name it exactly `AITYX_API_KEY` and paste the key as the value.
5. Under **Repository access**, select `aityx-labs/aityx-demos`, then
   choose **Add secret**.

Then open the demos in a codespace:

[![Open the aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

Six demos whose decisions run on [aityx.ai](https://aityx.ai), each an
app and an API. Dev container
[.devcontainer/aityx/](.devcontainer/aityx/devcontainer.json).

| Demo | What it shows |
|---|---|
| [Mortgage Hub](MortgageHub/) | A mortgage application from request to verdict: an app, an API, and a decision model run by [aityx.ai](https://aityx.ai) |
| [Contact Hub](ContactHub/) | Ask anything and have it routed to the right department or person. A request, typed or dictated on the device, routed by an aityx decision model: an app and an API |
| [Cellfie](Cellfie/) | The cells take a picture of themselves every generation, and aityx says who's in it: Conway's Game of Life on an infinite board, with the rules and pattern catalogue as an aityx decision model; one call per generation, with the board and every request and response shown in the app |
| [RiverRace](RiverRace/) | The 1982 Atari river shooter, remade with three planes up one river at once: two flown by aityx, each by its own editable rules, and one flown by you; every aityx call, sent and received, in a sidebar |
| [RoboRules](RoboRules/) | A web take on the old Robocode: robots whose behavior is an aityx decision model, fighting battles played turn by turn by aityx |
| [PokerFace](PokerFace/) | A poker simulator where every player is a set of rules run by [aityx.ai](https://aityx.ai): no-limit hold'em at a table of nine, every aityx call in a sidebar, the pace in your hands, and strategies you can read or write. An app and an API |

## Run all the demos

The demos that run as services, Mortgage Hub, Contact Hub and any other
folder with a `devbox.json` and a `process-compose.yaml`, start together
from the root of this repository with [Devbox](https://www.jetify.com/devbox):

```bash
./start-all.sh              # every demo, detached; waits until each answers
./start-aityx.sh            # the aityx demos: Mortgage Hub, Contact Hub, PokerFace, RoboRules, Cellfie, RiverRace, and their index
./start-all.sh ContactHub   # only the ones named
./stop-all.sh               # stops them all; ./stop-aityx.sh only the aityx demos
```

[start-all.sh](start-all.sh) runs `devbox services up -b` in each folder
and then prints where to open each app once its web app and API answer.
Each demo serves its app's release build and a compiled API, so a start
takes seconds once they are built; a demo whose build is missing or
older than its sources builds it first, a minute or two, one demo at a
time. [build-all.sh](build-all.sh) builds them all ahead, showing each
build. A demo that already answers on its port, started by hand or with
Docker Compose, is left as it is. The script checks for `AITYX_API_KEY` and
warns if it is missing; the apps still open, but their aityx-backed
features won't work. It passes `AITYX_API_KEY` and `AITYX_URL` from the
environment to each API service. API scripts prefer those values and
fall back to the demo's `.env`, which `start-all.sh` links to the one at
the root of the repository (see [.env.example](.env.example)): one key for
every demo. No `.env`, nor anything else git ignores, goes into a Docker
image: [sync-dockerignore.sh](sync-dockerignore.sh) copies the
`.gitignore` rules into every `.dockerignore`; run it after changing a
`.gitignore` or adding a Dockerfile (`--check` says whether one is stale).
`AITYX_URL` defaults to `https://api.aityx.ai`; a stage key needs
`AITYX_URL=https://api-stage.aityx.ai`. Watch one demo's services with
`devbox services attach -c <demo>`; [stop-all.sh](stop-all.sh) runs
`devbox services stop` in each folder that is running.

The same, in a codespace: its dev container, with its own image, starts
the index page and the demos on each start, as `./start-aityx.sh` would.
It needs your own `AITYX_API_KEY` Codespaces secret and,
optionally, an `AITYX_URL` secret (see [Launching it](#launching-it)
below).

| Dev container | Starts | Image | Machine |
|---|---|---|---|
| [aityx demos](.devcontainer/aityx/devcontainer.json) | Mortgage Hub, Contact Hub, Cellfie, RoboRules, RiverRace, PokerFace | `docker.io/aletyxcode/samples-and-demos-aityx` | 4-core, 16 GB |

Once it starts, the index page opens on port **8800** and links each
demo; the web apps are in the **Ports** panel too, made public so
the links can be shared. In the codespace, `./start-all.sh`, `./stop-all.sh` and
`./build-all.sh` act on the aityx demos only (`DEMOS_GROUP`, set by its
`devcontainer.json`). Every step of the start goes to `startup.log` at
the root.

### Ready when it opens: the published image

The dev container uses its own published image (built from
[image/Containerfile](image/Containerfile) by
`bash image/build-image.sh aityx`, see [image/](image/)): the toolchain,
process-compose, and **the release web build of each demo**. Creating a
codespace pulls it, copies the builds of the demos that haven't changed
since the image was made into the workspace (`onCreateCommand`) and
starts them (`postStartCommand`); a demo that did change builds itself,
a minute or two on 4 cores, while the others are already up. GitHub's
prebuilds and Actions are switched off for this organization, so the
image is built on a laptop and pushed after merging to `main`; an old
image slows a changed demo down but breaks nothing. The demos run on the
image's own toolchain (`DEMOS_TOOLCHAIN=image`, see
[demos-toolchain.sh](demos-toolchain.sh)); devbox is for a laptop.

## Mortgage Hub

[MortgageHub/](MortgageHub/) brings a home buyer's mortgage, from
application to closing, into one place. A buyer fills in a proposal
request, and a regulatory check says whether a lender can process it under
current US rules — Fannie Mae's eligibility matrix, the 2026 FHFA and FHA
limits, FHA, VA and USDA rules and DTI limits — executed as a decision
model on [aityx.ai](https://aityx.ai).

| Part | Technology |
|---|---|
| App | Web, Android, iOS and Linux from one codebase |
| API | Holds the [aityx](https://aityx.ai) key and runs the check |
| Rules | An [aityx.ai](https://aityx.ai) decision model |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) in a [dev container](https://containers.dev/) |

### Launching it

**You need your own [aityx.ai](https://aityx.ai) API key.** No key ships
with this repository. Without one the codespace still starts and the app
still opens, but the regulatory check — the point of the demo — cannot run.

Add it before launching: go to
[github.com/settings/codespaces](https://github.com/settings/codespaces),
choose **New secret** under *Codespaces secrets*, name it exactly
`AITYX_API_KEY`, paste your own key, and give it access to this repository.
For a non-default endpoint, add an `AITYX_URL` secret and set it to
`https://api-stage.aityx.ai` for a stage key; leave it unset to use
`https://api.aityx.ai`. Give it access to this repository too. The
[Mortgage Hub README](MortgageHub/README.md#run-it-in-a-codespace) shows
the secret setup and codespace creation. The dev container
passes both values to each API service; they are not written to disk or logged.
The same secrets can be used for every demo.

Then launch the demos with the badge under
[aityx demos](#aityx-demos-1) at the top. That opens its dev container, **aityx demos**, on a 4-core
machine (16 GB RAM): it starts Mortgage Hub with the other aityx demos
and the index page. If you create the codespace yourself through *Code →
Codespaces → New with options*, choose **aityx demos** as the dev
container configuration.

Once it starts, the apps start too: when Mortgage Hub answers, seconds
from the image, or after its build, open port **8880** from the **Ports**
panel, or from its card on the index page (port **8800**, opened for
you). Check that the port's visibility says **Public**, so the link can
be shared; if it says Private, right-click it and choose **Port
Visibility → Public**. The full instructions, including running it
without a codespace, are in the
[Mortgage Hub README](MortgageHub/README.md).

### Running it locally

Put your key in the root `.env` (copy [.env.example](.env.example)) or export
`AITYX_API_KEY`. Then, from the root of this repository, either:

```bash
# With Docker alone: builds the web app and the API, then starts both
docker compose -f MortgageHub/compose.yaml up --build

# Or with Devbox: the app's release build, the compiled API and a health monitor
devbox services up -c MortgageHub --pcflags "--tui=false"
```

Both serve the app at http://localhost:8880/app/. Stop them with
`docker compose -f MortgageHub/compose.yaml down` or
`devbox services stop -c MortgageHub`.

## Contact Hub

[ContactHub/](ContactHub/) will let someone ask anything and route the
question to the right department or person, with its checks run on the
way. Built like Mortgage Hub: an app takes the request (typed,
dictated with speech recognized in the browser, or picked from samples),
and an API routes it with one aityx call, in which Jev classifies and
checks the message and a decision model picks the department, the person
and the priority. The app shows why, and the aityx call, with links to
exactly the JSON behind each item. Put your key in the root `.env`
(see [.env.example](.env.example)), then, from the root of this
repository:

```bash
devbox services up -c ContactHub --pcflags "--tui=false"
# or, with Docker alone
docker compose -f ContactHub/compose.yaml up --build
```

Both serve the app at http://localhost:8890/app/, so it runs alongside
Mortgage Hub. The badge above opens it in a codespace, which uses the same
`AITYX_API_KEY` Codespaces secret as Mortgage Hub. See the
[Contact Hub README](ContactHub/README.md).

## Cellfie

[Cellfie/](Cellfie/) plays Conway's Game of Life on an infinite board,
with the rules and pattern catalogue run as an aityx decision model.
Each generation is one aityx call: the app sends the board's situations
and clusters, displays the next generation, labels recognized patterns,
and shows the full request and response in a side panel. Choose a random
soup, islands, a glider fleet, a pattern zoo or a methuselah, then play
at a chosen acceleration or step one generation at a time. The rule
switches include Conway, HighLife and Life without death.

Put your `AITYX_API_KEY` in the root `.env` for local use (see
[.env.example](.env.example)), or use the Codespaces
secrets described above. To start it locally from the repository root:

```bash
devbox services up -c Cellfie --pcflags "--tui=false"
# or, with Docker alone
docker compose -f Cellfie/compose.yaml up --build
```

Both serve the app at http://localhost:8930/app/, alongside the other
samples. See the [Cellfie README](Cellfie/README.md).

## RiverRace

[RiverRace/](RiverRace/) remakes the 1982 Atari river shooter: a river
with banks, islands and bridges, tankers, helicopters, jets and fuel
depots, fuel that runs out, and points for what you shoot. Three planes
fly up the same river at once: two are flown by aityx, each by its own
strategy, a decision table of rules you can add to, change and remove
while they fly, and the yellow one is yours (arrow keys and space). Every
few frames one aityx call decides what both aityx pilots do; the side
panel shows each call, sent and received, and the rule that fired.

To start it locally from the repository root:

```bash
devbox services up -c RiverRace --pcflags "--tui=false"
# or, with Docker alone
docker compose -f RiverRace/compose.yaml up --build
```

Both serve the app at http://localhost:8940/app/. See the
[RiverRace README](RiverRace/README.md).

## RoboRules

[RoboRules/](RoboRules/) is a web take on the old Robocode, in its look:
tanks fight on a dark battlefield until one is left. Each robot's behavior
is an aityx decision model, a table of rules over what it senses (the
nearest enemy's distance and bearing, walls, energy, its gun) that sets how
it drives, turns, aims and fires; pick Robocode's sample robots or random
ones, and select a robot to change its rules. The battle itself is played by aityx: one call plays up to 50 turns of sensing,
every robot's rules, Robocode's motion, bullets, collisions and damage, and
another scores each round. Put your key in the root `.env`, then:

```bash
devbox services up -c RoboRules --pcflags "--tui=false"
# or, with Docker alone
docker compose -f RoboRules/compose.yaml up --build
```

and open http://localhost:8920/app/. Its ports are its own, so it runs at
the same time as Mortgage Hub (8880) and Contact Hub (8890). See the
[RoboRules README](RoboRules/README.md).

## PokerFace

[PokerFace/](PokerFace/) is a poker simulator, no-limit Texas hold'em at
a table of up to nine, where every player is a set of rules: a decision
model run on [aityx.ai](https://aityx.ai) at each turn, on the player's
situation as the app computes it (cards, hand, equity, pot odds,
position, a random number for mixed play). Five strategies come with it,
the Rock, the Maniac, the Calling Station, the Mathematician and the
Shark, each a file of rules; add players with any of them, read the
rules, or write your own. The table plays like an online poker room, a
sidebar shows every call to aityx with its request and response, and a
slider sets the pace. Put your key in the root `.env` (see
[.env.example](.env.example)), then, from the root of this
repository:

```bash
devbox services up -c PokerFace --pcflags "--tui=false"
# or, with Docker alone
docker compose -f PokerFace/compose.yaml up --build
```

Both serve the app at http://localhost:8910/app/, alongside the other
samples. The badge above opens it in a codespace, with the same
`AITYX_API_KEY` Codespaces secret. See the
[PokerFace README](PokerFace/README.md).

## License

[MIT](LICENSE).
