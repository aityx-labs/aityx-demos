# Deciding on aityx

The app calls aityx from the browser, one systemone call per decision,
through the shared [aityx-js](../../packages/aityx_js/README.md) package,
the TypeScript twin of the Flutter demos' aityx_web: the same storage
entries (`aityx.key`, `aityx.url`), the same order, the same checks.

## The decision

The one decision in tatyx is a team's: **what its next megabyte buys**.
Whenever a team has a megabyte, no question pending and the match is
not paused, its strategy is asked ([play.ts](../tatyx_app/src/game/play.ts), `Match`), and the
answer is applied at once ([The game](game.md#buying-and-hacking)).

The **team model** ([models/team.json](../tatyx_app/src/game/models/team.json))
declares what a strategy sees, the team's situation
(`situation` in world.ts):

| Input | What it says |
|---|---|
| `seconds` | Since the start |
| `bytes_mb` | Unspent bytes (at least 1 when asked), in MB |
| `bots`, `hackers` | How many bots the team has, and how many of them it has sent to the mainframe |
| `anchors`, `builders`, `testers`, `combinators`, `explorers` | How many the team has at work, by kind (its hackers left out) |
| `sites_known`, `sites_held`, `sites_total` | Sites found, sites with the team's Anchor on them, sites on the map |
| `room_mb` | MB still to build on the sites the team knows that no other team holds |
| `links_known`, `links_rotting` | Live links the team knows, and those under a third of their health |
| `income_kbs` | KB/s the team is building, lately |
| `mainframe_connected` | Whether the origin reaches the mainframe over known links |
| `hack_pct`, `leader_pct` | The team's progress, and the best other team's |
| `threat` | Other teams' bots on sites the team knows |

A **strategy** ([strategies/*.json](../tatyx_app/src/game/strategies))
is the `build` decision on those inputs, a table tried top to bottom,
answering `anchor`, `builder`, `tester`, `combinator`, `explorer`,
`hack` (send a bot to the mainframe) or `save`, each row with a `why`;
in the shape of PokerFace's strategies. Five presets:

- **The Farmer** (Cyan to begin with): two Builders, two Anchors to hold
  their sites, two Testers to double them, a first bot into the hack as
  soon as the mainframe is in reach, then a third Builder, an Explorer
  when the mainframe is still out of reach, and the rest into the hack.
- **The Sprinter** (Magenta): a second Explorer until the way to the
  mainframe is open, a second Builder to pay for it, a second Tester to
  hold the way, then every bot it can into the hack.
- **The Swarm** (Green): three Combinators, three Builders, an Anchor or
  two, more Builders up to twelve bots, and the hack once it is well in
  or someone else gets close.
- **The Doubler**: a Tester beside every Builder, three pairs, then the
  hack; sooner if another team is halfway in.
- **The Fortress**: Anchors first, more when other teams' bots are on
  its sites, Builders behind them, a Tester when links rot, then the
  hack.

## A team's own strategy

On the title, each team's card shows its strategy, and **◀ ▶** step
through the presets ([lineup.ts](../tatyx_app/src/game/lineup.ts)).
**Download** saves the team's strategy as a JSON file (with a line on
how the table works, the inputs it may look at and the answers it may
give); **Upload** reads one back as the team's own, checked first: JSON,
a name of 1 to 60 characters, a `decisions.build.table` whose rules look
only at the team model's inputs and answer one of the builds, 64 KB at
most; what to fix is said on the card, in red. The lineup is kept in
this browser (`tatyx.lineup`, localStorage), and the match plays it.

The call sends `{"decision": {name, types, inputs, decisions}, "state":
situation}` ([strategy.ts](../tatyx_app/src/game/strategy.ts),
`buildRequest`), where the name is the team model's and the strategy's
("tatyx · a team's next megabyte · The Farmer"), and waits 30 s
([aityx.ts](../tatyx_app/src/game/aityx.ts)). From the answer it reads
`answers.build.choice`, and `receipt.decisions.build.rule`, the 1-based
row that fired, for its `why`.

`decideLocally` in strategy.ts takes the same decision from the table
itself, without aityx: what the tests and the headless match use, and
the only thing to compare aityx's answer against.

## Errors

A question that fails is shown in the panel and the team is asked again
in 15 s:

| When | Shown |
|---|---|
| no key | `aityx is not set up: set your key (the light, top right)` |
| aityx answers 401 or 403 | `aityx rejected the key` |
| no answer in 30 s, or the relay can't reach aityx | `aityx did not answer` |
| any other status | `aityx answered HTTP n: <detail>` |
| an answer without a `build`, or a `decision_error` | `aityx could not decide it: ...` |

## Where the key comes from

See [Sign-in and keys](players.md): the player's own key, kept in the
browser with its URL, else none: the light is red. Nobody lends one.
A key for this server's aityx (`/api/config`'s `aityxUrl`, staging on a
laptop) goes through the server's relay, `/aityx/v1/systemone` on the
game's own origin (`aityxRelay`), since aityx staging takes no calls
from browsers; the relay passes the player's Authorization header on,
never adds a key, answers this origin's pages only, forwards to an https
URL only and never follows a redirect. A key pointed at another aityx
(production's, on a laptop) goes there straight from the browser.

## The check

The light asks aityx whether it accepts the key without running a model:
an empty POST to systemone, which checks the key first, so a working key
gets 400 `invalid_request` ("ready"), a bad one 401 or 403 ("rejected"),
a relay that couldn't reach aityx 502 ("not reachable"), anything else
"not working". It checks on start, when the key changes (the dialog, or
another tab), and when the window regains focus, at most once every 30 s
for focus; never on a timer, since each check spends a request of the
user's quota.

## The calls panel

The sidebar's second tab, **aityx calls (n)**: every decision as it is
made, newest first, one line each: the team's colour, the match's clock,
the team and its strategy and what it bought (`Cyan · Farmer →
builder`), how long it took, and, on hover, the rule that fired and its
why; a failed one in red. A click opens the whole call: the request's
body and the answer, pretty-printed, with **Copy request** and **Copy
response**. The request's headers, where a key would be, are never
shown. A new match clears the list.

## Next

- A strategy editor in the app, with **Try it on aityx**, beside the
  upload.
- Scenarios on the real aityx, tagged, as PokerFace's `model-test.sh`.
