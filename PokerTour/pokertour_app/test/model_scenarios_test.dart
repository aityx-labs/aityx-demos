/// Every strategy's rules (assets/models/strategies/*.json) executed on
/// aityx.ai with fixed situations at the table, checking that each plays
/// in character. Tagged `aityx`: skipped by `flutter test`, run by
/// scripts/model-test.sh, which passes AITYX_API_KEY and AITYX_URL from
/// the repository's .env. A plain `test`, not a widget test: the widget
/// test binding would replace the network.
@Tags(['aityx'])
library;

import 'dart:io';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poker_core/table.dart';

import 'model_files.dart';

/// A situation: on the button with A-K, by default before the flop in an
/// unopened pot, 100 big blinds deep.
Map<String, Object?> at({
  String street = 'preflop',
  String position = 'late',
  List<String> hole = const ['Ah', 'Kd'],
  List<String> board = const [],
  String hand = 'strong',
  String made = 'high_card',
  bool flushDraw = false,
  String straightDraw = 'none',
  double equity = 0.6,
  num pot = 15,
  num bet = 10,
  num toCall = 10,
  int raises = 0,
  num stack = 1000,
  num minRaise = 20,
  int players = 5,
  int after = 2,
  double random = 0.42,
}) => {
  'street': street,
  'position': position,
  'hole': hole,
  'board': board,
  'hand': hand,
  'made_hand': made,
  'flush_draw': flushDraw,
  'straight_draw': straightDraw,
  'equity': equity,
  'pot': pot,
  'current_bet': bet,
  'to_call': toCall,
  'pot_odds': toCall == 0 ? 0 : toCall / (pot + toCall),
  'can_check': toCall == 0,
  'can_raise': stack > toCall,
  'raises': raises,
  'stack': stack,
  'big_blind': 10,
  'stack_bb': stack / 10,
  'min_raise': minRaise,
  'max_raise': stack + (bet - toCall),
  'players_in_hand': players,
  'players_after': after,
  'random': random,
};

late final Models models;
late final AityxClient aityx;

/// [strategy]'s action in [situation], run on aityx.
Future<({String action, num raiseTo, int? rule})> play(
  String strategy,
  Map<String, Object?> situation,
) async {
  final sent = actRequest(models, models.strategies[strategy]!, situation);
  final answer = await aityx.systemone(sent);
  expect(answer.status, 200, reason: answer.text);
  final action = toAction(sent, answer.json! as Map<String, Object?>);
  return (
    action: action['action'] as String,
    raiseTo: action['raise_to'] as num,
    rule: action['rule'] as int?,
  );
}

void main() {
  setUpAll(() async {
    final env = Platform.environment;
    // The key goes in the Authorization header only; never print it.
    aityx = AityxClient(
      connection: AityxConnection.user(
        env['AITYX_API_KEY'] ?? '',
        url: env['AITYX_URL'],
      ),
    );
    models = await loadModels();
  });
  tearDownAll(() => aityx.close());

  group('every strategy', () {
    test('answers, with a rule that fired', () async {
      for (final id in models.strategies.keys) {
        final r = await play(id, at());
        expect(r.rule, isNotNull, reason: id);
        expect(r.raiseTo, greaterThan(0), reason: id);
      }
    });
  });

  group('the Rock', () {
    test('raises premium cards, calls strong ones against a raise', () async {
      expect((await play('rock', at(hand: 'premium'))).action, 'raise');
      final r = await play('rock', at(raises: 1, bet: 30, toCall: 30, pot: 45));
      expect(r.action, 'call');
    });

    test('folds the rest, but sees a cheap flop and checks a free one', () async {
      expect((await play('rock', at(hand: 'weak'))).action, 'fold');
      expect((await play('rock', at(hand: 'medium'))).action, 'call');
      expect(
        (await play('rock', at(hand: 'medium', raises: 2, bet: 90, toCall: 90, pot: 135))).action,
        'fold',
      );
      final free = await play(
        'rock',
        at(hand: 'weak', position: 'blinds', toCall: 0),
      );
      expect(free.action, 'check');
    });

    test('goes all in with a playable hand once short-stacked', () async {
      final short = await play('rock', at(hand: 'speculative', stack: 240));
      expect(short.action, 'all_in');
      expect((await play('rock', at(hand: 'weak', stack: 240))).action, 'fold');
    });

    test('calls with one pair, raises two pair', () async {
      final pair = await play(
        'rock',
        at(
          street: 'flop',
          board: ['Ks', '7c', '2d'],
          made: 'pair',
          equity: 0.7,
          pot: 120,
          bet: 40,
          toCall: 40,
          raises: 1,
        ),
      );
      expect(pair.action, 'call');
      final two = await play(
        'rock',
        at(
          street: 'flop',
          board: ['Ks', 'Ac', '2d'],
          made: 'two_pair',
          equity: 0.9,
          pot: 120,
          bet: 40,
          toCall: 40,
          raises: 1,
        ),
      );
      expect(two.action, 'raise');
      expect(two.raiseTo, 60); // half the pot
    });
  });

  group('the Maniac', () {
    test('raises almost any hand before the flop, four big blinds', () async {
      final r = await play(
        'maniac',
        at(hole: ['7h', '2d'], hand: 'weak', equity: 0.2),
      );
      expect(r.action, 'raise');
      expect(r.raiseTo, 40);
    });

    test(
      'folds weak cards against two raises only when the coin says so',
      () async {
        final heavy = at(
          hole: ['7h', '2d'],
          hand: 'weak',
          equity: 0.2,
          raises: 2,
          bet: 90,
          toCall: 90,
          pot: 135,
        );
        expect(
          (await play('maniac', {...heavy, 'random': 0.8})).action,
          'fold',
        );
        expect(
          (await play('maniac', {...heavy, 'random': 0.2})).action,
          'raise',
        );
      },
    );

    test('bluffs the pot with nothing when the coin says so and few are left', () async {
      final nothing = at(
        street: 'flop',
        board: ['9s', '7c', '2d'],
        equity: 0.3,
        pot: 60,
        bet: 0,
        toCall: 0,
        minRaise: 10,
        players: 3,
      );
      final bluff = await play('maniac', {...nothing, 'random': 0.1});
      expect(bluff.action, 'raise');
      expect(bluff.raiseTo, 60);
      expect(
        (await play('maniac', {...nothing, 'random': 0.9})).action,
        'check',
      );
      expect(
        (await play('maniac', {...nothing, 'random': 0.1, 'players_in_hand': 5})).action,
        'check',
      );
    });

    test('folds a call that costs its stack without a likely winner', () async {
      final big = at(
        street: 'flop',
        board: ['9s', '7c', '2d'],
        made: 'pair',
        equity: 0.45,
        pot: 400,
        bet: 200,
        toCall: 200,
        raises: 1,
      );
      expect((await play('maniac', big)).action, 'fold');
      expect((await play('maniac', {...big, 'equity': 0.7})).action, 'raise');
    });
  });

  group('the Calling Station', () {
    test(
      'calls before the flop, up to four big blinds with weak cards',
      () async {
        expect((await play('station', at())).action, 'call');
        final ok = at(
          hole: ['7h', '2d'],
          hand: 'weak',
          equity: 0.2,
          raises: 2,
          bet: 40,
          toCall: 40,
          pot: 75,
        );
        expect((await play('station', ok)).action, 'call');
        final tooMuch = at(
          hole: ['7h', '2d'],
          hand: 'weak',
          equity: 0.2,
          raises: 2,
          bet: 41,
          toCall: 41,
          pot: 75,
        );
        expect((await play('station', tooMuch)).action, 'fold');
      },
    );

    test('raises the minimum only with three of a kind or better', () async {
      final r = await play(
        'station',
        at(
          street: 'river',
          hole: ['Ah', '9h'],
          board: ['Kh', '7h', '2d', '3c', 'Th'],
          hand: 'speculative',
          made: 'flush',
          equity: 0.97,
          pot: 400,
          bet: 200,
          toCall: 200,
          raises: 1,
          minRaise: 400,
        ),
      );
      expect(r.action, 'raise');
      expect(r.raiseTo, 400);
    });

    test('folds only when hopeless', () async {
      final r = await play(
        'station',
        at(
          street: 'river',
          board: ['Kh', '7h', '2d', '3c', 'Th'],
          equity: 0.05,
          pot: 400,
          bet: 300,
          toCall: 300,
          raises: 1,
        ),
      );
      expect(r.action, 'fold');
    });

    test('folds a call of a fifth of its stack without an even chance', () async {
      final dear = at(
        street: 'turn',
        board: ['Kh', '7h', '2d', '3c'],
        made: 'pair',
        equity: 0.4,
        pot: 300,
        bet: 200,
        toCall: 200,
        raises: 1,
      );
      expect((await play('station', dear)).action, 'fold');
      expect((await play('station', {...dear, 'to_call': 100, 'pot_odds': 0.25})).action, 'call');
    });
  });

  group('the Mathematician', () {
    test('calls when the equity beats the pot odds, folds when not', () async {
      // Equity 0.3 against pot odds 0.25: call. Against 0.4: fold.
      final cheap = at(
        street: 'turn',
        board: ['Kh', '7h', '2d', '3c'],
        equity: 0.3,
        pot: 120,
        bet: 40,
        toCall: 40,
        raises: 1,
      );
      expect((await play('mathematician', cheap)).action, 'call');
      final dear = at(
        street: 'turn',
        board: ['Kh', '7h', '2d', '3c'],
        equity: 0.3,
        pot: 120,
        bet: 80,
        toCall: 80,
        raises: 1,
      );
      expect((await play('mathematician', dear)).action, 'fold');
    });

    test('raises two thirds of the pot with a big edge', () async {
      final r = await play(
        'mathematician',
        at(
          street: 'flop',
          board: ['Ks', '7c', '2d'],
          made: 'pair',
          equity: 0.78,
          pot: 120,
          bet: 40,
          toCall: 40,
          raises: 1,
        ),
      );
      expect(r.action, 'raise');
      expect(r.raiseTo, 79);
    });

    test('checks a free card without 60% equity', () async {
      final r = await play(
        'mathematician',
        at(
          street: 'flop',
          board: ['9s', '7c', '2d'],
          equity: 0.5,
          pot: 60,
          bet: 0,
          toCall: 0,
        ),
      );
      expect(r.action, 'check');
    });
  });

  group('the Shark', () {
    test(
      'opens medium cards, calls them against a raise with position',
      () async {
        expect((await play('shark', at(hand: 'medium'))).action, 'raise');
        final r = await play(
          'shark',
          at(hand: 'medium', raises: 1, bet: 30, toCall: 30, pot: 45),
        );
        expect(r.action, 'call');
        final early = await play(
          'shark',
          at(
            hand: 'medium',
            position: 'early',
            raises: 1,
            bet: 30,
            toCall: 30,
            pot: 45,
          ),
        );
        expect(early.action, 'fold');
      },
    );

    test('steals from middle or late position four times in five', () async {
      final junk = at(hole: ['9h', '4d'], hand: 'weak', equity: 0.3);
      expect((await play('shark', {...junk, 'random': 0.7})).action, 'raise');
      expect((await play('shark', {...junk, 'random': 0.9})).action, 'fold');
      expect((await play('shark', {...junk, 'position': 'early', 'random': 0.1})).action, 'fold');
    });

    test('plays medium cards harder when the table is short', () async {
      final short = at(hand: 'medium', position: 'early', raises: 1, bet: 30, toCall: 30, pot: 45, players: 3);
      expect((await play('shark', short)).action, 'raise');
    });

    test(
      'semi-bluffs a flush draw when nobody has bet, folds it to a big bet',
      () async {
        final draw = at(
          street: 'turn',
          hole: ['Ah', '9h'],
          board: ['Kh', '7h', '2d', '3c'],
          hand: 'speculative',
          flushDraw: true,
          equity: 0.2,
        );
        final free = await play('shark', {
          ...draw,
          'pot': 200,
          'current_bet': 0,
          'to_call': 0,
          'pot_odds': 0,
          'can_check': true,
          'min_raise': 10,
          'random': 0.9,
        });
        expect(free.action, 'raise');
        final bet = await play('shark', {
          ...draw,
          'pot': 200,
          'current_bet': 100,
          'to_call': 100,
          'pot_odds': 100 / 300,
          'can_check': false,
          'raises': 1,
          'min_raise': 200,
        });
        expect(bet.action, 'fold');
      },
    );
  });
}
