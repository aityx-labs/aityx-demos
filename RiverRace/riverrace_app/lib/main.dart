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
  const RiverRaceApp({super.key, this.decider, this.seed});

  /// Asks aityx what the pilots do: the app's API unless a test says.
  final Decider? decider;
  final int? seed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      home: RaceScreen(decider: decider, seed: seed),
    );
  }
}
