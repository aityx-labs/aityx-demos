import 'dart:convert';
import 'dart:io';

import 'package:cellfie_app/aityx/life.dart';
import 'package:flutter_test/flutter_test.dart';

/// A valid request: a glider, a block, a standing blinker and a soup.
Map<String, Object?> body({
  Object? generation = 7,
  Object? situations,
  Object? clusters,
}) => {
  'generation': generation,
  'situations':
      situations ??
      [
        {'alive': true, 'neighbours': 2, 'cells': 9},
        {'alive': false, 'neighbours': 3, 'cells': 4},
      ],
  'clusters':
      clusters ??
      [
        {'cells': 4, 'width': 2, 'height': 2, 'shape': 'oo/oo'},
      ],
};

void main() {
  group('the state', () {
    test('is the generation, the situations and the clusters', () {
      expect(stateFrom(body()), {
        'generation': 7,
        'rules': {'conway': true, 'highlife': false, 'no_death': false},
        'situations': [
          {'alive': true, 'neighbours': 2, 'cells': 9},
          {'alive': false, 'neighbours': 3, 'cells': 4},
        ],
        'clusters': [
          {'cells': 4, 'width': 2, 'height': 2, 'shape': 'oo/oo'},
        ],
      });
    });

    test('needs no clusters, and Conway\'s rules alone when not told', () {
      final state = stateFrom({'generation': 0, 'situations': []});
      expect(state['clusters'], isEmpty);
      expect(state['rules'], {
        'conway': true,
        'highlife': false,
        'no_death': false,
      });
    });

    test('takes the rules that are on, the others as by default', () {
      final state = stateFrom(body()..['rules'] = {'highlife': true});
      expect(state['rules'], {
        'conway': true,
        'highlife': true,
        'no_death': false,
      });
    });

    test('refuses what is not a board', () {
      void refuses(Object? request, String message) {
        expect(
          () => stateFrom(request),
          throwsA(
            isA<InvalidRequest>().having((e) => e.message, 'message', message),
          ),
        );
      }

      refuses('x', 'expected an object');
      refuses(
        body(generation: -1),
        'generation must be a whole number, 0 or more',
      );
      refuses(
        body(generation: 1.5),
        'generation must be a whole number, 0 or more',
      );
      refuses({'generation': 1}, 'situations is required');
      refuses(
        body(
          situations: List.filled(19, {
            'alive': true,
            'neighbours': 1,
            'cells': 1,
          }),
        ),
        'at most 18 situations are distinct',
      );
      refuses(body(situations: [1]), 'situation 0 is not an object');
      refuses(
        body(
          situations: [
            {'alive': 1, 'neighbours': 1, 'cells': 1},
          ],
        ),
        'situation 0: alive must be true or false',
      );
      refuses(
        body(
          situations: [
            {'alive': true, 'neighbours': 9, 'cells': 1},
          ],
        ),
        'situation 0: neighbours must be 0 to 8',
      );
      refuses(
        body(
          situations: [
            {'alive': true, 'neighbours': 1, 'cells': 0},
          ],
        ),
        'situation 0: cells must be 1 or more',
      );
      refuses(
        body(
          situations: [
            {'alive': true, 'neighbours': 1, 'cells': 1},
            {'alive': true, 'neighbours': 1, 'cells': 2},
          ],
        ),
        'situation 1 repeats an earlier one',
      );
      refuses(body()..['rules'] = 'x', 'rules must be an object');
      refuses(body()..['rules'] = {'seeds': true}, 'rules: unknown rule seeds');
      refuses(
        body()..['rules'] = {'conway': 1},
        'rules.conway must be true or false',
      );
      refuses(body(clusters: 'x'), 'clusters must be a list');
      refuses(
        body(
          clusters: List.filled(25, {
            'cells': 1,
            'width': 1,
            'height': 1,
            'shape': 'o',
          }),
        ),
        'at most 24 clusters are described',
      );
      refuses(body(clusters: [1]), 'cluster 0 is not an object');
      refuses(
        body(
          clusters: [
            {'cells': 0, 'width': 1, 'height': 1, 'shape': 'o'},
          ],
        ),
        'cluster 0: cells must be 1 or more',
      );
      refuses(
        body(
          clusters: [
            {'cells': 1, 'width': 65, 'height': 1, 'shape': 'o'},
          ],
        ),
        'cluster 0: width must be 1 to 64',
      );
      refuses(
        body(
          clusters: [
            {'cells': 1, 'width': 1, 'height': 0, 'shape': 'o'},
          ],
        ),
        'cluster 0: height must be 1 to 64',
      );
      refuses(
        body(
          clusters: [
            {'cells': 1, 'width': 1, 'height': 1},
          ],
        ),
        'cluster 0: shape is required',
      );
      // The wrong number of rows, a row of the wrong width, a stray
      // character, and a count that doesn't match.
      for (final shape in ['oo/oo/oo', 'oo/o', 'ox/oo', 'oo/o.']) {
        refuses(
          body(
            clusters: [
              {'cells': 4, 'width': 2, 'height': 2, 'shape': shape},
            ],
          ),
          'cluster 0: shape must be 2 rows of 2 o or ., with 4 o',
        );
      }
    });
  });

  test('the request is the model with the state', () {
    final sent = generationRequest({
      'decision': {'name': 'Life'},
    }, stateFrom(body()));
    expect(sent.keys, ['decision', 'state']);
    expect((sent['state'] as Map)['generation'], 7);
  });

  group('the generation read from aityx\'s answer', () {
    // A real answer, from api.aityx.ai, to generation 7 of a board with a
    // glider, a block, a standing blinker and a five-cell soup.
    final fixture = jsonDecode(
      File('test/fixtures/generation-7.json').readAsStringSync(),
    ) as Map;
    final sent = (fixture['request'] as Map).cast<String, Object?>();
    final answer = (fixture['response'] as Map).cast<String, Object?>();
    final generation = toGeneration(sent, answer);

    test('counts the generations and the cells', () {
      expect(generation['generation'], 7);
      expect(generation['next_generation'], 8);
      expect(generation['population'], 16);
      expect(generation['population_next'], 17);
      expect(generation['births'], 4);
      expect(generation['deaths'], 3);
      expect(generation['survivors'], 13);
    });

    test('gives each situation its fate, the rule and why', () {
      final situations = (generation['situations'] as List).cast<Map>();
      expect(situations, hasLength(7));
      expect(situations[0]['fate'], 'dies_lonely');
      expect(situations[0]['alive_next'], false);
      expect(situations[0]['rule'], 3);
      expect(situations[0]['why'], startsWith('Underpopulation'));
      expect(situations[1]['fate'], 'survives');
      expect(situations[1]['rule'], 4);
      expect(situations[3]['fate'], 'dies_crowded');
      expect(situations[3]['rule'], 5);
      expect(situations[6]['fate'], 'is_born');
      expect(situations[6]['alive_next'], true);
      expect(situations[6]['rule'], 6);
      expect(situations[6]['why'], startsWith('Reproduction'));
      expect(situations[4]['fate'], 'stays_empty');
      expect(situations[4]['rule'], 8);
      // What was sent comes back with it.
      expect(situations[1]['cells'], 9);
    });

    test('names each cluster\'s pattern, with the row that matched', () {
      final clusters = (generation['clusters'] as List).cast<Map>();
      expect(clusters, hasLength(4));
      expect(clusters[0]['pattern'], 'glider');
      expect(clusters[0]['kind'], 'spaceship');
      expect(clusters[0]['why'], startsWith('Glider'));
      expect(
        clusters[0]['about'],
        startsWith('The glider, the smallest spaceship'),
      );
      expect(clusters[0]['shape'], '..o/o.o/.oo');
      expect(clusters[1]['pattern'], 'block');
      expect(clusters[1]['rule'], 1);
      expect(clusters[2]['pattern'], 'blinker');
      expect(clusters[2]['kind'], 'oscillator');
      expect(clusters[3]['pattern'], 'unknown');
      expect(clusters[3]['kind'], 'unknown');
      expect(clusters[3]['about'], startsWith('Not in the catalogue'));
      expect(generation['recognized'], 3);
    });

    test('fails on a decision error, missing answers or wrong lengths', () {
      void fails(Map<String, Object?> answer, String message) {
        expect(
          () => toGeneration(sent, answer),
          throwsA(
            isA<GenerationFailed>().having(
              (e) => e.message,
              'message',
              message,
            ),
          ),
        );
      }

      fails({
        'decision_error': {'code': 'bad'},
      }, 'the Life model failed: bad');
      fails({}, 'no answers');
      fails({'answers': {}, 'receipt': {}}, 'no fates');
      fails({
        'answers': {
          'fates': {
            'value': ['survives'],
          },
        },
        'receipt': {},
      }, 'aityx answered fates for 1 items, not 7');
    });
  });

  test('the answer carries the call unless it holds the key', () {
    final generation = {'generation': 1};
    final sent = {'state': {}};
    final answer = {'answers': {}};
    final text = jsonEncode(answer);
    expect(withAityx(generation, sent, answer, text, 'secret', tookMs: 12), {
      'generation': generation,
      'aityx': {'request': sent, 'response': answer, 'took_ms': 12},
    });
    expect(
      withAityx(generation, sent, answer, 'has secret', 'secret', tookMs: 12),
      {'generation': generation},
    );
  });
}
