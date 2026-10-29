import 'dart:convert';

import 'package:mortgagehub_api/proposal_check.dart';
import 'package:test/test.dart';

Map<String, Object?> request() => {
  'loan': {
    'purpose': 'cashOutRefinance',
    'program': 'notSure',
    'termYears': 30,
    'rateType': 'fixed',
    'timeline': 'shopping',
    'amount': 350000,
  },
  'property': {
    'type': 'twoToFourUnits',
    'occupancy': 'secondHome',
    'found': true,
    'street': '1 Main St',
    'city': 'Austin',
    'state': 'TX',
    'zip': '78701',
    'value': 500000,
    'downPayment': 0,
    'currentBalance': 300000,
    'cashOut': 50000,
    'annualTaxes': null,
    'annualInsurance': 1800,
    'monthlyHoa': null,
  },
  'borrower': {
    'firstName': 'Ana',
    'lastName': 'Lee',
    'email': 'ana@example.com',
    'phone': '5125550100',
    'hasCoBorrower': false,
    'creditScore': 'excellent',
    'employment': 'employed',
    'annualIncome': 120000,
    'monthlyDebts': 500,
    'assets': null,
    'firstTimeBuyer': false,
    'militaryService': true,
  },
};

void main() {
  test('maps a request to the model inputs', () {
    final state = toState(request(), 6.5);
    expect(state, {
      'loan_purpose': 'cash_out_refinance',
      'loan_program': 'not_sure',
      'rate_type': 'fixed',
      'term_years': 30,
      'property_type': 'two_to_four_units',
      'occupancy': 'second_home',
      'state': 'TX',
      'property_value': 500000,
      'down_payment': 0,
      'current_balance': 300000,
      'cash_out': 50000,
      'annual_taxes': null,
      'annual_insurance': 1800,
      'monthly_hoa': null,
      'credit_score': 's780',
      'annual_income': 120000,
      'monthly_debts': 500,
      'first_time_buyer': false,
      'military_service': true,
      'assumed_rate': 6.5,
    });
  });

  test('sends no personal details to aityx', () {
    final state = toState(request(), 6.5);
    for (final personal in ['Ana', 'Lee', 'ana@example.com', '5125550100']) {
      expect(state.values, isNot(contains(personal)));
    }
  });

  test('rejects a request with a missing or wrong field', () {
    final missing = request()..remove('loan');
    expect(() => toState(missing, 6.5), throwsA(isA<InvalidRequest>()));
    final wrong = request();
    (wrong['property'] as Map)['value'] = '500000';
    expect(() => toState(wrong, 6.5), throwsA(isA<InvalidRequest>()));
  });

  test('maps aityx answers to the result', () {
    Map<String, Object?> check(String result) => {
      'type': 'value',
      'value': {'result': result, 'reason': 'Because.'},
    };
    final result = toResult({
      'answers': {
        'status': {'type': 'choice', 'choice': 'needs_review'},
        'loan_amount': {'type': 'number', 'number': 400000},
        'ltv': {'type': 'number', 'number': 80},
        'max_ltv': {'type': 'number', 'number': 97},
        'principal_and_interest': {'type': 'number', 'number': 2528.27},
        'housing_payment': {'type': 'number', 'number': 3090.77},
        'dti': {'type': 'number', 'number': 35.91},
        'program_check': check('pass'),
        'ltv_check': check('pass'),
        'limit_check': check('review'),
        'credit_check': check('pass'),
        'dti_check': check('pass'),
      },
    }, 6.5);
    expect(result['status'], 'needs_review');
    expect((result['figures'] as Map)['dti'], 35.91);
    final checks = result['checks'] as List;
    expect(checks.map((c) => (c as Map)['id']), checkIds);
    expect(checks[2], {
      'id': 'limit',
      'result': 'review',
      'reason': 'Because.',
    });
  });

  test('fails on a decision error or missing answers', () {
    expect(
      () => toResult({'decision_error': 'boom', 'answers': {}}, 6.5),
      throwsFormatException,
    );
    expect(() => toResult({'answers': {}}, 6.5), throwsFormatException);
  });

  test('adds the aityx request and response to the result', () {
    final sent = {
      'decision': {'name': 'proposal-check'},
      'state': {'loan_program': 'fha'},
    };
    final answers = {
      'answers': {'status': {}},
      'receipt': {'id': 'r1'},
      'usage': {'input_tokens': 6000},
    };
    final result = withAityx(
      {'status': 'processable'},
      sent,
      answers,
      jsonEncode(answers),
      'secret-key',
    );
    expect(result['status'], 'processable');
    expect(result['aityx'], {'request': sent, 'response': answers});
  });

  test('leaves the aityx answer out if it contains the key', () {
    final answers = {'echo': 'Bearer secret-key'};
    final result = withAityx(
      {'status': 'processable'},
      {'state': {}},
      answers,
      jsonEncode(answers),
      'secret-key',
    );
    expect(result, {'status': 'processable'});
  });
}
