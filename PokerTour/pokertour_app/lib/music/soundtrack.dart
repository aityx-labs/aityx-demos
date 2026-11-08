import 'dart:math';

import 'package:aityx_web/aityx_web.dart' show StorageArea;
import 'package:flutter/foundation.dart';

import 'track_player_vm.dart' if (dart.library.js_interop) 'track_player_web.dart' as impl;

/// Plays one track at a time: the browser's audio element on the web,
/// nothing elsewhere.
abstract class TrackPlayer {
  /// Starts [asset] (a path in the app's assets) at [volume], 0..1; calls
  /// [onEnded] when it has played to the end.
  void play(String asset, double volume, {required VoidCallback onEnded});

  void setVolume(double volume);

  void pause();

  /// Resumes the track paused, or does nothing when there is none.
  void resume();

  void dispose();
}

TrackPlayer defaultTrackPlayer() => impl.trackPlayer();

/// The table's jazz: five soft tracks (assets/music/, made by
/// scripts/jazz.dart) in a random order, round and round, never the same
/// one twice in a row, with a volume and a mute the browser remembers.
class Soundtrack extends ChangeNotifier {
  Soundtrack({required this.storage, TrackPlayer? player, Random? random})
    : _player = player ?? defaultTrackPlayer(),
      _random = random ?? Random() {
    final v = double.tryParse(storage.read(_volumeKey) ?? '');
    if (v != null) volume = v.clamp(0.0, 1.0);
    muted = storage.read(_mutedKey) == 'true';
  }

  static const tracks = [
    'assets/music/1.mp3',
    'assets/music/2.mp3',
    'assets/music/3.mp3',
    'assets/music/4.mp3',
    'assets/music/5.mp3',
  ];

  /// Soft by default: background music.
  static const defaultVolume = 0.3;

  static const _volumeKey = 'pokertour.music.volume';
  static const _mutedKey = 'pokertour.music.muted';

  final StorageArea storage;
  final TrackPlayer _player;
  final Random _random;

  double volume = defaultVolume;
  bool muted = false;

  /// The track playing (or paused by the mute), or null before the first.
  String? current;

  /// The tracks still to play this round, in their order.
  final List<String> _bag = [];

  /// Starts the music, unless muted or started already.
  void start() {
    if (current != null || muted) return;
    _next();
  }

  void _next() {
    if (_bag.isEmpty) {
      _bag.addAll([...tracks]..shuffle(_random));
      // A new round doesn't start with the track that ended the last.
      if (_bag.first == current && _bag.length > 1) _bag.add(_bag.removeAt(0));
    }
    current = _bag.removeAt(0);
    _player.play(current!, volume, onEnded: _next);
    notifyListeners();
  }

  void setVolume(double v) {
    volume = v.clamp(0.0, 1.0);
    _player.setVolume(volume);
    _write(_volumeKey, volume.toStringAsFixed(2));
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    if (muted) {
      _player.pause();
    } else if (current == null) {
      _next();
    } else {
      _player.resume();
    }
    _write(_mutedKey, '$muted');
    notifyListeners();
  }

  void _write(String name, String value) {
    try {
      storage.write(name, value);
    } catch (_) {
      // Storage blocked: the setting lasts this visit.
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
