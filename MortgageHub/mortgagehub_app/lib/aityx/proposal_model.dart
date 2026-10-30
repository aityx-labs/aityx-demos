/// Maps a proposal request (ProposalRequest.toJson()) to the inputs of the
/// aityx model (assets/models/proposal-check.json), and aityx's answers to
/// the check the summary shows. No I/O: see AityxProposalChecker in
/// lib/proposal/proposal_check.dart. Formerly the API's
/// (mortgagehub_api/lib/proposal_check.dart).
library;

/// The model, as an asset: sent with every call, since aityx stores none.
const modelAsset = 'assets/models/proposal-check.json';

/// The annual rate, in percent, the payment is estimated with.
const assumedRate = 6.5;

/// The model's checks, in the order the app shows them.
const checkIds = ['program', 'ltv', 'limit', 'credit', 'dti'];

class InvalidRequest implements Exception {
  InvalidRequest(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The app's enum names that differ from the model's choices.
const _choices = {
  'cashOutRefinance': 'cash_out_refinance',
  'notSure': 'not_sure',
  'singleFamily': 'single_family',
  'twoToFourUnits': 'two_to_four_units',
  'secondHome': 'second_home',
  'excellent': 's780',
};

/// The aityx state for [request], with [assumedRate] (annual %) for the
/// payment estimate. Throws [InvalidRequest] when a field is missing or of
/// the wrong type.
Map<String, Object?> toState(Map<String, Object?> request, double assumedRate) {
  final loan = _group(request, 'loan');
  final property = _group(request, 'property');
  final borrower = _group(request, 'borrower');
  String choice(Map<String, Object?> group, String key) {
    final value = group[key];
    if (value is! String) throw InvalidRequest('$key must be a string');
    return _choices[value] ?? value;
  }

  num number(Map<String, Object?> group, String key) {
    final value = group[key];
    if (value is! num) throw InvalidRequest('$key must be a number');
    return value;
  }

  num? optional(Map<String, Object?> group, String key) {
    final value = group[key];
    if (value != null && value is! num) {
      throw InvalidRequest('$key must be a number or null');
    }
    return value as num?;
  }

  bool flag(Map<String, Object?> group, String key) {
    final value = group[key];
    if (value is! bool) throw InvalidRequest('$key must be true or false');
    return value;
  }

  return {
    'loan_purpose': choice(loan, 'purpose'),
    'loan_program': choice(loan, 'program'),
    'rate_type': choice(loan, 'rateType'),
    'term_years': number(loan, 'termYears'),
    'property_type': choice(property, 'type'),
    'occupancy': choice(property, 'occupancy'),
    'state': choice(property, 'state'),
    'property_value': number(property, 'value'),
    'down_payment': number(property, 'downPayment'),
    'current_balance': number(property, 'currentBalance'),
    'cash_out': number(property, 'cashOut'),
    'annual_taxes': optional(property, 'annualTaxes'),
    'annual_insurance': optional(property, 'annualInsurance'),
    'monthly_hoa': optional(property, 'monthlyHoa'),
    'credit_score': choice(borrower, 'creditScore'),
    'annual_income': number(borrower, 'annualIncome'),
    'monthly_debts': number(borrower, 'monthlyDebts'),
    'first_time_buyer': flag(borrower, 'firstTimeBuyer'),
    'military_service': flag(borrower, 'militaryService'),
    'assumed_rate': assumedRate,
  };
}

Map<String, Object?> _group(Map<String, Object?> request, String key) {
  final group = request[key];
  if (group is! Map<String, Object?>) {
    throw InvalidRequest('$key must be an object');
  }
  return group;
}

num _round2(num value) => (value * 100).round() / 100;

/// The check, from aityx's [response] to the model: the status, the
/// figures it worked out, and each check's result and reason. Throws
/// [FormatException] when the answers aren't what the model gives.
Map<String, Object?> toResult(
  Map<String, Object?> response,
  double assumedRate,
) {
  if (response['decision_error'] != null) {
    throw FormatException('aityx: ${response['decision_error']}');
  }
  final answers = response['answers'];
  if (answers is! Map<String, Object?>) {
    throw const FormatException('aityx: no answers');
  }
  Object? field(String name, String key) {
    final answer = answers[name];
    if (answer is! Map<String, Object?> || !answer.containsKey(key)) {
      throw FormatException('aityx: no $key answer for $name');
    }
    return answer[key];
  }

  num number(String name) => switch (field(name, 'number')) {
    final num value => value,
    _ => throw FormatException('aityx: $name is not a number'),
  };
  return {
    'status': field('status', 'choice'),
    'figures': {
      'loanAmount': number('loan_amount'),
      // The model keeps LTV and DTI exact for its rules; shown rounded.
      'ltv': _round2(number('ltv')),
      'maxLtv': number('max_ltv'),
      'principalAndInterest': number('principal_and_interest'),
      'housingPayment': number('housing_payment'),
      'dti': _round2(number('dti')),
      'assumedRate': assumedRate,
    },
    'checks': [
      for (final id in checkIds)
        {
          'id': id,
          ...switch (field('${id}_check', 'value')) {
            {'result': final String result, 'reason': final String reason} => {
              'result': result,
              'reason': reason,
            },
            _ => throw FormatException('aityx: bad ${id}_check answer'),
          },
        },
    ],
  };
}

/// [result] with what the app shows under the check: the body [sent] to
/// aityx and its [answers] (parsed from [text]), under `aityx`. Left out if
/// [text] contains the [key], so a key aityx ever echoed isn't put on
/// screen.
Map<String, Object?> withAityx(
  Map<String, Object?> result,
  Map<String, Object?> sent,
  Map<String, Object?> answers,
  String text,
  String key,
) => {
  ...result,
  if (key.isEmpty || !text.contains(key))
    'aityx': {'request': sent, 'response': answers},
};
