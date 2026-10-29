import 'package:faker/faker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/proposal/proposal_request.dart';
import 'package:mortgagehub_app/proposal/random_proposal.dart';

void main() {
  test('random requests always pass the form\'s checks', () {
    final faker = Faker(seed: 42);
    for (var i = 0; i < 500; i++) {
      final r = randomProposal(faker);
      expect(r.propertyValue, greaterThan(0));
      expect(r.loanAmount, greaterThan(0));
      expect(r.loanAmount, lessThan(r.propertyValue));
      if (r.purpose.isPurchase) {
        expect(r.downPayment, lessThan(r.propertyValue));
      } else {
        expect(r.currentBalance, greaterThan(0));
        expect(r.propertyFound, isTrue);
      }
      if (r.purpose == LoanPurpose.cashOutRefinance) {
        expect(r.cashOut, greaterThan(0));
      }
      if (r.program
          case LoanProgram.fha || LoanProgram.va || LoanProgram.usda) {
        expect(r.occupancy, Occupancy.primary);
      }
      if (r.program == LoanProgram.va) expect(r.militaryService, isTrue);
      if (r.propertyFound) {
        expect(r.street, isNotEmpty);
        expect(r.city, isNotEmpty);
      }
      expect(usStates.containsKey(r.state), isTrue);
      expect(r.zip, matches(RegExp(r'^\d{5}$')));
      expect(r.email, matches(RegExp(r'^[a-z.]+@example\.com$')));
      expect(r.phone, matches(RegExp(r'^[2-9]\d{2}55501\d{2}$')));
      expect(r.annualIncome, greaterThan(0));
      expect(r.firstName, isNotEmpty);
      expect(r.lastName, isNotEmpty);
    }
  });
}
