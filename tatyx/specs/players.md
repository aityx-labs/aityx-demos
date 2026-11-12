# Sign-in and keys

As in Poker Tour: players sign in with Google to play, the game runs on
**the player's own key**, kept in their browser with its URL (nobody
lends one), and the leaderboard plays on a **leaderboard key** of its
own, a different one for staging and production, which never leaves the
server.

## Signing in

Only signed-in players play: **Start** on the map and **Play** on the
title (which reads **Sign in to play** while signed out) open Profile
instead (and with no key of their own, both are greyed out). Anyone
may look at the title, the board and the leaderboard.

- **The Google client**: Google project `aletyxcode-tatyx` (tatyx's own,
  in the aletyx.com organization), its consent screen "tatyx",
  *External* and in production, so any Google account can sign in at
  Google's side, and its *Web application* client `tatyx-web`, whose
  authorized JavaScript origins are `http://localhost:9710` and
  `http://localhost:9711` (Vite's dev server); add any address it is
  served from. Its id, which is not a secret, is `TATYX_OIDC_CLIENT_ID`
  in the repository's root `.env`; the client's secret was never
  downloaded, since nothing needs it. Without an id, Profile says
  sign-in is not set up, and nobody can play.
- **In the browser** ([ui/auth.ts](../tatyx_app/src/ui/auth.ts)):
  Google's own button (Google Identity Services, loaded from
  `accounts.google.com` only when the server has a client id), in
  Profile. Its ID token goes once to `POST /api/session`.
- **On the server** ([tatyx_server/auth.mjs](../tatyx_server/auth.mjs)):
  the token is verified there, with no package: RS256 against Google's
  published keys (cached as long as Google says), the issuer, the
  audience (the client id), the expiry, a verified email, and the
  email's domain among `TATYX_ALLOWED_DOMAINS` (`*`, any, by
  default). Then a **session**: an HMAC-signed cookie,
  `tatyx_session` (`HttpOnly`, `SameSite=Strict`, `Secure` over https),
  for 30 days since the player's last visit (`GET /api/session` renews
  it, at most once a day), signed with `TATYX_SESSION_SECRET`, else the
  secret in `<data>/session-secret` (made on the first start, mode 600,
  ignored by git), so a restart keeps everyone signed in. The page never sees the
  token again, nor the cookie. `GET /api/session` says who is signed in;
  `DELETE /api/session` (Profile's **Sign out**) ends it. Admins, who
  may start a tournament now, are the `aletyx.com` and `aletyx.ai`
  players, whatever `TATYX_ALLOWED_DOMAINS` lets play: no setting
  widens them.

## Whose key, on which aityx

| | The players' games, in the browser | The leaderboard, on the server |
|---|---|---|
| The key | the player's own, set in Profile, kept in their browser; nothing else | `TATYX_LEADERBOARD_KEY` (else `AITYX_API_KEY`) on a laptop; `TATYX_PROD_LEADERBOARD_KEY`, a different key, deployed; never lent |
| On which aityx | the URL saved with the key (the field starts with this server's, `AITYX_URL`: staging on a laptop) | `AITYX_URL` (`AITYX_PROD_URL` deployed) |
| Who | players | the server, on its schedule or an admin's word |

The server never lends a key: `/api/config` names no key and says only
where its aityx is (`aityxUrl`) and the path that relays to it
(`aityxRelay`, `/aityx/`). A player's calls to that aityx go to `POST
/aityx/v1/systemone` on the game's own origin, with their own key as the
Authorization header, which the server passes on as it is, never logs
and never replaces (no header: 401); aityx staging takes no calls from
browsers, hence the relay. A key pointed at another aityx goes there
straight from the browser.

The player's key and its URL are kept in their browser (localStorage,
`aityx.key` and `aityx.url`, on the game's own origin) until **Forget**:
the URL saved with it, production's too, so the key keeps going where it
was checked, whatever the server's aityx later is. Signing out and the
server's restarts leave it as it is. The alias is the
server's (below), so it follows the player to any browser.

The leaderboard's keys are in the repository's root `.env`, each its
own: staging's `TATYX_LEADERBOARD_KEY`, for a laptop's server, and
production's `TATYX_PROD_LEADERBOARD_KEY`, for the deployment ([Deployment](deploy.md)),
which a local server never reads.

## Profile

The sidebar's third tab ([ui/shell.ts](../tatyx_app/src/ui/shell.ts)):

- **Account**: "Sign in to play." and Google's button; once
  signed in, the picture, the name, the email, an **admin** badge, and
  **Sign out**; what went wrong with a sign-in, in red (another domain's
  account, a token that didn't check out). **Your name on the
  leaderboard**: an alias, 32 characters at most, shown under the
  player's strategies there; the field starts with their name (their
  alias once they have one), and the name itself, or an empty field,
  means the name. Kept on the server, in
  the store's `players.json` (`<TATYX_DATA_DIR>/`, or the data bucket
  deployed), set with `PUT /api/me`.
- **Your aityx key**: which key the games run on, in a line (the
  player's own, or none, in red: every player brings their own), and
  the shared key form: the key; its URL, filled with this server's
  aityx, staging locally and production deployed, else the one saved
  with the key; **Save profile** and **Forget**. Where to get a key.
- **Save profile**, the profile's one button (Enter in the name does the
  same): it saves the name when it changed, then the key when it or its
  URL changed, checked first where the game will send it, through the
  relay for this server's aityx, and kept with its URL in this browser
  until **Forget**; an unchanged key spends no check. One line under it
  says what was saved, or why not.

The sidebar opens on Profile, and its tab wears a red dot, whenever
the player has no key of their own. A click on the aityx light opens it
too.

## Known limitations

- A player's key goes from the browser to aityx (through the relay for
  this server's aityx); the sign-in is asked by the page, not enforced
  by aityx or the relay, which spends only the caller's own key.
- A session can't be ended from the server before its 30 days: signing
  out clears the cookie in that browser only, and changing the secret
  (`TATYX_SESSION_SECRET`, or deleting `<data>/session-secret`) signs
  everyone out.
