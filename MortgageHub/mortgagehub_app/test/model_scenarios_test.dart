/// The mortgage rules (assets/models/proposal-check.json) executed on
/// aityx.ai, with the expected verdicts, including values just below, at
/// and just above the limits. Tagged `aityx`: skipped by `flutter test`,
/// run by scripts/model-test.sh, which passes AITYX_API_KEY and AITYX_URL
/// from the repository's .env. Plain tests, not widget tests, so the
/// HttpClient is the real one.
@Tags(['aityx'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// A conventional purchase that passes every check: $500,000, 20% down,
/// 30-year fixed, primary single-family in Texas, 740s, $120,000 a year,
/// $500 of debts, taxes and insurance estimated by the model.
const base = <String, Object?>{
  'loan_purpose': 'purchase',
  'loan_program': 'conventional',
  'rate_type': 'fixed',
  'term_years': 30,
  'property_type': 'single_family',
  'occupancy': 'primary',
  'state': 'TX',
  'property_value': 500000,
  'down_payment': 100000,
  'current_balance': 0,
  'cash_out': 0,
  'annual_taxes': null,
  'annual_insurance': null,
  'monthly_hoa': null,
  'credit_score': 's740',
  'annual_income': 120000,
  'monthly_debts': 500,
  'first_time_buyer': true,
  'military_service': false,
  'assumed_rate': 6.5,
};

/// The model's housing payment for [base] with [loan]: principal and
/// interest, and taxes (1%) and insurance (0.35%) of the value, in cents.
double housingPayment(num loan, num value) {
  double cents(num x) => (x * 100).round() / 100;
  const rate = 6.5 / 100 / 12;
  final pi = cents(loan * rate / (1 - pow(1 + rate, -360)));
  return cents(pi + (value * 0.01 + value * 0.0035) / 12);
}

late final Object? model;
late final String key;
late final Uri aityx;
final client = HttpClient();

Future<Map<String, Object?>> run(Map<String, Object?> changes) async {
  final call = await client.postUrl(aityx.resolve('/v1/systemone'));
  call.headers
    ..set('Authorization', 'Bearer $key')
    ..contentType = ContentType.json;
  call.write(
    jsonEncode({
      'decision': model,
      'state': {...base, ...changes},
    }),
  );
  final response = await call.close();
  final body = await response.transform(utf8.decoder).join();
  expect(response.statusCode, 200, reason: body);
  final json = jsonDecode(body) as Map<String, Object?>;
  expect(json['decision_error'], isNull);
  return json['answers'] as Map<String, Object?>;
}

/// Expects [status] and, for each named check, its result.
Future<void> expectVerdict(
  Map<String, Object?> changes,
  String status, [
  Map<String, String> checks = const {},
]) async {
  final answers = await run(changes);
  expect((answers['status'] as Map)['choice'], status, reason: '$changes');
  for (final MapEntry(key: id, value: result) in checks.entries) {
    final check = (answers['${id}_check'] as Map)['value'] as Map;
    expect(check['result'], result, reason: '$id: ${check['reason']}');
  }
}

void main() {
  setUpAll(() async {
    key = Platform.environment['AITYX_API_KEY'] ?? '';
    if (key.isEmpty) fail('AITYX_API_KEY is not set');
    final url = Platform.environment['AITYX_URL'] ?? '';
    aityx = Uri.parse(url.isEmpty ? 'https://api.aityx.ai' : url);
    model = jsonDecode(
      await File('assets/models/proposal-check.json').readAsString(),
    );
  });
  tearDownAll(() => client.close());

  test('the base case is processable, with the figures worked out', () async {
    final answers = await run({});
    expect((answers['status'] as Map)['choice'], 'processable');
    expect((answers['loan_amount'] as Map)['number'], 400000);
    expect((answers['ltv'] as Map)['number'], 80);
    expect((answers['principal_and_interest'] as Map)['number'], 2528.27);
    expect((answers['housing_payment'] as Map)['number'], 3090.77);
  });

  group('maximum LTV', () {
    test('97% with a first-time buyer: at, and just above', () async {
      await expectVerdict({'down_payment': 15000}, 'processable');
      await expectVerdict(
        {'down_payment': 14999},
        'not_processable',
        {'ltv': 'fail'},
      );
    });
    test('95% without a first-time buyer: at, and just above', () async {
      await expectVerdict({
        'down_payment': 25000,
        'first_time_buyer': false,
      }, 'processable');
      await expectVerdict(
        {'down_payment': 24999, 'first_time_buyer': false},
        'not_processable',
        {'ltv': 'fail'},
      );
    });
    test('investment cash-out on 2-4 units: 70%', () async {
      final cashOut = {
        'loan_purpose': 'cash_out_refinance',
        'occupancy': 'investment',
        'property_type': 'two_to_four_units',
        'down_payment': 0,
        'current_balance': 300000,
      };
      await expectVerdict({...cashOut, 'cash_out': 50000}, 'processable');
      await expectVerdict(
        {...cashOut, 'cash_out': 50001},
        'not_processable',
        {'ltv': 'fail'},
      );
    });
    test('FHA below 620: review above 90%, fail above 96.5%', () async {
      final fha = {'loan_program': 'fha', 'credit_score': 'below620'};
      await expectVerdict(
        {...fha, 'down_payment': 50000},
        'needs_review',
        {'ltv': 'pass', 'credit': 'review'},
      );
      await expectVerdict(
        {...fha, 'down_payment': 40000},
        'needs_review',
        {'ltv': 'review'},
      );
      await expectVerdict(
        {...fha, 'down_payment': 17499},
        'not_processable',
        {'ltv': 'fail'},
      );
    });
  });

  group('loan limits (2026)', () {
    test('conforming baseline \$832,750: at, and just above', () async {
      final big = {'property_value': 1100000, 'annual_income': 400000};
      await expectVerdict({...big, 'down_payment': 267250}, 'processable');
      await expectVerdict(
        {...big, 'down_payment': 267249},
        'needs_review',
        {'limit': 'review'},
      );
    });
    test('FHA ceiling \$1,249,125: at, and just above', () async {
      final fha = {
        'loan_program': 'fha',
        'property_value': 1400000,
        'annual_income': 600000,
      };
      await expectVerdict(
        {...fha, 'down_payment': 150875},
        'needs_review',
        {'limit': 'review'},
      );
      await expectVerdict(
        {...fha, 'down_payment': 150874},
        'not_processable',
        {'limit': 'fail'},
      );
    });
  });

  group('debt-to-income', () {
    // Debts that put the DTI at exactly 50% of $10,000 a month.
    final atFifty = 5000 - housingPayment(400000, 500000);
    test('conventional 50%: at is a review, just above fails', () async {
      await expectVerdict(
        {'monthly_debts': atFifty},
        'needs_review',
        {'dti': 'review'},
      );
      await expectVerdict(
        {'monthly_debts': atFifty + 0.01},
        'not_processable',
        {'dti': 'fail'},
      );
    });
  });

  group('program eligibility', () {
    test('FHA, VA and USDA only for a primary residence', () async {
      for (final program in ['fha', 'va', 'usda']) {
        await expectVerdict(
          {
            'loan_program': program,
            'occupancy': 'investment',
            'military_service': true,
          },
          'not_processable',
          {'program': 'fail'},
        );
      }
    });
    test('VA needs military service', () async {
      await expectVerdict(
        {'loan_program': 'va'},
        'not_processable',
        {'program': 'fail'},
      );
      await expectVerdict({
        'loan_program': 'va',
        'military_service': true,
      }, 'processable');
    });
    test('USDA is always reviewed, and allows no cash-out', () async {
      await expectVerdict(
        {'loan_program': 'usda', 'down_payment': 0, 'annual_income': 200000},
        'needs_review',
        {'program': 'review'},
      );
      await expectVerdict(
        {
          'loan_program': 'usda',
          'loan_purpose': 'cash_out_refinance',
          'down_payment': 0,
          'current_balance': 200000,
          'cash_out': 50000,
        },
        'not_processable',
        {'program': 'fail'},
      );
    });
    test('an unknown credit score is a review', () async {
      await expectVerdict(
        {'credit_score': 'unknown'},
        'needs_review',
        {'credit': 'review'},
      );
    });
  });
}
