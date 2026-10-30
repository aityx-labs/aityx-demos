import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../aityx/battle.dart' as aityx;
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

/// Plays turns and scores rounds: on aityx unless a test says.
abstract interface class BattleApi {
  Future<Turns> turns(List<Robot> robots, World world, int turns);
  Future<RoundScore> score(World last);
}

/// The battle on aityx, called from the app: the battle's model
/// (assets/models/world.json with each robot's brain added, see
/// lib/aityx/battle.dart) or the scoring model, sent to aityx's
/// `/v1/systemone` on the key aityx_web finds (the user's, set on the index
/// page, or the index server's dev key). The call kept for the viewer is
/// the request's body, never its headers, which carry the key.
class AityxBattleApi implements BattleApi {
  /// [client] is aityx (a new AityxClient unless given); [world] and
  /// [scoring] are the models (the app's assets unless given).
  AityxBattleApi({
    AityxClient? client,
    Map<String, Object?>? world,
    Map<String, Object?>? scoring,
  }) : _aityx = client ?? AityxClient(),
       _models = {
         if (world != null) 'world.json': Future.value(world),
         if (scoring != null) 'scoring.json': Future.value(scoring),
       };

  /// How long a call waits for aityx.
  static const deadline = Duration(seconds: 90);

  final AityxClient _aityx;
  final Map<String, Future<Map<String, Object?>>> _models;

  /// The model asset [name], read once (and again after a failure).
  Future<Map<String, Object?>> _model(String name) =>
      _models[name] ??= () async {
        try {
          final text = await rootBundle.loadString('assets/models/$name');
          return (jsonDecode(text) as Map).cast<String, Object?>();
        } catch (_) {
          _models.remove(name);
          throw BattleException('the app could not read its model $name');
        }
      }();

  @override
  Future<Turns> turns(List<Robot> robots, World world, int turns) async {
    final model = await _model('world.json');
    final Map<String, Object?> sent;
    try {
      sent = aityx.battleRequest(
        model,
        [for (final r in robots) r.toModel()],
        world.toJson(),
        turns,
      );
    } on aityx.InvalidBattle catch (e) {
      throw BattleException(e.message);
    }
    final (answer, shown) = await _call(sent);
    return _reading(() {
      final frames = aityx.framesOf(answer);
      return Turns(
        [for (final f in frames) World.fromJson(f as Map)],
        request: shown ? sent : null,
        response: shown ? answer : null,
      );
    });
  }

  @override
  Future<RoundScore> score(World last) async {
    final model = await _model('scoring.json');
    final results = [
      for (final b in last.bots)
        {'id': b.id, 'died': b.died, 'damage': b.damage},
    ];
    if (results.isEmpty) throw const BattleException('results is required');
    final sent = {
      'decision': model,
      'state': {'results': results},
    };
    final (answer, shown) = await _call(sent);
    return _reading(() {
      final answers = answer['answers'] as Map?;
      final scores = (answers?['scores'] as Map?)?['value'];
      if (scores is! List) {
        throw aityx.InvalidBattle('aityx answered without scores');
      }
      return RoundScore(
        [for (final s in scores) Score.fromJson(s as Map)],
        (answers?['winner'] as Map?)?['value'] as String?,
        request: shown ? sent : null,
        response: shown ? answer : null,
      );
    });
  }

  /// Sends [sent] to aityx: its answer, and whether the call may be kept
  /// for the viewer (not when aityx's answer holds the user's key, as the
  /// old API checked), or a [BattleException] that says what went wrong in
  /// the words the app shows.
  Future<(Map<String, Object?>, bool)> _call(Map<String, Object?> sent) async {
    final AityxAnswer answer;
    try {
      answer = await _aityx.systemone(sent, timeout: deadline);
    } on AityxNoKey {
      throw const BattleException(AityxNoKey.message);
    } on AityxUnreachable {
      throw const BattleException(AityxUnreachable.message);
    }
    if (!answer.ok) throw BattleException(_problem(answer));
    final json = answer.json;
    if (json is! Map) {
      throw const BattleException('unexpected answer from aityx');
    }
    // The connection the call just used (cached): null in dev mode, where
    // the key never reaches the app.
    final key = (await _aityx.connection()).key;
    final shown = key == null || key.isEmpty || !answer.text.contains(key);
    return (json.cast<String, Object?>(), shown);
  }

  /// [read] the answer, its own failures and an answer of the wrong
  /// shape as [BattleException]s.
  T _reading<T>(T Function() read) {
    try {
      return read();
    } on aityx.InvalidBattle catch (e) {
      throw BattleException(e.message);
    } on TypeError {
      throw const BattleException('unexpected answer from aityx');
    }
  }
}

/// What a failed call says: "aityx rejected the key", or "aityx answered
/// HTTP n" with aityx's detail and errors, which say what in a robot's
/// rules it couldn't run.
String _problem(AityxAnswer answer) {
  final status = answer.status;
  if (status == 401 || status == 403) return answer.problem!;
  final json = answer.json;
  final why = <String>[
    ?answer.detail,
    if (json is Map && json['errors'] is List)
      for (final e in json['errors'] as List)
        if (e is Map && e['message'] is String) e['message'] as String,
  ].join(' ');
  return 'aityx answered HTTP $status${why.isEmpty ? '' : ': $why'}';
}

class BattleException implements Exception {
  const BattleException(this.message);

  final String message;

  @override
  String toString() => message;
}
