import 'dart:math';

/// A card's suit, in the order of its letter: c, d, h, s.
enum Suit {
  clubs('c', '♣'),
  diamonds('d', '♦'),
  hearts('h', '♥'),
  spades('s', '♠');

  const Suit(this.letter, this.symbol);

  final String letter;
  final String symbol;

  /// Red suits are diamonds and hearts.
  bool get red => this == diamonds || this == hearts;
}

/// A playing card: a rank from 2 to 14 (the ace) and a suit.
class Card implements Comparable<Card> {
  const Card(this.rank, this.suit)
    : assert(rank >= 2 && rank <= 14, 'rank must be 2 to 14');

  /// A card from its two-character label, rank then suit: `Ah`, `Td`.
  factory Card.parse(String label) {
    if (label.length != 2) throw FormatException('not a card: $label');
    final rank = _ranks.indexOf(label[0]) + 2;
    if (rank < 2) throw FormatException('not a rank: ${label[0]}');
    final suit = Suit.values.where((s) => s.letter == label[1]).firstOrNull;
    if (suit == null) throw FormatException('not a suit: ${label[1]}');
    return Card(rank, suit);
  }

  static const _ranks = '23456789TJQKA';

  final int rank;
  final Suit suit;

  /// `A`, `K`, `Q`, `J`, `T` or the digit.
  String get rankLabel => _ranks[rank - 2];

  /// `Ah`, `Td`: the label the strategies and the API use.
  String get label => '$rankLabel${suit.letter}';

  /// `A♥`, `T♦`: the label the table shows.
  String get display => '$rankLabel${suit.symbol}';

  @override
  int compareTo(Card other) =>
      rank != other.rank ? rank - other.rank : suit.index - other.suit.index;

  @override
  bool operator ==(Object other) =>
      other is Card && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => rank * 4 + suit.index;

  @override
  String toString() => label;
}

/// All 52 cards, 2♣ to A♠.
final List<Card> fullDeck = List.unmodifiable([
  for (final suit in Suit.values)
    for (var rank = 2; rank <= 14; rank++) Card(rank, suit),
]);

/// A shuffled deck to draw from.
class Deck {
  Deck(Random random, {Iterable<Card>? without})
    : _cards = [
        for (final c in fullDeck)
          if (without == null || !without.contains(c)) c,
      ]..shuffle(random);

  final List<Card> _cards;

  int get remaining => _cards.length;

  Card draw() => _cards.removeLast();

  List<Card> drawMany(int n) => [for (var i = 0; i < n; i++) draw()];
}
