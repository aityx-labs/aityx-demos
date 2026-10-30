# mortgagehub_app

The Mortgage Hub app, in Flutter (web, Android, iOS and Linux from one
codebase). For now it's a welcome screen
([lib/welcome/](lib/welcome/welcome_screen.dart)), a mortgage proposal
request form ([lib/proposal/](lib/proposal/)) and its regulatory check,
which the app runs with aityx itself: the mapping to the model's inputs in
[lib/aityx/](lib/aityx/proposal_model.dart), the model in
[assets/models/](assets/models/proposal-check.json), and the calls through
the shared [aityx_web](../../packages/aityx_web) package.

Build it for the index with `bash ../scripts/build.sh` and run it from the
repository with `./start-aityx.sh MortgageHub`, then open
http://localhost:8800/mortgagehub/ (see the [project README](../README.md)).
Test it here with `flutter analyze` and `flutter test`; the tests that call
aityx run with `bash ../scripts/model-test.sh`.
