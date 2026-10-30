import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'aityx_status.dart';
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
  const RiverRaceApp({super.key, this.decider, this.seed, this.statusClient});

  /// Asks aityx what the pilots do: the app's API unless a test says.
  final Decider? decider;
  final int? seed;

  /// Asks the API for the aityx status light, unless a test says.
  final http.Client? statusClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      home: RaceScreen(decider: decider, seed: seed),
      // The aityx status light, over every screen in the top right corner;
      // in an Overlay of its own so its tooltip has one.
      builder: (context, child) => Overlay.wrap(
        child: Stack(
          children: [
            ?child,
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AityxStatus(client: statusClient),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
