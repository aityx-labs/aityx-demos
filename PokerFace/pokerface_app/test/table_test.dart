import 'package:flutter_test/flutter_test.dart';
import 'package:pokerface_app/aityx/table.dart';

import 'model_files.dart';

/// A situation the table might send: the Shark on the button, facing a
/// bet on the flop with top pair.
Map<String, Object?> situation({Map<String, Object?> over = const {}}) => {
  'street': 'flop',
  'position': 'late',
  'hole': ['Ah', 'Kd'],
  'board': ['Ks', '7c', '2d'],
  'hand': 'strong',
  'made_hand': 'pair',
  'flush_draw': false,
  'straight_draw': 'none',
  'equity': 0.78,
  'pot': 120,
  'current_bet': 40,
  'to_call': 40,
  'pot_odds': 0.25,
  'can_check': false,
  'can_raise': true,
  'raises': 1,
  'stack': 960,
  'big_blind': 10,
  'stack_bb': 96,
  'min_raise': 80,
  'max_raise': 1000,
  'players_in_hand': 3,
  'players_after': 0,
  'random': 0.42,
  ...over,
};

void main() {
  late Models models;
  setUpAll(() async {
    models = await loadModels();
  });

  group('the models', () {
    test('load the table and every preset, in file order', () {
      expect(models.table['inputs'], isA<Map>());
      expect(models.strategies.keys, [
        'maniac',
        'mathematician',
        'rock',
        'shark',
        'station',
      ]);
      for (final s in models.strategies.values) {
        expect(s.name, isNotEmpty, reason: s.id);
        expect(s.tagline, isNotEmpty, reason: s.id);
        expect(s.decisions['action'], isA<Map>(), reason: s.id);
        expect(s.decisions['raise_to'], isA<Map>(), reason: s.id);
      }
    });

    test('declare every input the app checks, and no other', () {
      final declared = (models.table['inputs'] as Map).keys.toSet();
      expect(situationFrom(situation()).keys.toSet(), declared);
    });

    test("every action table's rows test only columns in its header", () {
      for (final s in models.strategies.values) {
        final table = (s.decisions['action'] as Map)['table'] as List;
        final header = (table[0] as List).cast<String>();
        for (final row in table.skip(1)) {
          final when = ((row as Map)['when'] as Map?) ?? const {};
          for (final column in when.keys) {
            expect(header, contains(column), reason: '${s.id}: $row');
          }
          expect(row['why'], isA<String>(), reason: '${s.id}: $row');
        }
        // The last row is the else row.
        expect((table.last as Map)['when'], isNull, reason: s.id);
      }
    });
  });

  group('the strategy of a request', () {
    test("is a preset by id, or the app's own", () {
      expect(models.strategyFrom('shark').name, 'The Shark');
      final own = models.strategyFrom({
        'name': 'Mine',
        'decisions': {
          'action': {'type': 'Action', 'expr': '"call"'},
          'raise_to': {'type': 'number', 'expr': 'min_raise'},
        },
      });
      expect(own.id, 'custom');
      expect(own.name, 'Mine');
    });

    test('is refused when unknown or incomplete', () {
      expect(() => models.strategyFrom('nit'), throwsA(isA<InvalidRequest>()));
      expect(() => models.strategyFrom(null), throwsA(isA<InvalidRequest>()));
      expect(
        () => models.strategyFrom({'name': 'x', 'decisions': {}}),
        throwsA(isA<InvalidRequest>()),
      );
      expect(
        () => models.strategyFrom({
          'name': 'x',
          'decisions': {'action': {}},
        }),
        throwsA(
          isA<InvalidRequest>().having(
            (e) => e.message,
            'message',
            contains('raise_to'),
          ),
        ),
      );
    });
  });

  group('the situation of a request', () {
    test('is kept as sent, with nothing extra', () {
      final s = situationFrom({...situation(), 'extra': 1});
      expect(s, situation());
    });

    test('must have every input', () {
      final missing = situation()..remove('equity');
      expect(
        () => situationFrom(missing),
        throwsA(
          isA<InvalidRequest>().having(
            (e) => e.message,
            'message',
            'situation.equity is required',
          ),
        ),
      );
    });

    test('is checked input by input', () {
      void refuses(Map<String, Object?> over, String message) => expect(
        () => situationFrom(situation(over: over)),
        throwsA(
          isA<InvalidRequest>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
        reason: '$over',
      );
      refuses({'street': 'showdown'}, 'situation.street must be one of');
      refuses({'equity': 1.5}, 'from 0 to 1');
      refuses({'pot': -1}, '0 or more');
      refuses({'raises': 1.5}, 'whole number');
      refuses({'can_check': 'yes'}, 'true or false');
      refuses({
        'hole': ['Ah', '1x'],
      }, 'list of cards');
      refuses({
        'board': ['Ah', 'Kd', 'Qc', 'Js', 'Th', '9d'],
      }, 'list of cards');
      refuses({'big_blind': 0}, 'more than 0');
      refuses({'players_in_hand': 1}, '2 or more');
    });
  });

  group('the aityx call', () {
    test('sends the table model with the strategy and the situation', () {
      final sent = actRequest(models, models.strategies['rock']!, situation());
      final decision = sent['decision'] as Map;
      expect(decision['name'], endsWith('The Rock'));
      expect(decision['inputs'], models.table['inputs']);
      expect(decision['decisions'], models.strategies['rock']!.decisions);
      expect(sent['state'], situation());
    });

    test("reads the action, the amount, and the rule's why", () {
      final sent = actRequest(models, models.strategies['rock']!, situation());
      final action = toAction(sent, {
        'answers': {
          'action': {'type': 'choice', 'choice': 'call'},
          'raise_to': {'type': 'number', 'number': 60},
          'strong_made': {'type': 'noul', 'noul': 0},
        },
        'receipt': {
          'decisions': {
            'action': {'value': 'call', 'rule': 10},
          },
        },
      });
      expect(action['action'], 'call');
      expect(action['raise_to'], 60);
      expect(action['rule'], 10);
      expect(action['why'], startsWith('A pair that is likely best: call'));
      expect(action['decisions'], {'strong_made': 0});
    });

    test('fails on a decision error or a missing answer', () {
      final sent = actRequest(models, models.strategies['rock']!, situation());
      expect(
        () => toAction(sent, {
          'decision_error': {'code': 'invalid_state', 'detail': 'x'},
        }),
        throwsA(
          isA<DecisionFailed>().having(
            (e) => e.message,
            'message',
            contains('invalid_state, x'),
          ),
        ),
      );
      expect(
        () => toAction(sent, {'answers': {}, 'receipt': {}}),
        throwsA(isA<DecisionFailed>()),
      );
    });

    test('is kept for the calls sidebar, unless it contains the key', () {
      final sent = actRequest(models, models.strategies['rock']!, situation());
      final action = {'action': 'fold', 'raise_to': 0};
      final text = '{"answers": {}}';
      final ok = withAityx(action, sent, {}, text, 'secret', tookMs: 12);
      expect(ok['action'], action);
      expect((ok['aityx'] as Map)['took_ms'], 12);
      final leaked = withAityx(action, sent, {}, 'secret', 'secret', tookMs: 1);
      expect(leaked.containsKey('aityx'), isFalse);
    });
  });
}
