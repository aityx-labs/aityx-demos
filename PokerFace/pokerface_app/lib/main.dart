import 'package:flutter/material.dart';

import 'aityx_status.dart';
import 'api/poker_api.dart';
import 'app_version.dart';
import 'game/controller.dart';
import 'table/table_screen.dart';
import 'theme.dart';

export 'table/table_screen.dart' show TableScreen;

void main() {
  runApp(const PokerFaceApp());
}

class PokerFaceApp extends StatefulWidget {
  const PokerFaceApp({super.key, this.api});

  /// Decides for the players: the app's API unless a test says.
  final PokerApi? api;

  @override
  State<PokerFaceApp> createState() => _PokerFaceAppState();
}

class _PokerFaceAppState extends State<PokerFaceApp> {
  late final GameController _controller = GameController(
    api: widget.api ?? HttpPokerApi(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: aityxDarkTheme(),
      // The aityx light, top right over every screen.
      builder: (context, child) => WithAityxStatus(child: child!),
      home: TableScreen(controller: _controller),
    );
  }
}
