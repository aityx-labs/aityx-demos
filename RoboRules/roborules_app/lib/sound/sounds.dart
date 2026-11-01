/// The battle's sounds: synthesized with Web Audio in a browser, silent
/// elsewhere (tests, native builds).
library;

export 'battle_sound.dart';
export 'sounds_silent.dart' if (dart.library.js_interop) 'sounds_web.dart';
