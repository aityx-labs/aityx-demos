# aityx demos

Working examples of business automation with aityx: processes, decision
models, and applications built around them. Each folder is a self-contained
sample with its own documentation.

## aityx demos

The demos call [aityx.ai](https://aityx.ai) with your own API key, which
you set once, in your browser, on their index page:

1. Sign up at [aityx.ai](https://aityx.ai).
2. In the [aityx console](https://console.aityx.ai), open the **API keys**
   page and copy a key.
3. Open the demos (in a codespace, with the badge below, or on your own
   machine, see [Run all the demos](#run-all-the-demos)): the index page
   opens.
4. Paste the key in **Your aityx key** and choose **Check and save**.

Every demo, on the same address as the index, uses it from then on. It
stays in your browser ("Remember on this device", or "Only this
session"), and each app calls aityx with it directly.

[![Open the aityx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Faityx%2Fdevcontainer.json&machine=standardLinux32gb)

Six demos whose decisions run on [aityx.ai](https://aityx.ai), each a
Flutter web app that calls aityx from the browser, all served by the
[index](Index/) on one port. Dev container
[.devcontainer/aityx/](.devcontainer/aityx/devcontainer.json).

| Demo | Path | What it shows |
|---|---|---|
| [Mortgage Hub](MortgageHub/) | `/mortgagehub/` | A mortgage application from request to verdict: an app and a decision model run by [aityx.ai](https://aityx.ai) |
| [Contact Hub](ContactHub/) | `/contacthub/` | Ask anything and have it routed to the right department or person. A request, typed or dictated on the device, routed by an aityx decision model |
| [Cellfie](Cellfie/) | `/cellfie/` | The cells take a picture of themselves every generation, and aityx says who's in it: Conway's Game of Life on an infinite board, with the rules and pattern catalogue as an aityx decision model; one call per generation, with the board and every request and response shown in the app |
| [RiverRace](RiverRace/) | `/riverrace/` | The 1982 Atari river shooter, remade with three planes up one river at once: two flown by aityx, each by its own editable rules, and one flown by you; every aityx call, sent and received, in a sidebar |
| [RoboRules](RoboRules/) | `/roborules/` | A web take on the old Robocode: robots whose behavior is an aityx decision model, fighting battles played turn by turn by aityx |
| [PokerFace](PokerFace/) | `/pokerface/` | A poker simulator where every player is a set of rules run by [aityx.ai](https://aityx.ai): no-limit hold'em at a table of nine, every aityx call in a sidebar, the pace in your hands, and strategies you can read or write |

## Run all the demos

From the root of this repository, with [Devbox](https://www.jetify.com/devbox):

```bash
./start-aityx.sh            # the six aityx demos, on http://localhost:8800/
./start-all.sh              # every demo, the datyx group too
./start-aityx.sh ContactHub # only the ones named (and the index)
./stop-aityx.sh             # stops them; ./stop-all.sh stops everything
```

Then open http://localhost:8800/, set your key in **Your aityx key**,
and open a demo from its card, or at its path:
http://localhost:8800/mortgagehub/, /contacthub/, /pokerface/,
/roborules/, /cellfie/, /riverrace/.

[start-all.sh](start-all.sh) builds each aityx demo's release web build
whose build is missing or older than its sources (its `scripts/build.sh`,
a minute or two, one demo at a time; up to date, a second or two), then
starts the index ([Index/](Index/)), which serves the page and the six
apps, and prints each demo's link once it answers. The demos have no
servers of their own. [build-all.sh](build-all.sh) builds them all ahead,
showing each build. Watch the index with
`devbox services attach -c Index`; [stop-all.sh](stop-all.sh) stops it.

**A dev key.** Without a key of your own in the browser, the apps ask the
index server whether it has one: `AITYX_API_KEY` in its environment, or
in the root `.env` (copy [.env.example](.env.example)). If it does, it
lends it through its own proxy, so the key never reaches the browser,
and the demos work with nothing set on the page. `AITYX_URL` defaults to
`https://api.aityx.ai`. The same `.env` key runs each demo's
`scripts/model-test.sh`, the tests that call aityx. No `.env`, nor
anything else git ignores, goes into a Docker image:
[sync-dockerignore.sh](sync-dockerignore.sh) copies the `.gitignore`
rules into every `.dockerignore`; run it after changing a `.gitignore` or
adding a Dockerfile (`--check` says whether one is stale).

The same, in a codespace: its dev container, with its own image, starts
the index, which serves the six demos, on each start, as
`./start-aityx.sh` would.

| Dev container | Starts | Image | Machine |
|---|---|---|---|
| [aityx demos](.devcontainer/aityx/devcontainer.json) | Mortgage Hub, Contact Hub, Cellfie, RoboRules, RiverRace, PokerFace | `docker.io/aletyxcode/samples-and-demos-aityx` | 4-core, 16 GB |

Once it starts, the index page opens on port **8800**, the only port,
made public so the link can be shared: each visitor sets their own key on
it. Optionally, an `AITYX_API_KEY` Codespaces secret is a dev key every
visitor of your codespace uses unless they set their own (see
[Launching it](#launching-it) below). In the codespace, `./start-all.sh`,
`./stop-all.sh` and `./build-all.sh` act on the aityx demos only
(`DEMOS_GROUP`, set by its `devcontainer.json`). Every step of the start
goes to `startup.log` at the root.

### Ready when it opens: the published image

The dev container uses its own published image (built from
[image/Containerfile](image/Containerfile) by
`bash image/build-image.sh aityx`, see [image/](image/)): the toolchain,
process-compose, and **the release web build of each demo**. Creating a
codespace pulls it, copies the builds of the demos that haven't changed
since the image was made into the workspace (`onCreateCommand`) and
starts the index (`postStartCommand`); a demo that did change builds
itself, a minute or two on 4 cores, while the others are already up.
GitHub's prebuilds and Actions are switched off for this organization, so
the image is built on a laptop and pushed after merging to `main`; an old
image slows a changed demo down but breaks nothing. The demos are built
with the image's own toolchain (`DEMOS_TOOLCHAIN=image`, see
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
| App | Web, Android, iOS and Linux from one codebase; on the web it calls aityx itself, with your key |
| Rules | An [aityx.ai](https://aityx.ai) decision model |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) in a [dev container](https://containers.dev/) |

### Launching it

**You need your own [aityx.ai](https://aityx.ai) API key.** No key ships
with this repository. Without one the app still opens, but the
regulatory check, the point of the demo, cannot run.

Launch the demos with the badge under [aityx demos](#aityx-demos-1) at
the top. That opens its dev container, **aityx demos**, on a 4-core
machine (16 GB RAM): it starts the index, which serves Mortgage Hub with
the other aityx demos. If you create the codespace yourself through
*Code → Codespaces → New with options*, choose **aityx demos** as the dev
container configuration. When the index page opens (port **8800**), paste
your key in **Your aityx key**, then open Mortgage Hub from its card, at
`/mortgagehub/` on the same address. Check that port 8800's visibility
says **Public**, so the link can be shared; if it says Private,
right-click it in the **Ports** panel and choose **Port Visibility →
Public**. Anyone you share it with sets their own key.

Optionally, before launching, add a dev key: at
[github.com/settings/codespaces](https://github.com/settings/codespaces),
choose **New secret** under *Codespaces secrets*, name it exactly
`AITYX_API_KEY`, paste your own key, and give it access to this
repository. The index server then lends it, through its own proxy, to
every visitor of your codespace who hasn't set a key of their own; it is
never written to disk, logged, or sent to a browser. An `AITYX_URL`
secret sets its endpoint (`https://api.aityx.ai` when unset). The full
instructions are in the [Mortgage Hub README](MortgageHub/README.md).

### Running it locally

From the root of this repository:

```bash
./start-aityx.sh MortgageHub
```

builds the app if it is stale and serves it, with the index, at
http://localhost:8800/mortgagehub/. Set your key on the index page,
http://localhost:8800/, or put a dev key in the root `.env` (copy
[.env.example](.env.example)). Stop it with `./stop-aityx.sh`.

## Contact Hub

[ContactHub/](ContactHub/) will let someone ask anything and route the
question to the right department or person, with its checks run on the
way. Built like Mortgage Hub: an app takes the request (typed,
dictated with speech recognized in the browser, or picked from samples),
and routes it with one aityx call, in which Jev classifies and checks the
message and a decision model picks the department, the person and the
priority. The app shows why, and the aityx call, with links to exactly
the JSON behind each item. From the root of this repository:

```bash
./start-aityx.sh ContactHub
```

serves it at http://localhost:8800/contacthub/, beside the others, with
the key you set on the index page. The badge above opens it in a
codespace. See the [Contact Hub README](ContactHub/README.md).

## Cellfie

[Cellfie/](Cellfie/) plays Conway's Game of Life on an infinite board,
with the rules and pattern catalogue run as an aityx decision model.
Each generation is one aityx call: the app sends the board's situations
and clusters, displays the next generation, labels recognized patterns,
and shows the full request and response in a side panel. Choose a random
soup, islands, a glider fleet, a pattern zoo or a methuselah, then play
at a chosen acceleration or step one generation at a time. The rule
switches include Conway, HighLife and Life without death.

To start it locally from the repository root:

```bash
./start-aityx.sh Cellfie
```

and open http://localhost:8800/cellfie/, with the key you set on the
index page. See the [Cellfie README](Cellfie/README.md).

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
./start-aityx.sh RiverRace
```

and open http://localhost:8800/riverrace/. See the
[RiverRace README](RiverRace/README.md).

## RoboRules

[RoboRules/](RoboRules/) is a web take on the old Robocode, in its look:
tanks fight on a dark battlefield until one is left. Each robot's behavior
is an aityx decision model, a table of rules over what it senses (the
nearest enemy's distance and bearing, walls, energy, its gun) that sets how
it drives, turns, aims and fires; pick Robocode's sample robots or random
ones, and select a robot to change its rules. The battle itself is played by aityx: one call plays up to 50 turns of sensing,
every robot's rules, Robocode's motion, bullets, collisions and damage, and
another scores each round. From the root of this repository:

```bash
./start-aityx.sh RoboRules
```

and open http://localhost:8800/roborules/, beside the other demos. See
the [RoboRules README](RoboRules/README.md).

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
slider sets the pace. From the root of this repository:

```bash
./start-aityx.sh PokerFace
```

serves it at http://localhost:8800/pokerface/, alongside the other
demos, with the key you set on the index page. The badge above opens it
in a codespace. See the [PokerFace README](PokerFace/README.md).

## License

[MIT](LICENSE).
