import 'battle_sound.dart';

/// No sound: the battle outside a browser.
class Sounds {
  /// Plays [sound].
  void play(BattleSound sound) {}

  /// Whether the user last turned the sound on or off, if they did.
  bool? get saved => null;

  /// Remembers that the user turned the sound [on] or off.
  void save(bool on) {}
}
