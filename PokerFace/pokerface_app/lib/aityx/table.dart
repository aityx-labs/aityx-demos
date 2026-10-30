/// One decision at the table: the body sent to aityx (assets/models/
/// table.json, the shared types and inputs, with a strategy's decisions
/// and the player's situation as the state) and the action read back from
/// aityx's answer, apart from the call itself (AityxPokerApi, in
/// lib/api/aityx_poker_api.dart) so it can be tested without aityx.
///
/// Once the API's (pokerface_api/lib/table.dart): it runs in the app now,
/// which calls aityx itself.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// A request the app refuses before calling aityx.
class InvalidRequest implements Exception {
  InvalidRequest(this.message);

  final String message;

  @override
  String toString() => message;
}

/// aityx answered, but not with an action.
class DecisionFailed implements Exception {
  DecisionFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A strategy: a name, a line about it, and its rules, the decisions of
/// the table model (an `action`, a `raise_to`, and whatever they need).
/// A preset comes from assets/models/strategies/; a custom one is written
/// in the app.
class Strategy {
  const Strategy({
    required this.id,
    required this.name,
    required this.tagline,
    required this.decisions,
    this.custom = false,
  });

  /// A preset's file, `assets/models/strategies/<id>.json`, or a custom
  /// one as [toRequest] gives it; throws [InvalidRequest] when it isn't a
  /// strategy.
  factory Strategy.fromJson(Object? json, {String? id, bool custom = false}) {
    if (json is! Map) throw InvalidRequest('strategy must be an object');
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw InvalidRequest('strategy.name is required');
    }
    if (name.length > maxNameLength) {
      throw InvalidRequest(
        'strategy.name is longer than $maxNameLength characters',
      );
    }
    final decisions = json['decisions'];
    if (decisions is! Map || decisions.isEmpty) {
      throw InvalidRequest('strategy.decisions is required');
    }
    for (final needed in const ['action', 'raise_to']) {
      if (decisions[needed] == null) {
        throw InvalidRequest('strategy.decisions.$needed is required');
      }
    }
    final tagline = json['tagline'];
    return Strategy(
      id: id ?? (json['id'] is String ? json['id'] as String : 'custom'),
      name: name.trim(),
      tagline: tagline is String ? tagline : '',
      decisions: decisions.cast<String, Object?>(),
      custom: custom,
    );
  }

  static const maxNameLength = 60;

  final String id;
  final String name;
  final String tagline;
  final Map<String, Object?> decisions;

  /// Written in the app, so it's sent whole with every decision.
  final bool custom;

  /// What a decision names: a preset's id, or the custom rules.
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

/// The models: the table (types and inputs, assets/models/table.json)
/// and the preset strategies (assets/models/strategies/*.json), by id, in
/// file order.
class Models {
  Models(this.table, this.strategies);

  /// The table's JSON and each preset's, by id; in the order given.
  factory Models.fromJson(Object? table, Map<String, Object?> strategies) {
    if (table is! Map) throw InvalidRequest('table.json must be an object');
    return Models(table.cast<String, Object?>(), {
      for (final MapEntry(key: id, value: json) in strategies.entries)
        id: Strategy.fromJson(json, id: id),
    });
  }

  /// Where the models are among the app's assets (pubspec.yaml lists
  /// both folders).
  static const folder = 'assets/models';

  final Map<String, Object?> table;
  final Map<String, Strategy> strategies;

  /// Reads [bundle]'s table.json and every strategies/*.json, sorted by
  /// file name.
  static Future<Models> load(AssetBundle bundle) async {
    final table = jsonDecode(await bundle.loadString('$folder/table.json'));
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final files =
        manifest
            .listAssets()
            .where(
              (path) =>
                  path.startsWith('$folder/strategies/') &&
                  path.endsWith('.json'),
            )
            .toList()
          ..sort();
    final strategies = <String, Object?>{};
    for (final path in files) {
      final name = path.split('/').last;
      final id = name.substring(0, name.length - '.json'.length);
      strategies[id] = jsonDecode(await bundle.loadString(path));
    }
    return Models.fromJson(table, strategies);
  }

  /// The strategy a decision names: a preset's id, or a strategy object
  /// of the app's own.
  Strategy strategyFrom(Object? value) {
    if (value is String) {
      final preset = strategies[value];
      if (preset == null) throw InvalidRequest('unknown strategy "$value"');
      return preset;
    }
    return Strategy.fromJson(value, custom: true);
  }
}

/// The situation's inputs, as assets/models/table.json declares them:
/// each with what the app must send.
const _situationInputs = <String, Object>{
  'street': ['preflop', 'flop', 'turn', 'river'],
  'position': ['early', 'middle', 'late', 'blinds'],
  'hole': 'cards',
  'board': 'cards',
  'hand': ['premium', 'strong', 'medium', 'speculative', 'weak'],
  'made_hand': [
    'high_card',
    'pair',
    'two_pair',
    'three_of_a_kind',
    'straight',
    'flush',
    'full_house',
    'four_of_a_kind',
    'straight_flush',
  ],
  'flush_draw': 'boolean',
  'straight_draw': ['none', 'gutshot', 'open_ended'],
  'equity': 'unit',
  'pot': 'chips',
  'current_bet': 'chips',
  'to_call': 'chips',
  'pot_odds': 'unit',
  'can_check': 'boolean',
  'can_raise': 'boolean',
  'raises': 'count',
  'stack': 'chips',
  'big_blind': 'chips',
  'stack_bb': 'chips',
  'min_raise': 'chips',
  'max_raise': 'chips',
  'players_in_hand': 'count',
  'players_after': 'count',
  'random': 'unit',
};

final _card = RegExp(r'^[2-9TJQKA][cdhs]$');

/// The player's situation as the table computed it, checked against the
/// table's inputs, with nothing else in it.
Map<String, Object?> situationFrom(Object? body) {
  if (body is! Map) throw InvalidRequest('situation must be an object');
  final situation = <String, Object?>{};
  for (final MapEntry(key: name, value: kind) in _situationInputs.entries) {
    final value = body[name];
    if (value == null) throw InvalidRequest('situation.$name is required');
    switch (kind) {
      case List<Object?> choices:
        if (!choices.contains(value)) {
          throw InvalidRequest(
            'situation.$name must be one of ${choices.join(', ')}',
          );
        }
      case 'boolean':
        if (value is! bool) {
          throw InvalidRequest('situation.$name must be true or false');
        }
      case 'unit':
        if (value is! num || value < 0 || value > 1) {
          throw InvalidRequest('situation.$name must be a number from 0 to 1');
        }
      case 'chips':
        if (value is! num || value < 0 || value > 1e9) {
          throw InvalidRequest('situation.$name must be a number, 0 or more');
        }
      case 'count':
        if (value is! int || value < 0 || value > 23) {
          throw InvalidRequest('situation.$name must be a whole number');
        }
      case 'cards':
        if (value is! List ||
            value.length > 5 ||
            value.any((c) => c is! String || !_card.hasMatch(c))) {
          throw InvalidRequest(
            'situation.$name must be a list of cards like "Ah" or "Td"',
          );
        }
    }
    situation[name] = value;
  }
  if (situation['big_blind'] == 0) {
    throw InvalidRequest('situation.big_blind must be more than 0');
  }
  if ((situation['players_in_hand'] as int) < 2) {
    throw InvalidRequest('situation.players_in_hand must be 2 or more');
  }
  return situation;
}

/// The body sent to aityx's /v1/systemone: the table model from [models]
/// with [strategy]'s decisions, and the [situation] as its state.
Map<String, Object?> actRequest(
  Models models,
  Strategy strategy,
  Map<String, Object?> situation,
) => {
  'decision': {
    'name': '${models.table['name']} · ${strategy.name}',
    'types': models.table['types'],
    'inputs': models.table['inputs'],
    'decisions': strategy.decisions,
  },
  'state': situation,
};

/// The action in aityx's [answer] to [sent]: what to do, the total bet
/// when raising, the rule of the action table that fired and its `# why`,
/// and the strategy's other decisions by name. Throws [DecisionFailed]
/// when the answer holds none.
Map<String, Object?> toAction(
  Map<String, Object?> sent,
  Map<String, Object?> answer,
) {
  if (answer['decision_error'] case final Map error) {
    throw DecisionFailed(
      'the strategy failed: ${error['code']}'
      '${error['detail'] is String ? ', ${error['detail']}' : ''}',
    );
  }
  final answers = answer['answers'];
  final receipt = answer['receipt'];
  if (answers is! Map || receipt is! Map) throw DecisionFailed('no answers');
  final action = (answers['action'] as Map?)?['choice'];
  if (action is! String) throw DecisionFailed('no action');
  final raiseTo = (answers['raise_to'] as Map?)?['number'];
  if (raiseTo is! num) throw DecisionFailed('no raise_to');
  final table = _actionTable(sent);
  final rule = ((receipt['decisions'] as Map?)?['action'] as Map?)?['rule'];
  final fired = rule is int && rule >= 1 && rule < table.length ? rule : null;
  return {
    'action': action,
    'raise_to': raiseTo,
    if (fired != null) ...{'rule': fired, 'why': _why(table[0], table[fired])},
    'decisions': {
      for (final MapEntry(:key, :value) in answers.entries)
        if (key != 'action' && key != 'raise_to' && value is Map)
          key:
              value['choice'] ??
              value['number'] ??
              value['noul'] ??
              value['level'] ??
              value['value'],
    },
  };
}

/// The action decision's table in [sent]'s model; empty if it's not a
/// table.
List<Object?> _actionTable(Map<String, Object?> sent) {
  final decisions = (sent['decision'] as Map?)?['decisions'];
  final action = (decisions as Map?)?['action'];
  final table = action is Map ? action['table'] : action;
  return table is List ? table : const [];
}

/// A table row's `# why`: an object row's `why`, or the cell under the
/// header's `# ...` column; null when it isn't text (a custom strategy may
/// say anything there).
String? _why(Object? header, Object? row) {
  final Object? why;
  if (row is Map) {
    why = row['why'];
  } else if (row is List && header is List) {
    final column = header.indexWhere((h) => h is String && h.startsWith('#'));
    why = column >= 0 && column < row.length ? row[column] : null;
  } else {
    why = null;
  }
  return why is String ? why : null;
}

/// The decision as the app keeps it: the action, and the aityx call
/// behind it, with how long aityx took, unless aityx's answer somehow
/// contains the key (it never should): the calls sidebar shows the call,
/// and the key must not be on screen.
Map<String, Object?> withAityx(
  Map<String, Object?> action,
  Map<String, Object?> sent,
  Map<String, Object?> answer,
  String text,
  String key, {
  required int tookMs,
}) => {
  'action': action,
  if (key.isEmpty || !text.contains(key))
    'aityx': {'request': sent, 'response': answer, 'took_ms': tookMs},
};

/// aityx's problem details, in a short form for people: the code, the
/// detail, and the first errors' paths and messages, after a colon; empty
/// when [text] holds none. A custom strategy's mistake reaches the editor
/// this way.
String problemDetail(String text) {
  try {
    final json = jsonDecode(text);
    if (json is! Map) return '';
    final parts = <String>[
      if (json['code'] is String) json['code'] as String,
      if (json['detail'] is String) json['detail'] as String,
    ];
    if (json['errors'] case final List errors) {
      for (final e in errors.take(3)) {
        if (e is Map) parts.add('${e['path']}: ${e['message']}');
      }
    }
    return parts.isEmpty ? '' : ': ${parts.join('; ')}';
  } on FormatException {
    return '';
  }
}
