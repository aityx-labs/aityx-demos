import 'dart:math';

import 'package:faker/faker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/proposal/proposal_check.dart';
import 'package:mortgagehub_app/proposal/proposal_request.dart';
import 'package:mortgagehub_app/proposal/targeted_proposal.dart';

/// The form's own checks (proposal_form_screen.dart): a targeted request
/// must pass them, whatever verdict it aims for.
void expectFormValid(ProposalRequest r) {
  expect(r.propertyValue, greaterThan(0));
  expect(r.loanAmount, inExclusiveRange(0, r.propertyValue));
  if (!r.purpose.isPurchase) expect(r.currentBalance, greaterThan(0));
  if (r.purpose == LoanPurpose.cashOutRefinance) {
    expect(r.cashOut, greaterThan(0));
  }
  if (r.program case LoanProgram.fha || LoanProgram.va || LoanProgram.usda) {
    expect(r.occupancy, Occupancy.primary);
  }
  if (r.program == LoanProgram.va) expect(r.militaryService, isTrue);
  if (r.propertyFound) expect(r.street, isNotEmpty);
  expect(r.zip, matches(RegExp(r'^\d{5}$')));
  expect(r.annualIncome, greaterThan(0));
  expect(r.monthlyDebts, greaterThanOrEqualTo(0));
  if (!r.purpose.isPurchase) expect(r.firstTimeBuyer, isFalse);
}

/// The monthly housing payment the model estimates: principal and interest
/// at the check's assumed rate of 6.5%, plus taxes, insurance and any HOA
/// dues. Where taxes or insurance are left out, the model estimates them at
/// 1% and 0.35% of the value a year, as fitIncome does.
double monthlyHousing(ProposalRequest r) {
  const rate = 6.5 / 100 / 12;
  final payments = r.term.years * 12;
  final principalAndInterest =
      r.loanAmount * rate / (1 - pow(1 + rate, -payments));
  return principalAndInterest +
      (r.annualTaxes ?? r.propertyValue * 0.01) / 12 +
      (r.annualInsurance ?? r.propertyValue * 0.0035) / 12 +
      (r.monthlyHoa ?? 0);
}

/// The debt-to-income ratio the check will see, in percent.
double debtToIncome(ProposalRequest r) =>
    (monthlyHousing(r) + r.monthlyDebts) * 12 * 100 / r.annualIncome;

void main() {
  for (final target in CheckStatus.values) {
    test('${target.label} requests pass the form\'s checks', () {
      final faker = Faker(seed: target.index);
      for (var i = 0; i < 300; i++) {
        expectFormValid(targetedProposal(target, faker));
      }
    });
  }

  test('processable requests stay clear of the limits', () {
    final faker = Faker(seed: 11);
    for (var i = 0; i < 300; i++) {
      final r = targetedProposal(CheckStatus.processable, faker);
      expect(r.creditScore, isNot(CreditScoreRange.unknown));
      expect(r.creditScore, isNot(CreditScoreRange.below620));
      expect(r.program, isNot(LoanProgram.usda));
      // VA has no loan limit with full entitlement, so a VA draft may
      // exceed the conforming baseline and still be processable. Every
      // other program here stays under it.
      if (r.program != LoanProgram.va) {
        expect(r.loanAmount, lessThanOrEqualTo(832750));
      }
      if (r.program == LoanProgram.fha) {
        expect(r.loanAmount, lessThanOrEqualTo(541287));
      }
      expect(r.loanToValue, lessThanOrEqualTo(95));
    }
  });

  // fitIncome works the income back from the payment, so nothing else
  // checks its arithmetic: the form accepts any positive income, and only
  // the live tests see a verdict. These recompute the ratio from the
  // finished request.
  test('processable requests keep the ratio in the band they aim for', () {
    final faker = Faker(seed: 11);
    for (var i = 0; i < 300; i++) {
      final r = targetedProposal(CheckStatus.processable, faker);
      // The draft aims for 20 to 36%; the income is rounded to the nearest
      // $100 afterwards, which moves the ratio by well under a tenth.
      expect(debtToIncome(r), inInclusiveRange(19.9, 36.1));
    }
  });

  test('the ratio stays under every maximum the rules apply', () {
    final faker = Faker(seed: 7);
    for (var i = 0; i < 300; i++) {
      final r = targetedProposal(CheckStatus.processable, faker);
      // Fannie Mae's 50% maximum, and USDA's 41% guideline for the
      // programs that use it.
      expect(debtToIncome(r), lessThan(45));
    }
  });

  test('a targeted high ratio really does breach the maximum', () {
    final faker = Faker(seed: 3);
    final breached = <double>[];
    for (var i = 0; i < 300; i++) {
      final r = targetedProposal(CheckStatus.notProcessable, faker);
      final dti = debtToIncome(r);
      expect(dti, greaterThan(0));
      if (dti > 50) breached.add(dti);
    }
    // One of the Not processable reasons is a conventional DTI of 56 to
    // 75%. If fitIncome drifted, this would come back empty while the
    // form's own checks still passed.
    expect(breached, isNotEmpty);
    expect(breached.reduce(max), greaterThan(55));
  });

  test('a targeted review ratio lands between the two maximums', () {
    final faker = Faker(seed: 5);
    final reviewed = <double>[];
    for (var i = 0; i < 300; i++) {
      final dti = debtToIncome(
        targetedProposal(CheckStatus.needsReview, faker),
      );
      if (dti > 45) reviewed.add(dti);
    }
    // The review reason is a conventional DTI of 46.5 to 49%: over the 45%
    // that needs a second look, under Fannie Mae's 50% refusal.
    expect(reviewed, isNotEmpty);
    expect(reviewed.every((d) => d < 50), isTrue);
  });
}
