/// Everything the tour needs the app to hold: the server's config, who
/// is signed in and whether they may play, the aityx key the player's
/// table runs on (theirs: there is no other), the leaderboard, and
/// entering a strategy. Screens read it from the widget
/// tree (TourScope).
library;

import 'dart:async';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:poker_core/table.dart' show Strategy;

import '../aityx/player_keys.dart';
import '../auth/auth_controller.dart';
import '../persist/storage_area.dart';
import 'tour_api.dart';

/// Where the app is on its way to the table.
enum TourStage {
  /// Asking the server how to sign in.
  loading,

  /// The host hasn't set the sign-in up.
  notConfigured,

  /// Waiting for the user to sign in.
  signIn,

  /// Signed in with an account outside the tour's domains.
  notAllowed,

  /// At the table: signed in and allowed. The key may be missing: the
  /// Profile tab then asks for one.
  ready,
}

class TourSession extends ChangeNotifier {
  TourSession({required this.api, required this.auth, PlayerKeys? keys, http.Client? client})
    : keys = keys ?? PlayerKeys(local: localArea(), session: sessionArea()),
      _client = client ?? http.Client() {
    auth.addListener(_authChanged);
    this.keys.addListener(_keysChanged);
  }

  final TourApi api;
  final AuthController auth;

  /// The aityx key the player's table runs on: theirs.
  final PlayerKeys keys;
  final http.Client _client;

  TourConfig? config;
  Me? me;
  Leaderboard? leaderboard;
  List<TourStrategy> tourStrategies = const [];

  String? error;

  /// What aityx last said of the key in use: works, rejected, no key...
  AityxState? aityxState;

  TourStage _stage = TourStage.loading;
  Timer? _poll;
  bool _disposed = false;
  int _profileRequests = 0;

  TourStage get stage => _stage;

  /// Who is signed in, when they may play.
  SignedInUser? get player {
    final user = auth.user;
    final domains = config?.domains ?? const [];
    return user != null && user.allowedIn(domains) ? user : null;
  }

  /// Whether the leaderboard row [s] is the signed-in user's.
  bool mine(Standing s) => me != null && s.ownerId == me!.ownerId && !s.preset;

  /// Whether the signed-in user may start a tournament now.
  bool get admin => me?.admin ?? false;

  /// Whether the player has no key that works: none at all, or one aityx
  /// rejected. The Profile tab opens.
  bool get needsKey {
    if (_stage != TourStage.ready) return false;
    if (keys.key == null) return true;
    return aityxState?.kind == AityxStateKind.rejected;
  }

  /// Whether the player's table may play: their key is set and aityx
  /// said it works.
  bool get canPlay => keys.key != null && aityxState?.ok == true;

  /// Counts the asks to show the Profile tab (the aityx light's tap).
  int get profileRequests => _profileRequests;

  /// Asks the sidebar to show the Profile tab.
  void openProfile() {
    _profileRequests++;
    notifyListeners();
  }

  /// Asks the server how to sign in, again and again while it doesn't
  /// answer (it may still be starting), backing off up to half a minute.
  Future<void> start() async {
    var delay = const Duration(seconds: 3);
    while (!_disposed) {
      try {
        config = await api.config();
        break;
      } catch (e) {
        error = 'The server is not answering yet: $e';
        notifyListeners();
        await Future<void>.delayed(delay);
        if (delay < const Duration(seconds: 30)) delay *= 2;
      }
    }
    if (_disposed) return;
    error = null;
    final c = config!;
    keys.defaultUrl = c.aityxUrl;
    final relay = c.aityxRelay;
    keys.relay = relay == null || relay.isEmpty ? null : Uri.base.resolve(relay);
    if (!c.auth.enabled) {
      _stage = TourStage.notConfigured;
      notifyListeners();
      unawaited(refreshLeaderboard());
      return;
    }
    await auth.start(c.auth);
    _authChanged();
    unawaited(refreshLeaderboard());
  }

  void _authChanged() {
    if (_disposed || config == null || _stage == TourStage.notConfigured) return;
    final user = auth.user;
    if (user == null) {
      aityxState = null;
      me = null;
      tourStrategies = const [];
      _stage = TourStage.signIn;
      notifyListeners();
      return;
    }
    if (!user.allowedIn(config!.domains)) {
      _stage = TourStage.notAllowed;
      notifyListeners();
      return;
    }
    if (_stage != TourStage.ready) {
      _stage = TourStage.ready;
      notifyListeners();
      unawaited(refreshMe());
      unawaited(refreshStrategies());
      unawaited(checkKey());
    }
  }

  void _keysChanged() {
    if (_disposed) return;
    aityxState = null;
    notifyListeners();
    if (_stage == TourStage.ready) unawaited(checkKey());
  }

  /// Asks aityx whether the key in use works (an empty request: a working
  /// key gets 400, a bad one 401), for the Profile tab and the light.
  Future<AityxState> checkKey() async {
    // Never synchronously: the light asks while it is being built.
    await Future<void>.value();
    final connection = keys.connection;
    final AityxState state;
    if (connection.source == AityxSource.none) {
      state = AityxState(
        ok: false,
        key: false,
        source: AityxSource.none,
        url: keys.defaultUrl,
        detail: 'set yours in Profile',
        kind: AityxStateKind.noKey,
        whose: 'no key',
      );
    } else {
      final checked = await checkAityx(connection: connection, client: _client);
      state = AityxState(
        ok: checked.ok,
        key: checked.key,
        source: checked.source,
        url: checked.url,
        detail: checked.detail,
        kind: checked.kind,
        whose: keys.whose,
      );
    }
    if (_disposed) return state;
    // A later change of key makes this answer stale.
    if (identical(connection.key, keys.connection.key) || connection.key == keys.key) {
      aityxState = state;
      notifyListeners();
    }
    return state;
  }

  /// The signed-in player's strategies in the tour.
  List<TourStrategy> get myStrategies => [
    for (final t in tourStrategies)
      if (me != null && t.ownerId == me!.ownerId) t,
  ];

  /// Sets what the leaderboard calls the player (empty: their name);
  /// throws [TourException] with the server's reason.
  Future<void> setAlias(String alias) async {
    me = await api.setAlias(alias);
    notifyListeners();
    await Future.wait([refreshLeaderboard(), refreshStrategies()]);
  }

  Future<void> refreshMe() async {
    try {
      me = await api.me();
      notifyListeners();
    } on TourException {
      // The leaderboard then marks no row as yours.
    }
  }

  /// The leaderboard, now, and every [every] while [poll] is on.
  Future<void> refreshLeaderboard() async {
    try {
      leaderboard = await api.leaderboard();
      notifyListeners();
    } on TourException catch (e) {
      error ??= e.message;
    }
  }

  Future<void> refreshStrategies() async {
    if (player == null) return;
    try {
      tourStrategies = await api.strategies();
      notifyListeners();
    } on TourException {
      // Left as they were.
    }
  }

  /// Keeps the leaderboard fresh while a panel shows it.
  void poll(bool on, {Duration every = const Duration(seconds: 10)}) {
    _poll?.cancel();
    _poll = null;
    if (!on) return;
    _poll = Timer.periodic(every, (_) => refreshLeaderboard());
  }

  /// Enters [strategy] in the tour; throws [TourException] with the
  /// server's reason (aityx's, when it refused the rules).
  Future<TourStrategy> enter(Strategy strategy) async {
    final entered = await api.enter(strategy);
    await Future.wait([refreshLeaderboard(), refreshStrategies()]);
    return entered;
  }

  Future<void> withdraw(String id) async {
    await api.withdraw(id);
    await Future.wait([refreshLeaderboard(), refreshStrategies()]);
  }

  /// Starts a tournament now; the server's status ("started" or
  /// "running"). Throws [TourException] with the server's reason.
  Future<String> startTournament() async {
    final status = await api.startTournament();
    unawaited(refreshLeaderboard());
    return status;
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    auth.removeListener(_authChanged);
    keys.removeListener(_keysChanged);
    super.dispose();
  }
}

/// The session, for any screen: `TourScope.of(context)`; null in a test
/// that runs the table alone.
class TourScope extends InheritedNotifier<TourSession> {
  const TourScope({super.key, required TourSession session, required super.child})
    : super(notifier: session);

  static TourSession? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TourScope>()?.notifier;
}
