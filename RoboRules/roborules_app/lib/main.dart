import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';

import 'battle/controller.dart';
import 'files/files.dart';
import 'ui/battle_screen.dart';
import 'ui/classic.dart';

export 'ui/battle_screen.dart' show BattleScreen;

void main() {
  runApp(RoboRulesApp(controller: BattleController()..randomRobots(3)));
}

class RoboRulesApp extends StatelessWidget {
  const RoboRulesApp({super.key, required this.controller, this.files});

  final BattleController controller;

  /// Downloads and uploads: the browser's unless a test says.
  final Files? files;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboRules',
      debugShowCheckedModeBanner: false,
      theme: classicTheme(),
      home: BattleScreen(controller: controller, files: files),
      // The aityx light, top right on every screen.
      builder: withAityxStatus,
    );
  }
}
