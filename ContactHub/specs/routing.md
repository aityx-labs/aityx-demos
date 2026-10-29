# Routing

**Send** opens the routing screen, which asks the API to route the
request and shows where it went, why, and the aityx call behind it.

## How a request is routed

One call to aityx's `POST /v1/systemone`, built by
[lib/routing.dart](../contacthub_api/lib/routing.dart) from
[models/routing.json](../contacthub_api/models/routing.json), with the
the message, today and the order it names as the state (see
[Order policy](order-policy.md)):

1. **Jev** (`model: "jev-latest"`) answers five questions about the
   message:
   - `topic`, a **choice** among the departments' topics, each defined in
     plain words in its `criteria`, plus `other`; the answer carries Jev's
     `confidence` and every topic's probability;
   - `request_kind`, a **choice** of what the customer wants done with
     their order (see [Order policy](order-policy.md));
   - `urgent_probability`, `sensitive_data_probability` and
     `abusive_probability`, yes/no questions (**noul**) answered as
     probabilities.
2. The **routing model** then decides, deterministically, from those
   answers (its inputs are Jev's answers by name, and the topic's
   confidence, bound with `from: "jev:/answers/topic/confidence"`):
   - `urgent`, `sensitive_data`, `abusive`: the probability is at least
     `evidence_threshold`, 0.8;
   - `clear_topic`: the confidence is at least `confidence_threshold`, 0.6,
     and the topic isn't `other`;
   - `department` (a FIRST table): abuse goes to Trust & Safety whatever
     the topic; an unclear topic to General Inquiries; otherwise one row
     per topic; General Inquiries last;
   - `priority` (`low<normal<high`): high for abuse, sensitive data,
     urgency, a late package, and Trust & Safety or Legal; low for Marketing, Public
     Relations and Investor Relations; normal otherwise;
   - `response_hours`: 4 for high, 24 for normal, 48 for low;
   - `needs_review`: the topic is unclear, the message holds sensitive
     data or abuse, or the policy needs a person to approve it;
   - the store's policy for the order: see [Order policy](order-policy.md).

The API reads the department and priority from `answers`, the topic,
its confidence and the request kind as Jev answered them, and the reason
for each decision from the `# why` of the table row that fired, whose
number it finds in `receipt.decisions.<decision>.rule`.

## Departments

The usual departments of a large online store, each with a person (made
up, with `@contacthub.example` addresses) in the API's directory:

| Department | Handles | Person |
|---|---|---|
| Customer Service | Orders, delivery, returns, refunds, cancellations | Maria Lopez, Customer Service Lead |
| Billing & Payments | Charges, payment methods, invoices, gift cards, memberships | David Chen, Billing Operations Manager |
| Marketing | Products before buying, prices, promotions, reviews | Aisha Patel, Product Marketing Manager |
| Technical Support | The website, the app, sign-in, devices, digital services | Lukas Schmidt, Technical Support Lead |
| Trust & Safety | Fraud, scams, hacked accounts, counterfeits, abuse | Grace Okafor, Trust & Safety Investigator |
| Human Resources | Job applications, careers, employment verification | Sofia Rossi, Talent Acquisition Partner |
| Seller Services | Selling on the marketplace | Kenji Tanaka, Seller Success Manager |
| Procurement & Vendors | Suppliers who sell to the company | Olivia Brown, Vendor Relations Manager |
| Business Sales | Bulk and corporate purchases | Rafael Silva, Business Accounts Executive |
| Legal & Privacy | Legal notices, IP claims, privacy requests | Hannah Weiss, Privacy Counsel |
| Public Relations | Journalists and media | Tom Becker, Media Relations Manager |
| Investor Relations | Shareholders, results, reports | Priya Nair, Investor Relations Director |
| General Inquiries | Anything unclear, or that fits no department | Sam Taylor, Front Desk Coordinator |

## The routing screen

[RoutingScreen](../contacthub_app/lib/routing/routing_screen.dart), titled
**Request routed**, at most 1100 px wide:

- the message, with a link to it in the request;
- **The store's policy**, for a request about an order (see
  [Order policy](order-policy.md));
- a spinner, "Jev is reading your request, and aityx is routing it…",
  then the result, or the error with **Try again**;
- **Routed to**: the department, its person, role and email, and the
  reason;
- **Priority** (the level and hours, colored by level) and **Review**
  (whether a person checks it first), side by side, stacked on a phone;
- **Checks on the message**: urgent, sensitive data, abuse and an unclear
  topic, each with Jev's probability as a bar, flagged in amber;
- **aityx's reading of the message**: the top topics' probabilities, and
  what the customer wants done with their order, in words;
- **The aityx call**, below.

Every item has links (with ↗ for the request, ↙ for the response) to
**exactly** the JSON behind it: the department's answer, the department
table's row that fired (`decision.decisions.department.table.<rule>`),
its receipt entry and the whole table; the priority's answer and row;
each check's question, answer, rule and verdict; the topic's answer,
question and confidence input; the request kind's answer and question;
the message.

## The aityx call

[CallView](../contacthub_app/lib/routing/call_view.dart): one pane, as
in Mortgage Hub, with the key parts highlighted and labeled:

- **One pane**: under a **REQUEST** header, the whole body sent to
  `POST /v1/systemone`; under a **RESPONSE** header, a digest of aityx's
  answer ([decisionDigest](../contacthub_app/lib/routing/routing_screen.dart)):
  what Jev read (the topic, the request kind, the three probabilities),
  then the answers that decide the route (the checks, the department, the
  days, the resolution, the amount and date, the priority, the hours, the
  review), each without its probability map (a dozen zeros and a one);
  the receipt of the department, resolution, amount, priority and hours
  tables, with the rule that fired in each; and the provenance of every
  input (`jev` or `state`). Line numbers restart in each section. **Copy
  request** and **Copy full response** copy the whole of each; **Copy
  section** the marked part.
- **Key parts highlighted**: every part listed in `callTargets` (the
  model, the questions, the inputs, the thresholds, the tables and the
  rows that fired, the policy limits, the facts, the order, today, the
  message; in the response, what was read, the decision, the resolution,
  the priority, the rule that fired and the provenance) is tinted with
  its label on its first row, the innermost winning where they nest; a
  part over 12 rows is tinted on its first row only. A label's tooltip
  says why it matters.
- **Readable JSON**: 14 px Roboto Mono (bundled, see
  [assets/fonts](../contacthub_app/assets/fonts/README.md)), 22 px rows,
  with colors for keys, strings, numbers and literals; short lists, such
  as a table's rows, stay on one line; **a long string, or one with line
  breaks, wraps** at 88 characters, at the last space, and at its line
  breaks, onto continuation rows, unnumbered and shown as written (no
  `\n`, no escaped quotes), so a question's instructions, a topic's
  criteria or a rule's reason read as the prose they are
  ([json_layout.dart](../contacthub_app/lib/routing/json_layout.dart),
  `wrapString`, `JsonLine.continuation`). The copies are exact JSON. The
  pane is as high as its rows, up to 75% of the window (360 to 760 px).
  **Full screen** opens it in a dialog at the same place.
- **Exact navigation**: the layout records every value's first and last
  row on each side; since every row is the same height, a jump scrolls the
  value's first row to the top (one row of context above it), with room
  below the last row so the end reaches the top too. The value is marked
  strongly, and a panel above the pane says what it is, its side and path,
  and why it matters.
- **Jump to**: the request's key parts, then the response's, as chips. The
  result's links use the same mechanism; links to parts of the response
  the pane doesn't show are left out.

The API includes the call only if aityx's answer doesn't contain the key.

### Verified

Against the live API (`api.aityx.ai`): in Chrome, the links and chips
landed on exactly their values (a question's wrapped instructions,
department rule 3, the topic read and the provenance in the response),
and full screen opened at the marked value. Widget tests check the
scroll offset of a jump to the pixel, on both sides, that a question
wraps onto unnumbered rows, and that the screen fits a 390 px phone.
`dart run tool/route_samples.dart` in `contacthub_app/` routes every
sample through a running API and says where each went against its label
(see [Request box](request.md#samples)).

## Known limitations

- Jev's answers can vary between calls; the rules don't.
- The people are made up; nothing is sent to them.
- English only.
