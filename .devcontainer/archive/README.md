# Archived dev containers

Dev container configurations that are no longer offered when you create a
codespace (GitHub lists only `.devcontainer/devcontainer.json` and
`.devcontainer/<name>/devcontainer.json`, one level deep), kept for
reference.

- [MortgageHub/](MortgageHub/): the original Mortgage Hub dev container,
  the one the others were copied from. It started only Mortgage Hub. The
  aityx group's dev container, [../aityx/](../aityx/devcontainer.json),
  replaced it: it starts the aityx demos, Mortgage Hub among them, and is
  what the Mortgage Hub badges open.

The per-demo dev containers that followed (Cellfie, Contact Hub,
HealthHub, PokerFace, RiverRace, RoboRules) and the all-demos default,
`.devcontainer/devcontainer.json`, were removed when the dev containers
were split by demo group (aityx and datyx); they are in git history.
  Its scripts still name `.devcontainer/MortgageHub/`, their original
  location, so it does not run from here as it is.
