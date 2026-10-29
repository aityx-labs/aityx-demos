# Mortgage proposal request

The welcome page's **Request a mortgage proposal** button opens a form
([proposal_form_screen.dart](../mortgagehub_app/lib/proposal/proposal_form_screen.dart))
asking what a US lender needs to quote a loan: a rate, fees and a monthly
payment. A valid form opens a summary
([proposal_summary_screen.dart](../mortgagehub_app/lib/proposal/proposal_summary_screen.dart))
with the loan amount, loan-to-value (LTV) and current debt-to-income (DTI)
worked out from it, the [regulatory check](regulatory-check.md), then every
answer; **Done** goes back to the welcome page.
The request is a `ProposalRequest`
([proposal_request.dart](../mortgagehub_app/lib/proposal/proposal_request.dart)),
with `toJson()` in three groups: `loan`, `property`, `borrower`.

## What's asked, and why

The fields come from three sources: the Loan Estimate, which every lender
must give within three business days of an application (Regulation Z,
12 CFR 1026.37: the applicant, property, sale price or value, term,
purpose, product, loan type, loan amount, taxes, insurance and
assessments); the agencies' pricing factors (Fannie Mae's loan-level price
adjustments: credit score by LTV, then purpose, occupancy, property type
and units); and the payment and eligibility checks (DTI, the programs'
rules).

**The loan**

| Field | Required | Why |
|---|---|---|
| Purpose: buy, refinance (rate and term), cash-out refinance | yes | Loan Estimate *purpose*; cash-out is priced higher |
| Purchase price, or the home's estimated value | yes | Loan Estimate *sale price / estimated value*; LTV |
| Down payment (purchase) | yes, may be 0 | Loan amount and LTV; must be less than the price |
| Current mortgage balance (refinance) | yes | Loan amount; must be less than the value |
| Cash to take out (cash-out) | yes | Loan amount; balance plus cash out must be less than the value |
| Program: Conventional, FHA, VA, USDA, not sure | yes | Loan Estimate *loan type*; down payment, mortgage insurance, eligibility |
| Term: 30, 20, 15, 10 years | yes | Loan Estimate *loan term* |
| Rate type: fixed, adjustable, not sure | yes | Loan Estimate *product* |
| Timeline: within 30 days, 30–60, over 60, just comparing | yes | The rate lock period the quote needs |

The loan amount is worked out, not asked: price less down payment for a
purchase, the balance for a refinance, balance plus cash out for cash-out.

**The property**

| Field | Required | Why |
|---|---|---|
| Type: single-family, townhouse, condo, 2–4 units, manufactured | yes | Pricing (condos, 2–4 units and manufactured homes cost more) and eligibility |
| Use: primary residence, second home, investment | yes | Pricing; FHA, VA and USDA are for a primary residence only |
| Found the home (purchase) | yes | A buyer still looking gives only the location |
| Street and city | when the home is known | Loan Estimate *property address* |
| State and ZIP code (5 digits) | yes | Taxes, insurance, closing costs, loan limits, USDA areas |
| Annual property taxes, annual insurance, monthly HOA dues | optional | Loan Estimate *estimated taxes, insurance and assessments*; the lender estimates them from the location when left out |

**About you**

| Field | Required | Why |
|---|---|---|
| First and last name | yes | Loan Estimate *applicants* |
| Email, phone (10 digits) | yes | To send the proposal |
| Co-borrower | yes (switch) | Income and credit of two borrowers |
| Estimated credit score: 780+, then 20-point bands to 620, below 620, don't know | yes | The main pricing factor, with LTV; self-reported so no credit check is needed |
| Employment: W-2, self-employed, retired, other | yes | How income is documented later |
| Annual income before taxes (both borrowers when there's a co-borrower) | yes | DTI; Loan Estimate trigger item |
| Monthly debt payments (not rent, nor the mortgage being refinanced) | yes, may be 0 | DTI |
| Savings available to close | optional | Down payment and reserves |
| First-time homebuyer (purchase) | yes (switch) | Programs and fee waivers for first-time buyers |
| US military service, or surviving spouse | yes (switch) | VA eligibility |

The less common fields have an ⓘ tooltip (on hover, or tap) explaining
them: the loan purpose, program, rate type and timeline; the use of the
property; cash out, taxes, insurance, HOA dues and savings; the credit
score, employment, income and debts; and the co-borrower, first-time
buyer and military switches. Plain ones (name, email, phone, address,
ZIP, prices, term, property type) have none.

The program is checked against the rest: FHA, VA and USDA need a primary
residence, and VA needs military service. A consent to be contacted by
email or phone is required to submit.

## Fill random

The app bar's **Fill random** is a split button. Clicking it fills every
field with a random request that passes the form's checks, for demos and
testing. Its arrow opens a menu, **Processable**, **Requires review** and
**Not processable**, that fills a request built to get that verdict from
the [regulatory check](regulatory-check.md) (see
[Fill random for a verdict](#fill-random-for-a-verdict)). Plain random
requests come from
([random_proposal.dart](../mortgagehub_app/lib/proposal/random_proposal.dart)).
Names, streets, cities and ZIP codes come from the
[`faker`](https://pub.dev/packages/faker) package (the most used Dart
faker). Contact details are never real: emails at `example.com`
(reserved for examples, RFC 2606) and phones in the fictional
555-0100 to 555-0199 range. The amounts are realistic and consistent:
values from \$150,000 to \$1.5 million, down payments of 3 to 30%,
balances of 20 to 70% of the value, cash out of 5 to 15%, taxes and
insurance from the value. The optional fields are left empty at random:
taxes, insurance and savings half the time, HOA dues three times in four
for condos and townhouses and once in four for other homes. FHA, VA
and USDA come only with a primary residence, and VA always with military
service. It also ticks the consent, and clears the errors of an earlier
submit.

### Fill random for a verdict

[targeted_proposal.dart](../mortgagehub_app/lib/proposal/targeted_proposal.dart)
starts from a request that passes every check with room to spare (a
known credit score from 640 up, no USDA, loans under FHA's $541,287 floor
and under the $832,750 baseline wherever the baseline applies, an LTV
under each program's maximum, a DTI of 20 to 36%), then, for a verdict
other than Processable, adds one reason picked at random. VA is the one
exception to the baseline: it has no loan limit with full entitlement, so
a processable VA draft can run above $832,750.

- **Requires review:** no credit score; a score below 620; a high-balance
  conventional loan ($850,000 to $1.2 million, outside AK, HI, GU and
  VI); USDA; a conventional DTI of 46.5 to 49%; a VA cash-out at 92 to
  98%.
- **Not processable:** a conventional primary purchase at 98 to 99.5%
  LTV; an investment purchase at 88 to 95%; a conventional DTI of 56 to
  75%; an FHA loan above the $1,249,125 ceiling; a second home with 2-4
  units; a manufactured home as an investment; a USDA cash-out.

Every request still passes the form's own checks, so the failures are
ones only the regulatory check catches. The income is worked out for the
DTI with the API's default rate (6.5%). The generator aims; aityx gives
the verdict. Checked live: 270 of 270 requests (90 per verdict, two seed
sets) got their verdict; `flutter test --run-skipped --tags aityx` reruns
it against the running API.

## What's not asked, and why

- **No Social Security number, no credit check.** Under Regulation Z
  (12 CFR 1026.2(a)(3)(ii)), a lender that has a consumer's name, income,
  Social Security number (to get a credit report), property address,
  estimated property value and loan amount sought has an *application*:
  it then owes a Loan Estimate within three business days. Leaving out the
  SSN keeps this a request for a quote, priced on the self-reported credit
  score, until the lender and borrower choose to make it an application.
  It also keeps the app from holding SSNs.
- **Nothing Regulation B (Equal Credit Opportunity Act) forbids asking**
  (12 CFR 1002.5): no race, color, religion, national origin or sex; no
  marital status; no plans to have children. The income field's help
  text says alimony, child support or separate maintenance income need not
  be included unless the borrower wants it considered, as Regulation B
  requires before asking about income. The demographic questions a full
  mortgage application asks for government monitoring (1002.13, HMDA) are
  for the application, not this request.
- No date of birth, employer or bank details: those come with the
  application and its documents.

## Known limitations

- The request isn't saved anywhere: it's sent only to the regulatory
  check, and lost on leaving the summary.
- No rates or prices: the app doesn't quote, it collects the request.
- Amounts are whole US dollars without thousands separators while typing.
- No ARM product choice (5/6, 7/6, 10/6), discount points or rate lock
  length; the timeline stands in for the lock.
- English only.
