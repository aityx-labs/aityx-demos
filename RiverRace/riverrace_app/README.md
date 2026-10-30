# riverrace_app

The RiverRace app, in Flutter (web, Android, iOS and Linux from one
codebase): the game ([lib/game/](lib/game/)), the aityx pilots'
strategies and their cards ([lib/strategy/](lib/strategy/)), the race
screen ([lib/race_screen.dart](lib/race_screen.dart)), the side panel
with every call to aityx ([lib/calls/](lib/calls/)), and the request sent
to aityx and the actions read back ([lib/aityx/](lib/aityx/), with the
model in [assets/models/](assets/models/)). It calls aityx itself, through
the shared package [aityx_web](../../packages/aityx_web/README.md).

Build it for the index server with `bash ../scripts/build.sh`, or with
`make` (see the [project README](../README.md)). Test it here with
`flutter analyze` and `flutter test`; `bash ../scripts/model-test.sh` runs
the tests that call aityx.
