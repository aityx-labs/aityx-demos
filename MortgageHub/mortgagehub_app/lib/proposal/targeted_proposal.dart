import 'dart:math';

import 'package:faker/faker.dart';

import 'proposal_check.dart';
import 'proposal_request.dart';
import 'random_proposal.dart';

/// A random request built to get [target] from the regulatory check
/// (specs/regulatory-check.md), for Fill random's menu. It passes the
/// form's own checks, so a Not processable request fails only checks the
/// form can't make (the LTV maximum, DTI, loan limits, USDA's rules).
///
/// It aims, it doesn't decide: aityx gives the verdict. The amounts keep
/// clear of the limits, and the income is worked out for a DTI with the
/// API's default rate (6.5%), so another ASSUMED_RATE can move a DTI case.
ProposalRequest targetedProposal(CheckStatus target, [Faker? faker]) {
  final f = faker ?? Faker();
  final draft = _Draft.processable(f);
  switch (target) {
    case CheckStatus.processable:
      break;
    case CheckStatus.needsReview:
      f.randomGenerator.element(_reviews)(draft);
    case CheckStatus.notProcessable:
      f.randomGenerator.element(_failures)(draft);
  }
  return draft.build();
}

/// One reason for Requires review each, and nothing that fails.
final List<void Function(_Draft)> _reviews = [
  // No score: the lender needs the credit report.
  (d) => d.creditScore = CreditScoreRange.unknown,
  // Below 620: lenders' minimums (the draft's FHA LTV stays at or under 90%).
  (d) => d.creditScore = CreditScoreRange.below620,
  // A high-balance conventional loan, above the $832,750 baseline (not
  // in AK, HI, GU or VI, whose baseline is higher).
  (d) {
    d
      ..program = d.pick([LoanProgram.conventional, LoanProgram.notSure])
      ..state = d.pick(['TX', 'CA', 'NY', 'FL', 'WA'])
      ..setLoan(d.amount(850000, 1200000), ltv: d.number(50, 75))
      ..fitIncome(dti: d.number(20, 38));
  },
  // USDA: always a review of the area and the household income.
  (d) {
    d
      ..program = LoanProgram.usda
      ..occupancy = Occupancy.primary
      ..purpose = LoanPurpose.purchase
      ..propertyType = d.pick([
        PropertyType.singleFamily,
        PropertyType.townhouse,
        PropertyType.manufactured,
      ])
      ..setValue(d.amount(150000, 450000), ltv: d.number(90, 99))
      ..fitIncome(dti: d.number(20, 36));
  },
  // A conventional DTI between 45% and 50%.
  (d) {
    d
      ..program = d.pick([LoanProgram.conventional, LoanProgram.notSure])
      ..resetLtv()
      ..fitIncome(dti: d.number(46.5, 49));
  },
  // A VA cash-out above lenders' usual 90% cap.
  (d) {
    d
      ..program = LoanProgram.va
      ..militaryService = true
      ..occupancy = Occupancy.primary
      ..purpose = LoanPurpose.cashOutRefinance
      ..setValue(d.amount(200000, 600000), ltv: d.number(92, 98))
      ..fitIncome(dti: d.number(20, 36));
  },
];

/// One reason for Not processable each.
final List<void Function(_Draft)> _failures = [
  // Above the conventional maximum LTV: 97% for a primary purchase.
  (d) {
    d
      ..program = LoanProgram.conventional
      ..occupancy = Occupancy.primary
      ..purpose = LoanPurpose.purchase
      ..propertyType = PropertyType.singleFamily
      ..setValue(d.amount(150000, 700000), ltv: d.number(98, 99.5))
      ..fitIncome(dti: d.number(20, 38));
  },
  // Above the investment maximum: 85% for a purchase.
  (d) {
    d
      ..program = LoanProgram.conventional
      ..occupancy = Occupancy.investment
      ..purpose = LoanPurpose.purchase
      ..propertyType = PropertyType.singleFamily
      ..setValue(d.amount(150000, 700000), ltv: d.number(88, 95))
      ..fitIncome(dti: d.number(20, 38));
  },
  // A conventional DTI above Fannie Mae's 50% maximum.
  (d) {
    d
      ..program = LoanProgram.conventional
      ..resetLtv()
      ..fitIncome(dti: d.number(56, 75));
  },
  // An FHA loan above the 2026 ceiling of $1,249,125.
  (d) {
    d
      ..program = LoanProgram.fha
      ..occupancy = Occupancy.primary
      ..state = d.pick(['TX', 'CA', 'NY', 'FL', 'WA'])
      ..setLoan(d.amount(1300000, 1800000), ltv: d.number(80, 90))
      ..fitIncome(dti: d.number(20, 38));
  },
  // A second home with 2 to 4 units: Fannie Mae finances 1 unit.
  (d) {
    d
      ..program = LoanProgram.conventional
      ..occupancy = Occupancy.secondHome
      ..propertyType = PropertyType.twoToFourUnits;
  },
  // A manufactured home as an investment.
  (d) {
    d
      ..program = LoanProgram.conventional
      ..occupancy = Occupancy.investment
      ..propertyType = PropertyType.manufactured;
  },
  // USDA allows no cash-out refinance.
  (d) {
    d
      ..program = LoanProgram.usda
      ..occupancy = Occupancy.primary
      ..purpose = LoanPurpose.cashOutRefinance
      ..propertyType = PropertyType.singleFamily
      ..setValue(d.amount(150000, 450000), ltv: d.number(50, 70))
      ..fitIncome(dti: d.number(20, 36));
  },
];

/// A processable request, then changed by one review or failure: the
/// borrower and contact details from [randomProposal], and the loan built
/// to pass every check with room to spare.
class _Draft {
  _Draft.processable(this.f) : base = randomProposal(f) {
    purpose = pick(LoanPurpose.values);
    occupancy = pick(Occupancy.values);
    propertyType = switch (occupancy) {
      Occupancy.primary => pick(PropertyType.values),
      Occupancy.secondHome => pick(
        PropertyType.values.where((t) => t != PropertyType.twoToFourUnits),
      ),
      Occupancy.investment => pick(
        PropertyType.values.where((t) => t != PropertyType.manufactured),
      ),
    };
    program = occupancy == Occupancy.primary
        ? pick([
            LoanProgram.conventional,
            LoanProgram.notSure,
            LoanProgram.fha,
            LoanProgram.va,
          ])
        : pick([LoanProgram.conventional, LoanProgram.notSure]);
    militaryService = program == LoanProgram.va || random.integer(10) == 0;
    creditScore = pick([
      CreditScoreRange.excellent,
      CreditScoreRange.s760,
      CreditScoreRange.s740,
      CreditScoreRange.s720,
      CreditScoreRange.s700,
      CreditScoreRange.s680,
      CreditScoreRange.s660,
      CreditScoreRange.s640,
    ]);
    state = base.state;
    // Loans stay under FHA's $541,287 floor, and under the $832,750
    // conforming baseline for every program the baseline applies to. VA is
    // the exception: it has no loan limit with full entitlement (the
    // model's limit_check, 38 U.S.C. 3703), so a VA draft may run past the
    // baseline at up to 95% of $900,000.
    final maxValue = program == LoanProgram.fha ? 550000 : 900000;
    setValue(amount(150000, maxValue), ltv: number(40, safeLtv));
    taxRate = base.annualTaxes == null ? null : number(0.5, 2) / 100;
    insuranceRate = base.annualInsurance == null
        ? null
        : number(0.2, 0.6) / 100;
    monthlyDebts = amount(0, 1500, step: 50);
    fitIncome(dti: number(20, 36));
  }

  final Faker f;
  final ProposalRequest base;
  RandomGenerator get random => f.randomGenerator;

  late LoanPurpose purpose;
  late LoanProgram program;
  late Occupancy occupancy;
  late PropertyType propertyType;
  late bool militaryService;
  late CreditScoreRange creditScore;
  late String state;
  late int value;
  int downPayment = 0;
  int currentBalance = 0;
  int cashOut = 0;
  late int monthlyDebts;

  /// The yearly taxes and insurance as a share of the value, or null to
  /// leave them out (the model estimates them).
  double? taxRate;
  double? insuranceRate;

  int? get annualTaxes =>
      taxRate == null ? null : (value * taxRate! / 100).round() * 100;
  int? get annualInsurance => insuranceRate == null
      ? null
      : (value * insuranceRate! / 100).round() * 100;
  late int annualIncome;

  T pick<T>(Iterable<T> values) => random.element(values.toList());

  int amount(int min, int max, {int step = 1000}) =>
      random.integer(max ~/ step + 1, min: min ~/ step) * step;

  /// A number between [min] and [max], to a tenth.
  double number(double min, double max) =>
      random.integer((max * 10).round() + 1, min: (min * 10).round()) / 10;

  /// An LTV that passes for the draft's program, occupancy and purpose,
  /// below every maximum in the rules.
  double get safeLtv => switch (program) {
    LoanProgram.fha => purpose == LoanPurpose.cashOutRefinance ? 75 : 90,
    LoanProgram.va => purpose == LoanPurpose.cashOutRefinance ? 85 : 95,
    _ => switch ((occupancy, purpose)) {
      (_, LoanPurpose.cashOutRefinance) => 60,
      (Occupancy.primary, _) => 90,
      (Occupancy.secondHome, _) => 85,
      (Occupancy.investment, _) => 70,
    },
  };

  /// The value's loan at an LTV that passes for the current program.
  void resetLtv() => setValue(value, ltv: number(40, safeLtv));

  /// The loan at [ltv] percent of [value].
  void setValue(int value, {required double ltv}) {
    this.value = value;
    _split((value * ltv / 100 / 1000).floor() * 1000);
  }

  /// A [loan], with the value it takes for [ltv] percent.
  void setLoan(int loan, {required double ltv}) {
    value = (loan * 100 / ltv / 5000).ceil() * 5000;
    _split(loan);
  }

  /// Splits [loan] by the purpose: a down payment, a balance, or a balance
  /// and cash out.
  void _split(int loan) {
    downPayment = currentBalance = cashOut = 0;
    switch (purpose) {
      case LoanPurpose.purchase:
        downPayment = value - loan;
      case LoanPurpose.refinance:
        currentBalance = loan;
      case LoanPurpose.cashOutRefinance:
        cashOut = max(1000, (loan * 0.25 / 1000).floor() * 1000);
        currentBalance = loan - cashOut;
    }
  }

  int get loan => switch (purpose) {
    LoanPurpose.purchase => value - downPayment,
    LoanPurpose.refinance => currentBalance,
    LoanPurpose.cashOutRefinance => currentBalance + cashOut,
  };

  /// The annual income that puts the debt-to-income ratio at [dti] percent,
  /// with the payment the model estimates at 6.5%.
  void fitIncome({required double dti}) {
    const rate = 6.5 / 100 / 12;
    final payments = base.term.years * 12;
    final principalAndInterest = loan * rate / (1 - pow(1 + rate, -payments));
    final housing =
        principalAndInterest +
        (annualTaxes ?? value * 0.01) / 12 +
        (annualInsurance ?? value * 0.0035) / 12 +
        (base.monthlyHoa ?? 0);
    annualIncome =
        ((housing + monthlyDebts) * 12 * 100 / dti / 100).round() * 100;
  }

  ProposalRequest build() {
    final found = !purpose.isPurchase || base.propertyFound;
    return ProposalRequest(
      purpose: purpose,
      program: program,
      term: base.term,
      rateType: base.rateType,
      timeline: base.timeline,
      propertyType: propertyType,
      occupancy: occupancy,
      propertyFound: found,
      street: found
          ? (base.street.isEmpty ? f.address.streetAddress() : base.street)
          : '',
      city: found ? (base.city.isEmpty ? f.address.city() : base.city) : '',
      state: state,
      zip: base.zip,
      propertyValue: value,
      downPayment: downPayment,
      currentBalance: currentBalance,
      cashOut: cashOut,
      annualTaxes: annualTaxes,
      annualInsurance: annualInsurance,
      monthlyHoa: base.monthlyHoa,
      firstName: base.firstName,
      lastName: base.lastName,
      email: base.email,
      phone: base.phone,
      hasCoBorrower: base.hasCoBorrower,
      creditScore: creditScore,
      employment: base.employment,
      annualIncome: annualIncome,
      monthlyDebts: monthlyDebts,
      assets: base.assets,
      firstTimeBuyer: purpose.isPurchase && base.firstTimeBuyer,
      militaryService: militaryService,
    );
  }
}
