import 'package:aityx_web/aityx_web.dart';
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
  const CellfieApp({super.key, this.stepper, this.aityxLight});

  /// Runs the generations: aityx unless a test says.
  final GenerationStepper? stepper;

  /// The aityx status light: aityx_web's AityxStatusLight, which checks
  /// the user's key (or the index server's dev key), unless a test says.
  final Widget? aityxLight;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      home: LifeScreen(stepper: stepper),
      builder: (context, child) =>
          withAityxStatus(context, child, light: aityxLight),
    );
  }
}
