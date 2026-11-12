/// Makes the app's background music: five minimal lo-fi jazz tracks,
/// pokertour_app/assets/music/1.mp3 to 5.mp3, synthesized here from nothing
/// (no samples, no third-party music): a warm FM electric piano on a
/// four-bar loop of extended chords, a round sub bass, a sparse motif on
/// nylon guitar, vibraphone or high keys, dusty boom-bap drums of sines and
/// filtered noise crushed to ten bits, and the whole of it on a wobbling
/// tape, with vinyl hiss and crackle. The notes come from a seeded Random,
/// so every run makes the same tracks. Renders WAV to a temp folder, then
/// encodes MP3 with ffmpeg, which must be on the PATH. Run from PokerTour/:
/// `dart run scripts/jazz.dart`.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const sr = 44100;
const tau = 2 * pi;
const bitrate = '112k';

// ---------------------------------------------------------------- the tunes

const songs = [
  Song(
    title: 'Felt Room, 2 A.M.',
    key: 'D major',
    tonic: 2,
    bpm: 72,
    swing: 0.6,
    seed: 111,
    voice: 'guitar',
    melLo: 62,
    melHi: 79,
    loop: ['Dmaj9', 'Bm9', 'Em9', 'A13sus A13'],
    plan: 'intro4 groove8 theme8 groove8 break4 theme8 outro4',
    end: 'D6/9',
  ),
  Song(
    title: 'Slow Fold',
    key: 'A♭ major',
    tonic: 8,
    bpm: 76,
    swing: 0.58,
    seed: 222,
    voice: 'keys',
    melLo: 68,
    melHi: 84,
    loop: ['Fm9', 'Bbm9', 'Eb13sus Eb13', 'Abmaj9'],
    plan: 'intro4 groove8 theme8 groove8 break4 theme8 outro4',
    end: 'Ab6/9',
  ),
  Song(
    title: 'Pocket Kings',
    key: 'E♭ major',
    tonic: 3,
    bpm: 80,
    swing: 0.62,
    seed: 333,
    voice: 'vibes',
    melLo: 67,
    melHi: 86,
    loop: ['Ebmaj9', 'Abmaj7#11', 'Gm7 C7b9', 'Fm9 Bb13sus'],
    plan: 'intro4 groove8 theme8 groove8 break4 theme8 groove4 outro4',
    end: 'Eb6/9',
  ),
  Song(
    title: 'Rain on the River',
    key: 'A minor',
    tonic: 9,
    minor: true,
    bpm: 70,
    swing: 0.6,
    seed: 444,
    voice: 'guitar',
    melLo: 64,
    melHi: 81,
    loop: ['Am9', 'Dm9', 'Fmaj7#11', 'Bm7b5 E7b9'],
    plan: 'intro4 groove8 theme8 groove8 break4 theme8 outro4',
    end: 'Am6/9',
  ),
  Song(
    title: 'Short Stack Sunday',
    key: 'F major',
    tonic: 5,
    bpm: 84,
    swing: 0.6,
    seed: 555,
    voice: 'vibes',
    melLo: 65,
    melHi: 84,
    loop: ['Bbmaj9', 'Am7 D7b9', 'Gm9', 'C13sus C13'],
    plan: 'intro4 groove8 theme8 groove8 break4 theme8 groove4 outro4',
    end: 'F6/9',
  ),
];

/// A tune: its key's tonic (pitch class) and mode, for the motif's
/// pentatonic scale; the swing of its eighths; the motif's voice
/// ('guitar', 'vibes' or 'keys') and range; the four-bar loop every
/// section plays; and the plan, sections of whole loops: 'intro' (the
/// keys alone, their filter opening), 'groove' (keys, bass, drums),
/// 'theme' (and the motif), 'break' (keys and bass, darker), 'outro'
/// (the keys alone, their filter closing).
class Song {
  const Song({
    required this.title,
    required this.key,
    required this.tonic,
    this.minor = false,
    required this.bpm,
    required this.swing,
    required this.seed,
    required this.voice,
    required this.melLo,
    required this.melHi,
    required this.loop,
    required this.plan,
    required this.end,
  });
  final String title, key, voice, plan, end;
  final int tonic, bpm, seed, melLo, melHi;
  final bool minor;
  final double swing;
  final List<String> loop;
}

// ------------------------------------------------------------------ harmony
// ------------------------------------------------------------------ harmony
class Quality {
  const Quality(this.a, this.b, this.tones, this.scale);

  /// Two rootless voicings (semitones over the root), the chord tones a
  /// melody lands on, and the scale it passes through.
  final List<int> a, b, tones, scale;
}

const _ionian = [0, 2, 4, 5, 7, 9, 11];
const _lydian = [0, 2, 4, 6, 7, 9, 11];
const _dorian = [0, 2, 3, 5, 7, 9, 10];
const _melodic = [0, 2, 3, 5, 7, 9, 11];
const _mixo = [0, 2, 4, 5, 7, 9, 10];
const _phrygDom = [0, 1, 4, 5, 7, 8, 10];
const _altered = [0, 1, 3, 4, 6, 8, 10];
const _locrian2 = [0, 2, 3, 5, 6, 8, 10];
const _sus = [0, 2, 5, 7, 9, 10];
const _m9 = Quality([3, 7, 10, 14], [10, 14, 15, 19], [0, 3, 7, 10, 14], _dorian);

const qualities = {
  'maj9': Quality([4, 7, 11, 14], [11, 14, 16, 19], [0, 4, 7, 11, 14], _ionian),
  'maj7#11': Quality([4, 6, 11, 14], [11, 14, 16, 18], [0, 4, 7, 11, 14, 18], _lydian),
  '6/9': Quality([4, 7, 9, 14], [9, 14, 16, 19], [0, 4, 7, 9, 14], _ionian),
  'm9': _m9,
  'm7': _m9,
  'm6/9': Quality([3, 7, 9, 14], [9, 14, 15, 19], [0, 3, 7, 9, 14], _melodic),
  '13': Quality([10, 14, 16, 21], [4, 9, 10, 14], [0, 4, 7, 10, 14, 21], _mixo),
  '7b9': Quality([4, 7, 10, 13], [10, 13, 16, 19], [0, 4, 7, 10], _phrygDom),
  '7alt': Quality([4, 10, 15, 20], [10, 13, 16, 20], [0, 4, 10, 15, 20], _altered),
  'm7b5': Quality([3, 6, 10, 14], [10, 14, 15, 18], [0, 3, 6, 10], _locrian2),
  '13sus': Quality([5, 10, 14, 21], [10, 14, 17, 21], [0, 5, 7, 10, 14], _sus),
};

class Chord {
  Chord._(this.name, this.root, this.q);
  factory Chord(String name) {
    var root = const {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}[name[0]]!;
    var i = 1;
    if (name.length > 1 && (name[1] == 'b' || name[1] == '#')) {
      root += name[1] == 'b' ? -1 : 1;
      i = 2;
    }
    final q = qualities[name.substring(i)];
    if (q == null) throw ArgumentError('Unknown chord $name');
    return Chord._(name, root % 12, q);
  }
  final String name;
  final int root;
  final Quality q;

  bool has(int midi, List<int> set) => set.any((x) => (midi - root - x) % 12 == 0);
}

/// The rootless voicing of [c] nearest to [prev], kept around middle C.
List<int> voicing(Chord c, List<int>? prev, Random r) {
  List<int>? best;
  var bestScore = double.infinity;
  for (final form in [c.q.a, c.q.b]) {
    for (var base = 24; base <= 72; base += 12) {
      final v = [for (final x in form) base + c.root + x];
      if (v.first < 50 || v.first > 61 || v.last > 77) continue;
      final center = v.reduce((a, b) => a + b) / v.length;
      var score = (center - 62).abs() * (prev == null ? 1 : 0.35) + r.nextDouble() * 0.8;
      if (prev != null) {
        for (var i = 0; i < v.length; i++) {
          score += (v[i] - prev[i]).abs();
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = v;
      }
    }
  }
  return best!;
}

T pick<T>(List<T> xs, List<double> ws, Random r) {
  var x = r.nextDouble() * ws.fold(0.0, (a, b) => a + b);
  for (var i = 0; i < xs.length; i++) {
    x -= ws[i];
    if (x <= 0) return xs[i];
  }
  return xs.last;
}

double gauss(Random r) => sqrt(-2 * log(max(1e-12, r.nextDouble()))) * cos(tau * r.nextDouble());

double mtof(int m) => 440 * pow(2, (m - 69) / 12).toDouble();

// -------------------------------------------------------------- arrangement

/// One chord of the plan: where it starts and for how long (beats), its
/// section and bar, and its place in the loop ('bar/chord'), which keeps
/// the keys and the bass the same every time round.
class Span {
  Span(this.beat, this.beats, this.chord, this.sec, this.bar, this.slot);
  final double beat, beats;
  final Chord chord;
  final int sec, bar;
  final String slot;
}

class Sec {
  Sec(this.kind, this.beat, this.bars);
  final String kind;
  final double beat;
  final int bars;

  bool get bass => kind != 'intro' && kind != 'outro';
  bool get drums => kind == 'groove' || kind == 'theme';
  bool get lead => kind == 'theme';
}

/// A note: start and length in seconds, MIDI pitch, velocity 0..1.
class Ev {
  Ev(this.t, this.dur, this.midi, this.vel);
  final double t, dur, vel;
  final int midi;
}

class Hit {
  Hit(this.kind, this.t, this.vel);
  final String kind;
  final double t, vel;
}

typedef N = ({double off, double dur, int midi, double vel});

/// The notes of one tune: keys, bass, motif and drums, in seconds.
class Arrangement {
  Arrangement(this.s) : endChord = Chord(s.end) {
    var beat = 0.0;
    for (final word in s.plan.split(' ')) {
      final m = RegExp(r'^([a-z]+)(\d+)$').firstMatch(word)!;
      secs.add(Sec(m[1]!, beat, int.parse(m[2]!)));
      for (var b = 0; b < secs.last.bars; b++) {
        final li = b % s.loop.length;
        final names = s.loop[li].split(' ');
        for (var k = 0; k < names.length; k++) {
          spans.add(Span(beat, 4 / names.length, Chord(names[k]), secs.length - 1, b, '$li/$k'));
          beat += 4 / names.length;
        }
      }
    }
    endBeat = beat;
    _keys(Random(s.seed));
    _bass(Random(s.seed + 1));
    _lead(Random(s.seed + 2));
    _drums(Random(s.seed + 3));
  }

  final Song s;
  final Chord endChord;
  final spans = <Span>[];
  final secs = <Sec>[];
  late final double endBeat;
  final keys = <Ev>[], bass = <Ev>[], lead = <Ev>[];
  final hits = <Hit>[];

  /// Seconds at [beat], swung eighths included, after a short lead-in.
  double time(double beat) {
    final w = beat.floorToDouble(), f = beat - w;
    final g = f < 0.5 ? f * 2 * s.swing : s.swing + (f - 0.5) * 2 * (1 - s.swing);
    return 0.3 + (w + g) * 60 / s.bpm;
  }

  double get endTime => time(endBeat);

  /// The keys' lowpass at [t] seconds: it opens through the intro, dims in
  /// the break and closes through the outro.
  double keysCut(double t) {
    const open = 4500.0, shut = 450.0;
    for (final sec in secs) {
      final t0 = time(sec.beat), t1 = time(sec.beat + sec.bars * 4);
      if (t >= t1) continue;
      final x = max(0.0, (t - t0) / (t1 - t0));
      return switch (sec.kind) {
        'intro' => 500 * pow(open / 500, x).toDouble(),
        'break' => 1100.0,
        'outro' => open * pow(shut / open, x).toDouble(),
        _ => open,
      };
    }
    return shut;
  }

  /// The loop's chord [off] beats into it.
  Chord loopChord(double off) {
    final names = s.loop[(off ~/ 4) % s.loop.length].split(' ');
    return Chord(names[min(names.length - 1, ((off % 4) / (4 / names.length)).floor())]);
  }

  // Electric piano: a voicing and a rhythm for each place in the loop,
  // chosen once, so the loop is the same each time round; held whole where
  // the drums rest. Laid back a little, each chord softly rolled.
  void _keys(Random r) {
    final voiced = <String, List<int>>{};
    List<int>? prev;
    // Twice round, so the last chord's voicing leads back into the first.
    for (var pass = 0; pass < 2; pass++) {
      for (var li = 0; li < s.loop.length; li++) {
        final names = s.loop[li].split(' ');
        for (var k = 0; k < names.length; k++) {
          prev = voiced['$li/$k'] = voicing(Chord(names[k]), prev, r);
        }
      }
    }
    final rhythm = <String, List<List<double>>>{};
    for (final sp in spans) {
      final sec = secs[sp.sec];
      final v = voiced[sp.slot]!;
      final hits = sec.drums ? rhythm.putIfAbsent(sp.slot, () => _pattern(sp.beats, r)) : [[0.0, sp.beats - 0.1]];
      for (final h in hits) {
        final t0 = time(sp.beat + h[0]) + 0.022 + 0.006 * gauss(r);
        final t1 = time(sp.beat + h[0] + h[1]) + 0.022;
        final vel = 0.46 * (h[0] == 0 ? 1.0 : 0.85) * (1 + 0.06 * gauss(r));
        for (var k = 0; k < v.length; k++) {
          final t = t0 + k * 0.016 * (0.6 + 0.8 * r.nextDouble());
          final top = k == v.length - 1 ? 1.08 : 1.0;
          keys.add(Ev(t, max(0.1, t1 - t), v[k], vel * (0.9 + 0.15 * r.nextDouble()) * top));
        }
      }
    }
    final v = voicing(endChord, prev, r);
    for (var k = 0; k < v.length; k++) {
      keys.add(Ev(endTime + 0.03 + 0.03 * k, 5.0, v[k], 0.4));
    }
  }

  List<List<double>> _pattern(double beats, Random r) {
    final opts = beats >= 4
        ? [
            [[0.0, 3.8]],
            [[0.0, 3.8]],
            [[0.0, 2.4], [2.5, 1.35]],
            [[0.0, 1.4], [1.5, 2.3]],
            [[0.0, 3.0], [3.5, 0.4]],
          ]
        : [
            [[0.0, 1.9]],
            [[0.0, 1.9]],
            [[0.0, 0.9], [1.5, 0.45]],
          ];
    return opts[r.nextInt(opts.length)];
  }

  // Bass: the root on the one, held; now and then the fifth or the octave
  // later in the bar, and a step into the next chord. Chosen once for each
  // place in the loop, like the keys.
  static const bLo = 28, bHi = 45;

  int near(int pc, int ref) {
    var best = -1;
    for (var m = bLo; m <= bHi; m++) {
      if ((m - pc) % 12 == 0 && (best < 0 || (m - ref).abs() < (best - ref).abs())) best = m;
    }
    return best;
  }

  void _bass(Random r) {
    final lines = <String, List<(double, double, int)>>{};
    for (var i = 0; i < spans.length; i++) {
      final sp = spans[i];
      if (!secs[sp.sec].bass) continue;
      final next = i + 1 < spans.length ? spans[i + 1].chord : endChord;
      final line = lines.putIfAbsent(sp.slot, () {
        final ch = sp.chord;
        final root = near(ch.root, 36);
        if (sp.beats < 4) return [(0.0, sp.beats - 0.2, root)];
        final fifth = near((ch.root + 7) % 12, root);
        final second = r.nextBool() || root + 12 > 50 ? fifth : root + 12;
        final x = r.nextDouble();
        var notes = x < 0.4
            ? [(0.0, 2.2, root), (2.5, 1.2, second)]
            : x < 0.7
                ? [(0.0, 3.6, root)]
                : [(0.0, 1.6, root), (2.0, 1.8, second)];
        if (next.root != ch.root && r.nextDouble() < 0.35) {
          final step = near(next.root, root) + (r.nextBool() ? 1 : -1);
          notes = [
            for (final (o, d, m) in notes) (o, min(d, 3.4 - o), m),
            (3.5, 0.45, min(max(step, bLo), 50)),
          ];
        }
        return notes;
      });
      for (final (b, d, m) in line) {
        final t = time(sp.beat + b) + 0.01 + 0.004 * gauss(r);
        bass.add(Ev(t, time(sp.beat + b + d) - t, m, 0.75 * (b == 0 ? 1.0 : 0.85) * (1 + 0.05 * gauss(r))));
      }
    }
    bass.add(Ev(endTime, 4.5, near(endChord.root, 33), 0.65));
  }

  // The motif: four bars of a few notes from the key's pentatonic scale
  // (the long ones on the chord's tones), then its answer, the same rhythm
  // with a new ending; each theme plays the pair, round and round.
  void _lead(Random r) {
    final call = _phrase(null, r);
    final answer = _phrase(call, r);
    for (final sec in secs) {
      if (!sec.lead) continue;
      for (var bar = 0; bar < sec.bars; bar += 4) {
        for (final n in (bar ~/ 4).isEven ? call : answer) {
          final beat = sec.beat + bar * 4 + n.off;
          final t = time(beat) + 0.03 + 0.008 * gauss(r);
          lead.add(Ev(t, max(0.15, time(beat + n.dur) - t), n.midi, n.vel * (1 + 0.05 * gauss(r))));
        }
      }
    }
  }

  List<N> _phrase(List<N>? call, Random r) {
    final pent = s.minor ? const [0, 3, 5, 7, 10] : const [0, 2, 4, 7, 9];
    final rhythm = call == null ? _rhythm(r) : [for (final n in call) (n.off, n.dur)];
    final keep = call == null ? 0 : max(1, call.length - 2);
    final out = <N>[];
    var p = call?.first.midi ?? (s.melLo + s.melHi) ~/ 2;
    for (var i = 0; i < rhythm.length; i++) {
      if (i < keep) {
        out.add(call![i]);
        p = call[i].midi;
        continue;
      }
      final (off, dur) = rhythm[i];
      final c = loopChord(off);
      final last = i == rhythm.length - 1;
      final long = dur >= 1.4 || last;
      final ms = <int>[], ws = <double>[];
      for (var m = s.melLo; m <= s.melHi; m++) {
        final tone = c.has(m, c.q.tones);
        if (long ? !tone : !pent.contains((m - s.tonic) % 12)) continue;
        final d = (m - p).abs();
        var w = exp(-d / 2.2) * (tone ? 2.0 : 1.0);
        if (d == 0) w *= 0.3;
        if (d > 7) w *= 0.1;
        // The answer comes to rest low.
        if (last && call != null) w *= exp(-(m - s.melLo) / 6);
        ms.add(m);
        ws.add(w);
      }
      if (ms.isEmpty) continue;
      p = pick(ms, ws, r);
      out.add((off: off, dur: dur, midi: p, vel: 0.5 + (long ? 0.04 : 0) + 0.03 * gauss(r)));
    }
    return out;
  }

  /// The motif's rhythm in beats over four bars: a cell or a rest in each of
  /// the first three bars, a long note or silence in the fourth.
  List<(double, double)> _rhythm(Random r) {
    const cells = <List<(double, double)>>[
      [(0.0, 1.5)],
      [(0.5, 0.9), (1.5, 2.0)],
      [(1.0, 0.45), (1.5, 2.2)],
      [(2.0, 1.6)],
      [(0.0, 0.45), (0.5, 0.45), (1.0, 2.4)],
      [(2.5, 0.45), (3.0, 0.9)],
      [],
    ];
    while (true) {
      final out = <(double, double)>[];
      for (var bar = 0; bar < 3; bar++) {
        for (final (o, d) in cells[r.nextInt(cells.length)]) {
          out.add((bar * 4 + o, d));
        }
      }
      if (r.nextDouble() < 0.7) out.add((12.0, 2.5 + r.nextDouble()));
      if (out.length >= 3 && out.length <= 7) return out;
    }
  }

  // Boom-bap, lazy: a kick pattern for the tune, the snare late on two and
  // four, swung hats; a pickup kick some fourth bars, a ghost snare now and
  // then, an eighth bar's last hats left out.
  void _drums(Random r) {
    const kicks = <List<(double, double)>>[
      [(0.0, 1.0), (2.5, 0.75)],
      [(0.0, 1.0), (1.75, 0.5), (2.5, 0.75)],
      [(0.0, 1.0), (2.0, 0.6), (2.75, 0.55)],
    ];
    final kick = kicks[r.nextInt(kicks.length)];
    for (final sec in secs) {
      if (!sec.drums) continue;
      for (var bar = 0; bar < sec.bars; bar++) {
        final b0 = sec.beat + bar * 4;
        void hit(String kind, double beat, double vel, [double late = 0]) {
          hits.add(Hit(kind, time(b0 + beat) + late + 0.004 * gauss(r), vel * (1 + 0.08 * gauss(r))));
        }

        for (final (b, v) in kick) {
          hit('kick', b, v);
        }
        if (bar % 4 == 3 && r.nextDouble() < 0.6) hit('kick', 3.5, 0.45);
        hit('snare', 1, 0.8, 0.018);
        hit('snare', 3, 0.85, 0.018);
        if (r.nextDouble() < 0.25) hit('snare', 3.75, 0.2, 0.01);
        for (var k = 0; k < 8; k++) {
          if (bar % 8 == 7 && k >= 6) continue;
          if (r.nextDouble() < 0.06) continue;
          hit('hat', k * 0.5, k.isEven ? 0.6 : 0.38);
        }
      }
    }
  }
}

// -------------------------------------------------------------- instruments

double _tail(int i, int n) => min(1.0, (n - i) / (0.02 * sr));

/// Electric piano, mellow: 1:1 FM with a low index that falls after the
/// strike, a faint tine, soft attack, two-stage decay.
void rhodesNote(Float64List out, Ev e) {
  final f = mtof(e.midi), v = e.vel;
  final decay = (3.2 * pow(220 / f, 0.5)).clamp(0.8, 6.0);
  final start = (e.t * sr).round();
  final n = ((e.dur + 0.9) * sr).round();
  final w = tau * f / sr;
  final level = v * pow(261.6 / f, 0.2);
  for (var i = 0; i < n; i++) {
    final j = start + i;
    if (j < 0) continue;
    if (j >= out.length) break;
    final t = i / sr;
    var env = (1 - exp(-t / 0.006)) * (0.7 * exp(-t / decay) + 0.3 * exp(-t / 0.3));
    if (t > e.dur) env *= exp(-(t - e.dur) / 0.15);
    final idx = v * (0.5 + 1.4 * exp(-t / 0.25));
    final ph = w * i;
    final x = sin(ph + idx * sin(ph)) + 0.15 * v * exp(-t / 0.03) * sin(ph * 7);
    out[j] += level * env * x * _tail(i, n);
  }
}

/// Vibraphone: the bar's 1 : 4 : 10 modes, a slow motor tremolo, damper.
void vibesNote(Float64List out, Ev e) {
  final f = mtof(e.midi), v = e.vel;
  final decay = (3.5 * pow(440 / f, 0.4)).clamp(1.0, 6.0);
  final start = (e.t * sr).round();
  final n = ((e.dur + 1.2) * sr).round();
  final w = tau * f / sr;
  for (var i = 0; i < n; i++) {
    final j = start + i;
    if (j < 0) continue;
    if (j >= out.length) break;
    final t = i / sr;
    final ph = w * i;
    final x = exp(-t / decay) * sin(ph) +
        0.15 * v * exp(-t / 0.25) * sin(ph * 3.97) +
        0.03 * v * exp(-t / 0.05) * sin(ph * 9.8);
    final trem = 1 - 0.15 * (0.5 + 0.5 * sin(tau * 4.0 * (e.t + t)));
    var env = (1 - exp(-t / 0.003)) * trem;
    if (t > e.dur) env *= exp(-(t - e.dur) / 0.2);
    out[j] += v * env * x * _tail(i, n);
  }
}

/// Nylon guitar: a plucked string (Karplus–Strong, tuned with a fractional
/// delay), plucked softly with the thumb near the soundhole.
void guitarNote(Float64List out, Ev e, Random r) {
  final f = mtof(e.midi), v = e.vel;
  final start = (e.t * sr).round();
  final n = ((e.dur + 0.4) * sr).round();
  final period = sr / f;
  // The loop's two-point average delays half a sample.
  final d = period - 0.5, di = d.floor(), fr = d - di;
  final t60 = (3.0 * pow(200 / f, 0.3)).clamp(1.0, 4.0);
  final g = pow(0.001, 1 / (t60 * f)).toDouble();
  final pluck = Biquad.lowpass(1200 + 1800 * v);
  final exc = Float64List(period.ceil());
  for (var i = 0; i < exc.length; i++) {
    exc[i] = pluck.process(r.nextDouble() * 2 - 1);
  }
  // The pluck's position: a fifth of the way along the string.
  final pos = (period * 0.2).round();
  final y = Float64List(n);
  double at(int k) => k < 0 ? 0 : y[k];
  for (var i = 0; i < n; i++) {
    final x = (i < exc.length ? exc[i] : 0) - (i >= pos && i - pos < exc.length ? exc[i - pos] : 0);
    final a = (1 - fr) * at(i - di) + fr * at(i - di - 1);
    final b = (1 - fr) * at(i - di - 1) + fr * at(i - di - 2);
    y[i] = x + g * 0.5 * (a + b);
  }
  for (var i = 0; i < n; i++) {
    final j = start + i;
    if (j < 0) continue;
    if (j >= out.length) break;
    final t = i / sr;
    var env = 1.0;
    if (t > e.dur) env = exp(-(t - e.dur) / 0.1);
    out[j] += v * env * y[i] * _tail(i, n);
  }
}

/// Sub bass: a sine with a little second and third harmonic, a soft attack
/// and a slow fall, like a muted electric bass.
void bassNote(Float64List out, Ev e) {
  final f = mtof(e.midi), v = e.vel;
  final start = (e.t * sr).round();
  final n = ((e.dur + 0.25) * sr).round();
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final j = start + i;
    if (j >= out.length) break;
    final t = i / sr;
    phase += tau * f / sr;
    final x = sin(phase) + 0.22 * exp(-t / 0.4) * sin(2 * phase) + 0.06 * exp(-t / 0.15) * sin(3 * phase);
    var g = (1 - exp(-t / 0.008)) * (0.55 + 0.45 * exp(-t / 0.9));
    if (t > e.dur) g *= exp(-(t - e.dur) / 0.06);
    if (j >= 0) out[j] += v * g * x * _tail(i, n);
  }
}

const _kinds = ['kick', 'snare', 'hat'];
const _gain = {'kick': 1.0, 'snare': 0.9, 'hat': 0.35};
const _pan = {'kick': 0.0, 'snare': -0.08, 'hat': 0.3};

/// One drum sound, peak 1, made of sines and filtered noise.
Float64List makeDrum(String kind, Random r) {
  double nz() => r.nextDouble() * 2 - 1;
  final secs = switch (kind) { 'kick' => 0.45, 'snare' => 0.3, _ => 0.06 };
  final n = (secs * sr).round();
  final x = Float64List(n);
  switch (kind) {
    case 'kick':
      // A sine falling from 110 to 48 Hz, a soft beater.
      final lp = Biquad.lowpass(900);
      var ph = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        ph += tau * (48 + 62 * exp(-t / 0.035)) / sr;
        x[i] = sin(ph) * exp(-t / 0.22) * (1 - exp(-t / 0.0015)) + 0.25 * lp.process(nz()) * exp(-t / 0.004);
      }
    case 'snare':
      // A dusty snare: a short tone for the shell, filtered noise for the
      // wires, and a longer, darker tail.
      final bp = Biquad.bandpass(1900, 0.7), lp = Biquad.lowpass(3500);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        x[i] = (0.5 * sin(tau * 185 * t) * exp(-t / 0.04) +
                bp.process(nz()) * exp(-t / 0.05) +
                0.35 * lp.process(nz()) * exp(-t / 0.12)) *
            (1 - exp(-t / 0.001));
      }
    default: // a closed hat
      final hp = Biquad.highpass(3500), lp = Biquad.lowpass(9000);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        x[i] = lp.process(hp.process(nz())) * (1 - exp(-t / 0.0008)) * exp(-t / 0.018);
      }
  }
  var peak = 1e-9;
  for (var i = 0; i < n; i++) {
    peak = max(peak, x[i].abs());
  }
  for (var i = 0; i < n; i++) {
    x[i] = x[i] / peak * _tail(i, n);
  }
  return x;
}

// ------------------------------------------------------------------ the mix

class Buf {
  Buf(int n)
      : l = Float64List(n),
        r = Float64List(n);
  final Float64List l, r;
  int get length => l.length;
}

class Biquad {
  Biquad._(String type, double f, double q) {
    final w = tau * f / sr, c = cos(w), al = sin(w) / (2 * q);
    final double n0, n1, n2;
    switch (type) {
      case 'lp':
        n0 = (1 - c) / 2;
        n1 = 1 - c;
        n2 = n0;
      case 'hp':
        n0 = (1 + c) / 2;
        n1 = -(1 + c);
        n2 = n0;
      default:
        n0 = al;
        n1 = 0;
        n2 = -al;
    }
    final a0 = 1 + al;
    b0 = n0 / a0;
    b1 = n1 / a0;
    b2 = n2 / a0;
    a1 = -2 * c / a0;
    a2 = (1 - al) / a0;
  }
  Biquad.lowpass(double f, [double q = 0.7071]) : this._('lp', f, q);
  Biquad.highpass(double f, [double q = 0.7071]) : this._('hp', f, q);
  Biquad.bandpass(double f, [double q = 0.7071]) : this._('bp', f, q);

  late final double b0, b1, b2, a1, a2;
  double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

  double process(double x) {
    final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    return y;
  }

  void run(Float64List d) {
    for (var i = 0; i < d.length; i++) {
      d[i] = process(d[i]);
    }
  }
}

class _Comb {
  _Comb(int n) : buf = Float64List(n);
  final Float64List buf;
  int i = 0;
  double store = 0;
  double process(double x) {
    final y = buf[i];
    store = y * 0.65 + store * 0.35;
    buf[i] = x + store * 0.84;
    if (++i == buf.length) i = 0;
    return y;
  }
}

class _AllPass {
  _AllPass(int n) : buf = Float64List(n);
  final Float64List buf;
  int i = 0;
  double process(double x) {
    final b = buf[i];
    buf[i] = x + b * 0.5;
    if (++i == buf.length) i = 0;
    return b - x;
  }
}

/// A Freeverb-style room, darker than the original.
Buf reverb(Float64List x) {
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  const passes = [556, 441, 341, 225];
  final out = Buf(x.length);
  for (var ch = 0; ch < 2; ch++) {
    final cs = [for (final c in combs) _Comb(c + 23 * ch)];
    final ps = [for (final a in passes) _AllPass(a + 23 * ch)];
    final y = ch == 0 ? out.l : out.r;
    final lp = Biquad.lowpass(5500);
    for (var i = 0; i < x.length; i++) {
      var s = 0.0;
      for (final c in cs) {
        s += c.process(x[i]);
      }
      for (final p in ps) {
        s = p.process(s);
      }
      y[i] = lp.process(s);
    }
  }
  return out;
}

/// RMS over the 50 ms windows that are not silent.
double activeRms(List<Float64List> chans) {
  const w = 2205;
  var sum = 0.0, count = 0;
  for (var s = 0; s + w <= chans.first.length; s += w) {
    var ms = 0.0;
    for (final c in chans) {
      for (var i = s; i < s + w; i++) {
        ms += c[i] * c[i];
      }
    }
    ms /= w * chans.length;
    if (ms > 1e-7) {
      sum += ms;
      count++;
    }
  }
  return count == 0 ? 1e-9 : sqrt(sum / count);
}

double db(double x) => 20 * log(x) / ln10;
double undb(double d) => pow(10, d / 20).toDouble();

void scaleTo(List<Float64List> chans, double dbfs) {
  final g = undb(dbfs) / activeRms(chans);
  for (final c in chans) {
    for (var i = 0; i < c.length; i++) {
      c[i] *= g;
    }
  }
}

(double, double) panGains(double p) => (cos((p + 1) * pi / 4), sin((p + 1) * pi / 4));

class Rendered {
  Rendered(this.mix, this.rms, this.peak);
  final Buf mix;
  final double rms, peak;
}

/// [x] at a fractional index, 0 outside it.
double _at(Float64List x, double p) {
  final j = p.floor(), f = p - j;
  double v(int k) => k < 0 || k >= x.length ? 0 : x[k];
  return v(j) * (1 - f) + v(j + 1) * f;
}

/// Vinyl under the music: a low hiss, soft crackle, now and then a pop.
Float64List vinyl(int len, Random r) {
  double nz() => r.nextDouble() * 2 - 1;
  final hiss = Float64List(len), crackle = Float64List(len), pops = Float64List(len);
  final hp = Biquad.highpass(500), lp = Biquad.lowpass(4500);
  final bp = Biquad.bandpass(2200, 0.6), popLp = Biquad.lowpass(600);
  for (var i = 0; i < len; i++) {
    hiss[i] = lp.process(hp.process(nz()));
    final click = r.nextDouble() < 5 / sr ? pow(r.nextDouble(), 3) * nz().sign : 0.0;
    crackle[i] = bp.process(click.toDouble());
    pops[i] = popLp.process(r.nextDouble() < 0.2 / sr ? nz().sign : 0.0);
  }
  scaleTo([hiss], -54);
  for (final (x, ceiling) in [(crackle, -34.0), (pops, -30.0)]) {
    var peak = 1e-9;
    for (var i = 0; i < len; i++) {
      peak = max(peak, x[i].abs());
    }
    final g = undb(ceiling) / peak;
    for (var i = 0; i < len; i++) {
      hiss[i] += x[i] * g;
    }
  }
  return hiss;
}

Rendered render(Song s) {
  final a = Arrangement(s);
  final total = a.endTime + 6.0;
  final len = (total * sr).round();
  final ky = Float64List(len), ld = Float64List(len), bs = Float64List(len);
  final dr = Buf(len);
  final r = Random(s.seed + 4);

  for (final e in a.keys) {
    rhodesNote(ky, e);
  }
  for (final e in a.lead) {
    switch (s.voice) {
      case 'guitar':
        guitarNote(ld, e, r);
      case 'vibes':
        vibesNote(ld, e);
      default:
        rhodesNote(ld, e);
    }
  }
  for (final e in a.bass) {
    bassNote(bs, e);
  }
  final cache = <String, Float64List>{};
  for (final h in a.hits) {
    final variant = r.nextInt(3);
    final x = cache['${h.kind}/$variant'] ??=
        makeDrum(h.kind, Random(s.seed * 7 + _kinds.indexOf(h.kind) * 1009 + variant * 7919));
    final (gl, gr) = panGains(_pan[h.kind]!);
    final g = h.vel * _gain[h.kind]!;
    final start = (h.t * sr).round();
    for (var i = 0; i < x.length; i++) {
      final j = start + i;
      if (j < 0) continue;
      if (j >= len) break;
      dr.l[j] += x[i] * g * gl;
      dr.r[j] += x[i] * g * gr;
    }
  }

  // The drums crushed (every other sample held, ten bits) and dulled.
  for (final c in [dr.l, dr.r]) {
    var peak = 1e-9;
    for (var i = 0; i < len; i++) {
      peak = max(peak, c[i].abs());
    }
    final q = peak / 512;
    for (var i = 0; i < len; i++) {
      c[i] = ((i.isOdd ? c[i - 1] : c[i]) / q).round() * q;
    }
    Biquad.highpass(45).run(c);
    Biquad.lowpass(7000).run(c);
  }

  // The keys through their lowpass, which follows the sections.
  Biquad.highpass(120).run(ky);
  var y1 = 0.0, y2 = 0.0, alpha = 0.0;
  for (var i = 0; i < len; i++) {
    if (i % 64 == 0) alpha = 1 - exp(-tau * a.keysCut(i / sr) / sr);
    y1 += alpha * (ky[i] - y1);
    y2 += alpha * (y1 - y2);
    ky[i] = y2;
  }
  Biquad.highpass(180).run(ld);
  Biquad.lowpass(s.voice == 'vibes' ? 4200 : 3200, 0.6).run(ld);
  Biquad.highpass(35).run(bs);
  Biquad.lowpass(500).run(bs);
  scaleTo([ky], -21.0);
  scaleTo([ld], -24.0);
  scaleTo([bs], -23.0);
  scaleTo([dr.l, dr.r], -28.0);

  // The kick pumps the rest a little.
  final duck = Float64List(len)..fillRange(0, len, 1.0);
  final pump = (0.4 * sr).round();
  for (final h in a.hits) {
    if (h.kind != 'kick') continue;
    final start = (h.t * sr).round();
    for (var i = 0; i < pump && start + i < len; i++) {
      if (start + i < 0) continue;
      final d = 1 - 0.22 * h.vel * (1 - exp(-i / 220)) * exp(-i / (0.12 * sr));
      duck[start + i] = min(duck[start + i], d);
    }
  }

  final mix = Buf(len);
  final send = Float64List(len);
  final pre = (0.02 * sr).round();
  final (ll, lr) = panGains(0.22);
  for (var i = 0; i < len; i++) {
    final (kl, kr) = panGains(-0.08 + 0.1 * sin(tau * 0.07 * i / sr));
    final k = ky[i] * duck[i], l = ld[i] * duck[i], b = bs[i] * duck[i] * sqrt1_2;
    mix.l[i] = k * kl + l * ll + b + dr.l[i];
    mix.r[i] = k * kr + l * lr + b + dr.r[i];
    if (i + pre < len) send[i + pre] = k * 0.4 + l * 0.55 + (dr.l[i] + dr.r[i]) * 0.08;
  }
  final wet = reverb(send);
  final wetGain = undb(-11) * activeRms([mix.l, mix.r]) / activeRms([wet.l, wet.r]);
  for (var i = 0; i < len; i++) {
    mix.l[i] += wet.l[i] * wetGain;
    mix.r[i] += wet.r[i] * wetGain;
  }

  // Tape: the whole of it read back through a wobbling delay, a slow wow
  // and a faint flutter, about ten cents at the most.
  final tape = Buf(len);
  final wr = Random(s.seed + 6);
  final ph1 = tau * wr.nextDouble(), ph2 = tau * wr.nextDouble();
  for (var i = 0; i < len; i++) {
    final t = i / sr;
    final d = 0.006 +
        0.0014 * sin(tau * 0.43 * t + ph1) +
        0.0006 * sin(tau * 0.13 * t + ph2) +
        0.00005 * sin(tau * 5.3 * t);
    tape.l[i] = _at(mix.l, i - d * sr);
    tape.r[i] = _at(mix.r, i - d * sr);
  }

  // Master: dark, gentle high and low cut, fades, level, the vinyl, a soft
  // ceiling.
  final hl = Biquad.highpass(35), hr = Biquad.highpass(35);
  final ll2 = Biquad.lowpass(7500, 0.6), lr2 = Biquad.lowpass(7500, 0.6);
  final fadeIn = 1.0 * sr, fadeOut = 5.0 * sr;
  double fade(int i) {
    var g = 1.0;
    if (i < fadeIn) g = 0.5 - 0.5 * cos(pi * i / fadeIn);
    if (len - i < fadeOut) g *= 0.5 - 0.5 * cos(pi * (len - i) / fadeOut);
    return g;
  }

  for (var i = 0; i < len; i++) {
    mix.l[i] = ll2.process(hl.process(tape.l[i])) * fade(i);
    mix.r[i] = lr2.process(hr.process(tape.r[i])) * fade(i);
  }
  var sum = 0.0;
  for (var i = 0; i < len; i++) {
    sum += mix.l[i] * mix.l[i] + mix.r[i] * mix.r[i];
  }
  final gain = undb(-20) / sqrt(sum / (2 * len));
  final noise = vinyl(len, Random(s.seed + 7));
  final knee = undb(-7), ceiling = undb(-3.8);
  double limit(double x) {
    final ax = x.abs();
    if (ax <= knee) return x;
    final y = knee + (ceiling - knee) * _tanh((ax - knee) / (ceiling - knee));
    return x.sign * y;
  }

  var peak = 0.0;
  sum = 0;
  for (var i = 0; i < len; i++) {
    final v = noise[i] * fade(i);
    mix.l[i] = limit(mix.l[i] * gain + v);
    mix.r[i] = limit(mix.r[i] * gain + v);
    peak = max(peak, max(mix.l[i].abs(), mix.r[i].abs()));
    sum += mix.l[i] * mix.l[i] + mix.r[i] * mix.r[i];
  }
  return Rendered(mix, db(sqrt(sum / (2 * len))), db(peak));
}

double _tanh(double x) {
  final e = exp(2 * x);
  return (e - 1) / (e + 1);
}

void writeWav(String path, Buf b, Random r) {
  final n = b.length;
  final d = ByteData(44 + n * 4);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      d.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  d.setUint32(4, 36 + n * 4, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 2, Endian.little);
  d.setUint32(24, sr, Endian.little);
  d.setUint32(28, sr * 4, Endian.little);
  d.setUint16(32, 4, Endian.little);
  d.setUint16(34, 16, Endian.little);
  str(36, 'data');
  d.setUint32(40, n * 4, Endian.little);
  for (var i = 0; i < n; i++) {
    for (var ch = 0; ch < 2; ch++) {
      final x = ch == 0 ? b.l[i] : b.r[i];
      final v = (x * 32767 + r.nextDouble() - r.nextDouble()).round().clamp(-32768, 32767);
      d.setInt16(44 + i * 4 + ch * 2, v, Endian.little);
    }
  }
  File(path).writeAsBytesSync(d.buffer.asUint8List());
}

void main() {
  if (!File('pokertour_app/pubspec.yaml').existsSync()) {
    stderr.writeln('Run from PokerTour/: dart run scripts/jazz.dart');
    exit(2);
  }
  final out = Directory('pokertour_app/assets/music')..createSync(recursive: true);
  final tmp = Directory.systemTemp.createTempSync('jazz');
  try {
    for (var i = 0; i < songs.length; i++) {
      final s = songs[i];
      final rendered = render(s);
      final wav = '${tmp.path}/${i + 1}.wav';
      writeWav(wav, rendered.mix, Random(s.seed + 5));
      final mp3 = '${out.path}/${i + 1}.mp3';
      final res = Process.runSync('ffmpeg', [
        '-y', '-loglevel', 'error', '-i', wav, //
        '-c:a', 'libmp3lame', '-b:a', bitrate, '-ar', '$sr',
        '-map_metadata', '-1',
        '-metadata', 'title=${s.title}',
        '-metadata', 'artist=Poker Tour',
        '-metadata', 'comment=Generated by scripts/jazz.dart',
        mp3,
      ]);
      if (res.exitCode != 0) {
        stderr.write(res.stderr);
        exit(1);
      }
      final secs = rendered.mix.length / sr;
      print('${i + 1}.mp3  ${s.title}: ${s.key}, ${s.bpm} BPM, ${s.voice}, '
          '${secs ~/ 60}:${(secs % 60).round().toString().padLeft(2, '0')}, '
          'RMS ${rendered.rms.toStringAsFixed(1)} dBFS, peak ${rendered.peak.toStringAsFixed(1)} dBFS');
    }
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
