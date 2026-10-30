import '../aityx/table.dart' show Strategy;
import '../engine/game.dart';

export '../aityx/table.dart' show Strategy;

/// What the strategy decided, and the aityx call behind it.
class ActResult {
  const ActResult({
    required this.kind,
    required this.raiseTo,
    this.rule,
    this.why,
    this.decisions = const {},
    this.request,
    this.response,
    this.tookMs,
  });

  factory ActResult.fromJson(Map<String, Object?> json) {
    final action = (json['action'] as Map).cast<String, Object?>();
    final aityx = (json['aityx'] as Map?)?.cast<String, Object?>();
    return ActResult(
      kind: ActionKind.parse(action['action'] as String),
      raiseTo: action['raise_to'] as num,
      rule: action['rule'] as int?,
      why: action['why'] as String?,
      decisions:
          (action['decisions'] as Map?)?.cast<String, Object?>() ?? const {},
      request: aityx?['request'],
      response: aityx?['response'],
      tookMs: aityx?['took_ms'] as int?,
    );
  }

  final ActionKind kind;
  final num raiseTo;

  /// The row of the action table that fired (1-based), and its `# why`.
  final int? rule;
  final String? why;

  /// The strategy's other decisions, by name.
  final Map<String, Object?> decisions;

  final Object? request;
  final Object? response;
  final int? tookMs;
}

/// Decides for the players: aityx (AityxPokerApi), unless a test says.
abstract interface class PokerApi {
  Future<List<Strategy>> strategies();

  Future<ActResult> act(Strategy strategy, Map<String, Object?> situation);
}

/// What went wrong with a decision, in words for the user.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
