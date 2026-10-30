import 'package:flutter/material.dart';

import 'aityx_status.dart';
import 'app_version.dart';
import 'life/generation.dart';
import 'life/life_screen.dart';
import 'theme.dart';

export 'calls/calls_panel.dart' show CallsPanel;
export 'life/board_view.dart' show BoardView;
export 'life/life_screen.dart' show LifeScreen;

/// The status light's check of the app's API, one for the app's life.
final _apiAityxCheck = apiAityxChecker();

void main() {
  runApp(const CellfieApp());
}

class CellfieApp extends StatelessWidget {
  const CellfieApp({super.key, this.stepper, this.aityxCheck});

  /// Runs the generations: the app's API unless a test says.
  final GenerationStepper? stepper;

  /// Asks whether aityx is ready, for the status light: the app's API
  /// unless a test says.
  final AityxChecker? aityxCheck;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      home: LifeScreen(stepper: stepper),
      builder: (context, child) => WithAityxStatus(
        check: aityxCheck ?? _apiAityxCheck,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
