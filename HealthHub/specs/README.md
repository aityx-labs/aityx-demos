# HealthHub — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

HealthHub is a demo built like Mortgage Hub, Contact Hub and PokerFace,
with one more part: a PostgreSQL database. For now the app is a map: the
index, for someone not signed in, shows where they are with a welcome
over it; home, after signing in, is a dashboard whose one tile is the
same map. What HealthHub does, and what aityx decides in it, is still to
be specified.

## Features

**App**

- [Index](index.md): the page for someone not signed in, the map with
  the welcome over it and the sign-in; and which page the app shows.
- [Home](home.md): after signing in, the dashboard of tiles, for now the
  map.
- [The map](map.md): OpenStreetMap's tiles, darkened, with the user's
  location highlighted; how the location is asked for.
- [Theme](theme.md): the aityx dark palette.
- [App icon](app-icon.md): the heart with the pulse line, the launcher
  icons and the favicon.

**Backend**

- [API](api.md): `healthhub_api`, a Dart server that holds the aityx key,
  talks to PostgreSQL and serves `GET /api/hello` and `GET /api/health`.
- [Database](database.md): PostgreSQL as a container, the `healthhub`
  database and user, the `greetings` table the API makes.

**Project**

- [Development environment](dev-environment.md): devbox, process-compose,
  Docker for the database, the health monitor, the builds, Docker Compose
  and the dev container.

## Workflow

- Every new feature or bug fix starts on a new branch from `main`, with its
  own pull request. Nothing is pushed directly to `main`. See
  [CLAUDE.md](../CLAUDE.md).
- Every request updates the affected feature specs and the
  [request log](requests.md) in the same PR.
- Each feature file ends with its own **Known limitations**, where it has
  any.
