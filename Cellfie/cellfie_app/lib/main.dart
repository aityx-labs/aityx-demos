import 'package:flutter/material.dart';

import 'app_version.dart';
import 'life/generation.dart';
import 'life/life_screen.dart';
import 'theme.dart';

export 'calls/calls_panel.dart' show CallsPanel;
export 'life/board_view.dart' show BoardView;
export 'life/life_screen.dart' show LifeScreen;

void main() {
  runApp(const CellfieApp());
}

class CellfieApp extends StatelessWidget {
  const CellfieApp({super.key, this.stepper});

  /// Runs the generations: the app's API unless a test says.
  final GenerationStepper? stepper;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      home: LifeScreen(stepper: stepper),
    );
  }
}
