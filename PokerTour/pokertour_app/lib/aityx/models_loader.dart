import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:poker_core/table.dart';

/// Reads the models from the app's assets: table.json and every
/// strategies/*.json, sorted by file name (both folders are listed in
/// pubspec.yaml).
Future<Models> loadModels(AssetBundle bundle) async {
  const folder = Models.folder;
  final table = jsonDecode(await bundle.loadString('$folder/table.json'));
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final files =
      manifest
          .listAssets()
          .where(
            (path) =>
                path.startsWith('$folder/strategies/') &&
                path.endsWith('.json'),
          )
          .toList()
        ..sort();
  final strategies = <String, Object?>{};
  for (final path in files) {
    final name = path.split('/').last;
    final id = name.substring(0, name.length - '.json'.length);
    strategies[id] = jsonDecode(await bundle.loadString(path));
  }
  return Models.fromJson(table, strategies);
}
