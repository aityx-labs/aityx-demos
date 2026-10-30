import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';

import 'app_version.dart';
import 'proposal/proposal_check.dart';
import 'theme.dart';
import 'welcome/welcome_screen.dart';

export 'welcome/welcome_screen.dart' show WelcomeScreen;

void main() {
  runApp(const MortgageHubApp());
}

class MortgageHubApp extends StatelessWidget {
  const MortgageHubApp({super.key, this.checker, this.aityxLight});

  /// Runs proposals' regulatory check: aityx, from the app, unless a test
  /// says.
  final ProposalChecker? checker;

  /// The aityx status light, top right on every screen: aityx_web's
  /// AityxStatusLight unless a test says.
  final Widget? aityxLight;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      builder: (context, child) =>
          withAityxStatus(context, child, light: aityxLight),
      home: WelcomeScreen(checker: checker),
    );
  }
}
