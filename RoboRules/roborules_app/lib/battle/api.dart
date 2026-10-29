import 'dart:convert';

import 'package:http/http.dart' as http;

import 'model.dart';

/// Turns played on aityx: the world after each, and the call behind them.
class Turns {
  const Turns(this.frames, {this.request, this.response});

  final List<World> frames;
  final Object? request;
  final Object? response;
}

/// A round's score for one robot, as the scoring model counts it.
class Score {
  const Score({
    required this.id,
    required this.survival,
    required this.lastSurvivor,
    required this.bulletDamage,
    required this.total,
  });

  factory Score.fromJson(Map json) => Score(
    id: json['id'] as String,
    survival: (json['survival'] as num).toInt(),
    lastSurvivor: (json['last_survivor'] as num).toInt(),
    bulletDamage: (json['bullet_damage'] as num).toInt(),
    total: (json['total'] as num).toInt(),
  );

  final String id;
  final int survival;
  final int lastSurvivor;
  final int bulletDamage;
  final int total;
}

/// A round scored: each robot's score, the winner, and the call.
class RoundScore {
  const RoundScore(this.scores, this.winner, {this.request, this.response});

  final List<Score> scores;
  final String? winner;
  final Object? request;
  final Object? response;
}

/// Plays turns and scores rounds: the app's API unless a test says.
abstract interface class BattleApi {
  Future<Turns> turns(List<Robot> robots, World world, int turns);
  Future<RoundScore> score(World last);
}

/// The app's API, at API_BASE_URL: empty means the app's own origin (the
/// dev server's or nginx's /api/ proxy).
class HttpBattleApi implements BattleApi {
  HttpBattleApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  final http.Client _client;
  final String _baseUrl;

  Uri _url(String path) =>
      _baseUrl.isEmpty ? Uri.base.resolve(path) : Uri.parse('$_baseUrl$path');

  Future<Map<String, Object?>> _post(String path, Object body) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _url(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 100));
    } catch (_) {
      throw const BattleException('The API did not answer.');
    }
    Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      json = null;
    }
    if (response.statusCode != 200 || json is! Map) {
      final error = json is Map ? json['error'] : null;
      final detail = json is Map ? json['detail'] : null;
      throw BattleException(
        error is String
            ? '$error${detail is String ? ': $detail' : ''}'
            : 'The API answered HTTP ${response.statusCode}.',
      );
    }
    return json.cast<String, Object?>();
  }

  @override
  Future<Turns> turns(List<Robot> robots, World world, int turns) async {
    final json = await _post('/api/battle/turns', {
      'robots': [for (final r in robots) r.toModel()],
      'world': world.toJson(),
      'turns': turns,
      'explain': true,
    });
    final aityx = json['aityx'] as Map?;
    return Turns(
      [for (final f in json['frames'] as List) World.fromJson(f as Map)],
      request: aityx?['request'],
      response: aityx?['response'],
    );
  }

  @override
  Future<RoundScore> score(World last) async {
    final json = await _post('/api/battle/score', {
      'results': [
        for (final b in last.bots)
          {'id': b.id, 'died': b.died, 'damage': b.damage},
      ],
    });
    final aityx = json['aityx'] as Map?;
    return RoundScore(
      [for (final s in json['scores'] as List) Score.fromJson(s as Map)],
      json['winner'] as String?,
      request: aityx?['request'],
      response: aityx?['response'],
    );
  }
}

class BattleException implements Exception {
  const BattleException(this.message);

  final String message;

  @override
  String toString() => message;
}
