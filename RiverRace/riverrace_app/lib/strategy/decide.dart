/// One decision asked of aityx, from the app itself: what the aityx pilots
/// sense and their rules go out, as one call to aityx's /v1/systemone;
/// what each does, with the call behind it, comes back.
library;

import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../aityx/decision_request.dart' as aityx;
import '../game/race.dart';
import 'strategy.dart';

/// A pilot as aityx is asked about it.
class PilotAsk {
  const PilotAsk(this.id, this.strategy, this.sense);

  final String id;
  final Strategy strategy;
  final Map<String, Object> sense;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': strategy.name,
    'rules': [for (final r in strategy.rules) r.toJson()],
    'sense': sense,
  };
}

/// What aityx decided at one tick, with the call behind it.
class Decision {
  const Decision(
    this.tick,
    this.actions, {
    this.aityxRequest,
    this.aityxResponse,
    this.tookMs,
    this.inputTokens,
  });

  factory Decision.fromJson(Map<String, Object?> json) {
    final aityx = json['aityx'] as Map?;
    final usage = (aityx?['response'] as Map?)?['usage'] as Map?;
    return Decision(
      (json['tick'] as num).toInt(),
      {
        for (final MapEntry(:key, :value)
            in (json['actions'] as Map).cast<String, Object?>().entries)
          key: PilotAction.fromJson((value as Map).cast<String, Object?>()),
      },
      aityxRequest: aityx?['request'],
      aityxResponse: aityx?['response'],
      tookMs: (aityx?['took_ms'] as num?)?.toInt(),
      inputTokens: (usage?['input_tokens'] as num?)?.toInt(),
    );
  }

  final int tick;

  /// By pilot id.
  final Map<String, PilotAction> actions;
  final Object? aityxRequest;
  final Object? aityxResponse;
  final int? tookMs;
  final int? inputTokens;
}

/// Asks what the pilots do: aityx, from the app, unless a test says.
abstract interface class Decider {
  Future<Decision> decide(int tick, List<PilotAsk> pilots);
}

/// The decision model: the types the pilots' tables use.
const modelAsset = 'assets/models/river.json';

/// How long a decision waits for aityx.
const aityxDeadline = Duration(seconds: 30);

/// Asks aityx's /v1/systemone itself, on the key the index page set or the
/// index server's dev key (aityx_web's AityxClient finds which; the key is
/// in the request's headers, never in what the calls panel shows).
class AityxDecider implements Decider {
  AityxDecider({
    AityxClient? client,
    Future<Map<String, Object?>> Function()? model,
  }) : _client = client ?? AityxClient(),
       _loadModel = model ?? _bundledModel;

  final AityxClient _client;
  final Future<Map<String, Object?>> Function() _loadModel;
  Future<Map<String, Object?>>? _model;

  static Future<Map<String, Object?>> _bundledModel() async =>
      (jsonDecode(await rootBundle.loadString(modelAsset)) as Map)
          .cast<String, Object?>();

  /// Throws [DecideException] with a message for the user.
  @override
  Future<Decision> decide(int tick, List<PilotAsk> pilots) async {
    final ({int tick, List<aityx.Pilot> pilots}) asked;
    try {
      asked = aityx.requestFrom({
        'tick': tick,
        'pilots': [for (final p in pilots) p.toJson()],
      });
    } on aityx.InvalidRequest catch (error) {
      throw DecideException('aityx could not decide: ${_sentence(error)}');
    }
    final Map<String, Object?> model;
    try {
      model = await (_model ??= _loadModel());
    } catch (_) {
      _model = null;
      throw const DecideException(
        'aityx could not decide: the model did not load.',
      );
    }
    final sent = aityx.decisionRequest(model, asked.pilots);
    // The key this call goes out on (none in dev mode), for the guard
    // below; read now, so a key changed on the index page while aityx
    // answers doesn't make the guard look for another one.
    final String key;
    final AityxAnswer answer;
    try {
      key = (await _client.connection()).key ?? '';
      answer = await _client.systemone(sent, timeout: aityxDeadline);
    } on AityxNoKey {
      throw const DecideException(AityxNoKey.message);
    } on AityxUnreachable {
      throw const DecideException(AityxUnreachable.message);
    }
    if (!answer.ok) throw DecideException(problemWith(answer));
    final json = answer.json;
    if (json is! Map) {
      throw const DecideException(
        'aityx could not decide: unexpected answer from aityx.',
      );
    }
    final response = json.cast<String, Object?>();
    final Map<String, Object?> actions;
    try {
      actions = aityx.toActions(asked.tick, asked.pilots, response);
    } on aityx.DecisionFailed catch (error) {
      throw DecideException(
        'aityx could not decide: aityx could not decide it: '
        '${_sentence(error)}',
      );
    }
    return Decision.fromJson(
      aityx.withAityx(
        actions,
        sent,
        response,
        answer.text,
        key,
        tookMs: answer.took.inMilliseconds,
      ),
    );
  }
}

/// What a non-200 [answer] means, for the user: the key rejected, aityx not
/// reached (the index server's dev proxy says so with 502), or aityx's
/// status and detail with the messages of its problem details (a cell
/// aityx can't read, for instance).
String problemWith(AityxAnswer answer) {
  if (answer.status == 401 || answer.status == 403) {
    return answer.problem!;
  }
  if (answer.code == 'proxy_unreachable') return AityxUnreachable.message;
  final json = answer.json;
  final errors = json is Map ? json['errors'] : null;
  final problems = [
    if (errors is List)
      for (final e in errors.take(5))
        if (e is Map && e['message'] is String) e['message'] as String,
  ];
  return _sentence(
    'aityx could not decide: ${answer.problem}'
    '${problems.isEmpty ? '' : ' (${problems.join('; ')})'}',
  );
}

/// [text] ending with one full stop.
String _sentence(Object text) {
  final s = '$text';
  return s.endsWith('.') ? s : '$s.';
}

class DecideException implements Exception {
  const DecideException(this.message);

  final String message;

  @override
  String toString() => message;
}
