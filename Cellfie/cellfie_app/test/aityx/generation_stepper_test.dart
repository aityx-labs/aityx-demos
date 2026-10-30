import 'dart:convert';
import 'dart:io';

import 'package:aityx_web/aityx_web.dart';
import 'package:cellfie_app/aityx/generation_stepper.dart';
import 'package:cellfie_app/aityx/life.dart';
import 'package:cellfie_app/life/board.dart';
import 'package:cellfie_app/life/generation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A real call, from api.aityx.ai, for generation 7 of a board with a
/// glider, a block, a standing blinker and a five-cell soup (the same
/// fixture as life_test.dart).
final fixture = jsonDecode(
  File('test/fixtures/generation-7.json').readAsStringSync(),
) as Map<String, Object?>;
final sentFixture = (fixture['request'] as Map).cast<String, Object?>();
final answerFixture = (fixture['response'] as Map).cast<String, Object?>();
final stateFixture = (sentFixture['state'] as Map).cast<String, Object?>();

/// The fixture's model: what was sent, without the state.
Future<Map<String, Object?>> fixtureModel() async =>
    {...sentFixture}..remove('state');

/// A board that counts as the fixture's state: its situations, with as
/// many cells each, and its clusters' shapes.
({
  int generation,
  Map<String, bool> rules,
  Map<SituationKey, List<Cell>> situations,
  List<Cluster> clusters,
})
fixtureBoard() => (
  generation: stateFixture['generation'] as int,
  rules: (stateFixture['rules'] as Map).cast<String, bool>(),
  situations: {
    for (final s in (stateFixture['situations'] as List).cast<Map>())
      (alive: s['alive'] as bool, neighbours: s['neighbours'] as int): [
        for (var i = 0; i < (s['cells'] as int); i++) (x: i, y: 0),
      ],
  },
  clusters: [
    for (final c in (stateFixture['clusters'] as List).cast<Map>())
      Cluster(cellsOf(c['shape'] as String)),
  ],
);

/// What the app sends for the fixture's board: the fixture's request,
/// but each cluster's shape as the app's canonicalShape writes it (the
/// fixture's soup was written by hand).
Map<String, Object?> sentForBoard() {
  final board = fixtureBoard();
  return {
    ...sentFixture,
    'state': stateFrom(
      generationBody(
        board.generation,
        board.rules,
        board.situations,
        board.clusters,
      ),
    ),
  };
}

/// [stepper]'s step on the fixture's board.
Future<GenerationOutcome> stepFixture(GenerationStepper stepper) {
  final board = fixtureBoard();
  return stepper.step(
    board.generation,
    board.rules,
    board.situations,
    board.clusters,
  );
}

/// A stepper on the user's key 'test-key', whose aityx answers [answer].
AityxGenerationStepper stepperAnswering(
  Future<http.Response> Function(http.Request request) answer,
) => AityxGenerationStepper(
  aityx: AityxClient(
    client: MockClient(answer),
    connection: AityxConnection.user('test-key'),
  ),
  model: fixtureModel,
);

/// [stepper]'s failure on the fixture's board: its message.
Future<GenerationException> failure(GenerationStepper stepper) async {
  try {
    await stepFixture(stepper);
  } on GenerationException catch (error) {
    return error;
  }
  fail('the generation ran');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the Life model is one of the app\'s assets', () async {
    final model = await loadLifeModel();
    expect((model['decision'] as Map)['name'], contains('Game of Life'));
    expect(model.containsKey('state'), isFalse);
  });

  test('sends the model with the board, and reads the generation', () async {
    late http.Request asked;
    final stepper = stepperAnswering((request) async {
      asked = request;
      return http.Response(
        jsonEncode(answerFixture),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final outcome = await stepFixture(stepper);

    expect(asked.method, 'POST');
    expect(asked.url.toString(), 'https://api.aityx.ai/v1/systemone');
    expect(asked.headers['Authorization'], 'Bearer test-key');
    expect(jsonDecode(asked.body), sentForBoard());
    expect(
      (jsonDecode(asked.body) as Map)['decision'],
      sentFixture['decision'],
    );

    final g = outcome.generation;
    expect(g.generation, 7);
    expect(g.nextGeneration, 8);
    expect(g.population, 16);
    expect(g.births, 4);
    expect(g.situations[0].fate, 'dies_lonely');
    expect(g.situations[0].why, startsWith('Underpopulation'));
    expect(g.patterns.map((p) => p.pattern), [
      'glider',
      'block',
      'blinker',
      'unknown',
    ]);
    expect(g.recognized, 3);
    // The call, for the panel: the body sent (never the headers) and the
    // answer, timed here.
    expect(outcome.aityxRequest, sentForBoard());
    expect(outcome.aityxResponse, answerFixture);
    expect(outcome.tookMs, isNotNull);
    expect(outcome.inputTokens, isNotNull);
    expect(jsonEncode(outcome.aityxRequest), isNot(contains('test-key')));
  });

  test(
    'in dev mode, no Authorization: the index server adds the key',
    () async {
      late http.Request asked;
      final stepper = AityxGenerationStepper(
        aityx: AityxClient(
          client: MockClient((request) async {
            asked = request;
            return http.Response(jsonEncode(answerFixture), 200);
          }),
          connection: AityxConnection.dev(
            Uri.parse('http://localhost:8800/cellfie/'),
            url: 'https://api.aityx.ai',
            devKeyFrom: '.env',
          ),
        ),
        model: fixtureModel,
      );
      final outcome = await stepFixture(stepper);
      expect(asked.url.toString(), 'http://localhost:8800/aityx/v1/systemone');
      expect(asked.headers.containsKey('Authorization'), isFalse);
      expect(outcome.aityxRequest, sentForBoard());
    },
  );

  test(
    'leaves the call out of the panel if the answer holds the key',
    () async {
      final stepper = stepperAnswering(
        (request) async => http.Response(
          jsonEncode({...answerFixture, 'echo': 'test-key'}),
          200,
        ),
      );
      final outcome = await stepFixture(stepper);
      expect(outcome.generation.nextGeneration, 8);
      expect(outcome.aityxRequest, isNull);
      expect(outcome.aityxResponse, isNull);
    },
  );

  test('without a key, says to set it, and calls nothing', () async {
    var calls = 0;
    final stepper = AityxGenerationStepper(
      aityx: AityxClient(
        client: MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
        connection: AityxConnection.none,
      ),
      model: fixtureModel,
    );
    final error = await failure(stepper);
    expect(
      error.message,
      'aityx is not set up: set your key on the index page.',
    );
    expect(error.noKey, isTrue);
    expect(calls, 0);
  });

  test('refuses a board the model can\'t take, before calling', () async {
    var calls = 0;
    final stepper = stepperAnswering((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    final error = await (() async {
      try {
        await stepper.step(0, {'seeds': true}, const {}, const []);
      } on GenerationException catch (error) {
        return error;
      }
      fail('the generation ran');
    })();
    expect(
      error.message,
      'Could not run the generation: rules: unknown rule seeds.',
    );
    expect(calls, 0);
  });

  test('says why aityx\'s answer is not a generation', () async {
    Future<String> says(int status, Object body) async {
      final stepper = stepperAnswering(
        (request) async =>
            http.Response(body is String ? body : jsonEncode(body), status),
      );
      final error = await failure(stepper);
      expect(error.noKey, isFalse);
      return error.message;
    }

    expect(
      await says(401, {'detail': 'invalid API key'}),
      'Could not run the generation: aityx rejected the key.',
    );
    expect(
      await says(403, {'detail': 'forbidden'}),
      'Could not run the generation: aityx rejected the key.',
    );
    expect(
      await says(500, {'code': 'internal', 'detail': 'model crashed'}),
      'Could not run the generation: aityx answered HTTP 500: model crashed.',
    );
    expect(
      await says(429, 'slow down'),
      'Could not run the generation: aityx answered HTTP 429.',
    );
    expect(
      await says(200, 'not json'),
      'Could not run the generation: unexpected answer from aityx.',
    );
    expect(
      await says(200, {
        'decision_error': {'code': 'bad'},
      }),
      'Could not run the generation: '
      'aityx could not decide it: the Life model failed: bad.',
    );
    expect(
      await says(200, {'answers': {}, 'receipt': {}}),
      'Could not run the generation: aityx could not decide it: no fates.',
    );
    // A field of the wrong type: a TypeError in toGeneration.
    expect(
      await says(200, {
        ...answerFixture,
        'answers': {...(answerFixture['answers'] as Map), 'fates': 'survives'},
      }),
      'Could not run the generation: unexpected answer from aityx.',
    );
  });

  test('says when the Life model does not load, and reads it again', () async {
    var reads = 0;
    final stepper = AityxGenerationStepper(
      aityx: AityxClient(
        client: MockClient(
          (request) async => http.Response(jsonEncode(answerFixture), 200),
        ),
        connection: AityxConnection.user('test-key'),
      ),
      model: () async {
        if (++reads == 1) throw StateError('no asset');
        return fixtureModel();
      },
    );
    expect(
      (await failure(stepper)).message,
      'Could not run the generation: the Life model did not load.',
    );
    expect((await stepFixture(stepper)).generation.nextGeneration, 8);
    expect(reads, 2);
  });

  test('says when aityx does not answer', () async {
    final stepper = stepperAnswering(
      (request) async => throw http.ClientException('connection refused'),
    );
    expect(
      (await failure(stepper)).message,
      'Could not run the generation: aityx did not answer.',
    );

    final slow = AityxGenerationStepper(
      aityx: AityxClient(
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response(jsonEncode(answerFixture), 200);
        }),
        connection: AityxConnection.user('test-key'),
      ),
      model: fixtureModel,
      deadline: const Duration(milliseconds: 20),
    );
    expect(
      (await failure(slow)).message,
      'Could not run the generation: aityx did not answer in time.',
    );
  });
}
