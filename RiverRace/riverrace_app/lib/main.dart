import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';

import 'app_version.dart';
import 'race_screen.dart';
import 'strategy/decide.dart';
import 'theme.dart';

export 'calls/calls_panel.dart' show CallsPanel;
export 'race_screen.dart' show RaceScreen;

void main() {
  runApp(const RiverRaceApp());
}

class RiverRaceApp extends StatelessWidget {
  const RiverRaceApp({super.key, this.decider, this.seed, this.aityxLight});

  /// Asks aityx what the pilots do: aityx itself, from the app, unless a
  /// test says.
  final Decider? decider;
  final int? seed;

  /// The aityx status light: aityx_web's AityxStatusLight unless a test
  /// says.
  final Widget? aityxLight;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      home: RaceScreen(decider: decider, seed: seed),
      // The aityx status light, over every screen in the top right corner
      // (aityx_web).
      builder: (context, child) =>
          withAityxStatus(context, child, light: aityxLight),
    );
  }
}
