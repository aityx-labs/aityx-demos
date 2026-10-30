import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aityx_web/aityx_web.dart';
import 'package:contacthub_app/main.dart';
import 'package:contacthub_app/routing/json_layout.dart';
import 'package:contacthub_app/routing/routing.dart';
import 'package:contacthub_app/routing/routing_screen.dart' show decisionDigest;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A routed request as the routing screen reads it (withAityx), from a
/// real aityx answer: a tablet returned 20 days after delivery,
/// routed to Customer Service by department rule 3, and refunded less the
/// restocking fee by policy rule 16.
final _fixture = File('test/fixtures/route-tablet.json').readAsStringSync();
RoutingOutcome _outcome() => RoutingOutcome.fromJson(
  (jsonDecode(_fixture) as Map).cast<String, Object?>(),
);

class FakeRouter implements RequestRouter {
  FakeRouter([this.answer]);

  Object? answer;
  final asked = <String>[];

  @override
  Future<RoutingOutcome> route(String message) async {
    asked.add(message);
    final answer = this.answer;
    if (answer is Exception) throw answer;
    return answer as RoutingOutcome? ?? _outcome();
  }
}

/// The pane's rows for [o], as the routing screen lays them out.
CallLayout _pane(RoutingOutcome o) =>
    layoutCall(o.aityxRequest, decisionDigest(o.aityxResponse));

/// How far the call's pane is scrolled.
double _offset(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!.offset;

void main() {
  test('reads a routing', () {
    final o = _outcome();
    final r = o.routing;
    expect(r.department.name, 'Customer Service');
    expect(r.department.person, 'Maria Lopez');
    expect(r.departmentRule, 3);
    expect(r.priority, 'normal');
    expect(r.priorityRule, 7);
    expect(r.responseHours, 24);
    expect(r.needsReview, isFalse);
    expect(r.topic, 'customer_service');
    expect(r.topicConfidence, 1);
    expect(r.topicProbabilities['customer_service'], 1);
    expect(r.requestKind, 'return_refund');
    expect(r.policy!.resolution, 'refund');
    expect(r.policy!.rule, 16);
    expect(r.policy!.refundAmount, 279.65);
    expect(r.policy!.refundBy, DateTime(2026, 10, 28));
    expect(r.policy!.daysSinceDelivery, 20);
    expect(r.policy!.order!.item, 'Tablet');
    expect(r.checks.map((c) => c.id), [
      'urgent',
      'sensitive_data',
      'abusive',
      'clear_topic',
    ]);
    expect(o.aityxRequest, isA<Map>());
    expect(o.aityxResponse, isA<Map>());
  });

  test('the digest keeps what was read and what decides', () {
    final o = _outcome();
    final decision = decisionDigest(o.aityxResponse);
    final answers = decision['answers'] as Map;
    expect(answers.keys, contains('topic'));
    expect(answers.keys, contains('request_kind'));
    expect(answers.keys, contains('department'));
    expect(answers.keys, contains('resolution'));
    expect(answers.keys, isNot(contains('evidence_threshold')));
    expect((answers['topic'] as Map).keys, isNot(contains('probabilities')));
    expect(
      (answers['department'] as Map).keys,
      isNot(contains('probabilities')),
    );
    expect((answers['department'] as Map)['choice'], 'customer_service');
    final receipt = decision['receipt'] as Map;
    expect((receipt['decisions'] as Map).keys, [
      'department',
      'resolution',
      'refund_amount',
      'priority',
      'response_hours',
    ]);
    expect(((receipt['decisions'] as Map)['department'] as Map)['rule'], 3);
    expect((receipt['provenance'] as Map)['topic'], 'jev');
    expect((receipt['provenance'] as Map)['order'], 'state');
  });

  group('AityxRequestRouter', () {
    final model = (jsonDecode(
      File('assets/models/routing.json').readAsStringSync(),
    ) as Map).cast<String, Object?>();
    final tablet = File('test/fixtures/aityx/tablet-restocking.json')
        .readAsStringSync();
    const message = "I'd like to return the tablet from order 120-5150";

    /// A router on [key] whose aityx answers [answer].
    AityxRequestRouter router(
      Future<http.Response> Function(http.Request request) answer, {
      String key = 'test-key',
    }) => AityxRequestRouter(
      aityx: AityxClient(
        client: MockClient(answer),
        connection: AityxConnection.user(key),
      ),
      model: () async => model,
      today: () => DateTime.utc(2026, 10, 21),
    );

    Matcher fails(String message, {bool noKey = false}) => throwsA(
      isA<RoutingException>()
          .having((e) => e.message, 'message', message)
          .having((e) => e.noKey, 'noKey', noKey),
    );

    test('posts the model and the message to systemone, on the key', () async {
      late http.Request sent;
      final outcome = await router((request) async {
        sent = request;
        return http.Response(tablet, 200);
      }).route('  $message  ');

      expect(sent.url, Uri.parse('https://api.aityx.ai/v1/systemone'));
      expect(sent.headers['authorization'], 'Bearer test-key');
      final body = jsonDecode(sent.body) as Map;
      expect(body['questions'], model['questions']);
      expect(body['decision'], model['decision']);
      expect(body['state'], {
        'message': message,
        'today': '2026-10-21',
        'order': {
          'number': '120-5150',
          'item': 'Tablet',
          'placed_on': '2026-09-26',
          'delivered_on': '2026-10-01',
          'amount': 329.0,
          'current_price': 329.0,
          'category': 'electronics',
          'status': 'delivered',
          'charges': 1,
        },
      });

      final r = outcome.routing;
      expect(r.department.id, 'customer_service');
      expect(r.policy!.resolution, 'refund');
      expect(r.policy!.refundAmount, 279.65);
      // The call shown is the body sent, never the headers with the key.
      expect(outcome.aityxRequest, body);
      expect(jsonEncode(outcome.aityxRequest), isNot(contains('test-key')));
      expect(outcome.aityxResponse, jsonDecode(tablet));
    });

    test('refuses an empty message without calling aityx', () {
      var calls = 0;
      expect(
        router((_) async {
          calls++;
          return http.Response(tablet, 200);
        }).route('   '),
        fails('Could not route it: message is empty.'),
      );
      expect(calls, 0);
    });

    test('without a key, says to set one on the index page', () {
      final noKey = AityxRequestRouter(
        aityx: AityxClient(
          client: MockClient((_) async => fail('no call without a key')),
          connection: AityxConnection.none,
        ),
        model: () async => model,
      );
      expect(
        noKey.route(message),
        fails(
          'aityx is not set up: set your key on the index page.',
          noKey: true,
        ),
      );
    });

    test('says when aityx rejects the key', () {
      expect(
        router((_) async => http.Response('{"detail":"invalid API key"}', 401))
            .route(message),
        fails('Could not route it: aityx rejected the key.'),
      );
    });

    test("says aityx's status and detail on another error", () {
      expect(
        router(
          (_) async => http.Response(
            '{"code":"rate_limited","detail":"too many requests."}',
            429,
          ),
        ).route(message),
        fails(
          'Could not route it: aityx answered HTTP 429: too many requests.',
        ),
      );
    });

    test('says when aityx does not answer', () {
      expect(
        router((_) async => throw http.ClientException('offline'))
            .route(message),
        fails('aityx did not answer.'),
      );
    });

    test('says when the routing model failed', () {
      expect(
        router(
          (_) async => http.Response(
            jsonEncode({
              'answers': {},
              'decision_error': {'code': 'evaluation_failed', 'detail': 'x'},
            }),
            200,
          ),
        ).route(message),
        fails(
          'Could not route it: aityx could not route it: '
          'the routing model failed: evaluation_failed.',
        ),
      );
      expect(
        router((_) async => http.Response('<html>', 200)).route(message),
        fails('Could not route it: unexpected answer from aityx.'),
      );
    });

    test('in dev mode, posts to the index server, with no key', () async {
      late http.Request sent;
      final outcome = await AityxRequestRouter(
        aityx: AityxClient(
          client: MockClient((request) async {
            sent = request;
            return http.Response(tablet, 200);
          }),
          connection: AityxConnection.dev(
            Uri.parse('http://localhost:8800/contacthub/'),
            url: 'https://api.aityx.ai',
            devKeyFrom: '.env',
          ),
        ),
        model: () async => model,
        today: () => DateTime.utc(2026, 10, 21),
      ).route(message);

      expect(sent.url, Uri.parse('http://localhost:8800/aityx/v1/systemone'));
      expect(
        sent.headers.keys.map((h) => h.toLowerCase()),
        isNot(contains('authorization')),
      );
      // No key in the app, so nothing to leave out: the call is shown.
      expect(outcome.aityxRequest, jsonDecode(sent.body));
      expect(outcome.aityxResponse, jsonDecode(tablet));
    });

    test('refuses a message over 2000 characters without calling aityx', () {
      var calls = 0;
      expect(
        router((_) async {
          calls++;
          return http.Response(tablet, 200);
        }).route('a' * 2001),
        fails('Could not route it: message is longer than 2000 characters.'),
      );
      expect(calls, 0);
    });

    test('a 403 is a rejected key too', () {
      expect(
        router((_) async => http.Response('{}', 403)).route(message),
        fails('Could not route it: aityx rejected the key.'),
      );
    });

    test("in dev mode, the proxy's unreachable aityx did not answer", () {
      expect(
        router(
          (_) async => http.Response(
            '{"code":"proxy_unreachable",'
            '"detail":"aityx did not answer: SocketException"}',
            502,
          ),
        ).route(message),
        fails('aityx did not answer.'),
      );
    });

    testWidgets('says when aityx does not answer in 100 s', (tester) async {
      final never = Completer<http.Response>();
      Object? error;
      unawaited(
        router((_) => never.future)
            .route(message)
            .then<void>((_) {}, onError: (Object e) => error = e),
      );
      await tester.pump(const Duration(seconds: 99));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(
        error,
        isA<RoutingException>().having(
          (e) => e.message,
          'message',
          'aityx did not answer in time.',
        ),
      );
    });

    test("leaves out the call if aityx's answer contains the key", () async {
      final outcome = await router(
        (_) async => http.Response(tablet, 200),
        key: 'customer_service',
      ).route(message);
      expect(outcome.routing.department.id, 'customer_service');
      expect(outcome.aityxRequest, isNull);
      expect(outcome.aityxResponse, isNull);
    });
  });

  group('the routing screen', () {
    Future<void> pump(WidgetTester tester, RequestRouter router) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoutingScreen(message: 'Any jobs in Berlin?', router: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the department, the person and why', (tester) async {
      await pump(tester, FakeRouter());

      expect(find.text('Customer Service'), findsWidgets);
      expect(find.text('Maria Lopez'), findsOneWidget);
      expect(
        find.text(
          "Orders, deliveries, returns and refunds are Customer Service's.",
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Normal · answer within 24 h'),
        findsOneWidget,
      );
      expect(find.text('Goes straight to the department'), findsOneWidget);
    });

    testWidgets('shows what aityx read', (tester) async {
      await pump(tester, FakeRouter());

      expect(find.text("aityx's reading of the message"), findsOneWidget);
      expect(
        find.textContaining('aityx chose Customer Service, 100% confident'),
        findsOneWidget,
      );
      expect(
        find.text('What the customer wants: A return or a refund'),
        findsOneWidget,
      );
    });

    testWidgets('a rule link lands exactly on the row that fired', (
      tester,
    ) async {
      final outcome = _outcome();
      await pump(tester, FakeRouter(outcome));

      await tester.tap(find.text('Rule 3'));
      await tester.pumpAndSettle();

      // The request is shown, scrolled so the row's line is the second on
      // screen (one line of context above it), and the row is explained.
      final path = 'decision.decisions.department.table.3';
      final first = _pane(outcome).range('request', path)!.first;
      expect(_offset(tester), 8 + (first - 1) * 22.0);
      expect(
        find.textContaining('The row of the department table that fired'),
        findsOneWidget,
      );
    });

    testWidgets('a question is shown as wrapped prose, and lands exactly', (
      tester,
    ) async {
      final outcome = _outcome();
      await pump(tester, FakeRouter(outcome));

      await tester.tap(find.text('Question').first);
      await tester.pumpAndSettle();
      final pane = _pane(outcome);
      final question = pane.range('request', 'questions.urgent_probability')!;
      expect(_offset(tester), 8 + (question.first - 1) * 22.0);
      expect(find.textContaining('A yes/no question (noul)'), findsOneWidget);
      // The question's instructions wrap onto an unnumbered row.
      final instructions = pane.range(
        'request',
        'questions.urgent_probability.instructions',
      )!;
      expect(instructions.last, greaterThan(instructions.first));
      expect(pane.rows[instructions.last].line!.continuation, isTrue);
    });

    testWidgets('the jumped-to part stays selected when the page rebuilds', (
      tester,
    ) async {
      await pump(tester, FakeRouter());
      await tester.tap(find.text('Rule 3'));
      await tester.pumpAndSettle();
      ChoiceChip chip() => tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Department rule 3'),
      );
      expect(chip().selected, isTrue);

      // A resize rebuilds the page, and with it the targets.
      tester.view.physicalSize = const Size(1200, 1500);
      await tester.pumpAndSettle();
      expect(chip().selected, isTrue);
    });

    testWidgets("shows the store's policy, and its rule exactly", (
      tester,
    ) async {
      final outcome = _outcome();
      await pump(tester, FakeRouter(outcome));

      expect(find.text('Refund'), findsOneWidget);
      expect(find.text(r'$279.65, paid by Oct 28, 2026'), findsOneWidget);
      expect(find.text('Order 120-5150 · Tablet'), findsOneWidget);
      expect(find.textContaining('(20 days ago)'), findsOneWidget);

      await tester.tap(find.text('Rule 16'));
      await tester.pumpAndSettle();
      final first = _pane(outcome)
          .range('request', 'decision.decisions.resolution.table.16')!
          .first;
      expect(_offset(tester), 8 + (first - 1) * 22.0);
      expect(find.textContaining('fired for this order'), findsOneWidget);

      // The amount's rule lands exactly too, explained.
      // The card's link, scrolled back into view: the page moved to the
      // call after the first jump.
      final link = find.text('Amount rule 4').first;
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      final amount = _pane(outcome)
          .range('request', 'decision.decisions.refund_amount.table.4')!
          .first;
      expect(_offset(tester), 8 + (amount - 1) * 22.0);
      expect(find.textContaining('how much is paid back'), findsOneWidget);
    });

    testWidgets('an answer link lands in the response, below the request', (
      tester,
    ) async {
      final outcome = _outcome();
      await pump(tester, FakeRouter(outcome));

      await tester.tap(find.text('Receipt'));
      await tester.pumpAndSettle();

      final pane = _pane(outcome);
      final first = pane
          .range('response', 'receipt.decisions.department')!
          .first;
      expect(first, greaterThan(pane.range('request', '')!.last));
      expect(_offset(tester), 8 + (first - 1) * 22.0);
      expect(
        find.textContaining("The department table's trace"),
        findsOneWidget,
      );
    });

    testWidgets('the response shows what was read and what decides', (
      tester,
    ) async {
      final outcome = _outcome();
      await pump(tester, FakeRouter(outcome));

      final decision = decisionDigest(outcome.aityxResponse);
      expect(
        (decision['answers'] as Map).keys,
        isNot(contains('return_window_days')),
      );
      // Links to response parts the pane shows stay...
      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('Hours table'), findsOneWidget);
      // ...and the pane copies all of the answer.
      expect(find.text('Copy full response'), findsOneWidget);
      // Key parts are labeled in the pane before anything is jumped to.
      expect(find.text('The routing decision'), findsWidgets);
      expect(find.text('Topic read'), findsWidgets);
    });

    testWidgets('fits a phone screen', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoutingScreen(message: 'Any jobs?', router: FakeRouter()),
        ),
      );
      await tester.pumpAndSettle();

      // Overflows would have been reported as exceptions.
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Rule 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rule 3'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('The row of the department table'),
        findsOneWidget,
      );
    });

    testWidgets('says when routing failed, and tries again', (tester) async {
      final router = FakeRouter(
        const RoutingException('aityx did not answer.'),
      );
      await pump(tester, router);
      expect(find.text('aityx did not answer.'), findsOneWidget);
      expect(find.text('Set your key'), findsNothing);

      router.answer = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Maria Lopez'), findsOneWidget);
      expect(router.asked.length, 2);
    });

    testWidgets('without a key, offers the index page', (tester) async {
      await pump(
        tester,
        FakeRouter(
          const RoutingException(
            'aityx is not set up: set your key on the index page.',
            noKey: true,
          ),
        ),
      );
      expect(
        find.text('aityx is not set up: set your key on the index page.'),
        findsOneWidget,
      );
      expect(find.text('Set your key'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
