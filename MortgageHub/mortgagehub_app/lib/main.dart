import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'aityx_status.dart';
import 'app_version.dart';
import 'proposal/proposal_check.dart';
import 'theme.dart';
import 'welcome/welcome_screen.dart';

export 'welcome/welcome_screen.dart' show WelcomeScreen;

void main() {
  runApp(const MortgageHubApp());
}

class MortgageHubApp extends StatelessWidget {
  const MortgageHubApp({super.key, this.checker, this.aityxClient});

  /// Runs proposals' regulatory check: the app's API unless a test says.
  final ProposalChecker? checker;

  /// The aityx status light's HTTP client: a new one unless a test says.
  final http.Client? aityxClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      builder: (context, child) =>
          WithAityxStatus(client: aityxClient, child: child),
      home: WelcomeScreen(checker: checker),
    );
  }
}
