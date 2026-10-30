/// The models read straight from assets/models/ on disk, for tests that
/// run without Flutter's asset bundle (the aityx-tagged ones need the
/// real network, which the test binding would replace).
library;

import 'dart:convert';
import 'dart:io';

import 'package:pokerface_app/aityx/table.dart';

/// [dir]'s table.json and strategies/*.json, as Models.load reads them
/// from the bundle: the strategies sorted by file name.
Future<Models> loadModels([String dir = 'assets/models']) async {
  final table = jsonDecode(await File('$dir/table.json').readAsString());
  final files =
      await Directory('$dir/strategies')
            .list()
            .where((f) => f is File && f.path.endsWith('.json'))
            .cast<File>()
            .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return Models.fromJson(table, {
    for (final file in files)
      file.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''):
          jsonDecode(await file.readAsString()),
  });
}
