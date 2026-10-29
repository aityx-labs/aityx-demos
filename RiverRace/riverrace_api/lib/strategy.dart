/// One decision of the race: the body sent to aityx (models/river.json,
/// with each aityx pilot's rules as a function and what each plane senses
/// as the state) and the actions read back from aityx's answer, apart from
/// the HTTP plumbing in bin/server.dart so it can be tested without a
/// server.
///
/// A pilot's strategy is a list of rules, each `{"when": {sensor: cell},
/// "then": {"steer": ..., "throttle": ..., "fire": ...}, "why": ...}`. It
/// becomes a FIRST decision table, `strategy_p1` or `strategy_p2`: a column
/// for each sensor its rules test, the three commands, and the why. aityx
/// wants a FIRST table to end with an else row, every cell `-`, so one is
/// added when the strategy doesn't have one: fly straight on.
library;

/// A request the API refuses before calling aityx.
class InvalidRequest implements Exception {
  InvalidRequest(this.message);

  final String message;

  @override
  String toString() => message;
}

/// aityx answered, but not with the actions.
class DecisionFailed implements Exception {
  DecisionFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The aityx pilots, by id; the third plane is the player's and never
/// reaches the API.
const pilotIds = ['p1', 'p2'];

/// The most rules a strategy can have.
const maxRules = 40;

/// The longest cell, name or why.
const maxText = 200;

/// What a plane senses, with its type and meaning, in the table's column
/// order. A type of `a|b|c` is one of those words.
const sensors = <String, (String type, String desc)>{
  'fuel': ('number', 'Fuel left, 0 (empty) to 100 (full)'),
  'speed': ('slow|normal|fast', 'How fast the plane flies up the river'),
  'land_ahead': (
    'boolean',
    'Is there land (a bank or an island) straight ahead, within 48 pixels?',
  ),
  'land_distance': (
    'number',
    'Pixels to the nearest land straight ahead (999 when none in sight)',
  ),
  'channel': (
    'left|right|ahead',
    'Where the open water is, 48 pixels ahead: to the left, to the right, '
        'or straight ahead',
  ),
  'room_left': ('number', 'Pixels of water to the left of the plane'),
  'room_right': ('number', 'Pixels of water to the right of the plane'),
  'enemy_ahead': (
    'boolean',
    'Is a ship, helicopter or jet in the line of fire, within 120 pixels?',
  ),
  'enemy_distance': (
    'number',
    'Pixels to the nearest enemy in the line of fire (999 when none)',
  ),
  'threat': (
    'none|left|right|ahead',
    'An enemy about to collide with the plane, within 40 pixels: on its '
        'left, on its right, straight ahead, or none',
  ),
  'fuel_ahead': (
    'boolean',
    'Is a fuel depot in the line of fire, within 120 pixels?',
  ),
  'fuel_side': (
    'none|left|right|ahead',
    'Where the nearest fuel depot ahead is, within 120 pixels: left, '
        'right, straight ahead, or none',
  ),
  'bridge_ahead': (
    'boolean',
    'Is a bridge still standing within 120 pixels ahead?',
  ),
  'leading': ('boolean', 'Is this plane the furthest up the river?'),
  'missile_ready': (
    'boolean',
    "Can the plane fire? (one missile in the air at a time)",
  ),
};

/// The commands a rule sets, with their values.
const commands = <String, String>{
  'steer': 'left|right|straight|to_channel|to_fuel|dodge',
  'throttle': 'slow|normal|fast',
  'fire': 'boolean',
};

/// What a rule that sets nothing does: fly straight on.
const _defaults = {'steer': 'straight', 'throttle': 'normal', 'fire': false};

/// The request's pilots, checked: `{"tick": 120, "pilots": [{"id": "p1",
/// "name": "Careful", "rules": [...], "sense": {...}}, ...]}`, one or two,
/// p1 and p2 at most once each.
({int tick, List<Pilot> pilots}) requestFrom(Object? body) {
  if (body is! Map) throw InvalidRequest('expected an object');
  final tick = body['tick'];
  if (tick is! int || tick < 0) {
    throw InvalidRequest('tick must be a whole number, 0 or more');
  }
  final pilots = body['pilots'];
  if (pilots is! List || pilots.isEmpty || pilots.length > pilotIds.length) {
    throw InvalidRequest('pilots must list 1 to ${pilotIds.length} pilots');
  }
  final seen = <String>{};
  final checked = [for (final p in pilots) Pilot.from(p)];
  for (final p in checked) {
    if (!seen.add(p.id)) throw InvalidRequest('pilot ${p.id} is repeated');
  }
  return (tick: tick, pilots: checked);
}

/// One aityx pilot: its strategy and what its plane senses now.
class Pilot {
  Pilot(this.id, this.name, this.rules, this.sense);

  factory Pilot.from(Object? json) {
    if (json is! Map) throw InvalidRequest('a pilot is not an object');
    final id = json['id'];
    if (id is! String || !pilotIds.contains(id)) {
      throw InvalidRequest('pilot id must be one of ${pilotIds.join(', ')}');
    }
    final name = _text(json['name'] ?? id, '$id: name');
    final rules = json['rules'];
    if (rules is! List) throw InvalidRequest('$id: rules must be a list');
    if (rules.length > maxRules) {
      throw InvalidRequest('$id: at most $maxRules rules');
    }
    return Pilot(id, name, [
      for (final (i, r) in rules.indexed) Rule.from(r, '$id, rule ${i + 1}'),
    ], _sense(json['sense'], id));
  }

  final String id;
  final String name;
  final List<Rule> rules;
  final Map<String, Object> sense;

  /// The sensors its rules test, in [sensors]' order; `fuel` when none
  /// does, as a table needs a column.
  List<String> get columns {
    final used = [
      for (final s in sensors.keys)
        if (rules.any((r) => r.when.containsKey(s))) s,
    ];
    return used.isEmpty ? ['fuel'] : used;
  }

  /// Its strategy as a FIRST decision table, with an else row added when
  /// its last rule isn't one, and a why for each rule without one.
  List<List<String>> get table {
    final cols = columns;
    final rows = [
      for (final (i, r) in rules.indexed)
        [
          for (final c in cols) r.when[c] ?? '-',
          r.steer,
          r.throttle,
          '${r.fire}',
          // aityx wants a why on every row.
          r.why.trim().isEmpty ? 'Rule ${i + 1}.' : r.why,
        ],
    ];
    if (rules.isEmpty || !rules.last.isElse) {
      rows.add([
        for (final _ in cols) '-',
        '${_defaults['steer']}',
        '${_defaults['throttle']}',
        '${_defaults['fire']}',
        'No rule matched: fly straight on.',
      ]);
    }
    return [
      [
        ...cols,
        for (final MapEntry(:key, :value) in commands.entries)
          '=> $key: $value',
        '# why',
      ],
      ...rows,
    ];
  }
}

/// A rule: the cells it tests, by sensor (only those that aren't `-`),
/// what it does, and why.
class Rule {
  Rule(this.when, this.steer, this.throttle, this.fire, this.why);

  factory Rule.from(Object? json, String where) {
    if (json is! Map) throw InvalidRequest('$where is not an object');
    final when = json['when'] ?? const {};
    final then = json['then'] ?? const {};
    if (when is! Map || then is! Map) {
      throw InvalidRequest('$where: when and then must be objects');
    }
    final cells = <String, String>{};
    for (final MapEntry(:key, :value) in when.entries) {
      if (!sensors.containsKey(key)) {
        throw InvalidRequest(
          '$where: unknown sensor "$key" (use ${sensors.keys.join(', ')})',
        );
      }
      final cell = _text(value, '$where: $key').trim();
      if (cell.isEmpty || cell == '-') continue;
      cells[key as String] = cell;
    }
    String command(String name) {
      final value = then[name] ?? _defaults[name];
      final allowed = commands[name]!.split('|');
      if (value is! String || !allowed.contains(value)) {
        throw InvalidRequest(
          '$where: $name must be one of ${allowed.join(', ')}',
        );
      }
      return value;
    }

    final fire = then['fire'] ?? _defaults['fire'];
    if (fire is! bool) {
      throw InvalidRequest('$where: fire must be true or false');
    }
    return Rule(
      cells,
      command('steer'),
      command('throttle'),
      fire,
      _text(json['why'] ?? '', '$where: why'),
    );
  }

  final Map<String, String> when;
  final String steer;
  final String throttle;
  final bool fire;
  final String why;

  /// Whether it tests nothing, so it always matches.
  bool get isElse => when.isEmpty;
}

String _text(Object? value, String where) {
  if (value is! String) throw InvalidRequest('$where must be text');
  if (value.length > maxText) {
    throw InvalidRequest('$where is longer than $maxText characters');
  }
  return value;
}

/// What a plane senses, checked against [sensors]' types: all of them.
Map<String, Object> _sense(Object? json, String id) {
  if (json is! Map) throw InvalidRequest('$id: sense must be an object');
  return {
    for (final MapEntry(:key, :value) in sensors.entries)
      key: switch ((value.$1, json[key])) {
        ('number', final num n) => n,
        ('boolean', final bool b) => b,
        (final type, final String word) when type.split('|').contains(word) =>
          word,
        _ => throw InvalidRequest('$id: sense.$key must be ${value.$1}'),
      },
  };
}

/// The body sent to aityx's /v1/systemone: the model of [base]
/// (models/river.json) with each pilot's sense as an input, its strategy
/// as a function and its action as a decision.
Map<String, Object?> decisionRequest(
  Map<String, Object?> base,
  List<Pilot> pilots,
) {
  final decision = (base['decision'] as Map).cast<String, Object?>();
  final args = [for (final s in sensors.keys) s];
  return {
    'decision': {
      ...decision,
      'inputs': {
        for (final p in pilots)
          p.id: {
            'type': 'Sense',
            'desc': 'What ${p.name}\'s plane senses now',
            'from': "the app's game",
          },
      },
      'functions': {
        for (final p in pilots)
          'strategy_${p.id}': {
            'params': {
              for (final MapEntry(:key, :value) in sensors.entries)
                key: value.$1,
            },
            'returns': 'Act',
            'body': p.table,
          },
      },
      'decisions': {
        for (final p in pilots)
          '${p.id}_action': {
            'type': 'Act',
            'desc':
                'What ${p.name} does now: the first of its rules that '
                'matches',
            'expr':
                'strategy_${p.id}(${args.map((a) => '${p.id}.$a').join(', ')})',
          },
      },
    },
    'state': {for (final p in pilots) p.id: p.sense},
  };
}

/// The actions in aityx's [answer] for [pilots]: each pilot's commands, the
/// rule that fired (1-based; 0 the else row the API added) and its why.
Map<String, Object?> toActions(
  int tick,
  List<Pilot> pilots,
  Map<String, Object?> answer,
) {
  if (answer['decision_error'] case final Map error) {
    throw DecisionFailed(
      'the strategies failed: ${error['detail'] ?? error['code']}',
    );
  }
  final answers = answer['answers'];
  if (answers is! Map) throw DecisionFailed('no answers');
  final fired = (answer['receipt'] as Map?)?['functions'] as Map?;
  return {
    'tick': tick,
    'actions': {for (final p in pilots) p.id: _action(p, answers, fired)},
  };
}

Map<String, Object?> _action(Pilot pilot, Map answers, Map? fired) {
  final value = (answers['${pilot.id}_action'] as Map?)?['value'];
  if (value is! Map) throw DecisionFailed('no action for ${pilot.id}');
  final steer = value['steer'];
  final throttle = value['throttle'];
  final fire = value['fire'];
  if (steer is! String || throttle is! String || fire is! bool) {
    throw DecisionFailed('an incomplete action for ${pilot.id}');
  }
  final calls = fired?['strategy_${pilot.id}'];
  final first = calls is List && calls.isNotEmpty ? calls.first : null;
  final row = first is Map ? first['rule'] : null;
  final rule = row is int && row >= 1 && row <= pilot.rules.length ? row : 0;
  return {
    'steer': steer,
    'throttle': throttle,
    'fire': fire,
    'rule': rule,
    'why': rule == 0
        ? 'No rule matched: fly straight on.'
        : pilot.rules[rule - 1].why,
  };
}

/// The API's answer to the app: the actions, and the aityx call behind
/// them, with how long aityx took, unless aityx's answer somehow contains
/// the key (it never should).
Map<String, Object?> withAityx(
  Map<String, Object?> actions,
  Map<String, Object?> sent,
  Map<String, Object?> answer,
  String text,
  String key, {
  required int tookMs,
}) => {
  ...actions,
  if (key.isEmpty || !text.contains(key))
    'aityx': {'request': sent, 'response': answer, 'took_ms': tookMs},
};
