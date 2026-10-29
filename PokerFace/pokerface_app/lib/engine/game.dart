/// A no-limit Texas hold'em tournament table: the seats, the deal, the
/// betting rounds, side pots and the showdown, one step at a time, so the
/// app can pace it. Tournament rules: everyone starts with the same chips,
/// the blinds go up every [PokerGame.handsPerLevel] hands, a player out of
/// chips is out of the tournament (no rebuys), and it ends when one player
/// has them all. Every decision is somebody else's: [PokerGame.next] says
/// whose turn it is and what their situation is, [PokerGame.apply] plays
/// what they decided, made legal.
library;

import 'dart:math';

import 'cards.dart';
import 'evaluator.dart';

/// A betting round.
enum Street {
  preflop('preflop', 'Preflop'),
  flop('flop', 'Flop'),
  turn('turn', 'Turn'),
  river('river', 'River');

  const Street(this.id, this.label);

  final String id;
  final String label;

  Street? get nextStreet => index < 3 ? Street.values[index + 1] : null;
}

/// What a seat is doing.
enum SeatStatus {
  /// Joins at the next hand.
  waiting,

  /// In the hand, with chips to bet.
  active,

  /// Out of this hand.
  folded,

  /// In the hand, every chip in the pot.
  allIn,

  /// Out of the tournament: no chips left.
  out,
}

/// What a player can do.
enum ActionKind {
  fold('fold', 'Fold'),
  check('check', 'Check'),
  call('call', 'Call'),
  raise('raise', 'Raise'),
  allIn('all_in', 'All in');

  const ActionKind(this.id, this.label);

  final String id;
  final String label;

  static ActionKind parse(String id) =>
      values.firstWhere((k) => k.id == id, orElse: () => fold);
}

/// A decision: what to do and, for a raise, the total bet to make it to.
class PlayerAction {
  const PlayerAction(this.kind, {this.raiseTo = 0});

  final ActionKind kind;
  final num raiseTo;
}

/// What was played, after the table made the decision legal: the chips
/// put in, the label the table shows ("Raises to 120"), and a note when
/// it differs from what was decided.
class ActionTaken {
  const ActionTaken(this.kind, this.put, this.label, {this.note});

  final ActionKind kind;
  final int put;
  final String label;
  final String? note;
}

/// A player at the table.
class Seat {
  Seat({
    required this.id,
    required this.name,
    required this.strategyId,
    required this.stack,
    required this.status,
  }) : bought = stack;

  final int id;
  String name;
  String strategyId;
  int stack;
  SeatStatus status;

  /// The starting stack, so [net] says how the player is doing.
  int bought;
  int handsWon = 0;
  int handsPlayed = 0;

  /// Where the player finished: 1 for the winner, set when they bust.
  int? place;

  /// Leaves at the end of the hand.
  bool leaving = false;

  List<Card> hole = const [];

  /// Bet this round, and in the whole hand.
  int bet = 0;
  int committed = 0;

  /// Has acted in this round since the last raise.
  bool acted = false;

  /// The table's label for the last action ("Raises to 120"), and the
  /// hand shown at the last showdown.
  String? lastAction;
  String? shownHand;

  int get net => stack - bought;
  bool get inHand => status == SeatStatus.active || status == SeatStatus.allIn;
  bool get canAct => status == SeatStatus.active;
}

/// One pot (the main pot or a side pot) at the end of a hand, and who won
/// it.
class PotResult {
  const PotResult(
    this.amount,
    this.winners,
    this.hand, {
    this.uncalled = false,
  });

  final int amount;
  final List<Seat> winners;

  /// The winning hand in words; null when the others folded.
  final String? hand;

  /// Chips nobody matched, returned to their owner.
  final bool uncalled;
}

/// One line of the hand's story.
class LogEntry {
  LogEntry(this.hand, this.kind, this.text);

  final int hand;

  /// `hand`, `deal`, `action`, `showdown` or `info`.
  final String kind;
  final String text;

  /// For an action: the number of the aityx call that decided it, set by
  /// whoever made the call.
  int? call;
}

/// What [PokerGame.next] did: one atomic thing at the table.
sealed class Step {
  const Step();
}

/// The table can't deal: fewer than two players with chips.
class Waiting extends Step {
  const Waiting(this.reason);

  final String reason;
}

/// Blinds posted and cards dealt.
class HandStarted extends Step {
  const HandStarted(this.hand);

  final int hand;
}

/// A player must act; call [PokerGame.apply] with their decision.
class NeedsAction extends Step {
  const NeedsAction(this.seat, this.situation);

  final Seat seat;
  final Map<String, Object?> situation;
}

/// Community cards dealt.
class Dealt extends Step {
  const Dealt(this.street, this.cards);

  final Street street;
  final List<Card> cards;
}

/// The tournament is over: one player has every chip.
class TournamentOver extends Step {
  const TournamentOver(this.winner, this.standings);

  final Seat winner;

  /// Everyone, the winner first, then by where they finished.
  final List<Seat> standings;
}

/// The hand is over: the pots awarded.
class HandOver extends Step {
  const HandOver(this.hand, this.results, {required this.showdown});

  final int hand;
  final List<PotResult> results;

  /// Whether hands were compared, or everyone else folded.
  final bool showdown;
}

/// The table.
class PokerGame {
  PokerGame({
    Random? random,
    this.buyIn = 1000,
    this.handsPerLevel = 10,
    this.equitySamples = 200,
  }) : random = random ?? Random();

  static const maxSeats = 9;

  /// The blinds of each level, small then big.
  static const levels = <(int, int)>[
    (5, 10),
    (10, 20),
    (15, 30),
    (25, 50),
    (50, 100),
    (75, 150),
    (100, 200),
    (150, 300),
    (200, 400),
    (300, 600),
    (400, 800),
    (500, 1000),
    (750, 1500),
    (1000, 2000),
  ];

  final Random random;

  /// Everyone's starting stack.
  final int buyIn;

  /// Hands per blind level.
  final int handsPerLevel;
  final int equitySamples;

  /// The level of the hand in progress, or of the next one; from 1.
  int get level => levelOf(handInProgress ? handNumber : handNumber + 1);

  int levelOf(int hand) =>
      min((max(hand, 1) - 1) ~/ handsPerLevel + 1, levels.length);

  int get smallBlind => levels[level - 1].$1;
  int get bigBlind => levels[level - 1].$2;

  /// Hands left at this level, the one in progress included.
  int get handsToNextLevel {
    if (level >= levels.length) return 0;
    final played = (handInProgress ? handNumber : handNumber + 1) - 1;
    return handsPerLevel - played % handsPerLevel;
  }

  final List<Seat> seats = [];
  final List<LogEntry> log = [];
  int _nextId = 1;

  int handNumber = 0;
  Street? street;
  List<Card> board = [];
  Deck? _deck;
  int? _button;
  int? _actor;
  int currentBet = 0;
  int _lastRaiseSize = 0;
  int raises = 0;
  bool _showdownDone = false;
  List<PotResult> _results = const [];
  Seat? _winner;

  bool get handInProgress => street != null;

  /// The tournament's winner, once one player has every chip.
  Seat? get winner => _winner;
  bool get over => _winner != null;

  /// Everyone, the winner (or the chip leader) first, then by where they
  /// finished, the last to bust first.
  List<Seat> get standings => [...seats]
    ..sort((a, b) {
      final pa = a.place ?? 0, pb = b.place ?? 0;
      if (pa != pb) return pa - pb;
      return b.stack - a.stack;
    });
  Seat? get button => _button == null ? null : seats[_button!];
  Seat? get actor => _actor == null ? null : seats[_actor!];
  int get pot => seats.fold(0, (sum, s) => sum + s.committed);
  Iterable<Seat> get inHand => seats.where((s) => s.inHand);
  Iterable<Seat> get ready =>
      seats.where((s) => s.status == SeatStatus.active && !s.leaving);

  /// Seats a player; at the next hand when one is in progress. Null when
  /// the table is full. A player who joins after the tournament ended
  /// starts a new one against the winner.
  Seat? addPlayer(String name, String strategyId) {
    if (seats.length >= maxSeats) return null;
    if (over) _winner = null;
    final seat = Seat(
      id: _nextId++,
      name: name,
      strategyId: strategyId,
      stack: buyIn,
      status: handInProgress ? SeatStatus.waiting : SeatStatus.active,
    );
    seats.add(seat);
    _log('info', '${seat.name} sits down with $buyIn chips.');
    return seat;
  }

  /// The player leaves: now, or at the end of the hand they're in.
  void removePlayer(Seat seat) {
    if (handInProgress && seat.inHand) {
      seat.leaving = true;
      _log('info', '${seat.name} leaves after this hand.');
    } else {
      seats.remove(seat);
      _log('info', '${seat.name} leaves the table.');
    }
  }

  /// A new tournament: everyone starts again with the same chips.
  void reset() {
    street = null;
    board = [];
    _actor = null;
    _button = null;
    _showdownDone = false;
    _winner = null;
    handNumber = 0;
    log.clear();
    seats.removeWhere((s) => s.leaving);
    for (final s in seats) {
      s
        ..stack = buyIn
        ..bought = buyIn
        ..place = null
        ..handsWon = 0
        ..handsPlayed = 0
        ..hole = const []
        ..bet = 0
        ..committed = 0
        ..lastAction = null
        ..shownHand = null
        ..status = SeatStatus.active;
    }
  }

  /// One step at the table.
  Step next() {
    if (!handInProgress) return _startHand();
    if (_actor != null) {
      final seat = seats[_actor!];
      return NeedsAction(seat, situationFor(seat));
    }
    if (_showdownDone) return _finishHand();
    if (inHand.length == 1) {
      _results = _awardUncontested();
      _showdownDone = true;
      return _finishHand();
    }
    if (street == Street.river) {
      _results = _showdown();
      _showdownDone = true;
      return _finishHand();
    }
    return _dealNext();
  }

  Step _startHand() {
    final players = ready.toList();
    if (players.length < 2) {
      final busted = seats.where((s) => s.status == SeatStatus.out);
      if (players.length == 1 && busted.isNotEmpty) {
        final winner = players.single;
        if (_winner != winner) {
          winner.place = 1;
          _winner = winner;
          _log(
            'info',
            '${winner.name} wins the tournament with ${winner.stack} chips.',
          );
        }
        return TournamentOver(winner, standings);
      }
      return const Waiting('Two players with chips are needed to deal.');
    }
    handNumber++;
    if (handNumber > 1 && (handNumber - 1) % handsPerLevel == 0) {
      _log('info', 'Level $level: the blinds go up to $smallBlind/$bigBlind.');
    }
    board = [];
    _deck = Deck(random);
    _showdownDone = false;
    _results = const [];
    for (final s in seats) {
      s
        ..bet = 0
        ..committed = 0
        ..acted = false
        ..lastAction = null
        ..shownHand = null
        ..hole = const [];
      if (s.status == SeatStatus.active) s.handsPlayed++;
    }
    // The button moves to the next player with chips.
    _button = _button == null
        ? seats.indexOf(players.first)
        : _nextReady(_button!);
    final headsUp = players.length == 2;
    final sb = headsUp ? _button! : _nextReady(_button!);
    final bb = _nextReady(sb);
    _log(
      'hand',
      'Hand #$handNumber. ${seats[_button!].name} has the button; '
          'blinds $smallBlind/$bigBlind.',
    );
    _post(seats[sb], smallBlind, 'small blind');
    _post(seats[bb], bigBlind, 'big blind');
    currentBet = bigBlind;
    _lastRaiseSize = bigBlind;
    raises = 0;
    for (final s in seats.where((s) => s.inHand)) {
      s.hole = _deck!.drawMany(2);
    }
    street = Street.preflop;
    _log(
      'deal',
      [
        for (final s in inHand)
          '${s.name}: ${s.hole.map((c) => c.display).join(' ')}',
      ].join(' · '),
    );
    _actor = _firstToAct(bb);
    return HandStarted(handNumber);
  }

  void _post(Seat seat, int blind, String what) {
    final put = min(blind, seat.stack);
    seat
      ..stack -= put
      ..bet = put
      ..committed = put
      ..lastAction = '${what == 'small blind' ? 'SB' : 'BB'} $put';
    if (seat.stack == 0) seat.status = SeatStatus.allIn;
    _log('action', '${seat.name} posts the $what, $put.');
  }

  /// The next seat after [from] that is dealt in this hand.
  int _nextReady(int from) {
    for (var i = 1; i <= seats.length; i++) {
      final j = (from + i) % seats.length;
      if (seats[j].inHand && !seats[j].leaving) return j;
    }
    for (var i = 1; i <= seats.length; i++) {
      final j = (from + i) % seats.length;
      if (seats[j].inHand) return j;
    }
    return from;
  }

  /// The first seat after [from] that can still act this round, or null
  /// when the round is over (nobody can, or everyone has, with the bets
  /// matched).
  int? _firstToAct(int from) {
    if (inHand.where((s) => s.canAct).length < 2 && _betsMatched()) {
      return null;
    }
    for (var i = 1; i <= seats.length; i++) {
      final j = (from + i) % seats.length;
      final s = seats[j];
      if (s.canAct && (!s.acted || s.bet < currentBet)) return j;
    }
    return null;
  }

  bool _betsMatched() =>
      inHand.where((s) => s.canAct).every((s) => s.bet >= currentBet);

  Step _dealNext() {
    final next = street!.nextStreet!;
    final cards = _deck!.drawMany(next == Street.flop ? 3 : 1);
    board = [...board, ...cards];
    street = next;
    for (final s in seats) {
      s
        ..bet = 0
        ..acted = false;
      if (s.inHand) s.lastAction = null;
    }
    currentBet = 0;
    _lastRaiseSize = bigBlind;
    raises = 0;
    _log(
      'deal',
      '${next.label}: ${board.map((c) => c.display).join(' ')}'
          '  (pot $pot)',
    );
    _actor = _firstToAct(_button!);
    return Dealt(next, cards);
  }

  /// The player's situation, as the strategies' rules see it.
  Map<String, Object?> situationFor(Seat seat) {
    final players = inHand.toList();
    final toCall = min(currentBet - seat.bet, seat.stack);
    final others = inHand.where((s) => s != seat && s.canAct).length;
    final canRaise = seat.stack > toCall && others > 0;
    final maxRaise = seat.stack + seat.bet;
    final minRaise = min(currentBet + _lastRaiseSize, maxRaise);
    final made = board.length >= 3
        ? evaluateBest([...seat.hole, ...board]).category
        : seat.hole[0].rank == seat.hole[1].rank
        ? HandCategory.pair
        : HandCategory.highCard;
    final equity = estimateEquity(
      seat.hole,
      board,
      players.length - 1,
      random,
      samples: equitySamples,
    );
    final potNow = pot;
    final potOdds = toCall == 0 ? 0.0 : toCall / (potNow + toCall);
    return {
      'street': street!.id,
      'position': _position(seat),
      'hole': [for (final c in seat.hole) c.label],
      'board': [for (final c in board) c.label],
      'hand': classifyHole(seat.hole),
      'made_hand': made.id,
      'flush_draw': hasFlushDraw(seat.hole, board),
      'straight_draw': straightDraw(seat.hole, board),
      'equity': _round2(equity),
      'pot': potNow,
      'current_bet': currentBet,
      'to_call': toCall,
      'pot_odds': _round2(potOdds),
      'can_check': toCall == 0,
      'can_raise': canRaise,
      'raises': raises,
      'stack': seat.stack,
      'big_blind': bigBlind,
      'stack_bb': (seat.stack / bigBlind * 10).round() / 10,
      'min_raise': minRaise,
      'max_raise': maxRaise,
      'players_in_hand': players.length,
      'players_after': _playersAfter(seat),
      'random': _round2(random.nextDouble()),
    };
  }

  static double _round2(double x) => (x * 100).round() / 100;

  /// Players who can still act after [seat] in this round.
  int _playersAfter(Seat seat) {
    final from = seats.indexOf(seat);
    var n = 0;
    for (var i = 1; i < seats.length; i++) {
      final s = seats[(from + i) % seats.length];
      if (s.canAct && (!s.acted || s.bet < currentBet)) n++;
    }
    return n;
  }

  /// Early, middle or late by the order of play this round; the blinds
  /// before the flop.
  String _position(Seat seat) {
    final order = <Seat>[];
    if (street == Street.preflop) {
      final headsUp = inHand.length <= 2;
      final sb = headsUp ? _button! : _nextInHand(_button!);
      final bb = _nextInHand(sb);
      if (seat == seats[sb] || seat == seats[bb]) return 'blinds';
      var i = bb;
      do {
        i = _nextInHand(i);
        if (i != sb && i != bb) order.add(seats[i]);
      } while (i != bb && order.length < inHand.length);
    } else {
      var i = _button!;
      do {
        i = _nextInHand(i);
        order.add(seats[i]);
      } while (order.length < inHand.length);
    }
    final idx = order.indexOf(seat);
    final n = order.length;
    if (idx < 0) return 'middle';
    if (idx == n - 1 || idx * 3 >= 2 * n) return 'late';
    if (idx * 3 < n) return 'early';
    return 'middle';
  }

  int _nextInHand(int from) {
    for (var i = 1; i <= seats.length; i++) {
      final j = (from + i) % seats.length;
      if (seats[j].inHand) return j;
    }
    return from;
  }

  /// Plays [wanted] for the player to act, made legal: a fold with
  /// nothing to call is a check, a call of nothing is a check, a raise
  /// that isn't possible is a call, a raise is kept within the minimum
  /// and the stack, and a check facing a bet is a fold.
  ActionTaken apply(PlayerAction wanted) {
    final seat = actor;
    if (seat == null) throw StateError('nobody is to act');
    final toCall = min(currentBet - seat.bet, seat.stack);
    final others = inHand.where((s) => s != seat && s.canAct).length;
    final canRaise = seat.stack > toCall && others > 0;
    final maxRaise = seat.stack + seat.bet;
    final minRaise = min(currentBet + _lastRaiseSize, maxRaise);
    var kind = wanted.kind;
    String? note;
    if (kind == ActionKind.fold && toCall == 0) {
      kind = ActionKind.check;
      note = 'Nothing to call: a fold is a check.';
    } else if (kind == ActionKind.check && toCall > 0) {
      kind = ActionKind.fold;
      note = "Can't check facing a bet: a check is a fold.";
    } else if (kind == ActionKind.call && toCall == 0) {
      kind = ActionKind.check;
    } else if ((kind == ActionKind.raise || kind == ActionKind.allIn) &&
        !canRaise) {
      kind = toCall == 0 ? ActionKind.check : ActionKind.call;
      note = others == 0
          ? 'Nobody left to raise: a raise is a call.'
          : 'Not enough chips to raise: a raise is a call.';
    }
    final ActionTaken taken;
    switch (kind) {
      case ActionKind.fold:
        seat
          ..status = SeatStatus.folded
          ..acted = true;
        taken = ActionTaken(kind, 0, 'Folds', note: note);
      case ActionKind.check:
        seat.acted = true;
        taken = ActionTaken(kind, 0, 'Checks', note: note);
      case ActionKind.call:
        _put(seat, toCall);
        seat.acted = true;
        taken = ActionTaken(
          kind,
          toCall,
          seat.status == SeatStatus.allIn
              ? 'Calls $toCall, all in'
              : 'Calls $toCall',
          note: note,
        );
      case ActionKind.raise:
      case ActionKind.allIn:
        final asked = wanted.raiseTo.round();
        final total = kind == ActionKind.allIn
            ? maxRaise
            : asked.clamp(minRaise, maxRaise);
        if (kind == ActionKind.raise && asked != total) {
          note = asked < minRaise
              ? 'Raised to the minimum, $minRaise, not $asked.'
              : 'All in for $maxRaise, not $asked.';
        }
        final put = total - seat.bet;
        final raiseSize = total - currentBet;
        final opening = currentBet == 0;
        _put(seat, put);
        // A full raise reopens the round for everyone else; a short all
        // in doesn't.
        if (raiseSize >= _lastRaiseSize) {
          _lastRaiseSize = raiseSize;
          for (final s in seats) {
            if (s != seat) s.acted = false;
          }
        }
        currentBet = total;
        raises++;
        seat.acted = true;
        final allIn = seat.status == SeatStatus.allIn;
        taken = ActionTaken(
          allIn ? ActionKind.allIn : ActionKind.raise,
          put,
          allIn
              ? 'All in, $total'
              : opening
              ? 'Bets $total'
              : 'Raises to $total',
          note: note,
        );
    }
    seat.lastAction = taken.label;
    _log(
      'action',
      '${seat.name} ${taken.label.toLowerCase()}.'
          '${note == null ? '' : ' ($note)'}',
    );
    _actor = inHand.length < 2 ? null : _firstToAct(seats.indexOf(seat));
    return taken;
  }

  void _put(Seat seat, int chips) {
    final put = min(chips, seat.stack);
    seat
      ..stack -= put
      ..bet += put
      ..committed += put;
    if (seat.stack == 0) seat.status = SeatStatus.allIn;
  }

  List<PotResult> _awardUncontested() {
    final winner = inHand.single;
    final others = seats
        .where((s) => s != winner)
        .fold(0, (m, s) => max(m, s.committed));
    final uncalled = max(0, winner.committed - others);
    final amount = pot - uncalled;
    winner.stack += pot;
    winner.handsWon++;
    _log(
      'showdown',
      '${winner.name} wins $amount: everyone else folded.'
          '${uncalled > 0 ? ' ($uncalled uncalled, returned.)' : ''}',
    );
    return [
      PotResult(amount, [winner], null),
    ];
  }

  /// Compares the hands and pays each pot, side pots included: every
  /// level of commitment is a pot, shared by the best hand among the
  /// players who reached it.
  List<PotResult> _showdown() {
    final values = {
      for (final s in inHand) s: evaluateBest([...s.hole, ...board]),
    };
    for (final s in inHand) {
      s.shownHand = values[s]!.describe();
    }
    _log(
      'showdown',
      'Showdown: ${[for (final s in inHand) '${s.name} ${values[s]!.describe().toLowerCase()}'].join(' · ')}.',
    );
    final levels =
        seats
            .where((s) => s.committed > 0)
            .map((s) => s.committed)
            .toSet()
            .toList()
          ..sort();
    final results = <PotResult>[];
    var previous = 0;
    for (final level in levels) {
      var amount = 0;
      for (final s in seats) {
        amount += max(0, min(s.committed, level) - previous);
      }
      final eligible = inHand.where((s) => s.committed >= level).toList();
      previous = level;
      if (amount == 0) continue;
      if (eligible.length == 1) {
        // Chips nobody else matched go back.
        final owner = eligible.single;
        owner.stack += amount;
        results.add(PotResult(amount, [owner], null, uncalled: true));
        _log('showdown', '$amount uncalled, returned to ${owner.name}.');
        continue;
      }
      final best = eligible.map((s) => values[s]!.score).reduce(max);
      final winners = eligible.where((s) => values[s]!.score == best).toList();
      final share = amount ~/ winners.length;
      var odd = amount - share * winners.length;
      // Odd chips go to the first winner after the button.
      final ordered = [
        for (var i = 1; i <= seats.length; i++)
          if (winners.contains(seats[(_button! + i) % seats.length]))
            seats[(_button! + i) % seats.length],
      ];
      for (final w in ordered) {
        w.stack += share + (odd > 0 ? 1 : 0);
        if (odd > 0) odd--;
      }
      final hand = values[winners.first]!.describe();
      results.add(PotResult(amount, winners, hand));
      _log(
        'showdown',
        '${winners.map((w) => w.name).join(' and ')} '
            '${winners.length > 1 ? 'split' : 'wins'} '
            '${results.length > 1 ? 'a side pot of ' : ''}$amount with $hand.',
      );
    }
    // A hand won: the biggest pot's winners.
    final won = <Seat>{};
    for (final r in results) {
      if (!r.uncalled) won.addAll(r.winners);
    }
    for (final w in won) {
      w.handsWon++;
    }
    return results;
  }

  Step _finishHand() {
    final results = _results;
    final showdown = results.any((r) => r.hand != null);
    final hand = handNumber;
    street = null;
    _actor = null;
    for (final s in seats) {
      s
        ..bet = 0
        ..committed = 0;
    }
    for (final s in seats.toList()) {
      if (s.leaving) {
        seats.remove(s);
        _log('info', '${s.name} leaves the table.');
        continue;
      }
      if (s.status == SeatStatus.out) continue;
      if (s.stack == 0) {
        s.status = SeatStatus.out;
      } else {
        s.status = SeatStatus.active;
      }
    }
    // Those who busted this hand share the place after everyone still in.
    final busted = seats
        .where((s) => s.status == SeatStatus.out && s.place == null)
        .toList();
    if (busted.isNotEmpty) {
      final left = seats.where((s) => s.status != SeatStatus.out).length;
      for (final s in busted) {
        s.place = left + busted.length;
        _log('info', '${s.name} is out of chips: ${_ordinal(s.place!)} place.');
      }
    }
    return HandOver(hand, results, showdown: showdown);
  }

  void _log(String kind, String text) =>
      log.add(LogEntry(handNumber, kind, text));
}

/// 1st, 2nd, 3rd, 4th, ...
String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

String ordinal(int n) => _ordinal(n);
