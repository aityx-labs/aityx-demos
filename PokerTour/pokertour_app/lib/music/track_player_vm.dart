import 'package:flutter/foundation.dart';

import 'soundtrack.dart';

/// Off the web: silence.
TrackPlayer trackPlayer() => _Silent();

class _Silent implements TrackPlayer {
  @override
  void play(String asset, double volume, {required VoidCallback onEnded}) {}

  @override
  void setVolume(double volume) {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void dispose() {}
}
