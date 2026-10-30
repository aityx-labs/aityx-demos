import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';

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
  const ContactHubApp({super.key, this.voice, this.router, this.aityxLight});

  /// Dictation in the request box: the browser's unless a test says.
  final VoiceInput? voice;

  /// Routes requests: aityx, from the app, unless a test says.
  final RequestRouter? router;

  /// The aityx status light, top right on every screen: aityx_web's,
  /// checking the key the index page set, unless a test says.
  final Widget? aityxLight;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      builder: (context, child) =>
          withAityxStatus(context, child, light: aityxLight),
      home: WelcomeScreen(voice: voice, router: router),
    );
  }
}
