/// One generation of Life: the body sent to aityx (assets/models/
/// life.json, with the board's situations and clusters as its state) and
/// the generation read back from aityx's answer, apart from the HTTP
/// plumbing in generation_stepper.dart so it can be tested without aityx.
/// Pure Dart (no dart:io, no Flutter), as it was in the former API.
library;

/// A request the app refuses before calling aityx.
class InvalidRequest implements Exception {
  InvalidRequest(this.message);

  final String message;

  @override
  String toString() => message;
}

/// aityx answered, but not with a generation.
class GenerationFailed implements Exception {
  GenerationFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A cell can have 0 to 8 live neighbours, alive or dead: 18 situations.
const maxSituations = 18;

/// The most clusters sent in one generation; the app sends the first
/// ones, top to bottom.
const maxClusters = 24;

/// The widest or tallest cluster described; the catalogue's largest
/// pattern, the pulsar, is 15 cells across at its widest phase.
const maxClusterSide = 64;

/// The state sent to aityx, from the app's body (generationBody),
/// `{"generation": 12, "rules": {"conway": true, "highlife": false,
/// "no_death": false}, "situations": [{"alive": true, "neighbours": 2,
/// "cells": 5}, ...], "clusters": [{"cells": 5, "width": 3, "height": 3,
/// "shape": ".o./..o/ooo"}, ...]}`: the generation, which rules are on
/// (Conway's alone when the body doesn't say), every distinct situation
/// on the board with how many cells are in it, and every cluster of live
/// cells with its shape, as the app counted them.
Map<String, Object?> stateFrom(Object? body) {
  if (body is! Map) throw InvalidRequest('expected an object');
  final generation = body['generation'];
  if (generation is! int || generation < 0) {
    throw InvalidRequest('generation must be a whole number, 0 or more');
  }
  return {
    'generation': generation,
    'rules': _rules(body['rules']),
    'situations': _situations(body['situations']),
    'clusters': _clusters(body['clusters'] ?? const []),
  };
}

/// The rules the model knows, and whether each is on when the request
/// doesn't say: Conway's own, and the variants, off.
const defaultRules = {'conway': true, 'highlife': false, 'no_death': false};

Map<String, bool> _rules(Object? rules) {
  if (rules == null) return {...defaultRules};
  if (rules is! Map) throw InvalidRequest('rules must be an object');
  for (final key in rules.keys) {
    if (!defaultRules.containsKey(key)) {
      throw InvalidRequest('rules: unknown rule $key');
    }
  }
  return {
    for (final MapEntry(key: id, value: on) in defaultRules.entries)
      id: switch (rules[id]) {
        null => on,
        final bool enabled => enabled,
        _ => throw InvalidRequest('rules.$id must be true or false'),
      },
  };
}

List<Map<String, Object?>> _situations(Object? situations) {
  if (situations is! List) throw InvalidRequest('situations is required');
  if (situations.length > maxSituations) {
    throw InvalidRequest('at most $maxSituations situations are distinct');
  }
  final seen = <(bool, int)>{};
  final state = <Map<String, Object?>>[];
  for (final (i, situation) in situations.indexed) {
    if (situation is! Map) {
      throw InvalidRequest('situation $i is not an object');
    }
    final alive = situation['alive'];
    final neighbours = situation['neighbours'];
    final cells = situation['cells'];
    if (alive is! bool) {
      throw InvalidRequest('situation $i: alive must be true or false');
    }
    if (neighbours is! int || neighbours < 0 || neighbours > 8) {
      throw InvalidRequest('situation $i: neighbours must be 0 to 8');
    }
    if (cells is! int || cells < 1) {
      throw InvalidRequest('situation $i: cells must be 1 or more');
    }
    if (!seen.add((alive, neighbours))) {
      throw InvalidRequest('situation $i repeats an earlier one');
    }
    state.add({'alive': alive, 'neighbours': neighbours, 'cells': cells});
  }
  return state;
}

final _shapeRow = RegExp(r'^[o.]+$');

List<Map<String, Object?>> _clusters(Object? clusters) {
  if (clusters is! List) throw InvalidRequest('clusters must be a list');
  if (clusters.length > maxClusters) {
    throw InvalidRequest('at most $maxClusters clusters are described');
  }
  final state = <Map<String, Object?>>[];
  for (final (i, cluster) in clusters.indexed) {
    if (cluster is! Map) throw InvalidRequest('cluster $i is not an object');
    final cells = cluster['cells'];
    final width = cluster['width'];
    final height = cluster['height'];
    final shape = cluster['shape'];
    if (cells is! int || cells < 1) {
      throw InvalidRequest('cluster $i: cells must be 1 or more');
    }
    if (width is! int || width < 1 || width > maxClusterSide) {
      throw InvalidRequest('cluster $i: width must be 1 to $maxClusterSide');
    }
    if (height is! int || height < 1 || height > maxClusterSide) {
      throw InvalidRequest('cluster $i: height must be 1 to $maxClusterSide');
    }
    if (shape is! String) throw InvalidRequest('cluster $i: shape is required');
    // The shape is height rows of width o's and dots, with cells o's.
    final rows = shape.split('/');
    if (rows.length != height ||
        rows.any((row) => row.length != width || !_shapeRow.hasMatch(row)) ||
        'o'.allMatches(shape).length != cells) {
      throw InvalidRequest(
        'cluster $i: shape must be $height rows of $width o or ., '
        'with $cells o',
      );
    }
    state.add({
      'cells': cells,
      'width': width,
      'height': height,
      'shape': shape,
    });
  }
  return state;
}

/// The body sent to aityx's /v1/systemone: the Life model from [model]
/// (assets/models/life.json) and the [state] from [stateFrom].
Map<String, Object?> generationRequest(
  Map<String, Object?> model,
  Map<String, Object?> state,
) => {...model, 'state': state};

/// The generation in aityx's [answer] to [sent]: the fate of each
/// situation, with the rule that decided it and why, the counts, and the
/// pattern each cluster is, with the catalogue row that matched and what
/// the pattern is. Throws [GenerationFailed] when the answer holds none.
Map<String, Object?> toGeneration(
  Map<String, Object?> sent,
  Map<String, Object?> answer,
) {
  if (answer['decision_error'] case final Map error) {
    throw GenerationFailed('the Life model failed: ${error['code']}');
  }
  final answers = answer['answers'];
  final receipt = answer['receipt'];
  if (answers is! Map || receipt is! Map) throw GenerationFailed('no answers');
  List<Object?> list(String name, int length) {
    final value = (answers[name] as Map?)?['value'];
    if (value is! List) throw GenerationFailed('no $name');
    if (value.length != length) {
      throw GenerationFailed(
        'aityx answered $name for ${value.length} items, not $length',
      );
    }
    return value;
  }

  num number(String name) {
    final value = (answers[name] as Map?)?['number'];
    if (value is! num) throw GenerationFailed('no $name');
    return value;
  }

  final state = (sent['state'] as Map?) ?? const {};
  final situations = (state['situations'] as List?) ?? const [];
  final clusters = (state['clusters'] as List?) ?? const [];
  final fates = list('fates', situations.length);
  final aliveNext = list('alive_next', situations.length);
  final patterns = list('patterns', clusters.length);
  final kinds = list('kinds', clusters.length);
  // Each function's table, and the receipt of each call to it, one per
  // item in order: the row that fired, hence its why.
  final functions = (sent['decision'] as Map?)?['functions'];
  final fired = receipt['functions'];
  ({int rule, String? why})? row(String function, int i) {
    final table = ((functions as Map?)?[function] as Map?)?['body'];
    final calls = (fired as Map?)?[function];
    if (table is! List || calls is! List || i >= calls.length) return null;
    final rule = (calls[i] as Map?)?['rule'];
    if (rule is! int || rule < 1 || rule >= table.length) return null;
    return (rule: rule, why: _why(table[0], table[rule]));
  }

  return {
    'generation': state['generation'],
    'rules': state['rules'],
    'next_generation': number('next_generation'),
    'population': number('population'),
    'population_next': number('population_next'),
    'births': number('births'),
    'deaths': number('deaths'),
    'survivors': number('survivors'),
    'situations': [
      for (final (i, situation) in situations.indexed)
        {
          ...(situation as Map).cast<String, Object?>(),
          'fate': fates[i],
          'alive_next': aliveNext[i] == true,
          if (row('fate', i) case final fired?) ...{
            'rule': fired.rule,
            'why': fired.why,
          },
        },
    ],
    'clusters': [
      for (final (i, cluster) in clusters.indexed)
        {
          ...(cluster as Map).cast<String, Object?>(),
          'pattern': patterns[i],
          'kind': kinds[i],
          if (row('identify', i) case final fired?) ...{
            'rule': fired.rule,
            'why': fired.why,
          },
          if (row('kind_of', i) case final fired?) 'about': fired.why,
        },
    ],
    'recognized': number('recognized'),
  };
}

/// A table row's `# why`: an object row's `why`, or the cell under the
/// header's `# ...` column.
String? _why(Object? header, Object? row) {
  if (row is Map) return row['why'] as String?;
  if (row is List && header is List) {
    final column = header.indexWhere((h) => h is String && h.startsWith('#'));
    if (column >= 0 && column < row.length) return row[column] as String?;
  }
  return null;
}

/// The outcome, as GenerationOutcome.fromJson reads it: the generation,
/// and the aityx call behind it, with how long aityx took, unless aityx's
/// answer somehow contains the user's key (it never should; in dev mode
/// the app has no key, and [key] is empty).
Map<String, Object?> withAityx(
  Map<String, Object?> generation,
  Map<String, Object?> sent,
  Map<String, Object?> answer,
  String text,
  String key, {
  required int tookMs,
}) => {
  'generation': generation,
  if (key.isEmpty || !text.contains(key))
    'aityx': {'request': sent, 'response': answer, 'took_ms': tookMs},
};
