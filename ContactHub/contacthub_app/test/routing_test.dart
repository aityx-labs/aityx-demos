import 'dart:convert';
import 'dart:io';

import 'package:contacthub_app/main.dart';
import 'package:contacthub_app/routing/json_layout.dart';
import 'package:contacthub_app/routing/routing.dart';
import 'package:contacthub_app/routing/routing_screen.dart' show decisionDigest;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A real answer of the API: a tablet returned 20 days after delivery,
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
  test('reads the API\'s answer', () {
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

  group('ApiRequestRouter', () {
    test('posts the message to /api/route', () async {
      late http.Request sent;
      final router = ApiRequestRouter(
        baseUrl: 'http://localhost:8891',
        client: MockClient((request) async {
          sent = request;
          return http.Response(_fixture, 200);
        }),
      );

      final outcome = await router.route('Any jobs?');
      expect(sent.url, Uri.parse('http://localhost:8891/api/route'));
      expect(jsonDecode(sent.body), {'message': 'Any jobs?'});
      expect(outcome.routing.department.id, 'customer_service');
    });

    test("says the API's error", () {
      final router = ApiRequestRouter(
        baseUrl: 'http://localhost:8891',
        client: MockClient(
          (_) async => http.Response('{"error":"message is empty"}', 400),
        ),
      );
      expect(
        router.route(' '),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.message,
            'message',
            'Could not route it: message is empty.',
          ),
        ),
      );
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
        const RoutingException('The API did not answer.'),
      );
      await pump(tester, router);
      expect(find.text('The API did not answer.'), findsOneWidget);

      router.answer = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Maria Lopez'), findsOneWidget);
      expect(router.asked.length, 2);
    });
  });
}
