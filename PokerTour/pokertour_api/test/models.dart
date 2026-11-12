import 'dart:convert';
import 'dart:io';

import 'package:poker_core/table.dart';

/// The models from the app's assets, as the server reads them.
Future<Models> loadModels([String dir = '../pokertour_app/assets/models']) async {
  final table = jsonDecode(await File('$dir/table.json').readAsString());
  final files = await Directory('$dir/strategies').list().where((f) => f is File && f.path.endsWith('.json')).cast<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return Models.fromJson(table, {
    for (final file in files) file.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''): jsonDecode(await file.readAsString()),
  });
}
