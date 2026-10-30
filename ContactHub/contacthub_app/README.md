# contacthub_app

The Contact Hub app, in Flutter (web, Android, iOS and Linux from one
codebase): a welcome screen ([lib/welcome/](lib/welcome/welcome_screen.dart))
with the request box ([lib/request/](lib/request/)), typed or dictated on
the device, and the routing screen ([lib/routing/](lib/routing/)), which
routes the request on aityx from the app itself
([lib/aityx/](lib/aityx/), the model in
[assets/models/](assets/models/routing.json), the calls and the status
light from [packages/aityx_web](../../packages/aityx_web/README.md)).

Build it with `bash ../scripts/build.sh` and open it at
http://localhost:8800/contacthub/ once the index server runs (see the
[project README](../README.md)). Test it here with `flutter analyze` and
`flutter test`; `bash ../scripts/model-test.sh` runs the model's rules on
aityx.
