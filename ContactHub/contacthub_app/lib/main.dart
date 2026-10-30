import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'aityx_status.dart';
import 'app_version.dart';
import 'request/voice_input.dart';
import 'routing/routing.dart';
import 'theme.dart';
import 'welcome/welcome_screen.dart';

export 'request/request_box.dart' show RequestBox;
export 'routing/routing_screen.dart' show RoutingScreen;
export 'welcome/welcome_screen.dart' show WelcomeScreen;

void main() {
  runApp(const ContactHubApp());
}

class ContactHubApp extends StatelessWidget {
  const ContactHubApp({super.key, this.voice, this.router, this.aityxClient});

  /// Dictation in the request box: the browser's unless a test says.
  final VoiceInput? voice;

  /// Routes requests: the app's API unless a test says.
  final RequestRouter? router;

  /// Asks the API's /api/aityx for the status light: a real client unless
  /// a test says.
  final http.Client? aityxClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      builder: (context, child) =>
          WithAityxStatus(client: aityxClient, child: child!),
      home: WelcomeScreen(voice: voice, router: router),
    );
  }
}
