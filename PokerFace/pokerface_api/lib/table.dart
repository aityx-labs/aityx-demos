/// One decision at the table: the body sent to aityx (models/table.json,
/// the shared types and inputs, with a strategy's decisions and the
/// player's situation as the state) and the action read back from aityx's
/// answer, apart from the HTTP plumbing in bin/server.dart so it can be
/// tested without a server.
library;

import 'dart:convert';
import 'dart:io';

/// A request the API refuses before calling aityx.
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
class Strategy {
  const Strategy(this.id, this.name, this.tagline, this.decisions);

  /// A preset's file, `models/strategies/<id>.json`, or one sent by the
  /// app.
  factory Strategy.fromJson(Object? json, {String? id}) {
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
      id ?? (json['id'] is String ? json['id'] as String : 'custom'),
      name.trim(),
      tagline is String ? tagline : '',
      decisions.cast<String, Object?>(),
    );
  }

  static const maxNameLength = 60;

  final String id;
  final String name;
  final String tagline;
  final Map<String, Object?> decisions;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tagline': tagline,
    'decisions': decisions,
  };
}

/// The models: the table (types and inputs, models/table.json) and the
/// preset strategies (models/strategies/*.json), by id, in file order.
class Models {
  Models(this.table, this.strategies);

  final Map<String, Object?> table;
  final Map<String, Strategy> strategies;

  /// Reads [dir]'s table.json and strategies/*.json.
  static Future<Models> load(Directory dir) async {
    final table = jsonDecode(
      await File('${dir.path}/table.json').readAsString(),
    ) as Map<String, Object?>;
    final files =
        await Directory('${dir.path}/strategies')
              .list()
              .where((f) => f is File && f.path.endsWith('.json'))
              .cast<File>()
              .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final strategies = <String, Strategy>{};
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final id = name.substring(0, name.length - '.json'.length);
      strategies[id] = Strategy.fromJson(
        jsonDecode(await file.readAsString()),
        id: id,
      );
    }
    return Models(table, strategies);
  }

  /// The strategy the app's request names: a preset's id, or a strategy
  /// object of the app's own.
  Strategy strategyFrom(Object? value) {
    if (value is String) {
      final preset = strategies[value];
      if (preset == null) throw InvalidRequest('unknown strategy "$value"');
      return preset;
    }
    return Strategy.fromJson(value);
  }
}

/// The situation's inputs, as models/table.json declares them: each with
/// what the app must send.
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

/// The player's situation from the app's request body, checked against
/// the table's inputs, with nothing else in it.
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
/// header's `# ...` column.
String? _why(Object? header, Object? row) {
  if (row is Map) return row['why'] as String?;
  if (row is List && header is List) {
    final column = header.indexWhere((h) => h is String && h.startsWith('#'));
    if (column >= 0 && column < row.length) return row[column] as String?;
  }
  return null;
}

/// The API's answer to the app: the action, and the aityx call behind
/// it, with how long aityx took, unless aityx's answer somehow contains
/// the key (it never should).
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
