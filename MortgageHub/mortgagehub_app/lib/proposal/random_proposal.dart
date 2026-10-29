import 'package:faker/faker.dart';

import 'proposal_request.dart';

/// A random, valid proposal request, for the form's **Fill random**: names,
/// streets, cities and ZIP codes from [faker], and amounts that pass the
/// form's checks (the loan less than the value, the program allowed for
/// the occupancy and military service). Contact details are never real:
/// emails at example.com (reserved, RFC 2606) and phones in the fictional
/// 555-0100 to 555-0199 range.
ProposalRequest randomProposal([Faker? faker]) {
  final f = faker ?? Faker();
  final random = f.randomGenerator;
  T pick<T>(List<T> values) => random.element(values);

  /// A whole amount between [min] and [max], rounded to [step].
  int amount(int min, int max, {int step = 1000}) =>
      random.integer(max ~/ step + 1, min: min ~/ step) * step;

  final purpose = pick(LoanPurpose.values);
  final occupancy = pick(Occupancy.values);
  final propertyType = pick(PropertyType.values);
  final value = amount(150000, 1500000, step: 5000);

  // FHA, VA and USDA are only for a primary residence; VA needs service.
  final program = occupancy == Occupancy.primary
      ? pick(LoanProgram.values)
      : pick([LoanProgram.conventional, LoanProgram.notSure]);
  final militaryService = program == LoanProgram.va || random.integer(10) == 0;

  final downPayment = purpose.isPurchase
      ? amount(value * 3 ~/ 100, value * 30 ~/ 100)
      : 0;
  final currentBalance = purpose.isPurchase
      ? 0
      : amount(value * 20 ~/ 100, value * 70 ~/ 100);
  final cashOut = purpose == LoanPurpose.cashOutRefinance
      ? amount(value * 5 ~/ 100, value * 15 ~/ 100)
      : 0;
  final propertyFound = !purpose.isPurchase || random.boolean();
  // Condos and townhouses usually have HOA dues; other homes sometimes.
  final hasHoa =
      propertyType == PropertyType.condo ||
          propertyType == PropertyType.townhouse
      ? random.integer(4) > 0
      : random.integer(4) == 0;

  final firstName = f.person.firstName();
  final lastName = f.person.lastName();
  final emailName = '$firstName.$lastName'.toLowerCase().replaceAll(
    RegExp('[^a-z.]'),
    '',
  );

  return ProposalRequest(
    purpose: purpose,
    program: program,
    term: pick(LoanTerm.values),
    rateType: pick(RateType.values),
    timeline: pick(Timeline.values),
    propertyType: propertyType,
    occupancy: occupancy,
    propertyFound: propertyFound,
    street: propertyFound ? f.address.streetAddress() : '',
    city: propertyFound ? f.address.city() : '',
    state: random.mapElementKey(usStates),
    zip: f.address.zipCode().substring(0, 5),
    propertyValue: value,
    downPayment: downPayment,
    currentBalance: currentBalance,
    cashOut: cashOut,
    annualTaxes: random.boolean()
        ? amount(value ~/ 200, value ~/ 50, step: 100)
        : null,
    annualInsurance: random.boolean()
        ? amount(value ~/ 400, value ~/ 150, step: 100)
        : null,
    monthlyHoa: hasHoa ? amount(100, 700, step: 25) : null,
    firstName: firstName,
    lastName: lastName,
    email: '$emailName@example.com',
    phone:
        '${random.integer(10, min: 2)}${random.integer(10)}${random.integer(10)}'
        '55501${random.integer(10)}${random.integer(10)}',
    hasCoBorrower: random.boolean(),
    creditScore: pick(CreditScoreRange.values),
    employment: pick(EmploymentType.values),
    annualIncome: amount(40000, 400000),
    monthlyDebts: amount(0, 3000, step: 50),
    assets: random.boolean() ? amount(10000, 500000) : null,
    firstTimeBuyer: purpose.isPurchase && random.boolean(),
    militaryService: militaryService,
  );
}
