/// A battle on aityx: the world model (models/world.json) with each robot's
/// brain added, and the state to play from, apart from the HTTP plumbing in
/// bin/server.dart so it can be tested without a server.
///
/// A robot is an aityx model of its own: the sensors as its `inputs`, and
/// one decision, `action`, a FIRST table whose outputs are the four
/// commands (`drive`, `turn`, `gun`, `fire`). Each robot's table becomes a
/// function of the world model, `brain_r1`, `brain_r2`..., with a `rule`
/// output added (the row's number), and `brain_of` calls the right one for
/// each robot every turn.
library;

/// A request the API refuses before calling aityx.
class InvalidBattle implements Exception {
  InvalidBattle(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a robot senses each turn, with its type and meaning: a robot's
/// model has these as its inputs, and its table's columns test them.
const sensors = <String, (String type, String desc)>{
  'enemy_distance': (
    'number',
    'Distance to the nearest enemy, in pixels (9999 when none is left)',
  ),
  'enemy_bearing': (
    'number',
    'Where the nearest enemy is, in degrees from where the robot faces: '
        'negative to the left, positive to the right (-180 to 180)',
  ),
  'gun_bearing': (
    'number',
    'Where the nearest enemy is, in degrees from where the gun points',
  ),
  'enemy_in_sight': (
    'boolean',
    'Is the nearest enemy within 10 degrees of the gun?',
  ),
  'my_energy': ('number', 'The robot\'s energy (it starts at 100)'),
  'enemy_energy': ('number', "The nearest enemy's energy"),
  'near_wall': ('boolean', 'Is a wall within 80 pixels straight ahead?'),
  'wall_distance': ('number', 'Distance to the nearest wall, in pixels'),
  'gun_ready': ('boolean', 'Has the gun cooled down enough to fire?'),
  'was_hit': ('boolean', 'Was the robot hit by a bullet last turn?'),
  'speed': ('number', 'The robot\'s speed, -8 to 8 pixels a turn'),
  'enemies_left': ('number', 'How many enemies are still alive'),
};

/// The commands an action sets, as the output columns' headers.
const commands = <String, String>{
  'drive': 'ahead|back|stop',
  'turn': 'left|right|none|toward_enemy|away_from_enemy|perpendicular',
  'gun': 'aim|sweep_left|sweep_right|hold',
  'fire': 'number',
};

/// The inputs block every robot model has: the sensors.
Map<String, Object?> sensorInputs() => {
  for (final MapEntry(:key, :value) in sensors.entries)
    key: {'type': value.$1, 'desc': value.$2},
};

/// The id the battle gives robot number [index] (0-based): r1, r2...
String robotId(int index) => 'r${index + 1}';

/// [model]'s `action` table, checked, with rows as lists: a header of
/// sensor columns, the four `=> command` columns and an optional `# why`.
List<List<Object?>> actionTable(Object? model, String name) {
  if (model is! Map) throw InvalidBattle('$name: the robot is not a model');
  final decisions = model['decisions'];
  final action = decisions is Map ? decisions['action'] : null;
  final table = action is Map ? action['table'] : null;
  if (table is! List || table.length < 2) {
    throw InvalidBattle(
      '$name: decisions.action.table needs a header and '
      'at least one rule',
    );
  }
  final header = table.first;
  if (header is! List || header.any((h) => h is! String)) {
    throw InvalidBattle('$name: the table header must be a list of names');
  }
  final columns = header.cast<String>();
  final outputs = <String>[];
  for (final c in columns) {
    if (c.startsWith('=>')) {
      final command = c.substring(2).split(':').first.trim();
      if (!commands.containsKey(command)) {
        throw InvalidBattle(
          '$name: unknown command column "$c" (use '
          '${commands.keys.join(', ')})',
        );
      }
      outputs.add(command);
    } else if (!c.startsWith('#') && !sensors.containsKey(c)) {
      throw InvalidBattle(
        '$name: unknown sensor column "$c" (use '
        '${sensors.keys.join(', ')})',
      );
    }
  }
  for (final command in commands.keys) {
    if (!outputs.contains(command)) {
      throw InvalidBattle('$name: the table has no "=> $command" column');
    }
  }
  final rows = [for (final row in table.skip(1)) _row(row, columns, name)];
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < columns.length; c++) {
      if (columns[c].startsWith('=>')) {
        _checkCommand(columns[c], '${rows[r][c]}', '$name, rule ${r + 1}');
      }
    }
  }
  return [columns, ...rows];
}

/// [cell] must be one of its command's values, or for `fire` a power from
/// 0 to 3: aityx takes any word in an output column as a value.
void _checkCommand(String column, String cell, String where) {
  final command = column.substring(2).split(':').first.trim();
  final value = cell.trim();
  if (command == 'fire') {
    final power = num.tryParse(value);
    if (power == null || power < 0 || power > 3) {
      throw InvalidBattle(
        '$where: fire must be a power from 0 to 3, not "$value"',
      );
    }
    return;
  }
  final allowed = commands[command]!.split('|');
  if (!allowed.contains(value)) {
    throw InvalidBattle(
      '$where: $command must be one of ${allowed.join(', ')}, not "$value"',
    );
  }
}

/// A rule as a list of cells, whether it was written as a list or as
/// `{"when": {...}, "then": {...}, "why": "..."}`.
List<Object?> _row(Object? row, List<String> columns, String name) {
  if (row is List) {
    if (row.length != columns.length) {
      throw InvalidBattle(
        '$name: a rule has ${row.length} cells for '
        '${columns.length} columns',
      );
    }
    return row;
  }
  if (row is Map) {
    final when = row['when'] is Map ? row['when'] as Map : const {};
    final then = row['then'] is Map ? row['then'] as Map : const {};
    return [
      for (final c in columns)
        if (c.startsWith('=>'))
          '${then[c.substring(2).split(':').first.trim()] ?? '-'}'
        else if (c.startsWith('#'))
          row['why'] ?? ''
        else
          when[c] ?? '-',
    ];
  }
  throw InvalidBattle('$name: a rule must be a list or an object');
}

/// The world model function for a robot's [table]: its sensors as
/// parameters, its rules as the body, and a `rule` output, each row's
/// number, so the battle can show which rule fired.
Map<String, Object?> brainFunction(List<List<Object?>> table) {
  final header = [...table.first.cast<String>()];
  final why = header.indexWhere((c) => c.startsWith('#'));
  final at = why < 0 ? header.length : why;
  final columns = [
    for (final c in header)
      // An output column's type makes its words values (ahead, back...):
      // the robot's own, else the command's.
      if (c.startsWith('=>') && !c.contains(':'))
        '=> ${c.substring(2).trim()}: ${commands[c.substring(2).trim()]}'
      else
        c,
  ]..insert(at, '=> rule: number');
  return {
    'params': {
      for (final MapEntry(:key, :value) in sensors.entries) key: value.$1,
    },
    'returns': 'Act',
    'body': [
      columns,
      for (var i = 1; i < table.length; i++) [...table[i]]..insert(at, '$i'),
    ],
  };
}

/// The world model for a battle between [robots] (aityx robot models, in
/// order: r1, r2...), built on [world] (models/world.json).
Map<String, Object?> battleModel(
  Map<String, Object?> world,
  List<Object?> robots,
) {
  if (robots.length < 2) throw InvalidBattle('a battle needs two robots');
  if (robots.length > 10) throw InvalidBattle('at most 10 robots');
  final functions = Map<String, Object?>.of(
    (world['functions'] as Map).cast<String, Object?>(),
  );
  final args = sensors.keys.map((s) => 's.$s').join(', ');
  final chain = StringBuffer();
  for (var i = 0; i < robots.length; i++) {
    final id = robotId(i);
    final name = (robots[i] as Map?)?['name'] ?? id;
    functions['brain_$id'] = brainFunction(actionTable(robots[i], '$name'));
    chain.write('if s.id = "$id" then brain_$id($args) else ');
  }
  chain.write('{drive: "stop", turn: "none", gun: "hold", fire: 0, rule: 0}');
  functions['brain_of'] = {
    'params': {'s': 'Sense'},
    'returns': 'Act',
    'body': chain.toString(),
  };
  return {...world, 'functions': functions};
}

/// The body sent to aityx: the battle's model and the state to play from,
/// [world] (`tick`, `bots`, `bullets`) for [turns] turns.
Map<String, Object?> battleRequest(
  Map<String, Object?> worldModel,
  List<Object?> robots,
  Object? world,
  int turns,
) {
  if (world is! Map || world['bots'] is! List || world['bullets'] is! List) {
    throw InvalidBattle('world needs bots and bullets');
  }
  final bots = world['bots'] as List;
  if (bots.length != robots.length) {
    throw InvalidBattle('${robots.length} robots for ${bots.length} bots');
  }
  for (var i = 0; i < bots.length; i++) {
    if ((bots[i] as Map?)?['id'] != robotId(i)) {
      throw InvalidBattle('bot ${i + 1} must have id ${robotId(i)}');
    }
  }
  if (turns < 1 || turns > 50) throw InvalidBattle('turns must be 1 to 50');
  return {
    'decision': battleModel(worldModel, robots),
    'state': {'world': world, 'turns': turns},
  };
}

/// The frames in aityx's [answer]: the world after each turn.
List<Object?> framesOf(Map<String, Object?> answer) {
  if (answer['decision_error'] case final Map error) {
    throw InvalidBattle(
      'the battle failed: ${error['detail'] ?? error['code']}',
    );
  }
  final frames = (answer['answers'] as Map?)?['frames'];
  final value = frames is Map ? frames['value'] : null;
  if (value is! List) throw InvalidBattle('aityx answered without frames');
  return value;
}
