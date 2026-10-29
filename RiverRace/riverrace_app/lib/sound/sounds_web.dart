import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Atari-like sounds, made with Web Audio: a square-wave beep for
/// refueling and a burst of coarse noise, falling in pitch, for an
/// explosion. The browser lets audio start only after a key press or a
/// click, which is how a race starts.
class Sounds {
  web.AudioContext? _context;
  web.AudioBuffer? _noise;

  web.AudioContext get _audio {
    final context = _context ??= web.AudioContext();
    if (context.state == 'suspended') context.resume();
    return context;
  }

  /// A short refueling beep, higher the fuller the tank ([level], 0 to 1).
  void refuel(double level) {
    final audio = _audio;
    final t = audio.currentTime;
    final tone = audio.createOscillator()
      ..type = 'square'
      ..frequency.value = 330 + 660 * level.clamp(0, 1);
    final volume = audio.createGain();
    volume.gain
      ..setValueAtTime(0.06, t)
      ..setValueAtTime(0, t + 0.05);
    tone.connect(volume);
    volume.connect(audio.destination);
    tone
      ..start(t)
      ..stop(t + 0.06);
  }

  /// Something a missile hit blowing up.
  void explosion() {
    final audio = _audio;
    final t = audio.currentTime;
    final source = audio.createBufferSource()..buffer = _noiseIn(audio);
    final filter = audio.createBiquadFilter()..type = 'lowpass';
    filter.frequency
      ..setValueAtTime(3000, t)
      ..exponentialRampToValueAtTime(120, t + 0.45);
    final volume = audio.createGain();
    volume.gain
      ..setValueAtTime(0.35, t)
      ..exponentialRampToValueAtTime(0.001, t + 0.5);
    source.connect(filter);
    filter.connect(volume);
    volume.connect(audio.destination);
    source
      ..start(t)
      ..stop(t + 0.5);
  }

  /// Half a second of noise held for 6 samples at a time, the coarse
  /// grain of the Atari's sound chip.
  web.AudioBuffer _noiseIn(web.AudioContext audio) {
    if (_noise case final noise?) return noise;
    final rate = audio.sampleRate;
    final samples = Float32List((rate / 2).round());
    final random = Random(7);
    for (var i = 0; i < samples.length; i += 6) {
      final v = random.nextDouble() * 2 - 1;
      for (var j = i; j < min(i + 6, samples.length); j++) {
        samples[j] = v;
      }
    }
    final noise = audio.createBuffer(1, samples.length, rate)
      ..copyToChannel(samples.toJS, 0);
    return _noise = noise;
  }
}
