/// A ready-made request to try: one for each department, one for each of
/// the store's order policies (they name orders in the API's order book,
/// lib/orders.dart, with dates counted back from today), and a few that
/// exercise the checks.
class SampleRequest {
  const SampleRequest(this.department, this.title, this.text, {this.outcome});

  /// Where it should be routed, as people read it.
  final String department;
  final String title;
  final String text;

  /// What the policy should offer, for the order samples.
  final String? outcome;

  /// The line under the title in the menu.
  String get subtitle =>
      outcome == null ? department : '$department · $outcome';
}

const _lateLamp = SampleRequest(
  'Customer Service',
  'Where is my package?',
  'Where is my desk lamp? I ordered it 12 days ago (order 112-8834) for '
      "\$45, and the tracking hasn't moved since last week.",
  outcome: 'late: carrier investigation',
);

const _doubleCharge = SampleRequest(
  'Billing & Payments',
  'Charged twice',
  'I was charged twice for order 112-4432, the \$64.50 air fryer. Please '
      'refund one of the charges.',
  outcome: r'refund the duplicate $64.50',
);

const departmentSamples = [
  _lateLamp,
  _doubleCharge,
  SampleRequest(
    'Marketing',
    'A question about a product',
    'Does the Aurora 55-inch TV (\$449 this week) support HDMI 2.1, and '
        'does it come with a wall mount?',
  ),
  SampleRequest(
    'Technical Support',
    "Can't sign in",
    'Since yesterday at 9 pm the app says my password is wrong, even right '
        "after I reset it, three times now. I can't sign in.",
  ),
  SampleRequest(
    'Trust & Safety',
    'A phishing email',
    "I got an email that looks like it's from you, asking me to confirm my "
        'card details within 24 hours on a strange website. Is it a scam?',
  ),
  SampleRequest(
    'Human Resources',
    'A job application',
    "I'd like to apply for the warehouse supervisor position in Dallas "
        '(posting 4471, closing November 15). Where should I send my CV?',
  ),
  SampleRequest(
    'Seller Services',
    'Selling on the marketplace',
    'I make handmade candles, about 300 a month, and want to start selling '
        'them on your marketplace. What are the seller fees?',
  ),
  SampleRequest(
    'Procurement & Vendors',
    'Becoming a supplier',
    "We're a furniture manufacturer with 12 years of export experience and "
        'would like to supply your home section wholesale. Who handles new '
        'vendors?',
  ),
  SampleRequest(
    'Business Sales',
    'A bulk order',
    'Our company needs 200 laptops for new employees starting January 5. '
        'Can we get a business quote, paid by invoice on 30-day terms?',
  ),
  SampleRequest(
    'Legal & Privacy',
    'Delete my data',
    'Under the GDPR, please delete all the personal data you hold about me '
        'and confirm in writing within 30 days.',
  ),
  SampleRequest(
    'Public Relations',
    'A press request',
    "I'm a reporter at the Daily Ledger writing about holiday delivery "
        'delays. Could someone give us a comment by Friday at noon?',
  ),
  SampleRequest(
    'Investor Relations',
    'A shareholder question',
    'I hold 1,200 shares. When is the Q4 earnings call, and where can I '
        "find last year's annual report?",
  ),
  SampleRequest(
    'General Inquiries',
    'Too vague to tell',
    'hello? anyone there',
  ),
];

/// One for each of the store's order policies: what it offers depends on
/// the dates, amounts and category on file.
const policySamples = [
  SampleRequest(
    'Customer Service',
    'On its way',
    'Just checking on order 121-0408, the phone case I ordered two days '
        'ago. When will it arrive?',
    outcome: 'on schedule: share tracking',
  ),
  _lateLamp,
  SampleRequest(
    'Customer Service',
    'Return within 30 days',
    "I'd like to return the running shoes from order 113-2045. They "
        'arrived 9 days ago and are a size too small.',
    outcome: r'refund $89.99',
  ),
  SampleRequest(
    'Customer Service',
    'Return after 45 days',
    'Can I still return the winter jacket from order 114-7781? It was '
        'delivered about six weeks ago and I never wore it.',
    outcome: r'store credit $240',
  ),
  SampleRequest(
    'Customer Service',
    'Return after 3 months',
    'I want my money back for the coffee maker in order 115-0032. I bought '
        "it three months ago and I don't use it.",
    outcome: 'not eligible: past 60 days',
  ),
  SampleRequest(
    'Customer Service',
    'A final-sale item',
    'I changed my mind about the cushion set from order 116-4410. Can I '
        r'return it for a refund of the $59?',
    outcome: 'not eligible: final sale',
  ),
  SampleRequest(
    'Customer Service',
    'Arrived damaged',
    'My blender from order 113-5567 arrived cracked two days ago. I want a '
        'replacement or my money back.',
    outcome: r'replace or refund $79.99',
  ),
  SampleRequest(
    'Customer Service',
    'Broken after 5 months',
    'My noise-cancelling headphones from order 111-9020 stopped charging. I '
        r'bought them about five months ago for $349.',
    outcome: 'warranty repair',
  ),
  SampleRequest(
    'Customer Service',
    'A refund over \$500',
    r'Please refund the laptop from order 117-3310 ($1,299). It was '
        "delivered 10 days ago, but it's not what I expected.",
    outcome: 'a person approves it',
  ),
  SampleRequest(
    'Customer Service',
    'Electronics after 14 days',
    "I'd like to return the tablet from order 120-5150, delivered 20 days "
        "ago. It works fine, I just don't need it.",
    outcome: r'refund $279.65, less 15%',
  ),
  SampleRequest(
    'Customer Service',
    'Cancel before it ships',
    r'Please cancel order 118-6621, the $189 bookshelf I ordered this '
        'morning.',
    outcome: r'cancel and refund $189',
  ),
  SampleRequest(
    'Customer Service',
    'The price dropped',
    r'I bought the 55-inch TV in order 119-2277 six days ago for $499, and '
        r"now it's $449. Can I get the $50 difference back?",
    outcome: r'refund the $50 difference',
  ),
  _doubleCharge,
  SampleRequest(
    'Customer Service',
    'No order number',
    'I want to return something I bought last month, but I lost the order '
        'number.',
    outcome: 'ask for the order number',
  ),
];

const checkSamples = [
  SampleRequest(
    'Billing & Payments · high priority, reviewed',
    'A card number in the message',
    'I was charged twice for order 112-4432. My card is 4111 1111 1111 '
        '1111, please refund one of the charges.',
  ),
  SampleRequest(
    'Trust & Safety · whatever the topic',
    'An abusive message',
    "You people are useless. If my refund isn't here tomorrow I'll come to "
        'your office and make you regret it.',
  ),
];
