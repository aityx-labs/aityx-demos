# cellfie_app

The Cellfie app, in Flutter (web, Android, iOS and Linux from one
codebase): the infinite board ([lib/life/](lib/life/)), its controls, and
the side panel with every call to aityx ([lib/calls/](lib/calls/)).

Run it from the repo with `devbox services up` or `devbox run web`, and
build it with `make` (see the [project README](../README.md)). Test it
here with `flutter analyze` and `flutter test`. `dart run
tool/catalogue.dart` rewrites the pattern catalogue in the API's model
from the seeds in [tool/catalogue.dart](tool/catalogue.dart).
