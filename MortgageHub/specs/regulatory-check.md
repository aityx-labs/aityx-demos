# Regulatory check

The proposal summary's **Regulatory check** section says whether a lender
can process the proposal under current US mortgage rules: **Processable**,
**Requires review** or **Not processable**, with the loan-to-value against the
program's maximum, the estimated monthly payment, the debt-to-income ratio
with that payment, and each check with its result (pass, review, fail) and
reason. The verdict comes from [aityx.ai](aityx.md), which executes the
rules as a decision model.

```
app (summary, in the browser)  ──POST <url>/v1/systemone {decision, state}──▶  aityx.ai
  AityxProposalChecker          Authorization: Bearer <the user's key>
                               ◀── answers, receipt, usage ─────────────────
or, with no key of the user's:  ──POST /aityx/v1/systemone──▶  index server  ──▶  aityx.ai
                                                               (adds the dev key from .env)
```

- **The app** ([proposal_check.dart](../mortgagehub_app/lib/proposal/proposal_check.dart),
  `AityxProposalChecker`) runs the check itself, on the shared
  [aityx_web](../../packages/aityx_web) package's `AityxClient`: the
  user's key from the index page, else the index server's dev key through
  its proxy (see [aityx.ai integration](aityx.md)). It maps the request to
  the model's inputs ([lib/aityx/proposal_model.dart](../mortgagehub_app/lib/aityx/proposal_model.dart)),
  without the borrower's name, email or phone, posts them with the model
  to aityx's System One (deterministic, about 6,000 input tokens a check,
  90 s at most), maps the answers to the status, the figures and the five
  checks, and shows a spinner, then the result, or the error with **Try
  again**. The errors: *aityx is not set up: set your key on the index
  page* (no key: nothing is sent), *aityx rejected the key* (401, 403),
  *aityx did not answer* (the network, CORS or the timeout), *aityx
  answered HTTP n* with aityx's `detail` (any other status), *unexpected
  answer from aityx* (no answers, or a `decision_error`), *the rules
  (the aityx model) didn't load* (the asset failed to load; **Try again**
  loads it again), and the
  request's own validation (*value must be a number*, ...), as the API
  worded them. Under the result, **Show aityx
  request and response** reveals, pretty-printed and selectable, aityx's
  answer (answers, receipt, usage) first, since it holds the verdict, then
  the exact body the app sent to aityx (the model and its inputs; the key
  is a header, not shown), so it's visible that the verdict and every
  reason come from aityx; the button then reads **Hide aityx request and
  response**. Without them (left out if aityx's answer ever contained the
  user's key), there's no button. A
  faint rule (the theme's outline variant at 60%) separates the response
  block from the request block. While
  they're shown, the regulatory check widens from the summary's 640 px to
  1100 px, so the JSON has room; the rest of the summary stays at 640 px.
  Each block
  ([aityx_json_view.dart](../mortgagehub_app/lib/proposal/aityx_json_view.dart))
  is a code pane 55% of the window high (320 to 640 px), one numbered line
  per row in Roboto Mono (bundled, see
  [assets/fonts](../mortgagehub_app/assets/fonts/README.md): Flutter on the
  web has no monospace font of its own), 14 px on fixed 22 px rows (both
  scaled with the user's text size), the
  numbers counting from 1 in each block, scrolling sideways for long
  lines. The parts that matter are highlighted: a tinted band with an
  edge in the theme's primary and a short label at the end of the value's
  first line (for example *The verdict*, *Cited rules*, *Provenance*),
  whose tooltip says why it matters. In the request: the model (the rules travel
  with every call), each table's header (its `# why` column cites the
  rule), the verdict rule, the facts and the inputs that pick the rules
  or give the figures. In the response: the answers, the verdict, each
  check with its reason, the figures shown, the receipt (computed values,
  provenance), the token usage and any `decision_error`. When the
  verdict is Not processable, the places aityx asserts it are
  highlighted in light red (the theme's error color lightened by a
  third, a stronger tint, an error icon on their chips and labels), each with its own tooltip: *Not processable* on
  `answers.status.choice`, *Failed check* on every check whose value has
  `"result": "fail"`, and *Verdict computed* on
  `receipt.decisions.status.value`. These notes apply only to those
  values; other verdicts and passing checks keep the usual highlight. A value printed
  on 15 lines or fewer is tinted whole, a longer one only on its first
  line; where highlights nest, the innermost wins.
- **Exact navigation.** Above each block, a **Jump to** chip per label
  goes to its first match; a label in the code goes to its own value (so
  the second *Cited rules* goes to the second table, not the first). A
  jump scrolls the page so the whole block (title, chips, explanation and
  code) is in view, and, since every row is the same height, scrolls the
  code so the value's first line is at the top with one line of context
  above it; there's room below the last line, so a value near the end
  reaches the top too. The whole value is marked strongly, its line
  numbers in the label's color, its chip selected, and a panel above the
  code says what it is: the label, the value's path (for example
  `answers.ltv_check.value`) and why it matters. A copy button copies the
  whole JSON. The text is still selectable (the line numbers and labels
  aren't) and printed
  exactly as `JsonEncoder.withIndent('  ')` prints it.
- The check's HTTP client is closed when the summary closes. aityx allows
  CORS from any origin, so the browser calls it directly; in dev mode the
  call goes to the index server, on the app's own origin.
- **The model** ([assets/models/proposal-check.json](../mortgagehub_app/assets/models/proposal-check.json))
  is a native aityx model: inputs, then decision tables (FIRST hit, a
  `# why` on every row citing the rule) and expressions. It's an asset of
  the app (loaded with `rootBundle` once per checker) and sent with each
  call, since aityx stores no models.

## The rules (as of October 2026)

**Figures.** Loan amount: price less down payment, the balance, or the
balance plus cash out. LTV = loan ÷ value. Payment: principal and interest
at an assumed 6.5% (`assumedRate` in `lib/aityx/proposal_model.dart`) over the term, plus taxes (1.0% of the
value a year when not given), insurance (0.35% a year when not given) and
HOA dues; mortgage insurance isn't included. DTI = (payment + monthly
debts) ÷ monthly gross income. The rules compare LTV and DTI unrounded
(97.0002% is above 97%); the app rounds them to two decimals for display.

**Program eligibility.** FHA, VA and USDA only for a primary residence
(HUD Handbook 4000.1; 38 U.S.C. 3704(c); 7 CFR 3555). VA needs military
service. USDA: no cash-out, no 2-4 units, refinances only of USDA loans
(review), and always a review of the rural area and the county income limit
(115% of the median). Conventional: second homes 1 unit only; manufactured
homes not as investments. "Not sure" is checked as conventional.

**Maximum LTV.** Conventional from Fannie Mae's Eligibility Matrix (August
5, 2026, Desktop Underwriter):

| | Purchase / rate-and-term | Cash-out |
|---|---|---|
| Primary, 1 unit | 97% fixed (above 95% a purchase needs a first-time buyer; a refinance needs Fannie Mae to own the loan: review), 95% ARM | 80% |
| Primary, 2-4 units | 95% | 75% |
| Primary, manufactured | 97% fixed, 95% ARM | 65% |
| Second home, 1 unit | 90% | 75% |
| Investment, 1 unit | 85% purchase, 75% refinance | 75% |
| Investment, 2-4 units | 75% | 70% |

FHA: 96.5% purchase (below 620 and above 90%: review, since 500-579 needs
10% down), 97.75% rate-and-term, 80% cash-out. VA: 100% (cash-out above
90%: review, the usual lender cap). USDA: 100%. Above 80%, conventional
loans need private mortgage insurance; FHA loans always carry MIP.

**Loan limits (2026).** Conventional: above the FHFA baseline of $832,750
(AK, HI, GU, VI: $1,249,125) is high-balance, depending on the county:
review; above the ceiling of $1,249,125 (AK, HI, GU, VI: $1,873,675) is a
jumbo loan: review. FHA: above the floor of $541,287 depends on the
county: review; above the ceiling of $1,249,125: fail (ML 2025-23). VA: no
limit with full entitlement. USDA: no loan limit.

**Credit score.** Unknown: review. Below 620: review for every program
(conventional: DU dropped its 620 minimum in November 2025, lenders
haven't; FHA: 580 / 500 tiers; VA: lender minimums of 580-620). USDA below
640: review (GUS automatic approval).

**Debt-to-income.** Conventional: above 50% fail (DU's maximum), above 45%
review. FHA: above 57% fail, above 43% review. VA: above 41% review
(residual income). USDA: above 41% review. Every lender also verifies the
ability to repay (Regulation Z, 12 CFR 1026.43).

**Status.** Any fail: Not processable; else any review: Requires review;
else Processable.

## Verified

- **Tests of the rules:** [model_scenarios_test.dart](../mortgagehub_app/test/model_scenarios_test.dart)
  runs the model on aityx with expected verdicts, at and just past each
  boundary (97% and 95% LTV, 70% investment cash-out, FHA below 620, the
  $832,750 baseline, the FHA ceiling, 50% DTI) and each program's
  eligibility. It calls aityx, so `flutter test` skips it (tag `aityx`);
  run `bash scripts/model-test.sh` after changing the model (the key from
  the repository's `.env`).
- **Tests of the app's side:** [proposal_model_test.dart](../mortgagehub_app/test/proposal_model_test.dart)
  (the mapping to the inputs and from the answers, the API's tests as
  they were) and [regulatory_check_test.dart](../mortgagehub_app/test/regulatory_check_test.dart)
  (`AityxProposalChecker` against a mock aityx: what it sends, with the
  key only in the header, the dev proxy at the origin's root with no
  Authorization header, what it shows, and each error's wording).
- 17 scenarios against aityx (each program's eligibility, the LTV
  maximums, the limits, credit and DTI) gave the expected results; the
  payment matched a hand calculation ($400,000 at 6.5% over 30 years:
  $2,528.27).
- The app's checker against aityx, with Fill random requests
  ([targeted_proposal_live_test.dart](../mortgagehub_app/test/targeted_proposal_live_test.dart),
  `bash scripts/model-test.sh test/targeted_proposal_live_test.dart`):
  every status came back, with the right failing checks.
- 2026-10-30, after the move into the browser: the base case of the
  model scenarios passed on production aityx through `scripts/model-test.sh`.

## Known limitations

- Self-reported answers only: no credit report, documents or appraisal.
  It's not a credit decision or a Loan Estimate.
- County-level limits (FHFA, FHA, USDA income) aren't looked up: amounts
  between the floor and the ceiling are reviews.
- 2-4 unit loan limits and Freddie Mac's rules aren't modeled; FHA and VA
  rules use the common thresholds, not each lender's overlays.
- The payment uses one assumed rate, not a priced rate.
- The rules are dated (2026 limits, the August 2026 matrix) and need
  updating when they change.
