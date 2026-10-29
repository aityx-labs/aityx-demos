@AGENTS.md

## Where things go

The datyx dashboard is the views of datyx, and nothing else:

- **Views go here**, in [datyx_dashboard/](datyx_dashboard/) (Flutter, like
  every demo's app): it invokes the datyx API and shows what it answers,
  with the details of each call. It never computes, stores or decides on
  its own.
- **Data and logic go in the API**, [../datyx/](../datyx/) (Quarkus):
  entities and persistence, rules, anything computed or aggregated, and
  the endpoints that expose it. When a view needs data the API doesn't
  have, add it to the API first, in its own pull request.
- Everything shared by this folder (the services, scripts, settings, the
  version, Docker) stays at this folder's root.

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
