import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mortgagehub_app/aityx/proposal_model.dart';
import 'package:mortgagehub_app/proposal/proposal_check.dart';
import 'package:mortgagehub_app/proposal/proposal_summary_screen.dart';
import 'package:mortgagehub_app/proposal/random_proposal.dart';
import 'package:faker/faker.dart';

import 'fake_checker.dart';

final request = randomProposal(Faker(seed: 7));

Future<void> showSummary(WidgetTester tester, ProposalChecker checker) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ProposalSummaryScreen(request: request, checker: checker),
    ),
  );
}

void main() {
  testWidgets('shows the verdict, the figures and every check', (tester) async {
    final checker = FakeChecker();
    await showSummary(tester, checker);
    expect(find.textContaining('Checking against'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(checker.calls, 1);
    expect(checker.last, same(request));
    expect(find.text('Regulatory check'), findsOneWidget);
    expect(find.byKey(const Key('checkStatus')), findsOneWidget);
    expect(find.text('Requires review'), findsOneWidget);
    expect(find.text('Loan-to-value (max 97.0%)'), findsOneWidget);
    expect(find.text(r'$3,091'), findsOneWidget);
    expect(find.text('35.9%'), findsOneWidget);
    final card = find.byType(RegulatoryCheckCard);
    for (final label in [
      'Program eligibility',
      'Loan-to-value',
      'Loan limits (2026)',
      'Credit score',
      'Debt-to-income',
    ]) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.text('Too high.'), findsOneWidget);
  });

  testWidgets('shows and hides the aityx request and response', (tester) async {
    final checker = FakeChecker(
      result: ProposalCheck(
        status: sampleCheck.status,
        checks: sampleCheck.checks,
        ltv: sampleCheck.ltv,
        maxLtv: sampleCheck.maxLtv,
        dti: sampleCheck.dti,
        housingPayment: sampleCheck.housingPayment,
        assumedRate: sampleCheck.assumedRate,
        aityxRequest: const {
          'state': {'loan_program': 'fha'},
        },
        aityxResponse: const {
          'answers': {'status': 'needs_review'},
        },
      ),
    );
    await showSummary(tester, checker);
    await tester.pumpAndSettle();
    expect(find.textContaining('"loan_program": "fha"'), findsNothing);

    await tester.tap(find.text('Show aityx request and response'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"loan_program": "fha"'), findsOneWidget);
    expect(find.textContaining('"status": "needs_review"'), findsOneWidget);

    await tester.tap(find.text('Hide aityx request and response'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"loan_program": "fha"'), findsNothing);
  });

  testWidgets('has no aityx button without the request and response', (
    tester,
  ) async {
    await showSummary(tester, FakeChecker());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aityxToggle')), findsNothing);
  });

  testWidgets('shows an error with a retry', (tester) async {
    final checker = FakeChecker(error: ProposalCheckException('aityx is down'));
    await showSummary(tester, checker);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't run the check: aityx is down"), findsOneWidget);

    checker.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(checker.calls, 2);
    expect(find.text('Requires review'), findsOneWidget);
  });

  group('AityxProposalChecker', () {
    test(
      'posts the model and the inputs to aityx, and parses the answers',
      () async {
        late http.Request sent;
        final client = MockClient((call) async {
          sent = call;
          return http.Response(jsonEncode(aityxAnswers), 200);
        });
        final check = await checkerOn(client).check(request);

        expect(sent.method, 'POST');
        expect(sent.url.toString(), 'https://api.aityx.ai/v1/systemone');
        expect(sent.headers['Authorization'], 'Bearer test-key');
        final body = jsonDecode(sent.body) as Map<String, Object?>;
        expect(body['decision'], model);
        expect(
          body['state'],
          toState(
            jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>,
            assumedRate,
          ),
        );
        // No personal details go to aityx.
        for (final personal in [request.firstName, request.email]) {
          expect(sent.body, isNot(contains(personal)));
        }

        expect(check.status, CheckStatus.needsReview);
        expect(check.ltv, 80);
        expect(check.maxLtv, 97);
        expect(check.dti, 35.91);
        expect(check.housingPayment, 3090.77);
        expect(check.assumedRate, assumedRate);
        expect(check.checks.map((c) => c.id), checkIds);
        expect(check.checks[2].result, CheckResult.review);
        // The request shown is the body sent, not the headers with the key.
        expect(check.aityxRequest, body);
        expect(check.aityxResponse, aityxAnswers);
      },
    );

    test(
      'leaves the aityx request and response out if the answer holds the key',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({...aityxAnswers, 'echo': 'Bearer test-key'}),
            200,
          ),
        );
        final check = await checkerOn(client).check(request);
        expect(check.status, CheckStatus.needsReview);
        expect(check.aityxRequest, isNull);
        expect(check.aityxResponse, isNull);
      },
    );

    Future<void> expectError(MockClient client, String message) => expectLater(
      checkerOn(client).check(request),
      throwsA(
        isA<ProposalCheckException>().having(
          (e) => e.message,
          'message',
          message,
        ),
      ),
    );

    test('says when aityx rejects the key', () async {
      await expectError(
        MockClient(
          (_) async => http.Response('{"detail":"invalid API key"}', 401),
        ),
        'aityx rejected the key',
      );
    });

    test('says what aityx answered when it fails', () async {
      await expectError(
        MockClient(
          (_) async => http.Response(
            '{"code":"invalid_request","detail":"state is required"}',
            400,
          ),
        ),
        'aityx answered HTTP 400: state is required',
      );
      await expectError(
        MockClient((_) async => http.Response('oops', 500)),
        'aityx answered HTTP 500',
      );
    });

    test('says when aityx does not answer', () async {
      await expectError(
        MockClient((_) async => throw http.ClientException('offline')),
        'aityx did not answer',
      );
    });

    test('says when the answers are not the model\'s', () async {
      await expectError(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'decision_error': 'boom', 'answers': {}}),
            200,
          ),
        ),
        'unexpected answer from aityx',
      );
      await expectError(
        MockClient((_) async => http.Response('[]', 200)),
        'unexpected answer from aityx',
      );
      // A verdict the app doesn't know.
      final answers = aityxAnswers['answers'] as Map<String, Object?>;
      await expectError(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              ...aityxAnswers,
              'answers': {
                ...answers,
                'status': {'type': 'choice', 'choice': 'maybe'},
              },
            }),
            200,
          ),
        ),
        'unexpected answer from aityx',
      );
    });

    test('without a key, says to set one, and sends nothing', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      final checker = AityxProposalChecker(
        aityx: AityxClient(client: client, store: AityxKeyStore.memory()),
        model: () async => model,
      );
      await expectLater(
        checker.check(request),
        throwsA(
          isA<ProposalCheckException>().having(
            (e) => e.message,
            'message',
            'aityx is not set up: set your key on the index page',
          ),
        ),
      );
      expect(calls, 0);
    });

    test('without a key of the user\'s, uses the index server\'s dev proxy, '
        'at the origin\'s root and without Authorization', () async {
      final asked = <http.Request>[];
      final client = MockClient((call) async {
        asked.add(call);
        return call.url.path == '/aityx/config'
            ? http.Response(
                '{"available":true,"url":"https://api.aityx.ai",'
                '"source":".env"}',
                200,
              )
            : http.Response(jsonEncode(aityxAnswers), 200);
      });
      final checker = AityxProposalChecker(
        aityx: AityxClient(
          client: client,
          store: AityxKeyStore.memory(),
          origin: Uri.parse('http://localhost:8800/mortgagehub/proposal'),
        ),
        model: () async => model,
      );
      final check = await checker.check(request);
      expect(asked.map((call) => call.url.toString()), [
        'http://localhost:8800/aityx/config',
        'http://localhost:8800/aityx/v1/systemone',
      ]);
      expect(asked.last.headers.containsKey('Authorization'), isFalse);
      expect(check.status, CheckStatus.needsReview);
      expect(check.aityxRequest, isNotNull);
    });

    test('a model that did not load is loaded again next time', () async {
      var loads = 0;
      final checker = AityxProposalChecker(
        aityx: AityxClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode(aityxAnswers), 200),
          ),
          connection: AityxConnection.user('test-key'),
        ),
        model: () async {
          if (++loads == 1) throw FlutterError('Unable to load asset');
          return model;
        },
      );
      await expectLater(
        checker.check(request),
        throwsA(
          isA<ProposalCheckException>().having(
            (e) => e.message,
            'message',
            "the rules (the aityx model) didn't load",
          ),
        ),
      );
      final check = await checker.check(request);
      expect(check.status, CheckStatus.needsReview);
      expect(loads, 2);
    });

    test('uses the key the user stored', () async {
      late http.Request sent;
      final client = MockClient((call) async {
        sent = call;
        return http.Response(jsonEncode(aityxAnswers), 200);
      });
      final checker = AityxProposalChecker(
        aityx: AityxClient(
          client: client,
          store: AityxKeyStore.memory(
            session: {
              'aityx.key': 'stored-key',
              'aityx.url': 'https://aityx.test',
            },
          ),
        ),
        model: () async => model,
      );
      await checker.check(request);
      expect(sent.url.toString(), 'https://aityx.test/v1/systemone');
      expect(sent.headers['Authorization'], 'Bearer stored-key');
    });
  });

  testWidgets('the summary shows why the check could not run', (tester) async {
    final checker = AityxProposalChecker(
      aityx: AityxClient(
        client: MockClient((_) async => http.Response('', 401)),
        connection: AityxConnection.user('test-key'),
      ),
      model: () async => model,
    );
    await showSummary(tester, checker);
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't run the check: aityx rejected the key"),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the model asset is the proposal-check model', (tester) async {
    final json = jsonDecode(await rootBundle.loadString(modelAsset));
    expect(json, isA<Map<String, Object?>>());
    expect((json as Map)['name'], isNotNull);
  });
}

/// A stand-in for the model the checker sends.
const model = {'name': 'proposal-check'};

AityxProposalChecker checkerOn(MockClient client) => AityxProposalChecker(
  aityx: AityxClient(
    client: client,
    connection: AityxConnection.user('test-key'),
  ),
  model: () async => model,
);

Map<String, Object?> _check(String result) => {
  'type': 'value',
  'value': {'result': result, 'reason': 'Because.'},
};

/// What aityx answers to the model: its answers, a receipt and the usage.
final aityxAnswers = <String, Object?>{
  'answers': {
    'status': {'type': 'choice', 'choice': 'needs_review'},
    'loan_amount': {'type': 'number', 'number': 400000},
    'ltv': {'type': 'number', 'number': 80.0004},
    'max_ltv': {'type': 'number', 'number': 97},
    'principal_and_interest': {'type': 'number', 'number': 2528.27},
    'housing_payment': {'type': 'number', 'number': 3090.77},
    'dti': {'type': 'number', 'number': 35.9097},
    'program_check': _check('pass'),
    'ltv_check': _check('pass'),
    'limit_check': _check('review'),
    'credit_check': _check('pass'),
    'dti_check': _check('pass'),
  },
  'receipt': {'id': 'r1'},
  'usage': {'input_tokens': 6000},
};
