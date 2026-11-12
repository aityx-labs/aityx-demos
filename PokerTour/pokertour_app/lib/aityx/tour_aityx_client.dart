import 'package:aityx_web/aityx_web.dart';

import 'player_keys.dart';

/// The table's aityx client: always on the connection [keys] gives now
/// (the player's key, else the tour's, through the server's relay on a
/// laptop), so a key set in Profile takes effect at the next decision.
class TourAityxClient extends AityxClient {
  TourAityxClient(this.keys, {super.client});

  final PlayerKeys keys;

  @override
  Future<AityxConnection> connection() => Future.value(keys.connection);
}
