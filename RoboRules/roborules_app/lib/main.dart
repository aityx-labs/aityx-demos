import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';

import 'battle/controller.dart';
import 'ui/battle_screen.dart';
import 'ui/classic.dart';

export 'ui/battle_screen.dart' show BattleScreen;

void main() {
  runApp(RoboRulesApp(controller: BattleController()..randomRobots(2)));
}

class RoboRulesApp extends StatelessWidget {
  const RoboRulesApp({super.key, required this.controller});

  final BattleController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboRules',
      debugShowCheckedModeBanner: false,
      theme: classicTheme(),
      home: BattleScreen(controller: controller),
      // The aityx light, top right on every screen.
      builder: withAityxStatus,
    );
  }
}
