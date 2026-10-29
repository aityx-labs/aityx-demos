import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cellfie_app/life/board.dart';
import 'package:cellfie_app/life/rules.dart';
import 'package:cellfie_app/life/seeds.dart';

import '../tool/catalogue.dart';

void main() {
  test('the model\'s catalogue is what the tool generates', () {
    // So the app's canonical shapes and the model's rows can't drift:
    // `dart run tool/catalogue.dart` rewrites the table.
    final model =
        jsonDecode(File('../cellfie_api/models/life.json').readAsStringSync())
            as Map;
    final functions = (model['decision'] as Map)['functions'] as Map;
    final table = (functions['identify'] as Map)['body'];
    expect(table, catalogueTable());
  });

  test('every seed repeats after its period, and its shapes are distinct', () {
    final shapes = <String, String>{};
    for (final seed in seeds) {
      var cells = cellsOf(seed.shape);
      for (var phase = 0; phase < seed.period; phase++) {
        final shape = canonicalShape(cells);
        expect(
          shapes.putIfAbsent(shape, () => seed.id),
          seed.id,
          reason: '${seed.name} shares a shape with ${shapes[shape]}',
        );
        cells = nextByConway(cells);
      }
      // A methuselah (period 1) is a seed, not a cycle.
      if (seed.period > 1) {
        expect(canonicalShape(cells), canonicalShape(cellsOf(seed.shape)));
      }
    }
  });

  test('the app\'s rules are the model\'s switches', () {
    final model =
        jsonDecode(File('../cellfie_api/models/life.json').readAsStringSync())
            as Map;
    final decision = model['decision'] as Map;
    final switches = ((decision['types'] as Map)['Rules'] as Map).keys;
    expect(switches, [for (final rule in lifeRules) rule.id]);
    // Each is a column of the fate table, and Conway's alone is on.
    final header = (((decision['functions'] as Map)['fate'] as Map)['body'] as List)[0] as List;
    for (final rule in lifeRules) {
      expect(header, contains(rule.id));
    }
    expect(defaultRules, {'conway': true, 'highlife': false, 'no_death': false});
  });
}
