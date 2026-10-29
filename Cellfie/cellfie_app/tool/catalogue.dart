/// Writes the pattern catalogue into the Life model
/// (../cellfie_api/models/life.json): the `identify` function's table,
/// one row per phase of each pattern, from the seeds below. Each seed is
/// run by Conway's rules for its period and every phase's canonical shape
/// (lib/life/board.dart, the same code the app uses to describe a
/// cluster) becomes a row; the seeds are in lib/life/seeds.dart, so aityx recognizes a pattern whichever way
/// it's turned and at any point of its cycle.
///
///   dart run tool/catalogue.dart          # rewrites the model's table
///   dart run tool/catalogue.dart --check  # exits 1 if it would change
library;

import 'dart:convert';
import 'dart:io';

import 'package:cellfie_app/life/board.dart';
import 'package:cellfie_app/life/seeds.dart';

/// The catalogue's rows after the header: cells, width, height, shape(s),
/// the pattern, and why.
List<List<String>> catalogueRows() {
  final rows = <List<String>>[];
  for (final seed in seeds) {
    var cells = cellsOf(seed.shape);
    // Every phase's canonical shape, deduplicated: a glider's four phases
    // are two shapes, each the other's mirror image.
    final phases = <String, Set<Cell>>{};
    for (var phase = 0; phase < seed.period; phase++) {
      phases.putIfAbsent(canonicalShape(cells), () => cells);
      cells = nextByConway(cells);
    }
    if (seed.period > 1 &&
        canonicalShape(cells) != canonicalShape(cellsOf(seed.shape))) {
      throw StateError('${seed.name} does not repeat after ${seed.period}');
    }
    // One row per distinct (cells, width, height); the shapes of that size
    // as a comma list.
    final bySize = <(int, int, int), List<String>>{};
    for (final MapEntry(key: shape, value: phaseCells) in phases.entries) {
      final cluster = Cluster(phaseCells);
      (bySize[(
                cluster.cells.length,
                cluster.shapeWidth,
                cluster.shapeHeight,
              )] ??=
              [])
          .add(shape);
    }
    for (final MapEntry(key: (count, width, height), value: shapes)
        in bySize.entries) {
      final phase = phases.length == 1
          ? ''
          : ', ${shapes.length == 1 ? 'one phase' : '${shapes.length} phases'}'
                ' of its ${seed.period}-generation cycle';
      rows.add([
        '$count',
        '$width',
        '$height',
        shapes.map(jsonEncode).join(', '),
        seed.id,
        '${seed.name}$phase.',
      ]);
    }
  }
  return rows;
}

/// The whole `identify` table: the header, the rows, and the else row.
List<List<String>> catalogueTable() => [
  ['cells', 'width', 'height', 'shape', '=>', '# why'],
  ...catalogueRows(),
  ['-', '-', '-', '-', 'unknown', 'Not a pattern in the catalogue.'],
];

Future<void> main(List<String> args) async {
  final file = File('../cellfie_api/models/life.json');
  final model = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  final functions = (model['decision'] as Map)['functions'] as Map;
  final identify = functions['identify'] as Map;
  final table = catalogueTable();
  final changed = jsonEncode(identify['body']) != jsonEncode(table);
  if (args.contains('--check')) {
    stdout.writeln(changed ? 'the catalogue is out of date' : 'up to date');
    exit(changed ? 1 : 0);
  }
  identify['body'] = table;
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(model)}\n',
  );
  stdout.writeln(
    '${table.length - 2} rows for ${seeds.length} patterns '
    '${changed ? 'written' : 'unchanged'} in ${file.path}',
  );
}
