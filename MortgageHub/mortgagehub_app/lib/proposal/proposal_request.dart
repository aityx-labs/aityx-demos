/// A request for a mortgage proposal (a quote), with what a US lender needs
/// to price a loan and estimate its payment. See specs/proposal-request.md
/// for why each field is asked, and why the Social Security number isn't.
library;

/// A choice shown in a dropdown: its label is what the borrower reads.
abstract interface class Labeled {
  String get label;
}

enum LoanPurpose implements Labeled {
  purchase('Buy a home'),
  refinance('Refinance (rate and term)'),
  cashOutRefinance('Cash-out refinance');

  const LoanPurpose(this.label);
  @override
  final String label;

  bool get isPurchase => this == purchase;
}

/// The loan program, which sets the down payment, mortgage insurance and
/// who may borrow (VA: service members and veterans; USDA: eligible rural
/// areas and incomes).
enum LoanProgram implements Labeled {
  conventional('Conventional'),
  fha('FHA'),
  va('VA'),
  usda('USDA'),
  notSure('Not sure, recommend one');

  const LoanProgram(this.label);
  @override
  final String label;
}

enum LoanTerm implements Labeled {
  years30('30 years', 30),
  years20('20 years', 20),
  years15('15 years', 15),
  years10('10 years', 10);

  const LoanTerm(this.label, this.years);
  @override
  final String label;
  final int years;
}

enum RateType implements Labeled {
  fixed('Fixed rate'),
  adjustable('Adjustable rate (ARM)'),
  notSure('Not sure');

  const RateType(this.label);
  @override
  final String label;
}

enum PropertyType implements Labeled {
  singleFamily('Single-family home'),
  townhouse('Townhouse'),
  condo('Condominium'),
  twoToFourUnits('2 to 4 units'),
  manufactured('Manufactured home');

  const PropertyType(this.label);
  @override
  final String label;
}

/// How the borrower will use the home: second homes and investment
/// properties are priced higher and need more down.
enum Occupancy implements Labeled {
  primary('Primary residence'),
  secondHome('Second home'),
  investment('Investment property');

  const Occupancy(this.label);
  @override
  final String label;
}

/// Self-reported, so the quote needs no credit check. The bands follow
/// the agencies' pricing grids (20-point steps from 620 to 780).
enum CreditScoreRange implements Labeled {
  excellent('780 or higher'),
  s760('760 to 779'),
  s740('740 to 759'),
  s720('720 to 739'),
  s700('700 to 719'),
  s680('680 to 699'),
  s660('660 to 679'),
  s640('640 to 659'),
  s620('620 to 639'),
  below620('Below 620'),
  unknown("I don't know");

  const CreditScoreRange(this.label);
  @override
  final String label;
}

enum EmploymentType implements Labeled {
  employed('Employed (W-2)'),
  selfEmployed('Self-employed'),
  retired('Retired'),
  other('Other');

  const EmploymentType(this.label);
  @override
  final String label;
}

enum Timeline implements Labeled {
  under30Days('Within 30 days'),
  days30to60('In 30 to 60 days'),
  over60Days('In more than 60 days'),
  shopping('Just comparing offers');

  const Timeline(this.label);
  @override
  final String label;
}

/// US states, DC and Puerto Rico, by postal code: taxes, insurance,
/// closing costs and loan limits depend on where the home is.
const usStates = <String, String>{
  'AL': 'Alabama',
  'AK': 'Alaska',
  'AZ': 'Arizona',
  'AR': 'Arkansas',
  'CA': 'California',
  'CO': 'Colorado',
  'CT': 'Connecticut',
  'DE': 'Delaware',
  'DC': 'District of Columbia',
  'FL': 'Florida',
  'GA': 'Georgia',
  'HI': 'Hawaii',
  'ID': 'Idaho',
  'IL': 'Illinois',
  'IN': 'Indiana',
  'IA': 'Iowa',
  'KS': 'Kansas',
  'KY': 'Kentucky',
  'LA': 'Louisiana',
  'ME': 'Maine',
  'MD': 'Maryland',
  'MA': 'Massachusetts',
  'MI': 'Michigan',
  'MN': 'Minnesota',
  'MS': 'Mississippi',
  'MO': 'Missouri',
  'MT': 'Montana',
  'NE': 'Nebraska',
  'NV': 'Nevada',
  'NH': 'New Hampshire',
  'NJ': 'New Jersey',
  'NM': 'New Mexico',
  'NY': 'New York',
  'NC': 'North Carolina',
  'ND': 'North Dakota',
  'OH': 'Ohio',
  'OK': 'Oklahoma',
  'OR': 'Oregon',
  'PA': 'Pennsylvania',
  'PR': 'Puerto Rico',
  'RI': 'Rhode Island',
  'SC': 'South Carolina',
  'SD': 'South Dakota',
  'TN': 'Tennessee',
  'TX': 'Texas',
  'UT': 'Utah',
  'VT': 'Vermont',
  'VA': 'Virginia',
  'WA': 'Washington',
  'WV': 'West Virginia',
  'WI': 'Wisconsin',
  'WY': 'Wyoming',
};

class ProposalRequest {
  const ProposalRequest({
    required this.purpose,
    required this.program,
    required this.term,
    required this.rateType,
    required this.timeline,
    required this.propertyType,
    required this.occupancy,
    required this.propertyFound,
    this.street = '',
    this.city = '',
    required this.state,
    required this.zip,
    required this.propertyValue,
    this.downPayment = 0,
    this.currentBalance = 0,
    this.cashOut = 0,
    this.annualTaxes,
    this.annualInsurance,
    this.monthlyHoa,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.hasCoBorrower,
    required this.creditScore,
    required this.employment,
    required this.annualIncome,
    required this.monthlyDebts,
    this.assets,
    required this.firstTimeBuyer,
    required this.militaryService,
  });

  // Loan
  final LoanPurpose purpose;
  final LoanProgram program;
  final LoanTerm term;
  final RateType rateType;
  final Timeline timeline;

  // Property
  final PropertyType propertyType;
  final Occupancy occupancy;

  /// Whether a buyer has found the home (a refinance always has).
  final bool propertyFound;
  final String street;
  final String city;
  final String state;
  final String zip;

  /// The purchase price, or the home's estimated value for a refinance.
  final int propertyValue;

  /// Purchase only.
  final int downPayment;

  /// Refinance only: what's left on the current mortgage.
  final int currentBalance;

  /// Cash-out refinance only.
  final int cashOut;

  /// Optional: the lender estimates them from the location when unknown.
  final int? annualTaxes;
  final int? annualInsurance;
  final int? monthlyHoa;

  // Borrower
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final bool hasCoBorrower;
  final CreditScoreRange creditScore;
  final EmploymentType employment;

  /// Gross (before tax), every borrower's together.
  final int annualIncome;

  /// Minimum monthly payments on debts: cards, car, student loans. Not
  /// rent, and not the mortgage being refinanced.
  final int monthlyDebts;

  /// Optional: savings and investments available to close.
  final int? assets;
  final bool firstTimeBuyer;
  final bool militaryService;

  /// The mortgage loan amount sought.
  int get loanAmount => switch (purpose) {
    LoanPurpose.purchase => propertyValue - downPayment,
    LoanPurpose.refinance => currentBalance,
    LoanPurpose.cashOutRefinance => currentBalance + cashOut,
  };

  /// Loan-to-value, in percent: with the credit score, the main driver of
  /// the rate and of mortgage insurance.
  double get loanToValue =>
      propertyValue == 0 ? 0 : loanAmount * 100 / propertyValue;

  /// Debts before the new mortgage, as a percent of gross monthly income.
  double get debtToIncome =>
      annualIncome == 0 ? 0 : monthlyDebts * 100 / (annualIncome / 12);

  Map<String, Object?> toJson() => {
    'loan': {
      'purpose': purpose.name,
      'program': program.name,
      'termYears': term.years,
      'rateType': rateType.name,
      'timeline': timeline.name,
      'amount': loanAmount,
    },
    'property': {
      'type': propertyType.name,
      'occupancy': occupancy.name,
      'found': propertyFound,
      'street': street,
      'city': city,
      'state': state,
      'zip': zip,
      'value': propertyValue,
      'downPayment': downPayment,
      'currentBalance': currentBalance,
      'cashOut': cashOut,
      'annualTaxes': annualTaxes,
      'annualInsurance': annualInsurance,
      'monthlyHoa': monthlyHoa,
    },
    'borrower': {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'hasCoBorrower': hasCoBorrower,
      'creditScore': creditScore.name,
      'employment': employment.name,
      'annualIncome': annualIncome,
      'monthlyDebts': monthlyDebts,
      'assets': assets,
      'firstTimeBuyer': firstTimeBuyer,
      'militaryService': militaryService,
    },
  };
}
