# Home

Where the user lands after signing in
([home_screen.dart](../healthhub_app/lib/screens/home_screen.dart)): a
dashboard of tiles under an app bar titled **HealthHub** with the
account corner.

- **The account corner** (`UserMenu`,
  [user_menu.dart](../healthhub_app/lib/auth/user_menu.dart)): the
  user's picture, name and a sign-out button. Signing out goes back to
  the [index](index.md).
- **The tiles**: a grid, each tile at most 720 px wide and 4:3, as many
  side by side as fit. A tile is a card with a header (an orange icon,
  the title and a status line) and its content filling the rest. For now
  there is one:
  - **Where you are**: the [map](map.md) with the user's position
    highlighted, the status line saying "The orange dot is you." or why
    there is no location.
- At the bottom, when the build has one, the version: `HealthHub X.Y.Z`.

## Known limitations

- One tile so far. The API still serves `/api/hello`, `/api/health` and
  the datyx routes, and the API client still has them, but no page shows
  them now.
