/// The demo's order book: a few made-up orders, the ones the sample
/// requests name. Their dates count back from today, so a sample routes
/// the same way whenever the demo runs (the jacket was always delivered 45
/// days ago).
library;

/// One order on file.
class Order {
  const Order({
    required this.item,
    required this.placedDaysAgo,
    this.deliveredDaysAgo,
    required this.amount,
    double? currentPrice,
    this.category = 'standard',
    this.status = 'delivered',
    this.charges = 1,
  }) : currentPrice = currentPrice ?? amount;

  final String item;
  final int placedDaysAgo;

  /// Null until it's delivered; it's then expected 5 days after it was
  /// placed.
  final int? deliveredDaysAgo;

  /// What was paid, and what it costs today, in USD.
  final double amount;
  final double currentPrice;

  /// `standard`, `final_sale` or `electronics`.
  final String category;

  /// `processing`, `shipped` or `delivered`.
  final String status;

  /// How many times it was charged.
  final int charges;

  /// The order as the routing model's state has it, on [today].
  Map<String, Object?> toState(String number, DateTime today) {
    String date(int daysAgo) => _iso(today.subtract(Duration(days: daysAgo)));
    return {
      'number': number,
      'item': item,
      'placed_on': date(placedDaysAgo),
      'delivered_on': date(deliveredDaysAgo ?? placedDaysAgo - 5),
      'amount': amount,
      'current_price': currentPrice,
      'category': category,
      'status': status,
      'charges': charges,
    };
  }
}

const orders = <String, Order>{
  '112-8834': Order(
    item: 'Desk lamp',
    placedDaysAgo: 12,
    amount: 45,
    status: 'shipped',
  ),
  '121-0408': Order(
    item: 'Phone case',
    placedDaysAgo: 2,
    amount: 19.99,
    status: 'shipped',
  ),
  '113-2045': Order(
    item: 'Running shoes',
    placedDaysAgo: 14,
    deliveredDaysAgo: 9,
    amount: 89.99,
  ),
  '114-7781': Order(
    item: 'Winter jacket',
    placedDaysAgo: 50,
    deliveredDaysAgo: 45,
    amount: 240,
  ),
  '115-0032': Order(
    item: 'Coffee maker',
    placedDaysAgo: 95,
    deliveredDaysAgo: 90,
    amount: 129,
  ),
  '116-4410': Order(
    item: 'Clearance cushion set',
    placedDaysAgo: 8,
    deliveredDaysAgo: 5,
    amount: 59,
    category: 'final_sale',
  ),
  '113-5567': Order(
    item: 'Blender',
    placedDaysAgo: 6,
    deliveredDaysAgo: 2,
    amount: 79.99,
  ),
  '111-9020': Order(
    item: 'Noise-cancelling headphones',
    placedDaysAgo: 155,
    deliveredDaysAgo: 150,
    amount: 349,
    category: 'electronics',
  ),
  '117-3310': Order(
    item: 'Laptop',
    placedDaysAgo: 14,
    deliveredDaysAgo: 10,
    amount: 1299,
    category: 'electronics',
  ),
  '120-5150': Order(
    item: 'Tablet',
    placedDaysAgo: 25,
    deliveredDaysAgo: 20,
    amount: 329,
    category: 'electronics',
  ),
  '118-6621': Order(
    item: 'Bookshelf',
    placedDaysAgo: 0,
    amount: 189,
    status: 'processing',
  ),
  '119-2277': Order(
    item: '55-inch TV',
    placedDaysAgo: 6,
    deliveredDaysAgo: 3,
    amount: 499,
    currentPrice: 449,
    category: 'electronics',
  ),
  '112-4432': Order(
    item: 'Air fryer',
    placedDaysAgo: 7,
    deliveredDaysAgo: 4,
    amount: 64.5,
    charges: 2,
  ),
};

/// An order number as the store prints them: three digits, a dash, four.
final _orderNumber = RegExp(r'\b(\d{3}-\d{4})\b');

/// The first order number in [message], whether or not it's on file.
String? orderNumberIn(String message) =>
    _orderNumber.firstMatch(message)?.group(1);

/// The routing model's `order` for [message] on [today]: the order it
/// names, or one with status `none` (and today's dates, zero amounts) when
/// it names none on file.
Map<String, Object?> orderState(String message, DateTime today) {
  final number = orderNumberIn(message);
  final order = number == null ? null : orders[number];
  if (order != null) return order.toState(number!, today);
  return {
    'number': number,
    'item': null,
    'placed_on': _iso(today),
    'delivered_on': _iso(today),
    'amount': 0,
    'current_price': 0,
    'category': 'standard',
    'status': 'none',
    'charges': 0,
  };
}

/// [day] as `YYYY-MM-DD`.
String isoDate(DateTime day) => _iso(day);

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
