import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokerface_app/engine/cards.dart';
import 'package:pokerface_app/engine/evaluator.dart';
import 'package:pokerface_app/engine/game.dart';

List<Card> cards(String labels) => [
  for (final l in labels.split(' ')) Card.parse(l),
];

void main() {
  group('cards', () {
    test('parse and print', () {
      final c = Card.parse('Td');
      expect(c.rank, 10);
      expect(c.suit, Suit.diamonds);
      expect(c.label, 'Td');
      expect(c.display, 'T♦');
      expect(() => Card.parse('1x'), throwsFormatException);
      expect(fullDeck.length, 52);
      expect(fullDeck.toSet().length, 52);
    });

    test('a deck deals every card once', () {
      final deck = Deck(Random(1));
      final dealt = deck.drawMany(52);
      expect(dealt.toSet().length, 52);
      expect(deck.remaining, 0);
    });
  });

  group('the evaluator', () {
    HandCategory cat(String five) => evaluateFive(cards(five)).category;

    test('names every category', () {
      expect(cat('Ah Kh Qh Jh Th'), HandCategory.straightFlush);
      expect(cat('9c 9d 9h 9s 2d'), HandCategory.fourOfAKind);
      expect(cat('9c 9d 9h 2s 2d'), HandCategory.fullHouse);
      expect(cat('Ah 9h 7h 4h 2h'), HandCategory.flush);
      expect(cat('9c 8d 7h 6s 5d'), HandCategory.straight);
      expect(cat('Ah 5d 4h 3s 2d'), HandCategory.straight);
      expect(cat('9c 9d 9h 6s 5d'), HandCategory.threeOfAKind);
      expect(cat('9c 9d 6h 6s 5d'), HandCategory.twoPair);
      expect(cat('9c 9d 7h 6s 5d'), HandCategory.pair);
      expect(cat('Kc 9d 7h 6s 5d'), HandCategory.highCard);
    });

    test('breaks ties by the ranks that matter', () {
      int score(String five) => evaluateFive(cards(five)).score;
      expect(score('9c 9d 7h 6s 5d'), greaterThan(score('8c 8d Ah Ks Qd')));
      expect(score('9c 9d Ah 6s 5d'), greaterThan(score('9h 9s Kh 6c 5c')));
      expect(score('6c 5d 4h 3s 2d'), greaterThan(score('Ah 5h 4c 3c 2c')));
      expect(score('9c 9d 9h 2s 2d'), greaterThan(score('8c 8d 8h As Ad')));
      expect(score('Kc 9d 7h 6s 5d'), score('Kh 9s 7c 6d 5c'));
    });

    test('finds the best five of seven', () {
      final v = evaluateBest(cards('Ah Kd 2c 3c 4c 5c 9s'));
      expect(v.category, HandCategory.straight);
      expect(v.ranks, [5]);
      final flush = evaluateBest(cards('Ac Kd 2c 3c 4c 9c 9s'));
      expect(flush.category, HandCategory.flush);
      expect(flush.describe(), 'Flush, ace high');
      expect(
        evaluateBest(cards('Kh Ks 7c 7d Ad 2c 3c')).describe(),
        'Two pair, kings and sevens',
      );
    });

    test('classes hole cards', () {
      expect(classifyHole(cards('Ah Ad')), 'premium');
      expect(classifyHole(cards('Ah Kh')), 'premium');
      expect(classifyHole(cards('Ah Kd')), 'strong');
      expect(classifyHole(cards('Jh Jd')), 'strong');
      expect(classifyHole(cards('Ah Qd')), 'medium');
      expect(classifyHole(cards('8h 8d')), 'medium');
      expect(classifyHole(cards('Jh Th')), 'medium');
      expect(classifyHole(cards('5h 4h')), 'speculative');
      expect(classifyHole(cards('Ah 2h')), 'speculative');
      expect(classifyHole(cards('3h 3d')), 'speculative');
      expect(classifyHole(cards('7h 2d')), 'weak');
      expect(classifyHole(cards('Kh 9d')), 'weak');
    });

    test('sees draws', () {
      expect(hasFlushDraw(cards('Ah 9h'), cards('Kh 7h 2d')), isTrue);
      expect(hasFlushDraw(cards('Ah 9h'), cards('Kh 7c 2d')), isFalse);
      expect(hasFlushDraw(cards('Ah 9h'), cards('Kh 7h 2h')), isFalse);
      expect(hasFlushDraw(cards('Ah 9h'), cards('Kh 7h 2d 3c Ts')), isFalse);
      expect(straightDraw(cards('9h 8d'), cards('7c 6d 2s')), 'open_ended');
      expect(straightDraw(cards('9h 8d'), cards('7c 5d 2s')), 'gutshot');
      expect(straightDraw(cards('9h 8d'), cards('7c 6d 5s')), 'none');
      expect(straightDraw(cards('Ah Kd'), cards('7c 2d 3s')), 'none');
      expect(straightDraw(cards('Ah 2d'), cards('3c 4d 9s')), 'gutshot');
    });

    test('estimates equity', () {
      final r = Random(7);
      final aces = estimateEquity(cards('Ah Ad'), [], 1, r, samples: 400);
      expect(aces, greaterThan(0.75));
      final junk = estimateEquity(cards('7h 2d'), [], 4, r, samples: 400);
      expect(junk, lessThan(0.2));
      final nuts = estimateEquity(
        cards('Ah Kh'),
        cards('Qh Jh Th 2c 3d'),
        3,
        r,
      );
      expect(nuts, 1);
      expect(estimateEquity(cards('7h 2d'), [], 0, r), 1);
    });
  });

  group('the game', () {
    PokerGame table({int players = 3, int seed = 1}) {
      final g = PokerGame(random: Random(seed), equitySamples: 20);
      for (var i = 0; i < players; i++) {
        g.addPlayer('P${i + 1}', 'rock');
      }
      return g;
    }

    int chips(PokerGame g) => g.seats.fold(0, (s, x) => s + x.stack) + g.pot;

    test('needs two players', () {
      final g = PokerGame(random: Random(1), equitySamples: 20);
      expect(g.next(), isA<Waiting>());
      g.addPlayer('A', 'rock');
      expect(g.next(), isA<Waiting>());
      g.addPlayer('B', 'rock');
      expect(g.next(), isA<HandStarted>());
    });

    test('posts the blinds and asks the player after the big blind', () {
      final g = table();
      expect(g.next(), isA<HandStarted>());
      expect(g.button, g.seats[0]);
      expect(g.seats[1].bet, 5);
      expect(g.seats[2].bet, 10);
      expect(g.pot, 15);
      final step = g.next() as NeedsAction;
      expect(step.seat, g.seats[0]);
      final s = step.situation;
      expect(s['street'], 'preflop');
      expect(s['to_call'], 10);
      expect(s['pot_odds'], 0.4);
      expect(s['can_check'], isFalse);
      expect(s['can_raise'], isTrue);
      expect(s['min_raise'], 20);
      expect(s['max_raise'], 1000);
      expect(s['players_in_hand'], 3);
      expect(s['players_after'], 2);
      expect(s['hole'], hasLength(2));
      expect(s['board'], isEmpty);
      expect(s['stack_bb'], 100);
      expect(chips(g), 3000);
    });

    test('the blinds are a position, the button is late', () {
      final g = table(players: 4);
      g.next();
      final first = g.next() as NeedsAction;
      expect(first.seat, g.seats[3]);
      expect(first.situation['position'], 'early');
      g.apply(const PlayerAction(ActionKind.call));
      final button = g.next() as NeedsAction;
      expect(button.seat, g.seats[0]);
      expect(button.situation['position'], 'late');
      g.apply(const PlayerAction(ActionKind.call));
      final sb = g.next() as NeedsAction;
      expect(sb.situation['position'], 'blinds');
    });

    test('everyone folds to the big blind, who wins the pot', () {
      final g = table();
      g.next();
      g.next();
      final fold = g.apply(const PlayerAction(ActionKind.fold));
      expect(fold.label, 'Folds');
      g.next();
      g.apply(const PlayerAction(ActionKind.fold));
      final over = g.next() as HandOver;
      expect(over.showdown, isFalse);
      expect(over.results.single.winners, [g.seats[2]]);
      expect(over.results.single.amount, 10);
      expect(g.seats[2].stack, 1005);
      expect(g.seats[2].handsWon, 1);
      expect(chips(g), 3000);
      expect(g.handInProgress, isFalse);
    });

    test('calls, the big blind checks its option, then the streets', () {
      final g = table();
      g.next();
      g.next();
      g.apply(const PlayerAction(ActionKind.call));
      g.next();
      final sb = g.apply(const PlayerAction(ActionKind.call));
      expect(sb.put, 5);
      final bb = g.next() as NeedsAction;
      expect(bb.seat, g.seats[2]);
      expect(bb.situation['can_check'], isTrue);
      final check = g.apply(const PlayerAction(ActionKind.fold));
      expect(check.kind, ActionKind.check);
      expect(check.note, isNotNull);
      final flop = g.next() as Dealt;
      expect(flop.street, Street.flop);
      expect(g.board, hasLength(3));
      final first = g.next() as NeedsAction;
      expect(first.seat, g.seats[1]); // the small blind acts first
      expect(first.situation['current_bet'], 0);
      expect(first.situation['raises'], 0);
      for (var i = 0; i < 3; i++) {
        g.apply(const PlayerAction(ActionKind.check));
        if (i < 2) g.next();
      }
      expect((g.next() as Dealt).street, Street.turn);
      for (var i = 0; i < 3; i++) {
        g.next();
        g.apply(const PlayerAction(ActionKind.check));
      }
      expect((g.next() as Dealt).street, Street.river);
      for (var i = 0; i < 3; i++) {
        g.next();
        g.apply(const PlayerAction(ActionKind.check));
      }
      final over = g.next() as HandOver;
      expect(over.showdown, isTrue);
      expect(over.results.single.amount, 30);
      expect(chips(g), 3000);
      expect(g.seats.where((s) => s.handsWon > 0), isNotEmpty);
    });

    test('a raise reopens the round, a short raise is made the minimum', () {
      final g = table();
      g.next();
      g.next();
      final raise = g.apply(const PlayerAction(ActionKind.raise, raiseTo: 30));
      expect(raise.label, 'Raises to 30');
      expect(g.currentBet, 30);
      final sb = g.next() as NeedsAction;
      expect(sb.situation['to_call'], 25);
      expect(sb.situation['min_raise'], 50);
      expect(sb.situation['raises'], 1);
      final small = g.apply(const PlayerAction(ActionKind.raise, raiseTo: 35));
      expect(small.note, contains('minimum, 50'));
      expect(g.currentBet, 50);
      g.next();
      g.apply(const PlayerAction(ActionKind.call));
      // Back to the raiser, who must call the re-raise.
      final again = g.next() as NeedsAction;
      expect(again.seat, g.seats[0]);
      expect(again.situation['to_call'], 20);
    });

    test('all in and side pots', () {
      final g = table();
      g.seats[0].stack = 100;
      g.seats[0].bought = 100;
      for (final s in g.seats.skip(1)) {
        s.stack = 300;
        s.bought = 300;
      }
      g.next();
      g.next();
      final shove = g.apply(const PlayerAction(ActionKind.allIn));
      expect(shove.label, 'All in, 100');
      expect(g.seats[0].status, SeatStatus.allIn);
      g.next();
      g.apply(const PlayerAction(ActionKind.raise, raiseTo: 300));
      g.next();
      g.apply(const PlayerAction(ActionKind.call));
      // Nobody can act against the all-in player: the board runs out.
      expect(g.next(), isA<Dealt>());
      expect(g.next(), isA<Dealt>());
      expect(g.next(), isA<Dealt>());
      final over = g.next() as HandOver;
      expect(over.showdown, isTrue);
      final amounts = over.results.map((r) => r.amount).toList();
      expect(amounts, [300, 400]); // the main pot, then the side pot
      expect(over.results[0].winners, isNotEmpty);
      expect(over.results[1].winners, isNot(contains(g.seats[0])));
      expect(chips(g), 700);
      expect(g.seats.where((s) => s.status == SeatStatus.out), isNotEmpty);
    });

    test('an uncalled bet comes back', () {
      final g = table(players: 2);
      g.next();
      // Heads up: the button is the small blind and acts first.
      final first = g.next() as NeedsAction;
      expect(first.seat, g.button);
      expect(first.situation['position'], 'blinds');
      g.apply(const PlayerAction(ActionKind.raise, raiseTo: 100));
      g.next();
      g.apply(const PlayerAction(ActionKind.fold));
      final over = g.next() as HandOver;
      expect(over.results.single.amount, 20);
      expect(g.seats[0].stack, 1010);
      expect(g.seats[1].stack, 990);
    });

    test('a busted player is out, with a place; the last one wins', () {
      final g = table(players: 3);
      g.seats[1].stack = 10;
      g.seats[1].bought = 10;
      g.next();
      g.next();
      g.apply(const PlayerAction(ActionKind.allIn));
      while (true) {
        final step = g.next();
        if (step is NeedsAction) {
          g.apply(const PlayerAction(ActionKind.call));
        } else if (step is HandOver) {
          break;
        }
      }
      expect(chips(g), g.seats.fold(0, (s, x) => s + x.bought));
      final out = g.seats.where((s) => s.status == SeatStatus.out).toList();
      expect(out, isNotEmpty);
      final left = g.seats.length - out.length;
      for (final s in out) {
        expect(s.place, left + out.length);
      }
      // Everyone but one busts: the tournament is over.
      final leader = g.seats.firstWhere((s) => s.stack > 0);
      for (final s in g.seats) {
        if (s != leader) {
          leader.stack += s.stack;
          s.stack = 0;
          s.status = SeatStatus.out;
          s.place ??= 2;
        }
      }
      final over = g.next();
      expect(over, isA<TournamentOver>());
      expect((over as TournamentOver).winner, leader);
      expect(leader.place, 1);
      expect(g.over, isTrue);
      expect(g.standings.first, leader);
      expect(g.next(), isA<TournamentOver>());
      g.reset();
      expect(g.over, isFalse);
      expect(g.seats.every((s) => s.stack == 1000 && s.place == null), isTrue);
      expect(g.next(), isA<HandStarted>());
    });

    test('the blinds go up every level', () {
      final g = PokerGame(
        random: Random(1),
        handsPerLevel: 2,
        equitySamples: 20,
      );
      g.addPlayer('A', 'rock');
      g.addPlayer('B', 'rock');
      expect(g.level, 1);
      expect(g.bigBlind, 10);
      expect(g.handsToNextLevel, 2);
      for (var hand = 1; hand <= 3; hand++) {
        g.next();
        if (hand == 3) {
          expect(g.level, 2);
          expect(g.smallBlind, 10);
          expect(g.bigBlind, 20);
          expect(g.seats.map((s) => s.bet).reduce((a, b) => a + b), 30);
          expect(g.log.any((e) => e.text.startsWith('Level 2:')), isTrue);
        }
        while (true) {
          final step = g.next();
          if (step is NeedsAction) {
            g.apply(const PlayerAction(ActionKind.call));
          } else if (step is HandOver) {
            break;
          }
        }
      }
      expect(g.handsToNextLevel, 1);
    });

    test('players join at the next hand and leave after theirs', () {
      final g = table(players: 2);
      g.next();
      final late = g.addPlayer('Late', 'maniac')!;
      expect(late.status, SeatStatus.waiting);
      g.removePlayer(g.seats[0]);
      expect(g.seats[0].leaving, isTrue);
      g.next();
      g.apply(const PlayerAction(ActionKind.fold));
      g.next();
      expect(g.seats.map((s) => s.name), ['P2', 'Late']);
      expect(late.status, SeatStatus.active);
      expect(g.next(), isA<HandStarted>());
      expect(g.inHand.length, 2);
    });

    test('many random hands keep the chips and end', () {
      final g = table(players: 6, seed: 42);
      final r = Random(3);
      var hands = 0;
      var steps = 0;
      var over = false;
      while (hands < 30 && steps < 5000 && !over) {
        final step = g.next();
        steps++;
        if (step is NeedsAction) {
          final kind = ActionKind.values[r.nextInt(5)];
          g.apply(PlayerAction(kind, raiseTo: r.nextInt(400)));
        } else if (step is HandOver) {
          hands++;
          expect(chips(g), g.seats.fold(0, (s, x) => s + x.bought));
        } else if (step is TournamentOver) {
          over = true;
          expect(step.winner.stack, 6000);
          expect(step.standings.first, step.winner);
          expect(step.standings.map((s) => s.place), everyElement(isNotNull));
        }
      }
      // Random play goes all in often: the tournament ends well before
      // 30 hands, with the chips accounted for.
      expect(over || hands == 30, isTrue);
      expect(hands, greaterThan(0));
    });
  });
}
