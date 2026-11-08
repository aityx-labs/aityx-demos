# poker_core

Poker Tour's engine and table logic as a pure Dart package, so the
Flutter app ([../pokertour_app](../pokertour_app)) and the server
([../pokertour_api](../pokertour_api)), which runs the leaderboard's
tournaments, play the same game:

- `engine/`: cards, the hand evaluator and the game (the deal, the
  betting rounds, side pots, the showdown, blind levels, eliminations).
- `table.dart`: a strategy (its rules), the models (the table and the
  presets, from their JSON), the checks on a situation, the body of one
  decision's call to aityx and the action read from its answer.
- `sample.dart`: the situation strategies are tried on.

The models themselves are the app's assets,
[../pokertour_app/assets/models/](../pokertour_app/assets/models): the
tests read them from there, and so does the server.

```sh
dart pub get
dart analyze
dart test
```
