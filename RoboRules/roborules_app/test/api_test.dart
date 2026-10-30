import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roborules_app/battle/api.dart';
import 'package:roborules_app/battle/model.dart';
import 'package:roborules_app/battle/predefined_robots.dart';
import 'package:roborules_app/battle/random_robots.dart';

Map<String, Object?> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Bot _bot(int i, {double energy = 100, int died = 0, double damage = 0}) => Bot(
  id: 'r${i + 1}',
  x: 100.0 + 200 * i,
  y: 300,
  heading: 90,
  v: 0,
  gun: 90,
  energy: energy,
  heat: 0,
  alive: died == 0,
  rule: 0,
  hit: false,
  damage: damage,
  fired: 0,
  died: died,
);

/// The world aityx would answer after a turn of [from].
Map<String, Object?> _next(World from) {
  final json = from.toJson();
  return {...json, 'tick': from.tick + 1};
}

void main() {
  final world = _json('assets/models/world.json');
  final scoring = _json('assets/models/scoring.json');
  final factory = RobotFactory(Random(1));
  final robots = [
    for (final name in ['SpinBot', 'Walls'])
      sampleRobots
          .firstWhere((k) => k.name == name)
          .make(taken: const [], factory: factory),
  ];
  final start = World(tick: 0, bots: [_bot(0), _bot(1)], bullets: const []);

  /// The API on [answer], with the user's key 'test-key'; [sent] gets
  /// each request.
  AityxBattleApi api(
    Future<http.Response> Function(http.Request request) answer, {
    List<http.Request>? sent,
  }) => AityxBattleApi(
    client: AityxClient(
      client: MockClient((request) {
        sent?.add(request);
        return answer(request);
      }),
      connection: AityxConnection.user('test-key'),
    ),
    world: world,
    scoring: scoring,
  );

  Matcher failsWith(String message) => throwsA(
    isA<BattleException>().having((e) => e.message, 'message', message),
  );

  group('turns', () {
    test(
      'sends the battle model and the world, and reads the frames',
      () async {
        final sent = <http.Request>[];
        final frames = [_next(start), _next(World.fromJson(_next(start)))];
        final turns = await api(
          (request) async => http.Response(
            jsonEncode({
              'answers': {
                'frames': {'value': frames},
              },
            }),
            200,
          ),
          sent: sent,
        ).turns(robots, start, 2);

        final request = sent.single;
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://api.aityx.ai/v1/systemone');
        expect(request.headers['Authorization'], 'Bearer test-key');
        final body = jsonDecode(request.body) as Map;
        expect(body['state'], {'world': start.toJson(), 'turns': 2});
        final functions = (body['decision'] as Map)['functions'] as Map;
        expect(
          functions.keys,
          containsAll(['brain_r1', 'brain_r2', 'brain_of']),
        );

        expect(turns.frames.map((f) => f.tick), [1, 2]);
        // The call kept for the viewer: the body sent, never the headers.
        expect(jsonEncode(turns.request), request.body);
        expect(jsonEncode(turns.request), isNot(contains('test-key')));
        expect((turns.response as Map)['answers'], isNotNull);
      },
    );

    test(
      'dev mode: the index server\'s proxy, with no key in the app',
      () async {
        final sent = <http.Request>[];
        final dev = AityxBattleApi(
          client: AityxClient(
            client: MockClient((request) async {
              sent.add(request);
              return http.Response(
                jsonEncode({
                  'answers': {
                    'frames': {
                      'value': [_next(start)],
                    },
                  },
                }),
                200,
              );
            }),
            connection: AityxConnection.dev(
              Uri.parse('http://localhost:8800/roborules/'),
              url: 'https://api.aityx.ai',
              devKeyFrom: '.env',
            ),
          ),
          world: world,
          scoring: scoring,
        );
        final turns = await dev.turns(robots, start, 1);
        final request = sent.single;
        expect(
          request.url.toString(),
          'http://localhost:8800/aityx/v1/systemone',
        );
        expect(
          request.headers.keys.map((h) => h.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(turns.frames.single.tick, 1);
        expect(turns.request, isNotNull);
      },
    );

    test('an answer holding the key is not kept for the viewer', () async {
      final turns = await api(
        (request) async => http.Response(
          jsonEncode({
            'answers': {
              'frames': {
                'value': [_next(start)],
              },
            },
            'echo': 'Bearer test-key',
          }),
          200,
        ),
      ).turns(robots, start, 1);
      expect(turns.frames.single.tick, 1);
      expect(turns.request, isNull);
      expect(turns.response, isNull);
    });

    test("refuses a battle aityx can't play, without calling it", () async {
      final sent = <http.Request>[];
      final one = api((request) async => http.Response('{}', 200), sent: sent);
      await expectLater(
        one.turns([robots.first], start, 5),
        failsWith('1 robots for 2 bots'),
      );
      await expectLater(
        one.turns(
          [robots.first],
          World(tick: 0, bots: [_bot(0)], bullets: const []),
          5,
        ),
        failsWith('a battle needs two robots'),
      );
      await expectLater(
        one.turns(robots, start, 51),
        failsWith('turns must be 1 to 50'),
      );
      final bad = Robot(
        name: 'Bad',
        color: Colors.red,
        rules: [Rule(drive: 'dance')],
      );
      await expectLater(
        one.turns([robots.first, bad], start, 5),
        throwsA(
          isA<BattleException>().having(
            (e) => e.message,
            'message',
            startsWith('Bad, rule 1: drive must be one of'),
          ),
        ),
      );
      expect(sent, isEmpty);
    });

    test('a decision error: the battle failed, with why', () async {
      final failing = api(
        (request) async => http.Response(
          jsonEncode({
            'answers': {},
            'decision_error': {
              'code': 'evaluation_failed',
              'detail': 'brain_r2: no rule matched',
            },
          }),
          200,
        ),
      );
      await expectLater(
        failing.turns(robots, start, 5),
        failsWith('the battle failed: brain_r2: no rule matched'),
      );
    });

    test('an answer without frames, or not JSON', () async {
      await expectLater(
        api((request) async => http.Response('{"answers": {}}', 200))
            .turns(robots, start, 5),
        failsWith('aityx answered without frames'),
      );
      await expectLater(
        api((request) async => http.Response('<html>', 200))
            .turns(robots, start, 5),
        failsWith('unexpected answer from aityx'),
      );
      await expectLater(
        api(
          (request) async =>
              http.Response('{"answers": {"frames": {"value": [1]}}}', 200),
        ).turns(robots, start, 5),
        failsWith('unexpected answer from aityx'),
      );
    });
  });

  group('what a failed call says', () {
    Future<void> expectProblem(int status, String body, String message) =>
        expectLater(
          api((request) async => http.Response(body, status))
              .turns(robots, start, 5),
          failsWith(message),
        );

    test('a rejected key', () async {
      await expectProblem(
        401,
        '{"detail": "invalid API key"}',
        'aityx rejected the key',
      );
      await expectProblem(403, '', 'aityx rejected the key');
    });

    test("aityx's status, detail and errors", () async {
      await expectProblem(
        422,
        jsonEncode({
          'code': 'invalid_model',
          'detail': 'The model has errors.',
          'errors': [
            {'message': 'brain_r1: unknown name "enemy_mood"'},
          ],
        }),
        'aityx answered HTTP 422: The model has errors. '
        'brain_r1: unknown name "enemy_mood"',
      );
      await expectProblem(500, 'oops', 'aityx answered HTTP 500');
      // The index server's dev proxy, when aityx is down.
      await expectProblem(
        502,
        '{"code": "proxy_unreachable", '
            '"detail": "aityx did not answer: SocketException"}',
        'aityx answered HTTP 502: aityx did not answer: SocketException',
      );
    });

    test('no answer', () async {
      await expectLater(
        api((request) async => throw http.ClientException('failed'))
            .turns(robots, start, 5),
        failsWith('aityx did not answer'),
      );
    });

    test('no key: set it on the index page, without calling aityx', () async {
      var calls = 0;
      final none = AityxBattleApi(
        client: AityxClient(
          client: MockClient((request) async {
            calls++;
            return http.Response('{}', 200);
          }),
          connection: AityxConnection.none,
        ),
        world: world,
        scoring: scoring,
      );
      await expectLater(
        none.turns(robots, start, 5),
        failsWith('aityx is not set up: set your key on the index page'),
      );
      await expectLater(
        none.score(start),
        failsWith('aityx is not set up: set your key on the index page'),
      );
      expect(calls, 0);
    });
  });

  group('score', () {
    test('sends each robot\'s result, and reads the scores', () async {
      final sent = <http.Request>[];
      final last = World(
        tick: 40,
        bots: [_bot(0, damage: 16), _bot(1, energy: 0, died: 40)],
        bullets: const [],
      );
      final score = await api(
        (request) async => http.Response(
          jsonEncode({
            'answers': {
              'scores': {
                'value': [
                  {
                    'id': 'r1',
                    'survival': 50,
                    'last_survivor': 10,
                    'bullet_damage': 16,
                    'total': 76,
                  },
                  {
                    'id': 'r2',
                    'survival': 0,
                    'last_survivor': 0,
                    'bullet_damage': 0,
                    'total': 0,
                  },
                ],
              },
              'winner': {'value': 'r1'},
            },
          }),
          200,
        ),
        sent: sent,
      ).score(last);

      final body = jsonDecode(sent.single.body) as Map;
      expect((body['decision'] as Map)['name'], 'RoboRules · Scoring a round');
      expect(body['state'], {
        'results': [
          {'id': 'r1', 'died': 0, 'damage': 16.0},
          {'id': 'r2', 'died': 40, 'damage': 0.0},
        ],
      });
      expect(score.winner, 'r1');
      expect(score.scores.map((s) => s.total), [76, 0]);
      expect(score.request, isNotNull);
      expect(score.response, isNotNull);
    });

    test('an answer without scores', () async {
      await expectLater(
        api((request) async => http.Response('{"answers": {}}', 200))
            .score(start),
        failsWith('aityx answered without scores'),
      );
    });
  });

  test('the models load from the app\'s assets', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final sent = <http.Request>[];
    final assets = AityxBattleApi(
      client: AityxClient(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('{"answers": {}}', 200);
        }),
        connection: AityxConnection.user('test-key'),
      ),
    );
    await expectLater(
      assets.score(start),
      failsWith('aityx answered without scores'),
    );
    await expectLater(
      assets.turns(robots, start, 5),
      failsWith('aityx answered without frames'),
    );
    expect(sent, hasLength(2));
    expect((jsonDecode(sent.first.body) as Map)['decision'], scoring);
    final battle = (jsonDecode(sent.last.body) as Map)['decision'] as Map;
    expect(battle['name'], world['name']);
    expect(
      (battle['functions'] as Map).keys,
      containsAll((world['functions'] as Map).keys),
    );
  });
}
