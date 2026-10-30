# cellfie_app

The Cellfie app, in Flutter (web, Android, iOS and Linux from one
codebase): the infinite board ([lib/life/](lib/life/)), its controls, the
side panel with every call to aityx ([lib/calls/](lib/calls/)), and the
calls themselves ([lib/aityx/](lib/aityx/)), made from the browser through
the shared package [aityx_web](../../packages/aityx_web/README.md) with
the Life model in [assets/models/life.json](assets/models/life.json).

Build it with `bash ../scripts/build.sh` (or `make`, see the [project
README](../README.md)); the index server serves it at
http://localhost:8800/cellfie/. Test it here with `flutter analyze` and
`flutter test`; `bash ../scripts/model-test.sh` runs the tests tagged
`aityx` on aityx itself. `dart run tool/catalogue.dart` rewrites the
pattern catalogue in the model from the seeds in
[lib/life/seeds.dart](lib/life/seeds.dart).
