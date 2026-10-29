@AGENTS.md

## Where things go

datyx is API only; its views are the dashboard, a folder of its own
([../datyx-dashboard/](../datyx-dashboard/)), and the two with HealthHub
are the datyx group, started and stopped together:

- **Data and logic go in the API**, [datyx-api/](datyx-api/) (Quarkus):
  entities and persistence, rules, anything computed or aggregated, and
  the endpoints that expose it. A new piece of information starts here.
- **Views go in the dashboard**, `../datyx-dashboard/datyx_dashboard/`
  (Flutter, like every demo's app): it invokes this API and shows what it
  answers. It never computes, stores or decides on its own; when a view
  needs data the API doesn't have, add it to the API first. Nothing of the
  dashboard lives in this folder: no Flutter, no web server, no nginx.
- Everything shared by this folder (the containers, scripts, settings,
  the version, Docker) stays at its root.

## Keep the specification up to date

After every user request, update the [specs/](specs/) folder in the same
change:

- Add a dated entry to [specs/requests.md](specs/requests.md) that says what
  was asked and what changed.
- Revise the feature specs the request touches, one file per feature (the
  index is [specs/README.md](specs/README.md)), so they describe the
  software as it is now. Add a feature file, and list it in the index, when a
  request adds a feature. Rewrite or delete statements the request made
  obsolete; don't just append.

## One pull request per change

Every new feature or bug fix starts on a **new branch from `main`**, with its
own pull request:

- Never commit or push directly to `main`.
- Don't bundle unrelated requests into one PR.
- Start from an up-to-date `main` (`git checkout main && git pull`). Stack on
  an unmerged branch only when the new work truly depends on it, and then
  target that branch.
- Include the matching `specs/` update in the same PR as the change.
