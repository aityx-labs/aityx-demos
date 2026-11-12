import 'package:flutter/services.dart';

import '../aityx/models_loader.dart';
import 'poker_api.dart';

/// The table behind the sign-in: the presets from the app's assets, and
/// no decisions (nobody plays before signing in).
class PreviewPokerApi implements PokerApi {
  PreviewPokerApi({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  @override
  Future<List<Strategy>> strategies() async {
    try {
      return (await loadModels(_bundle)).strategies.values.toList();
    } catch (error) {
      throw ApiException('the models could not be read: $error');
    }
  }

  @override
  Future<ActResult> act(Strategy strategy, Map<String, Object?> situation) =>
      throw ApiException('sign in to play');
}
