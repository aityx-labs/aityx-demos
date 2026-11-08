import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';

import 'aityx/tour_aityx_client.dart';
import 'api/aityx_poker_api.dart';
import 'api/poker_api.dart';
import 'app_version.dart';
import 'auth/auth_controller.dart';
import 'game/controller.dart';
import 'music/music_control.dart';
import 'music/soundtrack.dart';
import 'persist/storage_area.dart';
import 'screens/sign_in_screen.dart';
import 'table/table_screen.dart';
import 'theme.dart';
import 'tour/tour_sidebar.dart';
import 'tour/tour_api.dart';
import 'tour/tour_session.dart';

export 'table/table_screen.dart' show TableScreen;

void main() {
  runApp(const PokerTourApp());
}

/// Poker Tour: PokerFace's table, for the people of the tour. The server
/// (its own origin, /api/) says how to sign in and which aityx this
/// environment uses (staging on a laptop, production when deployed). Once
/// the user signs in with Google, the table opens: the title and the
/// table on the left, and on the right the sidebar's tabs, the
/// leaderboard, the aityx calls and the profile. The table runs on the
/// player's own key, set in Profile, and on no other: without one,
/// Profile opens and asks for it, and Play waits. The leaderboard plays
/// on the server, on a key of its own that players never get.
class PokerTourApp extends StatefulWidget {
  const PokerTourApp({super.key, this.api, this.tour, this.auth, this.session});

  /// Decides for the players: a test's, straight to the table, skipping
  /// the sign-in and the key. aityx otherwise, on the session's key.
  final PokerApi? api;

  /// The server's API unless a test says.
  final TourApi? tour;

  /// The sign-in, unless a test passes its own.
  final AuthController? auth;

  /// The session, unless a test passes its own (then it is started by
  /// the test, and the app shows the tour's sidebar beside the table).
  final TourSession? session;

  @override
  State<PokerTourApp> createState() => _PokerTourAppState();
}

class _PokerTourAppState extends State<PokerTourApp> {
  late final AuthController _auth = widget.session?.auth ?? widget.auth ?? AuthController();
  late final TourApi _tour = widget.tour ?? HttpTourApi(token: _auth.token, refreshToken: _auth.refresh);
  late final TourSession _session = widget.session ?? TourSession(api: _tour, auth: _auth);
  GameController? _controller;
  AityxClient? _aityx;

  /// The jazz at the table, from the moment it opens.
  late final Soundtrack _music = Soundtrack(storage: widget.api != null ? memoryArea() : localArea());

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    if (widget.api != null) {
      _controller = GameController(api: widget.api!);
    } else if (widget.session == null) {
      _session.start();
    } else {
      _changed();
    }
  }

  /// Signed in and allowed, the table (on the session's key store, which
  /// the client follows as the key changes); signed out, the sign-in
  /// again, with a fresh table next time.
  void _changed() {
    if (widget.api != null) return;
    final ready = _session.stage == TourStage.ready;
    if (ready && _controller == null) {
      _aityx = TourAityxClient(_session.keys);
      _controller = GameController(api: AityxPokerApi(aityx: _aityx!));
      _music.start();
    } else if (!ready && _controller != null) {
      _music.stop();
      _controller?.dispose();
      _controller = null;
      _aityx?.close();
      _aityx = null;
    }
    final controller = _controller;
    if (controller != null) _seatTourStrategies(controller);
    if (mounted) setState(() {});
  }

  /// The tour's strategies among the table's, to seat players with.
  void _seatTourStrategies(GameController controller) {
    final tour = _session.tourStrategies;
    if (tour.isEmpty) return;
    controller.addStrategies([
      for (final t in tour)
        Strategy(
          id: t.strategy.id,
          name: t.strategy.name,
          tagline: 'In the tour, by ${t.owner}. ${t.strategy.tagline}'.trim(),
          decisions: t.strategy.decisions,
          custom: true,
        ),
    ]);
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _music.dispose();
    _controller?.dispose();
    _aityx?.close();
    if (widget.session == null) {
      _session.dispose();
      if (widget.auth == null) _auth.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final keys = _session.keys;
    return TourScope(
      session: _session,
      child: MaterialApp(
        title: AppVersion.title,
        debugShowCheckedModeBanner: false,
        theme: aityxDarkTheme(),
        // The aityx light, top right: on the key the table runs on; a tap
        // opens Profile.
        builder: (context, child) => withAityxStatus(
          context,
          child,
          light: AityxStatusLight(
            key: ValueKey('${keys.source.name} ${keys.url} ${keys.key?.length}'),
            check: _check,
            onTap: _session.openProfile,
          ),
        ),
        home: controller == null
            ? SignInScreen(session: _session)
            : TableScreen(
                controller: controller,
                actions: [MusicControl(soundtrack: _music)],
                sidebar: widget.api != null && widget.session == null
                    ? null
                    : (context) => TourSidebar(session: _session, controller: controller),
              ),
      ),
    );
  }

  Future<AityxState> _check() {
    if (widget.api != null && widget.session == null) return Future.value(AityxState.noKey);
    return _session.checkKey();
  }
}
