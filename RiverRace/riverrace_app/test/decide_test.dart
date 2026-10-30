import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverrace_app/strategy/decide.dart';
import 'package:riverrace_app/strategy/strategy.dart';

import 'decision_request_test.dart' show calm;

/// Careful and Daredevil, both on open water.
final pilots = [
  PilotAsk('p1', careful(), calm().cast<String, Object>()),
  PilotAsk('p2', daredevil(), calm({'fuel': 30}).cast<String, Object>()),
];

/// What aityx answers when p1's rule 2 fires and nothing matches for p2.
Map<String, Object?> answered() => {
  'answers': {
    'p1_action': {
      'value': {'steer': 'dodge', 'throttle': 'slow', 'fire': true},
    },
    'p2_action': {
      'value': {'steer': 'straight', 'throttle': 'normal', 'fire': false},
    },
  },
  'receipt': {
    'functions': {
      'strategy_p1': [
        {'rule': 2},
      ],
      'strategy_p2': [
        {'rule': 99},
      ],
    },
  },
  'usage': {'input_tokens': 1234},
};

/// A decider on the user's key, [answer] standing in for aityx.
AityxDecider decider(
  Future<http.Response> Function(http.Request request) answer,
) => AityxDecider(
  client: AityxClient(
    client: MockClient(answer),
    connection: AityxConnection.user('test-key'),
  ),
);

Future<String> failure(
  Future<http.Response> Function(http.Request request) answer, {
  List<PilotAsk>? asking,
}) async {
  try {
    await decider(answer).decide(7, asking ?? pilots);
  } on DecideException catch (e) {
    return e.message;
  }
  fail('no DecideException');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asks aityx for both pilots and reads what each does', () async {
    late http.Request sent;
    final decision = await decider((request) async {
      sent = request;
      return http.Response(jsonEncode(answered()), 200);
    }).decide(7, pilots);

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.aityx.ai/v1/systemone');
    expect(sent.headers['Authorization'], 'Bearer test-key');
    final body = jsonDecode(sent.body) as Map;
    final decided = (body['decision'] as Map).cast<String, Object?>();
    // The bundled model's types, with each pilot's table.
    expect((decided['types'] as Map).keys, containsAll(['Sense', 'Act']));
    expect((decided['functions'] as Map).keys, ['strategy_p1', 'strategy_p2']);
    expect((body['state'] as Map)['p2'], containsPair('fuel', 30));

    expect(decision.tick, 7);
    expect(decision.actions['p1']!.steer, 'dodge');
    expect(decision.actions['p1']!.fire, isTrue);
    expect(decision.actions['p1']!.rule, 2);
    expect(decision.actions['p1']!.why, careful().rules[1].why);
    // Not one of p2's rules: the else row the app added.
    expect(decision.actions['p2']!.rule, 0);
    expect(decision.actions['p2']!.why, 'No rule matched: fly straight on.');
    // The calls panel shows the body sent, never the headers.
    expect(decision.aityxRequest, body);
    expect(jsonEncode(decision.aityxRequest), isNot(contains('test-key')));
    expect(decision.aityxResponse, answered());
    expect(decision.tookMs, isNotNull);
    expect(decision.inputTokens, 1234);
  });

  test('leaves the call out when the answer holds the key', () async {
    final decision = await decider(
      (_) async =>
          http.Response(jsonEncode({...answered(), 'echo': 'test-key'}), 200),
    ).decide(7, pilots);
    expect(decision.actions['p1']!.rule, 2);
    expect(decision.aityxRequest, isNull);
    expect(decision.aityxResponse, isNull);
    expect(decision.tookMs, isNull);
  });

  test('with the dev key, asks the index server, which adds the key', () async {
    final origin = Uri.parse('http://localhost:8800/riverrace/');
    final asked = <String>[];
    final decision = await AityxDecider(
      client: AityxClient(
        client: MockClient((request) async {
          asked.add('${request.method} ${request.url}');
          if (request.url.path == '/aityx/config') {
            return http.Response(
              '{"available": true, "url": "https://api.aityx.ai", '
              '"source": ".env"}',
              200,
            );
          }
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(jsonEncode(answered()), 200);
        }),
        store: AityxKeyStore.memory(),
        origin: origin,
      ),
    ).decide(7, pilots);
    expect(asked, [
      'GET http://localhost:8800/aityx/config',
      'POST http://localhost:8800/aityx/v1/systemone',
    ]);
    expect(decision.actions['p1']!.rule, 2);
  });

  test('without a key, says to set it, and asks nothing', () async {
    var calls = 0;
    final noKey = AityxDecider(
      client: AityxClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
        store: AityxKeyStore.memory(),
      ),
    );
    await expectLater(
      noKey.decide(7, pilots),
      throwsA(
        isA<DecideException>().having(
          (e) => e.message,
          'message',
          'aityx is not set up: set your key on the index page',
        ),
      ),
    );
    expect(calls, 0);
  });

  test('a rejected key, and an unreachable aityx, say so', () async {
    expect(
      await failure((_) async => http.Response('{"code":"unauthorized"}', 401)),
      'aityx rejected the key',
    );
    expect(
      await failure((_) async => throw http.ClientException('blocked')),
      'aityx did not answer',
    );
    // The index server's dev proxy, when it can't reach aityx.
    expect(
      await failure(
        (_) async => http.Response(
          '{"code":"proxy_unreachable","detail":"aityx did not answer: '
          'SocketException"}',
          502,
        ),
      ),
      'aityx did not answer',
    );
  });

  test("aityx's errors are shown with its problems", () async {
    expect(
      await failure(
        (_) async => http.Response(
          jsonEncode({
            'code': 'invalid_model',
            'detail': 'The model has errors',
            'errors': [
              {'message': 'strategy_p1, row 2: "lots" is not a number test'},
            ],
          }),
          422,
        ),
      ),
      'aityx could not decide: aityx answered HTTP 422: The model has errors '
      '(strategy_p1, row 2: "lots" is not a number test).',
    );
    expect(
      await failure((_) async => http.Response('oops', 500)),
      'aityx could not decide: aityx answered HTTP 500.',
    );
    expect(
      await failure((_) async => http.Response('not json', 200)),
      'aityx could not decide: unexpected answer from aityx.',
    );
    expect(
      await failure(
        (_) async => http.Response(
          '{"decision_error": {"code": "x", "detail": "no row matched"}}',
          200,
        ),
      ),
      'aityx could not decide: aityx could not decide it: the strategies '
      'failed: no row matched.',
    );
  });

  test('a strategy aityx could not run is refused before the call', () async {
    var calls = 0;
    Future<http.Response> count(http.Request _) async {
      calls++;
      return http.Response('{}', 200);
    }

    final tooMany = careful()
      ..rules.addAll([for (var i = 0; i < 40; i++) Rule(why: 'More.')]);
    expect(
      await failure(count, asking: [PilotAsk('p1', tooMany, pilots[0].sense)]),
      'aityx could not decide: p1: at most 40 rules.',
    );
    expect(
      await failure(
        count,
        asking: [
          PilotAsk('p1', careful(), {...pilots[0].sense}..remove('fuel')),
        ],
      ),
      'aityx could not decide: p1: sense.fuel must be number.',
    );
    expect(calls, 0);
  });
}
