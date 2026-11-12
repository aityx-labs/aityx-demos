/// The Poker Tour server's API, as the app calls it on its own origin
/// (`/api/`): how to sign in and which aityx to call (GET /api/config), the
/// leaderboard, the strategies entered in the tour, and entering one.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:poker_core/table.dart' show Strategy;

/// How the server signs users in: off until it has a Google client id.
class AuthConfig {
  const AuthConfig({required this.enabled, required this.issuer, this.clientId});

  factory AuthConfig.fromJson(Map<String, Object?> json) => AuthConfig(
    enabled: json['enabled'] == true,
    issuer: json['issuer'] as String? ?? '',
    clientId: json['clientId'] as String?,
  );

  final bool enabled;
  final String issuer;
  final String? clientId;
}

/// What GET /api/config answers.
class TourConfig {
  const TourConfig({
    required this.auth,
    required this.domains,
    required this.aityxUrl,
    this.aityxRelay,
  });

  factory TourConfig.fromJson(Map<String, Object?> json) => TourConfig(
    auth: AuthConfig.fromJson((json['auth'] as Map? ?? const {}).cast()),
    domains: ((json['domains'] as List?) ?? const []).cast<String>(),
    aityxUrl: json['aityxUrl'] as String? ?? '',
    aityxRelay: json['aityxRelay'] as String?,
  );

  final AuthConfig auth;

  /// The email domains allowed to play.
  final List<String> domains;

  /// Where aityx is, for the browser's calls.
  final String aityxUrl;

  /// The path on the server's origin that relays to [aityxUrl] (on a
  /// laptop: aityx staging takes no browser calls); null when the browser
  /// calls aityx directly.
  final String? aityxRelay;
}

/// Who the server says is calling (GET /api/me).
class Me {
  const Me({required this.email, required this.ownerId, this.name, this.alias, this.admin = false});

  factory Me.fromJson(Map<String, Object?> json) => Me(
    email: json['email'] as String? ?? '',
    ownerId: json['ownerId'] as String? ?? '',
    name: json['name'] as String?,
    alias: json['alias'] as String?,
    admin: json['admin'] == true,
  );

  final String email;

  /// How the leaderboard names the owner of a strategy, without the email.
  final String ownerId;
  final String? name;

  /// What the leaderboard calls them; null for their name.
  final String? alias;

  /// Their name as the leaderboard shows it when they have no alias.
  String get defaultName => (name ?? '').trim().isNotEmpty ? name!.trim() : email.split('@').first;

  /// An admin can start a tournament now.
  final bool admin;
}

/// One row of the leaderboard.
class Standing {
  const Standing({
    required this.id,
    required this.name,
    required this.tagline,
    required this.owner,
    required this.ownerId,
    required this.preset,
    required this.tournaments,
    required this.wins,
    required this.points,
    this.best,
    this.last,
    this.broken,
  });

  factory Standing.fromJson(Map<String, Object?> json) => Standing(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    tagline: json['tagline'] as String? ?? '',
    owner: json['owner'] as String? ?? '',
    ownerId: json['ownerId'] as String? ?? '',
    preset: json['preset'] == true,
    tournaments: (json['tournaments'] as num?)?.toInt() ?? 0,
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    points: (json['points'] as num?)?.toInt() ?? 0,
    best: (json['best'] as num?)?.toInt(),
    last: (json['last'] as num?)?.toInt(),
    broken: json['broken'] as String?,
  );

  final String id;
  final String name;
  final String tagline;

  /// Who entered it: a name, or "the house" for a preset.
  final String owner;
  final String ownerId;
  final bool preset;
  final int tournaments;
  final int wins;
  final int points;

  /// The best and the latest finishing place.
  final int? best;
  final int? last;

  /// Why the runner left it out, when aityx refused its rules.
  final String? broken;
}

/// A seat in the tournament being played now.
class LiveSeat {
  const LiveSeat({required this.name, required this.strategyId, required this.stack, this.place});

  factory LiveSeat.fromJson(Map<String, Object?> json) => LiveSeat(
    name: json['name'] as String? ?? '',
    strategyId: json['strategyId'] as String? ?? '',
    stack: (json['stack'] as num?)?.toInt() ?? 0,
    place: (json['place'] as num?)?.toInt(),
  );

  final String name;
  final String strategyId;
  final int stack;
  final int? place;
}

/// The tournament being played now.
class LiveTournament {
  const LiveTournament({required this.number, required this.hand, required this.seats, required this.calls});

  factory LiveTournament.fromJson(Map<String, Object?> json) => LiveTournament(
    number: (json['number'] as num?)?.toInt() ?? 0,
    hand: (json['hand'] as num?)?.toInt() ?? 0,
    calls: (json['calls'] as num?)?.toInt() ?? 0,
    seats: ((json['seats'] as List?) ?? const []).map((s) => LiveSeat.fromJson((s as Map).cast())).toList(),
  );

  final int number;
  final int hand;

  /// aityx calls so far in this tournament.
  final int calls;
  final List<LiveSeat> seats;
}

/// A finished tournament: who came where.
class PastTournament {
  const PastTournament({required this.number, required this.finished, required this.places});

  factory PastTournament.fromJson(Map<String, Object?> json) => PastTournament(
    number: (json['number'] as num?)?.toInt() ?? 0,
    finished: DateTime.tryParse(json['finished'] as String? ?? ''),
    places: ((json['places'] as List?) ?? const []).map((p) => (p as Map).cast<String, Object?>()).map((p) => (
      name: p['name'] as String? ?? '',
      place: (p['place'] as num?)?.toInt() ?? 0,
    )).toList(),
  );

  final int number;
  final DateTime? finished;
  final List<({String name, int place})> places;
}

/// What GET /api/leaderboard answers.
class Leaderboard {
  const Leaderboard({
    required this.standings,
    required this.current,
    required this.history,
    required this.runnerEnabled,
    required this.runnerState,
    required this.runnerDetail,
    this.nextRunAt,
    this.hoursUtc = const [],
    this.queue = const [],
  });

  factory Leaderboard.fromJson(Map<String, Object?> json) {
    final runner = (json['runner'] as Map? ?? const {}).cast<String, Object?>();
    return Leaderboard(
      standings: ((json['standings'] as List?) ?? const []).map((s) => Standing.fromJson((s as Map).cast())).toList(),
      current: json['current'] is Map ? LiveTournament.fromJson((json['current'] as Map).cast()) : null,
      history: ((json['history'] as List?) ?? const []).map((t) => PastTournament.fromJson((t as Map).cast())).toList(),
      runnerEnabled: runner['enabled'] == true,
      runnerState: runner['state'] as String? ?? 'idle',
      runnerDetail: runner['detail'] as String? ?? '',
      nextRunAt: DateTime.tryParse(runner['nextRunAt'] as String? ?? ''),
      hoursUtc: ((runner['hoursUtc'] as List?) ?? const []).map((h) => (h as num).toInt()).toList(),
      queue: [
        for (final r in (runner['queue'] as List?) ?? const [])
          if (r is Map && r['source'] is String) r['source'] as String,
      ],
    );
  }

  final List<Standing> standings;
  final LiveTournament? current;
  final List<PastTournament> history;
  final bool runnerEnabled;

  /// playing, waiting, idle or error.
  final String runnerState;
  final String runnerDetail;

  /// When the next scheduled tournament is; null when none is.
  final DateTime? nextRunAt;

  /// The hours of the day, UTC, at which tournaments are played.
  final List<int> hoursUtc;

  /// The tournaments waiting their turn, the oldest first, by who asked:
  /// schedule, admin or strategy.
  final List<String> queue;
}

/// A strategy entered in the tour, rules and all (GET /api/strategies).
class TourStrategy {
  const TourStrategy({required this.id, required this.owner, required this.ownerId, required this.strategy, this.preset = false, this.tournament});

  factory TourStrategy.fromJson(Map<String, Object?> json) => TourStrategy(
    id: json['id'] as String,
    owner: json['owner'] as String? ?? '',
    ownerId: json['ownerId'] as String? ?? '',
    strategy: Strategy.fromJson(json, id: 'tour-${json['id']}', custom: true),
    preset: json['preset'] == true,
    tournament: json['tournament'] as String?,
  );

  final String id;
  final String owner;
  final String ownerId;

  /// One of the presets, which the table has already, from the app.
  final bool preset;

  /// Once entered: the tournament it asked for, "started", "queued"
  /// (behind the one being played) or "waiting" (one asked for already
  /// waits, and it plays in it); null when the leaderboard is off.
  final String? tournament;

  /// The rules, as a custom strategy (sent whole with every decision),
  /// with the id `tour-<id>`.
  final Strategy strategy;
}

/// The server's API.
abstract interface class TourApi {
  Future<TourConfig> config();
  Future<Me> me();

  /// Sets what the leaderboard calls the caller; empty for their name.
  Future<Me> setAlias(String alias);
  Future<Leaderboard> leaderboard();
  Future<List<TourStrategy>> strategies();

  /// Enters [strategy] in the tour (or replaces the caller's entry of the
  /// same name); the server checks it on aityx first.
  Future<TourStrategy> enter(Strategy strategy);
  Future<void> withdraw(String id);

  /// Starts a tournament now (an admin): "started", or "running" when one
  /// is being played.
  Future<String> startTournament();
}

/// Thrown when the server answers an error, with its message.
class TourException implements Exception {
  const TourException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Gives the bearer token for a call, or null for none.
typedef TokenProvider = Future<String?> Function();

/// The server over HTTP, on this page's origin unless [base] says
/// (`/api/...`). [token] gives the signed-in user's ID token, sent as
/// `Authorization: Bearer`; after a 401, [refreshToken] is asked once for
/// a fresh one and the call is sent again.
class HttpTourApi implements TourApi {
  HttpTourApi({Uri? base, http.Client? client, this.token, this.refreshToken})
    : _base = base ?? Uri.base,
      _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  final TokenProvider? token;
  final TokenProvider? refreshToken;

  @override
  Future<TourConfig> config() async => TourConfig.fromJson(await _getMap('/api/config'));

  @override
  Future<Me> me() async => Me.fromJson(await _getMap('/api/me'));

  @override
  Future<Me> setAlias(String alias) async {
    final json = await _send('PUT', '/api/me', body: {'alias': alias});
    return Me.fromJson((json as Map).cast());
  }

  @override
  Future<Leaderboard> leaderboard() async => Leaderboard.fromJson(await _getMap('/api/leaderboard'));

  @override
  Future<List<TourStrategy>> strategies() async {
    final json = await _getMap('/api/strategies');
    return ((json['strategies'] as List?) ?? const [])
        .map((s) => TourStrategy.fromJson((s as Map).cast()))
        .toList();
  }

  @override
  Future<TourStrategy> enter(Strategy strategy) async {
    final json = await _send('POST', '/api/strategies', body: {
      'name': strategy.name,
      'tagline': strategy.tagline,
      'decisions': strategy.decisions,
    });
    return TourStrategy.fromJson((json as Map).cast());
  }

  @override
  Future<void> withdraw(String id) async {
    await _send('DELETE', '/api/strategies/${Uri.encodeComponent(id)}');
  }

  @override
  Future<String> startTournament() async {
    final json = await _send('POST', '/api/tournaments');
    return json is Map && json['status'] is String ? json['status'] as String : 'started';
  }

  Future<Map<String, Object?>> _getMap(String path) async {
    final json = await _send('GET', path);
    if (json is! Map) throw const TourException(500, 'unexpected answer from the server');
    return json.cast<String, Object?>();
  }

  Future<Object?> _send(String method, String path, {Object? body}) async {
    var bearer = await token?.call();
    var retried = false;
    while (true) {
      final request = http.Request(method, _base.resolve(path));
      request.headers['Accept'] = 'application/json';
      if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final http.Response response;
      try {
        response = await http.Response.fromStream(await _client.send(request)).timeout(const Duration(seconds: 60));
      } on TimeoutException {
        throw const TourException(0, 'the server did not answer');
      } catch (error) {
        throw TourException(0, 'the server could not be reached (${error.runtimeType})');
      }
      if (response.statusCode == 401 && bearer != null && !retried && refreshToken != null) {
        retried = true;
        final fresh = await refreshToken!.call();
        if (fresh != null && fresh != bearer) {
          bearer = fresh;
          continue;
        }
      }
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      Object? json;
      try {
        json = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        json = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = json is Map && json['error'] is String ? json['error'] as String : 'HTTP ${response.statusCode}';
        throw TourException(response.statusCode, error);
      }
      return json;
    }
  }
}
