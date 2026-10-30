import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokerface_app/api/aityx_poker_api.dart';
import 'package:pokerface_app/api/poker_api.dart';
import 'package:pokerface_app/engine/game.dart';

import 'table_test.dart' show situation;

/// What aityx answers the Rock calling with a pair: rule 10 fired.
const _calls = {
  'answers': {
    'action': {'type': 'choice', 'choice': 'call'},
    'raise_to': {'type': 'number', 'number': 60},
    'strong_made': {'type': 'noul', 'noul': 0},
  },
  'receipt': {
    'decisions': {
      'action': {'value': 'call', 'rule': 10},
    },
  },
};

const _rock = Strategy(
  id: 'rock',
  name: 'The Rock',
  tagline: '',
  decisions: {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What the mock was asked, in order.
  late List<http.Request> asked;

  /// An AityxPokerApi on the user key `test-key`, whose aityx answers
  /// with [answer].
  AityxPokerApi api(
    Future<http.Response> Function(http.Request) answer, {
    AityxConnection? connection,
  }) => AityxPokerApi(
    aityx: AityxClient(
      client: MockClient((request) {
        asked.add(request);
        return answer(request);
      }),
      connection: connection ?? AityxConnection.user('test-key'),
    ),
  );

  /// aityx answering [status] with [body] as JSON.
  Future<http.Response> Function(http.Request) answers(
    int status,
    Object body,
  ) =>
      (_) async => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Matcher fails(String message) =>
      throwsA(isA<ApiException>().having((e) => e.message, 'message', message));

  setUp(() => asked = []);

  group('the strategies', () {
    test('are the presets in the assets, in file order', () async {
      final presets = await AityxPokerApi(bundle: rootBundle).strategies();
      expect(presets.map((s) => s.id), [
        'maniac',
        'mathematician',
        'rock',
        'shark',
        'station',
      ]);
      expect(presets.firstWhere((s) => s.id == 'rock').name, 'The Rock');
      expect(presets.every((s) => !s.custom), isTrue);
    });
  });

  group('a decision', () {
    test('is one systemone call on the key, read into the action', () async {
      final result = await api(answers(200, _calls)).act(_rock, situation());
      expect(asked, hasLength(1));
      final request = asked.single;
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://api.aityx.ai/v1/systemone'));
      expect(request.headers['Authorization'], 'Bearer test-key');
      final sent = jsonDecode(request.body) as Map;
      expect((sent['decision'] as Map)['name'], endsWith('· The Rock'));
      expect(sent['state'], situation());

      expect(result.kind, ActionKind.call);
      expect(result.raiseTo, 60);
      expect(result.rule, 10);
      expect(result.why, startsWith('A pair that is likely best: call'));
      expect(result.decisions, {'strong_made': 0});
      // The call for the sidebar: the body sent, never the headers.
      expect(result.request, sent);
      expect(jsonEncode(result.request), isNot(contains('test-key')));
      expect(result.response, _calls);
      expect(result.tookMs, isNotNull);
    });

    test("sends a custom strategy's own rules", () async {
      const mine = Strategy(
        id: 'custom-1',
        name: 'Mine',
        tagline: '',
        decisions: {
          'action': {'type': 'Action', 'expr': '"call"'},
          'raise_to': {'type': 'number', 'expr': 'min_raise'},
        },
        custom: true,
      );
      await api(answers(200, _calls)).act(mine, situation());
      final decision = (jsonDecode(asked.single.body) as Map)['decision'];
      expect((decision as Map)['decisions'], mine.decisions);
      expect(decision['name'], endsWith('· Mine'));
    });

    test(
      'goes through the dev proxy without an Authorization header',
      () async {
        await api(
          answers(200, _calls),
          connection: AityxConnection.dev(
            Uri.parse('http://localhost:8800/pokerface/'),
          ),
        ).act(_rock, situation());
        expect(
          asked.single.url,
          Uri.parse('http://localhost:8800/aityx/v1/systemone'),
        );
        expect(asked.single.headers.containsKey('Authorization'), isFalse);
      },
    );

    test("is refused with the API's words, before calling aityx", () async {
      final poker = api(answers(200, _calls));
      await expectLater(
        poker.act(_rock, situation()..remove('equity')),
        fails('situation.equity is required'),
      );
      await expectLater(
        poker.act(
          const Strategy(id: 'nit', name: 'Nit', tagline: '', decisions: {}),
          situation(),
        ),
        fails('unknown strategy "nit"'),
      );
      await expectLater(
        poker.act(
          const Strategy(
            id: 'custom-1',
            name: 'Half',
            tagline: '',
            decisions: {'action': {}},
            custom: true,
          ),
          situation(),
        ),
        fails('strategy.decisions.raise_to is required'),
      );
      await expectLater(
        poker.act(
          Strategy(
            id: 'custom-1',
            name: 'Huge',
            tagline: 'x' * (70 * 1024),
            decisions: const {'action': {}, 'raise_to': {}},
            custom: true,
          ),
          situation(),
        ),
        fails('request too large'),
      );
      expect(asked, isEmpty);
    });

    test('says when there is no key, without calling aityx', () async {
      final poker = AityxPokerApi(
        aityx: AityxClient(
          client: MockClient((request) async {
            asked.add(request);
            return http.Response('{}', 200);
          }),
          store: AityxKeyStore.memory(),
        ),
      );
      await expectLater(
        poker.act(_rock, situation()),
        fails('aityx is not set up: set your key on the index page'),
      );
      expect(asked, isEmpty);
    });

    test('says when aityx rejects the key', () async {
      await expectLater(
        api(answers(401, {'code': 'unauthorized'})).act(_rock, situation()),
        fails('aityx rejected the key'),
      );
    });

    test("passes aityx's problem details on, for the editor", () async {
      await expectLater(
        api(
          answers(422, {
            'code': 'invalid_decision',
            'detail': 'the model has errors',
            'errors': [
              {'path': 'decision.decisions.action', 'message': 'bad cell'},
            ],
          }),
        ).act(_rock, situation()),
        fails(
          'aityx answered HTTP 422: invalid_decision; the model has errors; '
          'decision.decisions.action: bad cell',
        ),
      );
      await expectLater(
        api((_) async => http.Response('<html>oops</html>', 500))
            .act(_rock, situation()),
        fails('aityx answered HTTP 500'),
      );
    });

    test("keeps aityx's details out of sight if they hold the key", () async {
      await expectLater(
        api(answers(422, {'code': 'invalid_decision', 'detail': 'test-key'}))
            .act(_rock, situation()),
        fails('aityx answered HTTP 422'),
      );
    });

    test('says when aityx did not answer', () async {
      await expectLater(
        api((_) async => throw http.ClientException('failed'))
            .act(_rock, situation()),
        fails('aityx did not answer'),
      );
      // Past the deadline (30 s at the table; shorter here).
      await expectLater(
        AityxPokerApi(
          timeout: const Duration(milliseconds: 50),
          aityx: AityxClient(
            client: MockClient((_) async {
              await Future<void>.delayed(const Duration(seconds: 2));
              return http.Response(jsonEncode(_calls), 200);
            }),
            connection: AityxConnection.user('test-key'),
          ),
        ).act(_rock, situation()),
        fails('aityx did not answer'),
      );
      // The dev proxy, when it can't reach aityx.
      await expectLater(
        api(
          answers(502, {
            'code': 'proxy_unreachable',
            'detail': 'aityx did not answer: SocketException',
          }),
        ).act(_rock, situation()),
        fails('aityx did not answer'),
      );
    });

    test('fails when the answer holds no action', () async {
      await expectLater(
        api(
          answers(200, {
            'decision_error': {'code': 'invalid_state', 'detail': 'x'},
          }),
        ).act(_rock, situation()),
        fails(
          'aityx could not decide it: the strategy failed: invalid_state, x',
        ),
      );
      await expectLater(
        api(answers(200, {'answers': {}, 'receipt': {}}))
            .act(_rock, situation()),
        fails('aityx could not decide it: no action'),
      );
      await expectLater(
        api((_) async => http.Response('not json', 200))
            .act(_rock, situation()),
        fails('unexpected answer from aityx'),
      );
      // JSON, but not shaped like aityx's answer.
      await expectLater(
        api(
          answers(200, {
            'answers': {'action': 'call'},
            'receipt': {},
          }),
        ).act(_rock, situation()),
        fails('unexpected answer from aityx'),
      );
    });

    test("plays a custom strategy's row whose why isn't text", () async {
      const odd = Strategy(
        id: 'custom-1',
        name: 'Odd',
        tagline: '',
        decisions: {
          'action': {
            'type': 'Action',
            'table': [
              ['equity', '# why', 'action'],
              ['-', 42, '"call"'],
            ],
          },
          'raise_to': {'type': 'number', 'expr': 'min_raise'},
        },
        custom: true,
      );
      final result = await api(
        answers(200, {
          'answers': _calls['answers'],
          'receipt': {
            'decisions': {
              'action': {'value': 'call', 'rule': 1},
            },
          },
        }),
      ).act(odd, situation());
      expect(result.kind, ActionKind.call);
      expect(result.rule, 1);
      expect(result.why, isNull);
    });

    test('keeps the call out of sight if the answer holds the key', () async {
      final result = await api(answers(200, {..._calls, 'echo': 'test-key'}))
          .act(_rock, situation());
      expect(result.kind, ActionKind.call);
      expect(result.request, isNull);
      expect(result.response, isNull);
    });
  });
}
