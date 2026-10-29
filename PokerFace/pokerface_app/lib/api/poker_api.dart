import 'dart:convert';

import 'package:http/http.dart' as http;

import '../engine/game.dart';

/// A strategy: a name, a line about it, and its rules, the decisions of
/// the table model (an `action`, a `raise_to`, and whatever they need).
/// A preset comes from the API; a custom one is written in the app.
class Strategy {
  const Strategy({
    required this.id,
    required this.name,
    required this.tagline,
    required this.decisions,
    this.custom = false,
  });

  factory Strategy.fromJson(Map<String, Object?> json, {bool custom = false}) =>
      Strategy(
        id: json['id'] as String,
        name: json['name'] as String,
        tagline: (json['tagline'] as String?) ?? '',
        decisions: (json['decisions'] as Map).cast<String, Object?>(),
        custom: custom,
      );

  final String id;
  final String name;
  final String tagline;
  final Map<String, Object?> decisions;

  /// Written in the app, so it's sent to the API whole.
  final bool custom;

  /// What `POST /api/act` takes: a preset's id, or the custom rules.
  Object toRequest() => custom
      ? {'id': id, 'name': name, 'tagline': tagline, 'decisions': decisions}
      : id;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tagline': tagline,
    'decisions': decisions,
  };

  /// The rules as the editor shows them: the name, the tagline and the
  /// decisions, pretty-printed.
  String toEditable({String? as}) => const JsonEncoder.withIndent(
    '  ',
  ).convert({'name': as ?? name, 'tagline': tagline, 'decisions': decisions});

  /// A strategy from the editor's text; throws [FormatException] with a
  /// message for the user.
  static Strategy parse(String text, {required String id}) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('Not valid JSON: ${e.message}');
    }
    if (json is! Map) throw const FormatException('Expected a JSON object.');
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('"name" is required.');
    }
    final decisions = json['decisions'];
    if (decisions is! Map) {
      throw const FormatException('"decisions" is required: an object.');
    }
    for (final needed in const ['action', 'raise_to']) {
      if (decisions[needed] == null) {
        throw FormatException('"decisions" must have "$needed".');
      }
    }
    final tagline = json['tagline'];
    return Strategy(
      id: id,
      name: name.trim(),
      tagline: tagline is String ? tagline : '',
      decisions: decisions.cast<String, Object?>(),
      custom: true,
    );
  }
}

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

/// Decides for the players: the app's API, unless a test says.
abstract interface class PokerApi {
  Future<List<Strategy>> strategies();

  Future<ActResult> act(Strategy strategy, Map<String, Object?> situation);
}

/// The app's API, at API_BASE_URL: empty means the app's own origin (the
/// dev server's or nginx's /api/ proxy).
class HttpPokerApi implements PokerApi {
  HttpPokerApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  final http.Client _client;
  final String _baseUrl;

  Uri _url(String path) =>
      _baseUrl.isEmpty ? Uri.base.resolve(path) : Uri.parse('$_baseUrl$path');

  @override
  Future<List<Strategy>> strategies() async {
    final json = await _send(() => _client.get(_url('/api/strategies')));
    final list = json['strategies'];
    if (list is! List) throw const ApiException('No strategies came back.');
    return [
      for (final s in list)
        Strategy.fromJson((s as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<ActResult> act(
    Strategy strategy,
    Map<String, Object?> situation,
  ) async {
    final json = await _send(
      () => _client.post(
        _url('/api/act'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'strategy': strategy.toRequest(),
          'situation': situation,
        }),
      ),
    );
    try {
      return ActResult.fromJson(json);
    } catch (_) {
      throw const ApiException('The API answered without an action.');
    }
  }

  /// Throws [ApiException] with a message for the user.
  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() call,
  ) async {
    final http.Response response;
    try {
      response = await call().timeout(const Duration(seconds: 40));
    } catch (_) {
      throw const ApiException('The API did not answer.');
    }
    Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      json = null;
    }
    if (response.statusCode != 200) {
      final error = json is Map ? json['error'] : null;
      throw ApiException(
        error is String
            ? error
            : 'The API answered HTTP ${response.statusCode}.',
      );
    }
    if (json is! Map) throw const ApiException('The API answered no JSON.');
    return json.cast<String, Object?>();
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
