# The sidebar and the profile

Signed in, the screen is the title and the table on the left and, on
the right, the window's whole height, a sidebar of three tabs
([TourSidebar](../pokertour_app/lib/tour/tour_sidebar.dart)):

1. **Leaderboard**: the tour's standings, compact (each strategy's name
   with its owner, by alias, beneath, or "template strategy" for a
   preset; wins, tournaments played),
   what the leaderboard is doing and when the next tournament is, and
   above the table **Play a tournament now** (an admin)
   ([The tour](tour.md)).
2. **aityx calls (n)**: every decision asked of aityx, and the hand log a
   switch away (**Calls** | **Hand log**) ([The aityx calls](calls.md)).
3. **Profile**: the account, the player's alias, the aityx key the table
   runs on, and their strategies in the tour (below).

On a window narrower than 1100 px the sidebar opens from the app bar's
sidebar icon, as a bottom sheet. The sidebar opens on **Leaderboard**,
and on **Profile**, turning to it, whenever the table has no aityx key
that works; its tab then shows a red crossed-out key. A tap on the aityx
light opens it too.

## Profile

([ProfilePanel](../pokertour_app/lib/tour/profile_panel.dart)) The
account (picture, name, email, an **admin** badge for the tour's
admins, **Sign out**), and under it **Your name on the leaderboard**: the
alias, up to 32 characters, filled with the player's name until they
set another; the name itself, or an empty field, means no alias. Then
**Your aityx key**:

- "Your table runs on it: your players, your strategies, your bots. Set
  yours to play."
- An amber note: "Use a key made for demos only. Never reuse a
  production key here."
- When there is none, or aityx rejects it, a red note says so ("There is
  no aityx key for your table yet. Set yours below to play.", "aityx
  rejected your key. Set a key that works below.").
- **Your key** (hidden, with a button to show it) and **URL
  (optional)**, filled with the URL in use (the player's own, else this
  server's aityx: https://api-stage.aityx.ai locally). A URL must be
  https.
- **Save profile**, the profile's one button (Enter in a field does the
  same), saves whatever changed: the name, when it differs from the
  saved one, and the key, when one is typed (or, for the key already
  saved, a new URL); one message says what was saved. With nothing to
  save and no key, it asks for one. With a key saved, **Forget my key**.

Last, **Your strategies in the tour**: the player's entries, each with a
remove button that withdraws it, and **Upload a strategy**, which enters
a strategy file ([The tour](tour.md)); "None yet" when there are none.

## Whose key, on which aityx

([PlayerKeys](../pokertour_app/lib/aityx/player_keys.dart)) The table
runs on the player's own key, or on none: the app never gets another,
and players never get the host's. Without a key that aityx accepts,
**Play** and **Step** are disabled ([The table](table.md)).

| | On a laptop | Deployed |
|---|---|---|
| This environment's aityx (`GET /api/config`'s `aityxUrl`) | https://api-stage.aityx.ai (`AITYX_URL`) | https://api.aityx.ai (`AITYX_PROD_URL`) |
| The player's key | theirs, on its URL, else this environment's | the same |
| The leaderboard (server side) | the server's `POKERTOUR_LEADERBOARD_KEY` | the leaderboard's key object ([On AWS](aws.md)) |

The player's own key and its URL are kept in the browser, Poker Tour's
own entries (`pokertour.aityx.key`, `pokertour.aityx.url`), in
localStorage. The URL the key was saved with is always stored (the
field's, which starts as this environment's), so the key keeps going
where it was saved for when the server's aityx changes; a key saved
before URLs were always kept follows this environment's. The alias is
the server's, in the tour's table, so it follows the player to any
browser. Signing out keeps the key and its URL; **Forget** removes
them.

aityx staging takes no calls from browsers (its CORS preflight answers
403), so on a laptop the app's calls to it go to the local server's
relay, `POST /aityx/v1/systemone` on the same origin
([aityx_relay.dart](../pokertour_api/lib/aityx_relay.dart), announced as
`aityxRelay` in `GET /api/config`), which forwards them to `AITYX_URL`
with the browser's own Authorization header: it adds no key, logs no
header, and relays nothing else. Deployed there is no relay: aityx
production takes browser calls. A key the player points at another
aityx goes there directly.

## Known limitations

- On a laptop the player's key passes through the local server, in
  memory, on its way to staging.
- The key check costs one request of the key's quota each time the key
  changes or the light checks.
