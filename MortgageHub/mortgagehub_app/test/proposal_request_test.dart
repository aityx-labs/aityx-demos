import 'package:flutter_test/flutter_test.dart';
import 'package:mortgagehub_app/proposal/proposal_request.dart';
import 'package:mortgagehub_app/proposal/proposal_summary_screen.dart';

ProposalRequest request({
  LoanPurpose purpose = LoanPurpose.purchase,
  int value = 500000,
  int downPayment = 100000,
  int currentBalance = 0,
  int cashOut = 0,
}) => ProposalRequest(
  purpose: purpose,
  program: LoanProgram.conventional,
  term: LoanTerm.years30,
  rateType: RateType.fixed,
  timeline: Timeline.days30to60,
  propertyType: PropertyType.singleFamily,
  occupancy: Occupancy.primary,
  propertyFound: true,
  street: '1 Main St',
  city: 'Austin',
  state: 'TX',
  zip: '78701',
  propertyValue: value,
  downPayment: downPayment,
  currentBalance: currentBalance,
  cashOut: cashOut,
  firstName: 'Ana',
  lastName: 'Lee',
  email: 'ana@example.com',
  phone: '5125550100',
  hasCoBorrower: false,
  creditScore: CreditScoreRange.s740,
  employment: EmploymentType.employed,
  annualIncome: 120000,
  monthlyDebts: 500,
  firstTimeBuyer: true,
  militaryService: false,
);

void main() {
  test('a purchase borrows the price less the down payment', () {
    final r = request();
    expect(r.loanAmount, 400000);
    expect(r.loanToValue, 80);
    expect(r.debtToIncome, 5);
  });

  test('a refinance borrows the balance, plus any cash out', () {
    expect(
      request(
        purpose: LoanPurpose.refinance,
        currentBalance: 300000,
      ).loanAmount,
      300000,
    );
    final cashOut = request(
      purpose: LoanPurpose.cashOutRefinance,
      currentBalance: 300000,
      cashOut: 50000,
    );
    expect(cashOut.loanAmount, 350000);
    expect(cashOut.loanToValue, 70);
  });

  test('the JSON has the loan, the property and the borrower', () {
    final json = request().toJson();
    expect(json.keys, ['loan', 'property', 'borrower']);
    expect((json['loan'] as Map)['amount'], 400000);
    expect((json['borrower'] as Map).containsKey('ssn'), isFalse);
  });

  test('money and percentages are formatted for the summary', () {
    expect(money(425000), r'$425,000');
    expect(money(0), r'$0');
    expect(money(1234567), r'$1,234,567');
    expect(percent(80), '80.0%');
  });
}
