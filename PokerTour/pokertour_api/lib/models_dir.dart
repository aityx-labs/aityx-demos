/// The models from a folder: table.json and strategies/*.json, by file
/// name (the app's assets/models, copied beside the server).
library;

import 'dart:convert';
import 'dart:io';

import 'package:poker_core/table.dart';

Future<Models> loadModelsFrom(Directory dir) async {
  final table = jsonDecode(await File('${dir.path}/table.json').readAsString());
  final files = await Directory('${dir.path}/strategies')
      .list()
      .where((f) => f is File && f.path.endsWith('.json'))
      .cast<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return Models.fromJson(table, {
    for (final file in files)
      file.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''): jsonDecode(await file.readAsString()),
  });
}
