/// The battle's physics (models/world.json) played on aityx.ai, checked
/// against Robocode's rules with robots that do one thing: bullet damage
/// and the shooter's gain, a kill, a wall, a ram, turning by speed. Tagged
/// `aityx`: skipped by `dart test`, run by scripts/model-test.sh, which
/// passes AITYX_API_KEY and AITYX_URL.
@Tags(['aityx'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:roborules_api/battle.dart';
import 'package:test/test.dart';

/// A robot that always does the same: [drive], [turn], [gun], [fire].
Map<String, Object?> always(
  String drive,
  String turn, {
  String gun = 'hold',
  num fire = 0,
}) => {
  'name': 'Always $drive $turn',
  'inputs': sensorInputs(),
  'decisions': {
    'action': {
      'desc': 'One rule',
      'table': [
        [
          '=> drive: ahead|back|stop',
          '=> turn: left|right|none|toward_enemy|away_from_enemy|perpendicular',
          '=> gun: aim|sweep_left|sweep_right|hold',
          '=> fire: number',
          '# why',
        ],
        [drive, turn, gun, '$fire', 'Always.'],
      ],
    },
  },
};

Map<String, Object?> bot(
  int i,
  num x,
  num y, {
  num heading = 90,
  num v = 0,
  num energy = 100,
}) => {
  'id': robotId(i),
  'x': x,
  'y': y,
  'heading': heading,
  'v': v,
  'gun': heading,
  'energy': energy,
  'heat': 0,
  'alive': true,
  'rule': 0,
  'hit': false,
  'damage': 0,
  'fired': 0,
  'died': 0,
};

late final Map<String, Object?> world;
late final String key;
late final Uri aityx;
final client = HttpClient();

/// The frames of [turns] turns of [robots] from [bots].
Future<List<Map>> play(
  List<Map<String, Object?>> robots,
  List<Map<String, Object?>> bots,
  int turns,
) async {
  final sent = battleRequest(world, robots, {
    'tick': 0,
    'bots': bots,
    'bullets': [],
  }, turns);
  final call = await client.postUrl(aityx.resolve('/v1/systemone'));
  call.headers
    ..set('Authorization', 'Bearer $key')
    ..contentType = ContentType.json;
  call.write(jsonEncode(sent));
  final response = await call.close();
  final text = await response.transform(utf8.decoder).join();
  expect(response.statusCode, 200, reason: text);
  return framesOf(jsonDecode(text) as Map<String, Object?>).cast<Map>();
}

Map botIn(Map frame, int i) => (frame['bots'] as List)[i] as Map;

void main() {
  setUpAll(() {
    final env = Platform.environment;
    key = env['AITYX_API_KEY'] ?? '';
    aityx = Uri.parse(
      (env['AITYX_URL'] ?? '').isEmpty
          ? 'https://api.aityx.ai'
          : env['AITYX_URL']!,
    );
    world = jsonDecode(
      File('models/world.json').readAsStringSync(),
    ) as Map<String, Object?>;
  });
  tearDownAll(() => client.close());

  test('a power-3 bullet: 16 damage, the shooter gains 9', () async {
    // r1 fires once (its gun stays hot), r2 sits 100 px to its right.
    final frames = await play(
      [always('stop', 'none', fire: 3), always('stop', 'none')],
      [bot(0, 200, 300), bot(1, 300, 300)],
      8,
    );
    final first = frames.first;
    expect(botIn(first, 0)['fired'], 3);
    expect(botIn(first, 0)['energy'], 97); // 100 - 3 to fire
    expect((first['bullets'] as List), hasLength(1));
    final last = frames.last;
    expect(botIn(last, 1)['energy'], 84); // 100 - (4 * 3 + 2 * 2)
    expect(
      botIn(last, 1)['hit'] || frames.any((f) => botIn(f, 1)['hit']),
      isTrue,
    );
    expect(botIn(last, 0)['energy'], 106); // 97 + 3 * 3
    expect(botIn(last, 0)['damage'], 16);
    expect(last['bullets'], isEmpty);
  });

  test('a kill: the robot dies on the turn it reaches 0', () async {
    final frames = await play(
      [always('stop', 'none', fire: 3), always('stop', 'none')],
      [bot(0, 200, 300), bot(1, 300, 300, energy: 10)],
      8,
    );
    final death = frames.firstWhere((f) => botIn(f, 1)['alive'] == false);
    expect(botIn(death, 1)['energy'], 0);
    expect(botIn(death, 1)['died'], death['tick']);
    expect(botIn(frames.last, 1)['died'], death['tick']);
  });

  test('a wall stops the robot and costs |v| / 2 - 1', () async {
    // Heading west at full speed, 24 px from the left wall: 8 px moves it
    // past the 18 px it can reach.
    final frames = await play(
      [always('ahead', 'none'), always('stop', 'none')],
      [bot(0, 24, 300, heading: 270, v: 8), bot(1, 600, 300)],
      3,
    );
    final hit = frames.first;
    expect(botIn(hit, 0)['x'], 18);
    expect(botIn(hit, 0)['v'], 0);
    expect(botIn(hit, 0)['energy'], 97); // 8 / 2 - 1 = 3
  });

  test('a ram: both stop where they were and lose 0.6', () async {
    final frames = await play(
      [always('ahead', 'none'), always('ahead', 'none')],
      [
        bot(0, 300, 300, heading: 90, v: 8),
        bot(1, 340, 300, heading: 270, v: 8),
      ],
      1,
    );
    final f = frames.first;
    expect(botIn(f, 0)['x'], 300);
    expect(botIn(f, 1)['x'], 340);
    expect(botIn(f, 0)['v'], 0);
    expect(botIn(f, 0)['energy'], 99.4);
    expect(botIn(f, 1)['energy'], 99.4);
  });

  test('turning: 10 degrees a turn standing, 4 at full speed', () async {
    final frames = await play(
      [always('stop', 'right'), always('ahead', 'right')],
      [bot(0, 200, 300, heading: 0), bot(1, 600, 300, heading: 0, v: 8)],
      1,
    );
    expect(botIn(frames.first, 0)['heading'], 10);
    expect(botIn(frames.first, 1)['heading'], 4);
  });

  test('speed: +1 a turn up to 8, braking 2 a turn', () async {
    final frames = await play(
      [always('ahead', 'none'), always('stop', 'none')],
      [bot(0, 100, 300), bot(1, 600, 500, v: 8, heading: 90)],
      10,
    );
    expect(
      [for (final f in frames) botIn(f, 0)['v']],
      [
        1, 2, 3, 4, 5, 6, 7, 8, 8, 8, //
      ],
    );
    expect([for (final f in frames.take(5)) botIn(f, 1)['v']], [6, 4, 2, 0, 0]);
  });
}
