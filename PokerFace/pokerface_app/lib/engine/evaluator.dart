import 'dart:math';

import 'cards.dart';

/// The categories of a poker hand, weakest first; [id] is the name the
/// strategies' rules use.
enum HandCategory {
  highCard('high_card', 'High card'),
  pair('pair', 'Pair'),
  twoPair('two_pair', 'Two pair'),
  threeOfAKind('three_of_a_kind', 'Three of a kind'),
  straight('straight', 'Straight'),
  flush('flush', 'Flush'),
  fullHouse('full_house', 'Full house'),
  fourOfAKind('four_of_a_kind', 'Four of a kind'),
  straightFlush('straight_flush', 'Straight flush');

  const HandCategory(this.id, this.label);

  final String id;
  final String label;
}

/// The value of a five-card hand: its category, then its ranks in the
/// order that breaks ties (the trips before the pair of a full house, the
/// pair before the kickers, ...). [score] orders two values completely.
class HandValue implements Comparable<HandValue> {
  HandValue(this.category, this.ranks)
    : score = [
        ...ranks,
        for (var i = ranks.length; i < 5; i++) 0,
      ].fold(category.index, (s, r) => s * 16 + r);

  final HandCategory category;
  final List<int> ranks;
  final int score;

  @override
  int compareTo(HandValue other) => score.compareTo(other.score);

  /// The hand in words: "Two pair, kings and sevens".
  String describe() {
    String name(int r, {bool plural = false}) {
      const names = {
        14: 'ace',
        13: 'king',
        12: 'queen',
        11: 'jack',
        10: 'ten',
        9: 'nine',
        8: 'eight',
        7: 'seven',
        6: 'six',
        5: 'five',
        4: 'four',
        3: 'three',
        2: 'two',
      };
      final n = names[r]!;
      return plural ? (r == 6 ? 'sixes' : '${n}s') : n;
    }

    return switch (category) {
      HandCategory.highCard => 'High card, ${name(ranks[0])}',
      HandCategory.pair => 'Pair of ${name(ranks[0], plural: true)}',
      HandCategory.twoPair =>
        'Two pair, ${name(ranks[0], plural: true)} and '
            '${name(ranks[1], plural: true)}',
      HandCategory.threeOfAKind =>
        'Three of a kind, ${name(ranks[0], plural: true)}',
      HandCategory.straight => 'Straight to the ${name(ranks[0])}',
      HandCategory.flush => 'Flush, ${name(ranks[0])} high',
      HandCategory.fullHouse =>
        'Full house, ${name(ranks[0], plural: true)} over '
            '${name(ranks[1], plural: true)}',
      HandCategory.fourOfAKind =>
        'Four of a kind, ${name(ranks[0], plural: true)}',
      HandCategory.straightFlush =>
        ranks[0] == 14
            ? 'Royal flush'
            : 'Straight flush to the ${name(ranks[0])}',
    };
  }

  @override
  String toString() => '${category.id} $ranks';
}

/// The value of exactly five [cards].
HandValue evaluateFive(List<Card> cards) {
  assert(cards.length == 5);
  final ranks = cards.map((c) => c.rank).toList()..sort((a, b) => b - a);
  final flush = cards.every((c) => c.suit == cards[0].suit);
  final straightHigh = _straightHigh(ranks);
  if (flush && straightHigh != null) {
    return HandValue(HandCategory.straightFlush, [straightHigh]);
  }
  // Ranks grouped by how many times they appear, biggest groups first,
  // then higher ranks first.
  final counts = <int, int>{};
  for (final r in ranks) {
    counts[r] = (counts[r] ?? 0) + 1;
  }
  final groups = counts.entries.toList()
    ..sort((a, b) => b.value != a.value ? b.value - a.value : b.key - a.key);
  final ordered = [for (final g in groups) g.key];
  final shape = [for (final g in groups) g.value];
  if (shape[0] == 4) return HandValue(HandCategory.fourOfAKind, ordered);
  if (shape[0] == 3 && shape[1] == 2) {
    return HandValue(HandCategory.fullHouse, ordered);
  }
  if (flush) return HandValue(HandCategory.flush, ranks);
  if (straightHigh != null) {
    return HandValue(HandCategory.straight, [straightHigh]);
  }
  if (shape[0] == 3) return HandValue(HandCategory.threeOfAKind, ordered);
  if (shape[0] == 2 && shape[1] == 2) {
    return HandValue(HandCategory.twoPair, ordered);
  }
  if (shape[0] == 2) return HandValue(HandCategory.pair, ordered);
  return HandValue(HandCategory.highCard, ranks);
}

/// The high card of the straight in five distinct [ranks] sorted high to
/// low, the wheel (A 5 4 3 2) counting as a five-high straight; null if
/// they're no straight.
int? _straightHigh(List<int> ranks) {
  for (var i = 1; i < 5; i++) {
    if (ranks[i] != ranks[i - 1] - 1) {
      // A 5 4 3 2
      if (ranks[0] == 14 &&
          ranks[1] == 5 &&
          ranks[2] == 4 &&
          ranks[3] == 3 &&
          ranks[4] == 2) {
        return 5;
      }
      return null;
    }
  }
  return ranks[0];
}

/// The best five-card value in five, six or seven [cards].
HandValue evaluateBest(List<Card> cards) {
  assert(cards.length >= 5 && cards.length <= 7);
  if (cards.length == 5) return evaluateFive(cards);
  HandValue? best;
  final n = cards.length;
  final five = List<Card>.filled(5, cards[0]);
  // Every 5 of n: leave out one (n = 6) or two (n = 7).
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < (n == 7 ? n : a + 2); b++) {
      var k = 0;
      for (var i = 0; i < n; i++) {
        if (i == a || (n == 7 && i == b)) continue;
        five[k++] = cards[i];
      }
      final value = evaluateFive(five);
      if (best == null || value.score > best.score) best = value;
    }
  }
  return best!;
}

/// The player's chance of winning at showdown with [hole] on [board]
/// against [opponents] players with random cards, by [samples] random
/// run-outs; a tie counts as its share. Preflop with no board, too.
double estimateEquity(
  List<Card> hole,
  List<Card> board,
  int opponents,
  Random random, {
  int samples = 200,
}) {
  if (opponents < 1) return 1;
  final known = [...hole, ...board];
  final stock = [
    for (final c in fullDeck)
      if (!known.contains(c)) c,
  ];
  var won = 0.0;
  final toCome = 5 - board.length;
  final fullBoard = [...board, ...List<Card>.filled(toCome, hole[0])];
  final theirs = List<Card>.filled(2, hole[0]);
  for (var s = 0; s < samples; s++) {
    // A partial Fisher-Yates shuffle: just the cards this run-out needs.
    final need = toCome + 2 * opponents;
    for (var i = 0; i < need; i++) {
      final j = i + random.nextInt(stock.length - i);
      final t = stock[i];
      stock[i] = stock[j];
      stock[j] = t;
    }
    for (var i = 0; i < toCome; i++) {
      fullBoard[board.length + i] = stock[i];
    }
    final mine = evaluateBest([...hole, ...fullBoard]).score;
    var beaten = false;
    var ties = 0;
    for (var o = 0; o < opponents && !beaten; o++) {
      theirs[0] = stock[toCome + 2 * o];
      theirs[1] = stock[toCome + 2 * o + 1];
      final their = evaluateBest([...theirs, ...fullBoard]).score;
      if (their > mine) {
        beaten = true;
      } else if (their == mine) {
        ties++;
      }
    }
    if (!beaten) won += 1 / (ties + 1);
  }
  return won / samples;
}

/// The hole cards' class, as the strategies' rules know it: premium (AA,
/// KK, QQ, AKs), strong (JJ, TT, AKo, AQs, AJs, KQs), medium (99 to 77,
/// AQo, AJo, ATs, KQo, KJs, QJs, JTs), speculative (66 to 22, suited
/// connectors 54s to T9s, suited aces, KTs, QTs, J9s, T8s) or weak.
String classifyHole(List<Card> hole) {
  final a = max(hole[0].rank, hole[1].rank);
  final b = min(hole[0].rank, hole[1].rank);
  final suited = hole[0].suit == hole[1].suit;
  final pair = a == b;
  if (pair && a >= 12) return 'premium';
  if (a == 14 && b == 13 && suited) return 'premium';
  if (pair && a >= 10) return 'strong';
  if (a == 14 && b == 13) return 'strong';
  if (a == 14 && b >= 11 && suited) return 'strong';
  if (a == 13 && b == 12 && suited) return 'strong';
  if (pair && a >= 7) return 'medium';
  if (a == 14 && b >= 11) return 'medium';
  if (a == 14 && b == 10 && suited) return 'medium';
  if (a == 13 && b == 12) return 'medium';
  if (suited &&
      (a == 13 && b == 11 || a == 12 && b == 11 || a == 11 && b == 10)) {
    return 'medium';
  }
  if (pair) return 'speculative';
  if (suited && a == 14) return 'speculative';
  if (suited && a - b == 1 && b >= 4) return 'speculative';
  if (suited &&
      (a == 13 && b == 10 ||
          a == 12 && b == 10 ||
          a == 11 && b == 9 ||
          a == 10 && b == 8)) {
    return 'speculative';
  }
  return 'weak';
}

/// Whether [hole] and [board] hold four cards of one suit with cards
/// still to come (and no flush yet).
bool hasFlushDraw(List<Card> hole, List<Card> board) {
  if (board.isEmpty || board.length >= 5) return false;
  final counts = <Suit, int>{};
  for (final c in [...hole, ...board]) {
    counts[c.suit] = (counts[c.suit] ?? 0) + 1;
  }
  return counts.values.any((n) => n == 4);
}

/// The straight draw in [hole] and [board] with cards still to come:
/// `open_ended` when eight ranks complete a straight... counted as outs:
/// eight or more distinct ranks that would make a straight is open-ended,
/// four or more a gutshot, else `none`. A made straight is `none`.
String straightDraw(List<Card> hole, List<Card> board) {
  if (board.isEmpty || board.length >= 5) return 'none';
  final cards = [...hole, ...board];
  final have = {for (final c in cards) c.rank};
  if (_hasStraight(have)) return 'none';
  var outs = 0;
  for (var r = 2; r <= 14; r++) {
    if (have.contains(r)) continue;
    if (_hasStraight({...have, r})) outs++;
  }
  if (outs >= 2) return 'open_ended';
  if (outs == 1) return 'gutshot';
  return 'none';
}

/// Whether [ranks] contain five in a row (the ace low as well as high).
bool _hasStraight(Set<int> ranks) {
  final r = {...ranks, if (ranks.contains(14)) 1};
  for (var high = 14; high >= 5; high--) {
    if ([for (var i = 0; i < 5; i++) high - i].every(r.contains)) return true;
  }
  return false;
}
