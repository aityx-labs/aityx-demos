/// The routing model's rules (assets/models/routing.json) executed on aityx.ai
/// with fixed facts, checking the outcomes just inside and just outside
/// each limit of the store's policy. The questions aren't asked: their
/// answers are given in the state, so only the rules run and every run is
/// the same. Tagged `aityx`: skipped by `flutter test`, run by
/// scripts/model-test.sh, which passes AITYX_API_KEY and AITYX_URL. The
/// calls go through aityx_web's AityxClient, as the app's do.
@Tags(['aityx'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clear, civil request about a delivered $100 order.
Map<String, Object?> facts({
  String kind = 'return_refund',
  int placedDaysAgo = 10,
  int deliveredDaysAgo = 5,
  num amount = 100,
  num? currentPrice,
  String category = 'standard',
  String status = 'delivered',
  int charges = 1,
}) {
  final today = DateTime.utc(2026, 10, 21);
  String ago(int days) =>
      today.subtract(Duration(days: days)).toIso8601String().substring(0, 10);
  return {
    'topic': 'customer_service',
    'topic_confidence': 1,
    'urgent_probability': 0.01,
    'sensitive_data_probability': 0.01,
    'abusive_probability': 0.01,
    'request_kind': kind,
    'today': '2026-10-21',
    'order': {
      'placed_on': ago(placedDaysAgo),
      'delivered_on': ago(deliveredDaysAgo),
      'amount': amount,
      'current_price': currentPrice ?? amount,
      'category': category,
      'status': status,
      'charges': charges,
    },
  };
}

late final Map<String, Object?> decision;
late final AityxClient aityx;

/// The model's answers for [state]: `resolution`, `refund_amount`,
/// `priority`, `needs_review`.
Future<({String resolution, num amount, String priority, bool review})> run(
  Map<String, Object?> state,
) async {
  final answer = await aityx.systemone({'decision': decision, 'state': state});
  expect(answer.status, 200, reason: answer.text);
  final answers = (answer.json as Map)['answers'] as Map;
  return (
    resolution: answers['resolution']['choice'] as String,
    amount: answers['refund_amount']['number'] as num,
    priority: answers['priority']['level'] as String,
    review: answers['needs_review']['noul'] == 1,
  );
}

void main() {
  setUpAll(() {
    final env = Platform.environment;
    aityx = AityxClient(
      connection: AityxConnection.user(
        env['AITYX_API_KEY'] ?? '',
        url: env['AITYX_URL'],
      ),
    );
    final model = jsonDecode(
      File('assets/models/routing.json').readAsStringSync(),
    ) as Map;
    decision = (model['decision'] as Map).cast<String, Object?>();
    // Without the questions there's no answer to bind the topic's
    // confidence to: take it from the state like the other facts.
    final inputs = decision['inputs'] as Map;
    inputs['topic_confidence'] = {
      ...(inputs['topic_confidence'] as Map),
      'from': 'the state',
    };
  });
  tearDownAll(() => aityx.close());

  group('returns', () {
    test('30 days after delivery: refund', () async {
      final r = await run(facts(deliveredDaysAgo: 30));
      expect(r.resolution, 'refund');
      expect(r.amount, 100);
    });

    test('31 days: store credit for the full amount', () async {
      final r = await run(facts(deliveredDaysAgo: 31));
      expect(r.resolution, 'store_credit');
      expect(r.amount, 100);
    });

    test('60 days: still store credit', () async {
      expect(
        (await run(facts(deliveredDaysAgo: 60))).resolution,
        'store_credit',
      );
    });

    test('61 days: not eligible', () async {
      final r = await run(facts(deliveredDaysAgo: 61));
      expect(r.resolution, 'not_eligible');
      expect(r.amount, 0);
    });

    test('final sale: not eligible, even after 1 day', () async {
      expect(
        (await run(facts(deliveredDaysAgo: 1, category: 'final_sale')))
            .resolution,
        'not_eligible',
      );
    });

    test('not delivered yet: return once it arrives', () async {
      expect(
        (await run(facts(status: 'shipped'))).resolution,
        'return_after_delivery',
      );
    });
  });

  group('the restocking fee on electronics', () {
    test('14 days after delivery: no fee', () async {
      final r = await run(
        facts(deliveredDaysAgo: 14, amount: 329, category: 'electronics'),
      );
      expect(r.resolution, 'refund');
      expect(r.amount, 329);
    });

    test('15 days: 15% off', () async {
      final r = await run(
        facts(deliveredDaysAgo: 15, amount: 329, category: 'electronics'),
      );
      expect(r.resolution, 'refund');
      expect(r.amount, 279.65);
    });

    test("a standard item after 15 days: no fee", () async {
      expect((await run(facts(deliveredDaysAgo: 15))).amount, 100);
    });
  });

  group('a person approves refunds above \$500', () {
    test('\$500.00: refunded', () async {
      expect((await run(facts(amount: 500))).resolution, 'refund');
    });

    test('\$500.01: manual review, and a review flag', () async {
      final r = await run(facts(amount: 500.01));
      expect(r.resolution, 'manual_review');
      expect(r.amount, 0);
      expect(r.review, isTrue);
    });
  });

  group('damage', () {
    test('reported 7 days after delivery: replace or refund', () async {
      final r = await run(
        facts(kind: 'damaged_defective', deliveredDaysAgo: 7),
      );
      expect(r.resolution, 'replace_or_refund');
      expect(r.amount, 100);
    });

    test('8 days: a regular return', () async {
      expect(
        (await run(facts(kind: 'damaged_defective', deliveredDaysAgo: 8)))
            .resolution,
        'refund',
      );
    });

    test('electronics after 365 days: warranty; 366: past it', () async {
      final within = await run(
        facts(
          kind: 'damaged_defective',
          placedDaysAgo: 370,
          deliveredDaysAgo: 365,
          category: 'electronics',
        ),
      );
      expect(within.resolution, 'warranty_repair');
      final past = await run(
        facts(
          kind: 'damaged_defective',
          placedDaysAgo: 371,
          deliveredDaysAgo: 366,
          category: 'electronics',
        ),
      );
      expect(past.resolution, 'not_eligible');
    });
  });

  group('price drops', () {
    test('14 days after ordering: the difference back', () async {
      final r = await run(
        facts(
          kind: 'price_adjustment',
          placedDaysAgo: 14,
          deliveredDaysAgo: 10,
          amount: 499,
          currentPrice: 449,
        ),
      );
      expect(r.resolution, 'price_adjustment');
      expect(r.amount, 50);
    });

    test('15 days: not eligible', () async {
      expect(
        (await run(
          facts(
            kind: 'price_adjustment',
            placedDaysAgo: 15,
            deliveredDaysAgo: 10,
            amount: 499,
            currentPrice: 449,
          ),
        )).resolution,
        'not_eligible',
      );
    });
  });

  group('deliveries and cancellations', () {
    test('shipped 10 days ago: on schedule', () async {
      final r = await run(
        facts(kind: 'where_is_order', placedDaysAgo: 10, status: 'shipped'),
      );
      expect(r.resolution, 'share_tracking');
      expect(r.priority, 'normal');
    });

    test('11 days: late, high priority', () async {
      final r = await run(
        facts(kind: 'where_is_order', placedDaysAgo: 11, status: 'shipped'),
      );
      expect(r.resolution, 'investigate_late');
      expect(r.priority, 'high');
    });

    test('cancel while processing: refunded in full', () async {
      final r = await run(
        facts(kind: 'cancel_order', placedDaysAgo: 0, status: 'processing'),
      );
      expect(r.resolution, 'cancel_and_refund');
      expect(r.amount, 100);
    });

    test('cancel once shipped: return it once it arrives', () async {
      expect(
        (await run(facts(kind: 'cancel_order', status: 'shipped'))).resolution,
        'return_after_delivery',
      );
    });

    test('charged twice: the duplicate back; once: a review', () async {
      expect(
        (await run(facts(kind: 'duplicate_charge', charges: 2))).resolution,
        'refund_duplicate',
      );
      expect(
        (await run(facts(kind: 'duplicate_charge'))).resolution,
        'manual_review',
      );
    });
  });
}
