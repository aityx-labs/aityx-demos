# Index

The page for someone not signed in
([index_screen.dart](../healthhub_app/lib/screens/index_screen.dart)):
the [map](map.md) fills the screen, with the user's location
highlighted, and a card floats over its top, at most 440 px wide:

- A heart in the aityx orange and **Welcome to HealthHub**.
- One line on the location: "Finding where you are…" while the browser
  or the device answers, "The orange dot is you." once it has, or why
  there is none ("Allow location access to see where you are.",
  "Location services are off on this device.") with a **Try again**
  button.
- While the API wants a user, Google's own sign-in button, and the
  error under it when signing in fails. Nothing while sign-in is off.
- At the bottom, when the build has one, the version:
  `HealthHub X.Y.Z` (the `HEALTHHUB_VERSION` dart-define, see
  [Development environment](dev-environment.md)).

Signing in leads [home](home.md); signing out there comes back here.

`HealthHubApp` ([main.dart](../healthhub_app/lib/main.dart)) picks the
page: home once someone is signed in, or when the API has sign-in off
(there is nobody to wait for); the index otherwise, also while
`GET /api/auth/config` hasn't answered.

## Sign-in

`AuthController` ([lib/auth/](../healthhub_app/lib/auth/)) reads
`GET /api/auth/config` at start (asked again, 3 s then up to 30 s apart,
while the API doesn't answer), initializes `google_sign_in` with the
client id the API publishes, tries a silent sign-in, and hands the ID
token to the API client, which sends it as a bearer on every call and
retries once with a fresh one after a 401.

The ID token is kept in the browser tab's session storage
([lib/persist/](../healthhub_app/lib/persist/); memory off the web)
until it expires or the user signs out, so a reload stays signed in
without asking Google again. It is read as the app starts, so a reload
opens home at once; when the API's configuration comes, a token issued
for another client id, or any token while sign-in is off, is dropped. A
token within a minute of its expiry is renewed with a silent sign-in
before the next call; when Google can't renew it, the user is signed out
and the index shows the sign-in. A new tab, or a closed and reopened
browser, signs in again.

## Known limitations

- Nothing on the index but the map and the welcome, for now.
