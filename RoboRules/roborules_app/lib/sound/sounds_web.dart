import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'battle_sound.dart';

/// Short, quiet sounds made with Web Audio: a soft low thud for a
/// collision, a small pop of noise for a hit, a bigger boom of falling
/// noise for a robot lost. The browser lets audio start only after a click
/// or a key press, which is how a battle starts; the audio is made on the
/// first sound, and resumed if the browser suspended it.
class Sounds {
  static const _key = 'roborules.sound';

  web.AudioContext? _context;
  web.GainNode? _master;
  web.AudioBuffer? _noise;
  final _random = Random();

  web.AudioContext get _audio {
    final context = _context ??= web.AudioContext();
    if (context.state == 'suspended') context.resume();
    return context;
  }

  /// Everything goes through one quiet volume.
  web.GainNode _out(web.AudioContext audio) {
    if (_master case final master?) return master;
    final master = audio.createGain()..gain.value = 0.6;
    master.connect(audio.destination);
    return _master = master;
  }

  /// Plays [sound]; never fails the battle, whatever the browser does.
  void play(BattleSound sound) {
    try {
      switch (sound) {
        case BattleSound.collision:
          _thud();
        case BattleSound.hit:
          _pop();
        case BattleSound.loss:
          _boom();
      }
    } catch (_) {
      // No audio here: the battle plays on, silent.
    }
  }

  /// A volume that rises fast to [peak] and fades out over [length]
  /// seconds.
  web.GainNode _envelope(
    web.AudioContext audio,
    double t,
    double peak,
    double length,
  ) {
    final volume = audio.createGain();
    volume.gain
      ..setValueAtTime(0.0001, t)
      ..linearRampToValueAtTime(peak, t + 0.005)
      ..exponentialRampToValueAtTime(0.0001, t + length);
    volume.connect(_out(audio));
    return volume;
  }

  /// A soft, low thud: a sine falling from 140 to 50 Hz.
  void _thud() {
    final audio = _audio;
    final t = audio.currentTime;
    final tone = audio.createOscillator()..type = 'sine';
    tone.frequency
      ..setValueAtTime(140, t)
      ..exponentialRampToValueAtTime(50, t + 0.12);
    tone.connect(_envelope(audio, t, 0.25, 0.15));
    tone
      ..start(t)
      ..stop(t + 0.16);
  }

  /// A small pop: a few hundredths of a second of noise around 1.8 kHz.
  void _pop() {
    final audio = _audio;
    final t = audio.currentTime;
    final source = _noiseSource(audio);
    final filter = audio.createBiquadFilter()
      ..type = 'bandpass'
      ..Q.value = 1.2
      ..frequency.value = 1800;
    source.connect(filter);
    filter.connect(_envelope(audio, t, 0.18, 0.07));
    source.start(t, _random.nextDouble() * 0.4, 0.08);
  }

  /// A bigger boom: noise falling in pitch, over a low sine.
  void _boom() {
    final audio = _audio;
    final t = audio.currentTime;
    final source = _noiseSource(audio);
    final filter = audio.createBiquadFilter()..type = 'lowpass';
    filter.frequency
      ..setValueAtTime(1500, t)
      ..exponentialRampToValueAtTime(90, t + 0.55);
    source.connect(filter);
    filter.connect(_envelope(audio, t, 0.3, 0.6));
    source.start(t, 0, 0.6);
    final rumble = audio.createOscillator()..type = 'sine';
    rumble.frequency
      ..setValueAtTime(90, t)
      ..exponentialRampToValueAtTime(35, t + 0.5);
    rumble.connect(_envelope(audio, t, 0.25, 0.5));
    rumble
      ..start(t)
      ..stop(t + 0.52);
  }

  web.AudioBufferSourceNode _noiseSource(web.AudioContext audio) =>
      audio.createBufferSource()..buffer = _noiseIn(audio);

  /// A second of white noise, made once.
  web.AudioBuffer _noiseIn(web.AudioContext audio) {
    if (_noise case final noise?) return noise;
    final rate = audio.sampleRate;
    final samples = Float32List(rate.round());
    final random = Random(7);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = random.nextDouble() * 2 - 1;
    }
    final noise = audio.createBuffer(1, samples.length, rate)
      ..copyToChannel(samples.toJS, 0);
    return _noise = noise;
  }

  /// Whether the user last turned the sound on or off in this browser, if
  /// they did.
  bool? get saved {
    try {
      return switch (web.window.localStorage.getItem(_key)) {
        'on' => true,
        'off' => false,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  /// Remembers in this browser that the user turned the sound [on] or off.
  void save(bool on) {
    try {
      web.window.localStorage.setItem(_key, on ? 'on' : 'off');
    } catch (_) {
      // Storage blocked: the choice lasts until the page is closed.
    }
  }
}
