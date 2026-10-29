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
  const MortgageHubApp({super.key, this.checker});

  /// Runs proposals' regulatory check: the app's API unless a test says.
  final ProposalChecker? checker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      home: WelcomeScreen(checker: checker),
    );
  }
}
