# Order policy

When a request is about an order, the [routing](routing.md) also says
what the store's policy offers for it (a refund, store credit, a
replacement, a warranty repair, a price adjustment...), how much, by
when and why, decided from the order's dates and amounts by the same
aityx call.

## The facts

aityx's questions classify; they don't read numbers or dates. So the
facts come from where a store keeps them:

- **The order book** ([lib/aityx/orders.dart](../contacthub_app/lib/aityx/orders.dart)):
  the app finds the first order number in the message (three digits, a
  dash, four: `113-2045`) and sends that order as `state.order`: its
  `placed_on` and `delivered_on` dates (expected 5 days after it was placed
  until it's delivered), `amount` paid and `current_price`, `category`
  (`standard`, `final_sale`, `electronics`), `status` (`processing`,
  `shipped`, `delivered`) and `charges`, with its `number` and `item`. A
  message naming no order on file gets status `none`. The orders are made
  up, and their dates count back from today, so a sample routes the same
  way whenever the demo runs.
- **Today** (`state.today`), from the device's clock (UTC).
- **What the customer wants** (`request_kind`), a choice question for
  aityx: `where_is_order`, `return_refund`, `damaged_defective`,
  `cancel_order`, `price_adjustment`, `duplicate_charge`, or `none` when
  the message isn't about an order.

## The rules

In [assets/models/routing.json](../contacthub_app/assets/models/routing.json), each
limit a decision of its own so it shows in the JSON:

| Limit | Value |
|---|---|
| Refund window, from delivery | 30 days |
| Store-credit window, from delivery | 60 days |
| Damage reported, from delivery | 7 days |
| Electronics warranty, from delivery | 365 days |
| Price drop refunded, from ordering | 14 days |
| An undelivered order is late after | 10 days from ordering |
| A person approves refunds above | $500 |
| Restocking fee on electronics returned after 14 days | 15% |
| Refunds and credits are paid within | 5 days |

`days_since_order` and `days_since_delivery` (-1 until delivered) are
today minus the dates; the windows are booleans on them. The
**resolution** table, first match wins:

1. Not about an order → `none`.
2. No order on file → `ask_for_order`.
3. Cancel, still processing → `cancel_and_refund`; already shipped →
   `return_after_delivery`.
4. Where is it, late → `investigate_late` (and high priority); else →
   `share_tracking`.
5. Charged twice → `refund_duplicate`; once → `manual_review`.
6. Price drop within 14 days of ordering, cheaper now → `price_adjustment`;
   else → `not_eligible`.
7. Damaged within 7 days → `replace_or_refund`; electronics within the
   warranty → `warranty_repair`.
8. A return (or damage after those) before delivery →
   `return_after_delivery`; final sale → `not_eligible`; above $500 within
   60 days → `manual_review` (and a review); within 30 days → `refund`;
   within 60 → `store_credit`; later → `not_eligible`.

**refund_amount**: the full amount for a cancellation, a replacement or
refund, store credit and a duplicate charge; the difference for a price
drop; for a refund, the amount less 15% on electronics after 14 days;
otherwise 0. **refund_by** is today plus 5 days.

## On the routing screen

**The store's policy**, under **Routed to**, when a policy applies: the
resolution (green when the customer gets something, amber for a step to
take, red for a no), the amount and the date it's paid by, the reason for
the amount and for the resolution (the `# why` of each table's row that
fired), and the order's facts: number and item, ordered and delivered (or
expected) with how many days ago, what was paid and today's price, the
charges, the category. Its links go to the resolution's answer, the
policy rule and the amount rule that fired, the limits, the order and
today in the request, and the days since delivery and the request kind
in the response.

## The samples

**Try a sample**'s first section, one for each outcome, each naming an
order in the book: on schedule (phone case, 2 days), late (desk lamp, 12
days, not delivered), return within 30 days (running shoes, $89.99),
after 45 days (winter jacket, $240 store credit), after 3 months (coffee
maker, not eligible), final sale (cushion set), damaged (blender, 2 days,
$79.99), broken after 5 months (headphones, warranty), over $500 (laptop,
$1,299, a person approves it), electronics after 14 days (tablet, $329 →
$279.65), cancel before it ships (bookshelf, $189), a price drop (TV,
$499 → $449, $50 back), a double charge (air fryer, $64.50), and no order
number (ask for it).

### Verified

All 14, the 11 other department samples and the 2 check samples were sent
through the live API (before the app called aityx itself; the request
it sends is the same): each got the expected department and resolution,
amount and date. (The headphones first went to General Inquiries, torn
between Customer Service and Technical Support; the topics now say a
broken item bought here is a warranty claim, Customer Service's, and
three runs routed it there.) Tests use real aityx answers for the tablet,
the jacket and the late lamp.

`bash scripts/model-test.sh` runs the rules themselves on aityx
([test/model_scenarios_test.dart](../contacthub_app/test/model_scenarios_test.dart),
tagged `aityx`, skipped by a plain `flutter test`; it runs
`flutter test --run-skipped --tags aityx` in `contacthub_app/` with the
key from the environment or the repository's `.env`): 21 cases with fixed facts
just inside and just outside each limit (refund at 30 days, store credit
at 31 and 60, not eligible at 61; no restocking fee at 14 days, 15% at
15; $500.00 refunded, $500.01 to a person; damage at 7 and 8 days; the
warranty at 365 and 366; price drops at 14 and 15; late at 11 days, not
at 10; cancellations; duplicate charges). The questions' answers are given
in the state, so only the rules run and every run is the same. Changing
the refund window to 29 days fails the 30-day case.

## Known limitations

- The order book is a fixed demo list; there's no customer account.
- One order per request: the first number in the message.
- Business days, holidays and time zones are ignored: days are calendar
  days in UTC.
