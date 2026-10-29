import 'dart:convert';
import 'dart:io';

import 'package:contacthub_api/orders.dart';
import 'package:contacthub_api/routing.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

void main() {
  final model = _json('models/routing.json');

  group('messageFrom', () {
    test('takes the trimmed message', () {
      expect(
        messageFrom({'message': '  Where is my order?  '}),
        'Where is my order?',
      );
    });

    test('refuses a missing, empty or too long message', () {
      expect(() => messageFrom([]), throwsA(isA<InvalidRequest>()));
      expect(() => messageFrom({}), throwsA(isA<InvalidRequest>()));
      expect(
        () => messageFrom({'message': '   '}),
        throwsA(isA<InvalidRequest>()),
      );
      expect(
        () => messageFrom({'message': 'x' * (maxMessageLength + 1)}),
        throwsA(isA<InvalidRequest>()),
      );
    });
  });

  group('the model', () {
    test('names a department for every topic Jev can pick', () {
      final topics = (model['questions'] as Map)['topic']['criteria'] as Map;
      final departmentType =
          ((model['decision'] as Map)['types'] as Map)['Department'] as String;
      final ids = departmentType.split('|').toSet();
      expect(ids, departments.keys.toSet());
      for (final topic in topics.keys) {
        if (topic == 'other') continue;
        expect(ids, contains(topic), reason: '$topic has no department');
      }
    });

    test('the department table has a row for every department', () {
      final table =
          ((model['decision'] as Map)['decisions']
                  as Map)['department']['table']
              as List;
      final targets = {for (final row in table.skip(1)) (row as Map)['then']};
      expect(targets, departments.keys.toSet());
    });
  });

  group('the order book', () {
    final today = DateTime.utc(2026, 10, 21);

    test('finds the order number in a message', () {
      expect(orderNumberIn('Return order 113-2045 please'), '113-2045');
      expect(orderNumberIn('No number here, call 555-12345'), isNull);
    });

    test('dates count back from today', () {
      final jacket = orderState('order 114-7781', today);
      expect(jacket['placed_on'], '2026-09-01');
      expect(jacket['delivered_on'], '2026-09-06');
      expect(jacket['amount'], 240);
      expect(jacket['status'], 'delivered');
    });

    test('an undelivered order is expected 5 days after it was placed', () {
      final lamp = orderState('order 112-8834', today);
      expect(lamp['status'], 'shipped');
      expect(lamp['placed_on'], '2026-10-09');
      expect(lamp['delivered_on'], '2026-10-14');
    });

    test('a message without a known order gets status none', () {
      expect(orderState('I lost the number', today)['status'], 'none');
      expect(orderState('order 999-0000', today)['status'], 'none');
      expect(orderState('order 999-0000', today)['number'], '999-0000');
    });
  });

  test('routingRequest sends the questions, the model, the message, today '
      'and the order', () {
    final sent = routingRequest(
      model,
      'Return order 113-2045',
      today: DateTime.utc(2026, 10, 21),
    );
    expect(sent['questions'], model['questions']);
    expect(sent['decision'], model['decision']);
    final state = sent['state'] as Map;
    expect(state['message'], 'Return order 113-2045');
    expect(state['today'], '2026-10-21');
    expect((state['order'] as Map)['item'], 'Running shoes');
  });

  test('the resolution table covers every resolution it can give', () {
    final decisions = (model['decision'] as Map)['decisions'] as Map;
    final table = decisions['resolution']['table'] as List;
    final given = {for (final row in table.skip(1)) (row as Map)['then']};
    final type =
        ((model['decision'] as Map)['types'] as Map)['Resolution'] as String;
    expect(given, type.split('|').toSet());
  });

  group('toRouting, from real aityx answers', () {
    final sent = routingRequest(model, 'a message');

    test('an order goes to Customer Service', () {
      final routing = toRouting(sent, _json('test/fixtures/order.json'));
      expect((routing['department'] as Map)['id'], 'customer_service');
      expect((routing['department'] as Map)['person'], 'Maria Lopez');
      expect(routing['department_rule'], 3);
      expect(routing['reason'], contains('Customer Service'));
      expect(routing['priority'], 'normal');
      expect(routing['response_hours'], 24);
      expect(routing['needs_review'], isFalse);
      expect((routing['topic'] as Map)['choice'], 'customer_service');
      expect([
        for (final c in routing['checks'] as List)
          if (c['flagged']) c['id'],
      ], isEmpty);
    });

    test('a card number makes it high priority, for review', () {
      final routing = toRouting(
        sent,
        _json('test/fixtures/billing-card-number.json'),
      );
      expect((routing['department'] as Map)['id'], 'billing');
      expect(routing['priority'], 'high');
      expect(routing['priority_rule'], 2);
      expect(routing['priority_reason'], contains('Card numbers'));
      expect(routing['response_hours'], 4);
      expect(routing['needs_review'], isTrue);
      expect([
        for (final c in routing['checks'] as List)
          if (c['flagged']) c['id'],
      ], containsAll(['urgent', 'sensitive_data']));
    });

    test('abuse goes to Trust & Safety, whatever the topic', () {
      final routing = toRouting(sent, _json('test/fixtures/abusive.json'));
      expect((routing['topic'] as Map)['choice'], 'customer_service');
      expect((routing['department'] as Map)['id'], 'trust_safety');
      expect(routing['department_rule'], 1);
    });

    test('an electronics return after 14 days refunds less 15%', () {
      final sent = routingRequest(
        model,
        "I'd like to return the tablet from order 120-5150",
      );
      final routing = toRouting(
        sent,
        _json('test/fixtures/tablet-restocking.json'),
      );
      final policy = routing['policy'] as Map;
      expect(routing['request_kind'], 'return_refund');
      expect(policy['request_kind'], 'return_refund');
      expect(policy['resolution'], 'refund');
      expect(policy['resolution_rule'], 16);
      expect(policy['reason'], contains('30 days'));
      expect(policy['refund_amount'], 279.65);
      expect(policy['amount_rule'], 4);
      expect(policy['amount_reason'], contains('15% restocking fee'));
      expect(policy['days_since_delivery'], 20);
      expect((policy['order'] as Map)['item'], 'Tablet');
    });

    test('a return after 45 days gets store credit', () {
      final sent = routingRequest(model, 'order 114-7781');
      final policy =
          toRouting(
                sent,
                _json('test/fixtures/jacket-store-credit.json'),
              )['policy']
              as Map;
      expect(policy['resolution'], 'store_credit');
      expect(policy['refund_amount'], 240);
      expect(policy['days_since_delivery'], 45);
    });

    test('a package late after 12 days is investigated, high priority', () {
      final sent = routingRequest(model, 'order 112-8834');
      final routing = toRouting(sent, _json('test/fixtures/lamp-late.json'));
      expect((routing['policy'] as Map)['resolution'], 'investigate_late');
      expect(routing['priority'], 'high');
      expect(routing['priority_reason'], contains('late package'));
    });

    test('fails on a decision error', () {
      expect(
        () => toRouting(sent, {
          'answers': {},
          'decision_error': {'code': 'evaluation_failed', 'detail': 'x'},
        }),
        throwsA(isA<RoutingFailed>()),
      );
    });
  });

  test('withAityx leaves out the call if the answer contains the key', () {
    final out = withAityx({}, {}, {}, 'body with sk_123', 'sk_123');
    expect(out.containsKey('aityx'), isFalse);
    expect(withAityx({}, {}, {}, 'clean', 'sk_123')['aityx'], isNotNull);
  });
}
