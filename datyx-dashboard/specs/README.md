# datyx-dashboard: software specification

The current specification of the datyx dashboard, one file per feature.
Update the feature files a request changes, and add a file when a request
adds a feature. [requests.md](requests.md) holds the history of requests
that shaped it. The API it shows is specified in
[../../datyx/specs/](../../datyx/specs/).

## Product

The datyx dashboard is the views of datyx: a Flutter web app that invokes
the datyx API and shows what it answers, with the details of each call.
Data and logic live in the API; the dashboard only asks and shows. It is
its own folder, started with the API and HealthHub as the datyx group.

## Features

- [The dashboard](dashboard.md): the Flutter app, what it shows and how it
  reaches the API.
- [App icon](app-icon.md): the database cylinder with its catalog, the
  web icons and the favicon.
- [Development environment](dev-environment.md): devbox, process-compose,
  Docker Compose, the ports, the settings, the version and the build.
