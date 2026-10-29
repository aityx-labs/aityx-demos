/// One generation asked of the API: what's on the board, and what aityx
/// decided for it, with the call behind it.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'board.dart';

/// What happens to the cells in one situation.
class SituationFate {
  const SituationFate({
    required this.alive,
    required this.neighbours,
    required this.cells,
    required this.fate,
    required this.aliveNext,
    this.rule,
    this.why,
  });

  factory SituationFate.fromJson(Map<String, Object?> json) => SituationFate(
    alive: json['alive'] as bool,
    neighbours: (json['neighbours'] as num).toInt(),
    cells: (json['cells'] as num).toInt(),
    fate: json['fate'] as String,
    aliveNext: json['alive_next'] as bool,
    rule: (json['rule'] as num?)?.toInt(),
    why: json['why'] as String?,
  );

  final bool alive;
  final int neighbours;
  final int cells;

  /// `survives`, `dies_lonely`, `dies_crowded`, `is_born` or `stays_empty`.
  final String fate;
  final bool aliveNext;

  /// The row of the rules table that decided it (1-based), and its why.
  final int? rule;
  final String? why;
}

/// What aityx made of one cluster of live cells.
class ClusterPattern {
  const ClusterPattern({
    required this.cells,
    required this.width,
    required this.height,
    required this.shape,
    required this.pattern,
    required this.kind,
    this.rule,
    this.why,
    this.about,
  });

  factory ClusterPattern.fromJson(Map<String, Object?> json) => ClusterPattern(
    cells: (json['cells'] as num).toInt(),
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num).toInt(),
    shape: json['shape'] as String,
    pattern: json['pattern'] as String,
    kind: json['kind'] as String,
    rule: (json['rule'] as num?)?.toInt(),
    why: json['why'] as String?,
    about: json['about'] as String?,
  );

  final int cells;
  final int width;
  final int height;
  final String shape;

  /// `block`, `glider`..., or `unknown`.
  final String pattern;

  /// `still_life`, `oscillator`, `spaceship`, `methuselah` or `unknown`.
  final String kind;

  /// The catalogue row that matched, and its why.
  final int? rule;
  final String? why;

  /// What the pattern is, from the kinds table.
  final String? about;

  bool get recognized => pattern != 'unknown';
}

/// The next generation as aityx decided it.
class Generation {
  const Generation({
    required this.generation,
    required this.nextGeneration,
    required this.population,
    required this.populationNext,
    required this.births,
    required this.deaths,
    required this.survivors,
    required this.situations,
    required this.patterns,
    required this.recognized,
  });

  factory Generation.fromJson(Map<String, Object?> json) => Generation(
    generation: (json['generation'] as num).toInt(),
    nextGeneration: (json['next_generation'] as num).toInt(),
    population: (json['population'] as num).toInt(),
    populationNext: (json['population_next'] as num).toInt(),
    births: (json['births'] as num).toInt(),
    deaths: (json['deaths'] as num).toInt(),
    survivors: (json['survivors'] as num).toInt(),
    situations: [
      for (final s in (json['situations'] as List?) ?? const [])
        SituationFate.fromJson((s as Map).cast<String, Object?>()),
    ],
    patterns: [
      for (final c in (json['clusters'] as List?) ?? const [])
        ClusterPattern.fromJson((c as Map).cast<String, Object?>()),
    ],
    recognized: (json['recognized'] as num?)?.toInt() ?? 0,
  );

  final int generation;
  final int nextGeneration;
  final int population;
  final int populationNext;
  final int births;
  final int deaths;
  final int survivors;

  /// In the order the situations were sent.
  final List<SituationFate> situations;

  /// In the order the clusters were sent.
  final List<ClusterPattern> patterns;

  /// How many clusters aityx recognized.
  final int recognized;

  List<bool> get aliveNext => [for (final s in situations) s.aliveNext];
}

/// A generation and the aityx call behind it, as the API answered.
class GenerationOutcome {
  const GenerationOutcome(
    this.generation, {
    this.aityxRequest,
    this.aityxResponse,
    this.tookMs,
    this.inputTokens,
  });

  factory GenerationOutcome.fromJson(Map<String, Object?> json) {
    final aityx = json['aityx'] as Map?;
    final usage = (aityx?['response'] as Map?)?['usage'] as Map?;
    return GenerationOutcome(
      Generation.fromJson((json['generation'] as Map).cast<String, Object?>()),
      aityxRequest: aityx?['request'],
      aityxResponse: aityx?['response'],
      tookMs: (aityx?['took_ms'] as num?)?.toInt(),
      inputTokens: (usage?['input_tokens'] as num?)?.toInt(),
    );
  }

  final Generation generation;
  final Object? aityxRequest;
  final Object? aityxResponse;

  /// How long aityx took to answer, as the API measured it.
  final int? tookMs;
  final int? inputTokens;
}

/// What the app sends for a generation: the board's generation, the rules
/// that are on, its situations and its clusters, as JSON.
Map<String, Object?> generationBody(
  int generation,
  Map<String, bool> rules,
  Map<SituationKey, List<Cell>> situations,
  List<Cluster> clusters,
) => {
  'generation': generation,
  'rules': rules,
  'situations': [
    for (final MapEntry(key: key, value: cells) in situations.entries)
      Situation(key.alive, key.neighbours, cells.length).toJson(),
  ],
  'clusters': [for (final cluster in clusters) cluster.toJson()],
};

/// Asks for the next generation: the app's API unless a test says.
abstract interface class GenerationStepper {
  Future<GenerationOutcome> step(
    int generation,
    Map<String, bool> rules,
    Map<SituationKey, List<Cell>> situations,
    List<Cluster> clusters,
  );
}

/// The app's API, at API_BASE_URL: empty means the app's own origin (the
/// dev server's or nginx's /api/ proxy).
class ApiGenerationStepper implements GenerationStepper {
  ApiGenerationStepper({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL');

  final http.Client _client;
  final String _baseUrl;

  Uri get _stepUrl => _baseUrl.isEmpty
      ? Uri.base.resolve('/api/step')
      : Uri.parse('$_baseUrl/api/step');

  /// Throws [GenerationException] with a message for the user.
  @override
  Future<GenerationOutcome> step(
    int generation,
    Map<String, bool> rules,
    Map<SituationKey, List<Cell>> situations,
    List<Cluster> clusters,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _stepUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
              generationBody(generation, rules, situations, clusters),
            ),
          )
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw const GenerationException('The API did not answer.');
    }
    Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      json = null;
    }
    if (response.statusCode != 200) {
      final error = json is Map ? json['error'] : null;
      throw GenerationException(
        error is String
            ? 'Could not run the generation: $error.'
            : 'The API answered HTTP ${response.statusCode}.',
      );
    }
    try {
      return GenerationOutcome.fromJson((json as Map).cast<String, Object?>());
    } catch (_) {
      throw const GenerationException('The API answered without a generation.');
    }
  }
}

class GenerationException implements Exception {
  const GenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}
