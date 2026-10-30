# roborules_app

The RoboRules app, in Flutter for the web: Robocode's window, the
battlefield, the robot list and the rules editor
([lib/ui/](lib/ui/)), and the battle's controller and its calls to aityx
([lib/battle/](lib/battle/)). It calls aityx itself, through the shared
[aityx_web](../../packages/aityx_web) package: the battle's model is built
here ([lib/aityx/battle.dart](lib/aityx/battle.dart)) from the world model
and each robot's rules, and the models are the app's assets
([assets/models/](assets/models/), the world written by
[tool/build_world.py](tool/build_world.py)).

Run it from the repository's root with `./start-aityx.sh RoboRules`, at
http://localhost:8800/roborules/. Test it here with `flutter analyze` and
`flutter test`; `bash ../scripts/model-test.sh` runs the tests tagged
`aityx`, which play battles on aityx with the root `.env`'s key.
