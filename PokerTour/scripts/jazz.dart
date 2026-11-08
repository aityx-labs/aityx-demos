/// Makes the app's background music: five soft lounge-trio jazz tracks,
/// pokertour_app/assets/music/1.mp3 to 5.mp3, synthesized here from nothing
/// (no samples, no third-party music): an FM electric piano, an additive
/// upright bass, vibraphone, soft sax or flute, and brushes, ride and
/// percussion made of filtered noise. The notes come from a seeded Random,
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
    title: 'Last Call at the Felt Room',
    style: 'Ballad',
    key: 'D♭ major',
    bpm: 74,
    bpb: 4,
    swing: 0.6,
    seed: 101,
    feel: 'ballad',
    voice: 'sax',
    melLo: 60,
    melHi: 79,
    density: 0.3,
    forms: {
      'intro': ['Ebm9 Ab13', 'Ebm9 Ab13sus'],
      'A': ['Dbmaj9', 'Bbm9', 'Ebm9', 'Ab13', 'Fm7 Bb7b9', 'Ebm9 Ab13', 'Dbmaj9 Bbm9', 'Ebm9 Ab13'],
      'A2': ['Dbmaj9', 'Bbm9', 'Ebm9', 'Ab13', 'Fm7 Bb7b9', 'Ebm9 Ab13', 'Dbmaj9 Gbmaj7#11', 'Dbmaj9'],
      'B': ['Gbmaj9', 'Gbm6/9', 'Fm9', 'Bb7b9', 'Ebm9', 'Ab13', 'Ebm9', 'Ab13sus Ab13'],
    },
    plan: [
      P('intro', 'intro', 'two'),
      P('A', 'head', 'two'),
      P('A2', 'head', 'two', mel: 'A'),
      P('B', 'head', 'two'),
      P('A2', 'head', 'two', mel: 'A'),
      P('B', 'rhodes', 'walk', ride: true),
      P('A2', 'head', 'two', mel: 'A'),
    ],
    end: 'Db6/9',
  ),
  Song(
    title: 'Pocket Kings',
    style: 'Medium swing on ii–V–I changes',
    key: 'F major',
    bpm: 112,
    bpb: 4,
    swing: 0.64,
    seed: 202,
    feel: 'swing',
    voice: 'vibes',
    melLo: 65,
    melHi: 86,
    density: 0.55,
    forms: {
      'intro': ['Am7 D7b9', 'Gm9 C13', 'Am7 D7b9', 'Gm9 C13'],
      'A': [
        'Gm9', 'C13', 'Fmaj9', 'Fmaj9', 'Gm9', 'C13', 'Am7 D7b9', 'Gm9 C13', //
        'Cm9', 'F13', 'Bbmaj9', 'Bbm9 Eb13', 'Am7 D7b9', 'Gm9 C13', 'Fmaj9 D7b9', 'Gm9 C13',
      ],
    },
    plan: [
      P('intro', 'intro', 'two'),
      P('A', 'head', 'two'),
      P('A', 'rhodes', 'walk', ride: true),
      P('A', 'solo', 'walk', ride: true),
      P('A', 'head', 'walk'),
    ],
    end: 'F6/9',
  ),
  Song(
    title: 'Rio on the River',
    style: 'Bossa nova',
    key: 'A minor',
    bpm: 120,
    bpb: 4,
    swing: 0.5,
    seed: 303,
    feel: 'bossa',
    voice: 'flute',
    melLo: 64,
    melHi: 84,
    density: 0.4,
    forms: {
      'intro': ['Am9', 'Am9', 'Bm7b5', 'E7b9'],
      'A': [
        'Am9', 'Am9', 'Bm7b5', 'E7b9', 'Am9', 'Am9', 'Gm9', 'C13', //
        'Fmaj9', 'Fmaj9', 'Dm9', 'G13', 'Cmaj9', 'Fmaj7#11', 'Bm7b5', 'E7b9',
      ],
    },
    plan: [
      P('intro', 'intro', 'bossa'),
      P('A', 'head', 'bossa'),
      P('A', 'rhodes', 'bossa', ride: true),
      P('A', 'solo', 'bossa', ride: true),
      P('A', 'head', 'bossa'),
    ],
    end: 'Am6/9',
  ),
  Song(
    title: 'Slow Roll Blues',
    style: 'Minor blues',
    key: 'C minor',
    bpm: 84,
    bpb: 4,
    swing: 0.63,
    seed: 404,
    feel: 'swing',
    voice: 'sax',
    melLo: 58,
    melHi: 77,
    density: 0.45,
    forms: {
      'intro': ['Ab13', 'G7alt', 'Cm9', 'Dm7b5 G7b9'],
      'A': ['Cm9', 'Fm9', 'Cm9', 'Cm9', 'Fm9', 'Fm9', 'Cm9', 'Cm9', 'Ab13', 'G7alt', 'Cm9', 'Dm7b5 G7b9'],
    },
    plan: [
      P('intro', 'intro', 'two'),
      P('A', 'head', 'walk'),
      P('A', 'head', 'walk'),
      P('A', 'rhodes', 'walk', ride: true),
      P('A', 'head', 'walk', ride: true),
    ],
    end: 'Cm6/9',
  ),
  Song(
    title: 'Waltz for the Short Stack',
    style: 'Jazz waltz',
    key: 'E♭ major',
    bpm: 100,
    bpb: 3,
    swing: 0.62,
    seed: 505,
    feel: 'waltz',
    voice: 'vibes',
    melLo: 65,
    melHi: 86,
    density: 0.45,
    forms: {
      'intro': ['Fm9', 'Bb13', 'Fm9', 'Bb13sus'],
      'A': [
        'Ebmaj9', 'Cm9', 'Fm9', 'Bb13', 'Gm7', 'C7b9', 'Fm9', 'Bb13', //
        'Ebmaj9', 'Abmaj7#11', 'Gm7', 'C7b9', 'Fm9', 'Bb13', 'Ebmaj9', 'Bb13sus',
      ],
    },
    plan: [
      P('intro', 'intro', 'waltz'),
      P('A', 'head', 'waltz'),
      P('A', 'head', 'waltz'),
      P('A', 'rhodes', 'walk', ride: true),
      P('A', 'solo', 'walk', ride: true),
      P('A', 'head', 'waltz'),
    ],
    end: 'Eb6/9',
  ),
];

/// One section of a tune's plan: which form it plays, who has the tune
/// ('intro', 'head' for the melody, 'solo' for the melody voice
/// improvising, 'rhodes' for an electric piano solo), the bass feel ('two',
/// 'walk', 'bossa', 'waltz'), whether the ride plays, and which section's
/// melody a head repeats.
class P {
  const P(this.form, this.role, this.bass, {this.ride = false, this.mel});
  final String form, role, bass;
  final bool ride;
  final String? mel;
}

class Song {
  const Song({
    required this.title,
    required this.style,
    required this.key,
    required this.bpm,
    required this.bpb,
    required this.swing,
    required this.seed,
    required this.feel,
    required this.voice,
    required this.melLo,
    required this.melHi,
    required this.density,
    required this.forms,
    required this.plan,
    required this.end,
  });
  final String title, style, key, feel, voice, end;
  final int bpm, bpb, seed, melLo, melHi;
  final double swing, density;
  final Map<String, List<String>> forms;
  final List<P> plan;
}

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

/// The note nearest [m] in [lo, hi] that is in [c]'s chord tones (on a
/// strong beat) or scale.
int snap(int m, Chord c, bool strong, int lo, int hi) {
  final set = strong ? c.q.tones : c.q.scale;
  for (var d = 0; d < 12; d++) {
    for (final x in [m - d, m + d]) {
      if (x >= lo && x <= hi && c.has(x, set)) return x;
    }
  }
  return min(max(m, lo), hi);
}

int pickPitch(int prev, Chord c, bool strong, double contour, int lo, int hi, Random r) {
  final set = strong ? c.q.tones : c.q.scale;
  final ms = <int>[], ws = <double>[];
  for (var m = lo; m <= hi; m++) {
    if (!c.has(m, set)) continue;
    final d = (m - prev).abs();
    var w = exp(-d / 2.5) * exp(-(m - contour).abs() / 5);
    if (d == 0) w *= 0.35;
    if (d > 7) w *= 0.15;
    ms.add(m);
    ws.add(w);
  }
  return pick(ms, ws, r);
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

class Span {
  Span(this.beat, this.beats, this.chord, this.sec, this.bar);
  final double beat, beats;
  final Chord chord;
  final int sec, bar;
}

class Sec {
  Sec(this.p, this.beat, this.bars);
  final P p;
  final double beat;
  final int bars;
}

/// A note: start and length in seconds, MIDI pitch, velocity 0..1.
class Ev {
  Ev(this.t, this.dur, this.midi, this.vel);
  final double t, dur, vel;
  final int midi;
}

class Hit {
  Hit(this.kind, this.t, this.vel, [this.len = 0]);
  final String kind;
  final double t, vel, len;
}

typedef N = ({double off, double dur, int midi, double vel});

/// The notes of one tune: comping, bass, melody and drums, in seconds.
class Arrangement {
  Arrangement(this.s) : endChord = Chord(s.end) {
    var beat = 0.0;
    for (final p in s.plan) {
      final bars = s.forms[p.form]!;
      secs.add(Sec(p, beat, bars.length));
      for (var b = 0; b < bars.length; b++) {
        final names = bars[b].split(' ');
        for (final name in names) {
          final beats = s.bpb / names.length;
          spans.add(Span(beat, beats, Chord(name), secs.length - 1, b));
          beat += beats;
        }
      }
    }
    endBeat = beat;
    _comp(Random(s.seed));
    _bass(Random(s.seed + 1));
    _lines(Random(s.seed + 2));
    _drums(Random(s.seed + 3));
  }

  final Song s;
  final Chord endChord;
  final spans = <Span>[];
  final secs = <Sec>[];
  late final double endBeat;
  final rhodes = <Ev>[], bass = <Ev>[], lead = <Ev>[];
  final hits = <Hit>[];

  /// Seconds at [beat], swung eighths included, after a short lead-in.
  double time(double beat) {
    final w = beat.floorToDouble(), f = beat - w;
    final g = f < 0.5 ? f * 2 * s.swing : s.swing + (f - 0.5) * 2 * (1 - s.swing);
    return 0.3 + (w + g) * 60 / s.bpm;
  }

  double get endTime => time(endBeat);

  Chord chordAt(double beat) {
    if (beat >= endBeat) return endChord;
    var lo = 0, hi = spans.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (spans[mid].beat <= beat + 1e-9) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return spans[lo].chord;
  }

  bool strong(double off, double dur) =>
      dur >= 0.9 || (off % 1 == 0 && (off % s.bpb) % (s.bpb == 3 ? 3 : 2) == 0);

  /// An anticipated long note belongs to the chord it leans into.
  double harm(double off, double dur) => (off % 1 == 0.5 && dur >= 1) ? off + 0.5 : off;

  // Electric piano comping.
  void _comp(Random r) {
    List<int>? prev;
    for (final sp in spans) {
      final role = secs[sp.sec].p.role;
      final v = voicing(sp.chord, prev, r);
      prev = v;
      final f = switch (role) { 'intro' => 0.85, 'rhodes' => 0.8, _ => 1.0 };
      for (final h in _pattern(sp, role, r)) {
        final st = h[0];
        if (st >= sp.beats) continue;
        final d = min(h[1], sp.beats - st + 0.03);
        final t0 = time(sp.beat + st) + 0.006 * gauss(r);
        final t1 = time(sp.beat + st + d);
        final vel = 0.5 * f * (st == 0 ? 1.05 : 0.95) * (1 + 0.07 * gauss(r));
        final roll = s.feel == 'ballad' ? 0.024 : 0.008;
        for (var k = 0; k < v.length; k++) {
          final t = t0 + k * roll * (0.5 + r.nextDouble());
          final top = k == v.length - 1 ? 1.1 : 1.0;
          rhodes.add(Ev(t, max(0.1, t1 - t), v[k], vel * (0.9 + 0.15 * r.nextDouble()) * top));
        }
      }
    }
    final v = voicing(endChord, prev, r);
    for (var k = 0; k < v.length; k++) {
      rhodes.add(Ev(endTime + 0.05 * k, 5.0, v[k], 0.46));
    }
  }

  List<List<double>> _pattern(Span sp, String role, Random r) {
    final List<List<List<double>>> opts;
    switch (s.feel) {
      case 'ballad':
        opts = sp.beats >= 4
            ? [
                [[0, 3.9]],
                [[0, 3.9]],
                [[0, 1.9], [2, 1.9]],
                [[0, 2.4], [2.5, 1.45]],
              ]
            : [
                [[0, 1.95]],
              ];
      case 'bossa':
        if (sp.beats < 4) return [[0, 1.2], [1.5, 0.45]];
        return sp.bar.isEven ? [[0, 1.2], [1.5, 1.2], [3, 0.9]] : [[1, 1.2], [2.5, 1.4]];
      case 'waltz':
        opts = [
          [[1, 0.9], [2, 0.9]],
          [[1, 0.9], [2, 0.9]],
          [[0, 2.8]],
          [[1, 1.9]],
          [[0, 0.9], [1.5, 1.4]],
          [[2, 0.9]],
        ];
      default:
        if (sp.beats < 4) {
          opts = [
            [[0, 1.6]],
            [[0.5, 1.2]],
            [[0, 0.8], [1.5, 0.45]],
            [[1, 0.9]],
          ];
        } else if (role == 'rhodes') {
          opts = [
            [[1, 0.9], [3, 0.9]],
            [[0, 1.4]],
            [[1.5, 2.0]],
            [[2.5, 1.2]],
            [[0, 3.6]],
          ];
        } else {
          opts = [
            [[0, 1.4], [1.5, 2.0]],
            [[1, 0.9], [3, 0.9]],
            [[0, 3.6]],
            [[0.5, 1.0], [2.5, 1.2]],
            [[0, 0.9], [2, 1.8]],
            [[1.5, 2.2]],
            [[0, 1.4], [2.5, 1.2]],
          ];
        }
    }
    return opts[r.nextInt(opts.length)];
  }

  // Bass: two-feel, walking, bossa and waltz lines.
  static const bLo = 29, bHi = 48;

  int near(int pc, int ref) {
    var best = -1;
    for (var m = bLo; m <= bHi; m++) {
      if ((m - pc) % 12 == 0 && (best < 0 || (m - ref).abs() < (best - ref).abs())) best = m;
    }
    return best;
  }

  int step(int c, int tgt, int left, Chord ch, Random r) {
    final ideal = c + (tgt - c) / left;
    final tones = [for (final x in ch.q.tones) if (x < 12) x];
    final ms = <int>[], ws = <double>[];
    for (var m = max(bLo, c - 7); m <= min(bHi, c + 7); m++) {
      if (m == c) continue;
      final tone = ch.has(m, tones);
      if (!tone && !ch.has(m, ch.q.scale)) continue;
      var w = (tone ? 2.0 : 1.0) * exp(-(m - ideal).abs() / 2.0);
      if ((m - c).abs() > 5) w *= 0.4;
      ms.add(m);
      ws.add(w);
    }
    return pick(ms, ws, r);
  }

  int approach(int c, int tgt, Chord ch, Random r) {
    final x = r.nextDouble();
    final chromatic = c > tgt ? tgt + 1 : tgt - 1;
    var m = chromatic;
    if (x >= 0.55 && x < 0.8) {
      m = near((tgt + 7) % 12, c);
    } else if (x >= 0.8) {
      final side = c > tgt ? 1 : -1;
      for (var d = 1; d <= 2; d++) {
        if (ch.has(tgt + side * d, ch.q.scale)) {
          m = tgt + side * d;
          break;
        }
      }
    }
    if (m == c || m == tgt) m = chromatic;
    if (m == c) m = c > tgt ? tgt - 1 : tgt + 1;
    return min(max(m, bLo), bHi);
  }

  void _bass(Random r) {
    var cur = near(spans.first.chord.root, 36);
    for (var i = 0; i < spans.length; i++) {
      final sp = spans[i];
      final ch = sp.chord;
      final next = i + 1 < spans.length ? spans[i + 1].chord : endChord;
      final sec = secs[sp.sec];
      final feel = sec.p.bass;
      final same = i > 0 && spans[i - 1].chord.name == ch.name;
      var first = near(ch.root, cur);
      if (same && r.nextDouble() < 0.5) first = near((ch.root + ch.q.tones[1 + r.nextInt(2)]) % 12, cur);
      if (first == cur && feel == 'walk') first = near((ch.root + 7) % 12, cur);
      final fifth = near((ch.root + 7) % 12, first);
      final changes = next.name != ch.name;
      final notes = <(double, double, int)>[(0, 0.9, first)];
      switch (feel) {
        case 'walk':
          var c = first;
          final n = sp.beats.round();
          for (var k = 1; k < n; k++) {
            final tgt = near(next.root, c);
            c = k == n - 1 ? approach(c, tgt, ch, r) : step(c, tgt, n - k, ch, r);
            notes.add((k.toDouble(), 0.9, c));
          }
        case 'two':
          notes[0] = (0, 1.9, first);
          if (sp.beats >= 4) {
            final second = changes && r.nextDouble() < 0.4 ? approach(first, near(next.root, first), ch, r) : fifth;
            notes.add((2, 1.9, second));
          }
        case 'waltz':
          notes[0] = (0, 1.9, first);
          final second = changes && r.nextDouble() < 0.5 ? approach(first, near(next.root, first), ch, r) : fifth;
          notes.add((2, 0.9, second));
        case 'bossa':
          notes[0] = (0, 1.4, first);
          if (sp.beats >= 4) {
            final low5 = first - 5 >= bLo ? first - 5 : first + 7;
            if (r.nextDouble() < 0.3) notes.add((1.5, 0.45, low5));
            notes.add((2, 1.4, low5));
          }
      }
      final f = sec.p.role == 'intro' ? 0.9 : 1.0;
      for (final (b, d, m) in notes) {
        final t = time(sp.beat + b) + 0.004 * gauss(r);
        final vel = 0.7 * f * (b == 0 ? 1.05 : 1.0) * (1 + 0.06 * gauss(r));
        bass.add(Ev(t, time(sp.beat + b + d) - t, m, vel));
        cur = m;
      }
    }
    bass.add(Ev(endTime, 4.0, near(endChord.root, 33), 0.62));
  }

  // Melody and solos.
  void _lines(Random r) {
    final cache = <String, List<N>>{};
    var prevLead = (s.melLo + s.melHi) ~/ 2, prevRh = 74;
    var lastRole = '';
    for (final sec in secs) {
      final role = sec.p.role;
      if (role == 'head') {
        final line = cache[sec.p.mel ?? sec.p.form] ??= _head(sec, prevLead, r);
        for (final n in line) {
          final c = chordAt(sec.beat + harm(n.off, n.dur));
          final m = snap(n.midi, c, strong(n.off, n.dur), s.melLo, s.melHi);
          _emit(lead, sec.beat + n.off, n.dur, m, n.vel, 0.014, r);
          prevLead = m;
        }
      } else if (role == 'solo') {
        for (final n in _solo(sec, s.density + 0.15, s.melLo, s.melHi, prevLead, r)) {
          _emit(lead, sec.beat + n.off, n.dur, n.midi, n.vel, 0.014, r);
          prevLead = n.midi;
        }
      } else if (role == 'rhodes') {
        for (final n in _solo(sec, s.density + 0.1, 65, 84, prevRh, r)) {
          _emit(rhodes, sec.beat + n.off, n.dur, n.midi, n.vel * 0.85, 0.008, r);
          prevRh = n.midi;
        }
      }
      lastRole = role;
    }
    if (lastRole == 'head' || lastRole == 'solo') {
      lead.add(Ev(endTime + 0.03, 4.0, snap(prevLead, endChord, true, s.melLo, s.melHi), 0.5));
    }
  }

  void _emit(List<Ev> to, double beat, double dur, int m, double vel, double lay, Random r) {
    final t = time(beat) + lay + 0.007 * gauss(r);
    to.add(Ev(t, max(0.12, time(beat + dur) + lay - t), m, vel));
  }

  /// A head: four-bar phrases a a' b a'', where a' and a'' replay a's
  /// rhythm and shape over their own chords.
  List<N> _head(Sec sec, int prev, Random r) {
    final pb = min(4, sec.bars);
    const letters = ['a', 'a', 'b', 'a'];
    final out = <N>[];
    List<N>? a;
    var aStart = 0.0;
    for (var i = 0; i < sec.bars ~/ pb; i++) {
      final start = (i * pb * s.bpb).toDouble();
      final letter = letters[i % 4];
      if (letter == 'a' && a != null) {
        final c1 = chordAt(sec.beat + aStart), c2 = chordAt(sec.beat + start);
        var shift = (c2.root - c1.root + 6) % 12 - 6;
        final top = a.map((n) => n.midi).reduce(max), bottom = a.map((n) => n.midi).reduce(min);
        if (top + shift > s.melHi) shift -= 12;
        if (bottom + shift < s.melLo) shift += 12;
        for (final n in a) {
          final off = n.off - aStart + start;
          final c = chordAt(sec.beat + harm(off, n.dur));
          final m = snap(n.midi + shift, c, strong(off, n.dur), s.melLo, s.melHi);
          out.add((off: off, dur: n.dur, midi: m, vel: n.vel));
        }
      } else {
        final ph = _phrase(sec.beat, start, pb, s.density, s.melLo, s.melHi, prev, r);
        if (letter == 'a') {
          a = ph;
          aStart = start;
        }
        out.addAll(ph);
      }
      if (out.isNotEmpty) prev = out.last.midi;
    }
    return out;
  }

  /// A solo: two- and four-bar phrases, now and then a phrase left out.
  List<N> _solo(Sec sec, double density, int lo, int hi, int prev, Random r) {
    final out = <N>[];
    var bar = 0;
    while (bar < sec.bars) {
      final len = min(sec.bars - bar, r.nextDouble() < 0.5 ? 2 : 4);
      if (bar > 0 && r.nextDouble() < 0.15) {
        bar += len;
        continue;
      }
      final ph = _phrase(sec.beat, (bar * s.bpb).toDouble(), len, density, lo, hi, prev, r);
      out.addAll(ph);
      if (ph.isNotEmpty) prev = ph.last.midi;
      bar += len;
    }
    return out;
  }

  List<N> _phrase(double secBeat, double start, int bars, double density, int lo, int hi, int prev, Random r) {
    final total = (bars * s.bpb).toDouble();
    final center = lo + (hi - lo) * (0.3 + 0.35 * r.nextDouble());
    final arc = -2 + 8 * r.nextDouble();
    var p = min(max(prev, lo), hi);
    final out = <N>[];
    for (final (off, dur) in _rhythm(bars, density, r)) {
      final o = start + off;
      final x = off / total;
      final c = chordAt(secBeat + harm(o, dur));
      p = pickPitch(p, c, strong(o, dur), center + arc * sin(pi * x), lo, hi, r);
      final vel = 0.55 + 0.08 * sin(pi * x) + (dur >= 1 ? 0.04 : 0) + 0.035 * gauss(r);
      out.add((off: o, dur: dur, midi: p, vel: vel));
    }
    return out;
  }

  /// A phrase's rhythm in beats: notes, rests, a held note at the end.
  List<(double, double)> _rhythm(int bars, double density, Random r) {
    final total = (bars * s.bpb).toDouble();
    final hold = bars >= 4 ? total - s.bpb : total - 2;
    final out = <(double, double)>[];
    final x0 = r.nextDouble();
    var b = x0 < 0.3 ? 0.5 : (x0 < 0.6 ? 1.0 : 0.0);
    while (b < hold - 0.01) {
      final x = r.nextDouble();
      if (b % 1 != 0) {
        if (x < 0.5 && b + 1.5 <= hold) {
          out.add((b, 1.4));
          b += 1.5;
        } else {
          out.add((b, 0.45));
          b += 0.5;
        }
        continue;
      }
      final rest = 0.1 + 0.22 * (1 - density);
      final eighths = rest + 0.45 * density;
      final half = eighths + 0.22 * (1 - density);
      final sync = half + 0.14;
      if (x < rest) {
        b += 1;
      } else if (x < eighths) {
        out.add((b, 0.46));
        out.add((b + 0.5, 0.46));
        b += 1;
      } else if (x < half && b + 2 <= hold) {
        out.add((b, 1.9));
        b += 2;
      } else if (x < sync && b + 2 <= hold) {
        out.add((b, 0.46));
        out.add((b + 0.5, 1.4));
        b += 2;
      } else {
        out.add((b, 0.92));
        b += 1;
      }
    }
    final fs = hold - (r.nextDouble() < 0.3 ? 0.5 : 0);
    out.removeWhere((n) => n.$1 >= fs - 0.01);
    if (out.isNotEmpty) {
      final l = out.last;
      if (l.$1 + l.$2 > fs - 0.04) out[out.length - 1] = (l.$1, fs - l.$1 - 0.05);
    }
    out.add((fs, (total - fs) * (0.5 + 0.25 * r.nextDouble())));
    return out;
  }

  // Brushes, ride, hi-hat, and the bossa's rim, kick and shaker.
  void _drums(Random r) {
    final beatSec = 60 / s.bpm;
    for (final sec in secs) {
      final f = sec.p.role == 'intro' ? 0.8 : 1.0;
      final ride = sec.p.ride;
      for (var bar = 0; bar < sec.bars; bar++) {
        final b0 = sec.beat + bar * s.bpb;
        void hit(String kind, double beat, double vel, [double lenBeats = 0]) {
          final t = time(b0 + beat) + 0.004 * gauss(r);
          hits.add(Hit(kind, t, vel * f * (1 + 0.1 * gauss(r)), lenBeats * beatSec));
        }

        void ridePattern(double v) {
          for (final (b, a) in [(0.0, 0.55), (1.0, 0.7), (1.5, 0.4), (2.0, 0.55), (3.0, 0.7), (3.5, 0.4)]) {
            hit('ride', b, a * v);
          }
        }

        switch (s.feel) {
          case 'ballad':
            hit('swish', 0, 0.5, 1.9);
            hit('swish', 2, 0.42, 1.9);
            hit('tap', 3, 0.3);
            hit('chick', 1, 0.35);
            hit('chick', 3, 0.35);
            if (ride) ridePattern(0.7);
          case 'bossa':
            for (var k = 0; k < 8; k++) {
              hit('shaker', k * 0.5, k.isOdd ? 0.55 : 0.35);
            }
            for (final x in bar.isEven ? [0.0, 1.5, 3.0] : [1.0, 2.5]) {
              hit('rim', x, 0.5);
            }
            hit('kick', 0, 0.6);
            if (r.nextDouble() < 0.5) hit('kick', 1.5, 0.35);
            hit('kick', 2, 0.5);
            if (ride) {
              for (var k = 0; k < 4; k++) {
                hit('ride', k.toDouble(), k.isEven ? 0.45 : 0.35);
              }
            }
          case 'waltz':
            hit('swish', 0, 0.55, 0.95);
            hit('swish', 1, 0.42, 0.95);
            hit('swish', 2, 0.42, 0.95);
            hit('tap', 1, 0.35);
            hit('tap', 2, 0.3);
            hit('chick', 1, 0.45);
            if (ride) {
              for (final (b, a) in [(0.0, 0.6), (1.0, 0.45), (2.0, 0.55), (2.5, 0.35)]) {
                hit('ride', b, a);
              }
            }
          default:
            for (var k = 0; k < 4; k++) {
              hit('swish', k.toDouble(), k.isOdd ? 0.6 : 0.45, 0.95);
            }
            hit('tap', 1, 0.5);
            hit('tap', 3, 0.5);
            hit('chick', 1, 0.55);
            hit('chick', 3, 0.55);
            if (ride) ridePattern(1);
        }
      }
    }
    hits.add(Hit('ride', endTime, 0.4));
    hits.add(Hit('swish', endTime, 0.35, 2 * beatSec));
  }
}

// -------------------------------------------------------------- instruments

double _tail(int i, int n) => min(1.0, (n - i) / (0.02 * sr));

/// Electric piano: 1:1 FM with an index that falls after the strike, a
/// faint tine overtone, soft attack, two-stage decay.
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
    var env = (1 - exp(-t / 0.004)) * (0.7 * exp(-t / decay) + 0.3 * exp(-t / 0.3));
    if (t > e.dur) env *= exp(-(t - e.dur) / 0.12);
    final idx = v * (0.5 + 1.6 * exp(-t / 0.2));
    final ph = w * i;
    final x = sin(ph + idx * sin(ph)) + 0.18 * v * exp(-t / 0.035) * sin(ph * 7);
    out[j] += level * env * x * _tail(i, n);
  }
}

/// Vibraphone: the bar's 1 : 4 : 10 modes, motor tremolo, damper.
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
        0.2 * v * exp(-t / 0.25) * sin(ph * 3.97) +
        0.05 * v * exp(-t / 0.05) * sin(ph * 9.8);
    final trem = 1 - 0.18 * (0.5 + 0.5 * sin(tau * 5.0 * (e.t + t)));
    var env = (1 - exp(-t / 0.003)) * trem;
    if (t > e.dur) env *= exp(-(t - e.dur) / 0.18);
    out[j] += v * env * x * _tail(i, n);
  }
}

/// Soft sax or flute: additive harmonics, breath noise, a slow attack,
/// delayed vibrato and (for the sax) a small scoop up into the note.
void hornNote(Float64List out, Ev e, bool flute, Random r) {
  final f = mtof(e.midi), v = e.vel;
  final kMax = max(1, min(flute ? 6 : 12, (5500 / f).floor()));
  final amps = Float64List(kMax + 1);
  var sum = 0.0;
  for (var k = 1; k <= kMax; k++) {
    final a = flute
        ? const <double>[0, 1.0, 0.32, 0.1, 0.05, 0.02, 0.01][k]
        : exp(-(k - 1) * (0.62 - 0.25 * v)) * (1 + 0.5 * exp(-pow((k * f - 1100) / 600, 2)));
    amps[k] = a;
    sum += a;
  }
  final start = (e.t * sr).round();
  final n = ((e.dur + 0.6) * sr).round();
  final breath = Biquad.bandpass(flute ? 2400 : 1500, 0.8);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final j = start + i;
    if (j >= out.length) break;
    final t = i / sr;
    final vib = (flute ? 12 : 16) * min(1.0, max(0.0, (t - 0.25) / 0.4)) * sin(tau * 5.1 * t) / 100;
    final scoop = flute ? 0.0 : -0.3 * exp(-t / 0.045);
    phase += tau * f * exp((vib + scoop) * ln2 / 12) / sr;
    final c = cos(phase);
    var s1 = sin(phase), s0 = 0.0, x = amps[1] * s1;
    for (var k = 2; k <= kMax; k++) {
      final s2 = 2 * c * s1 - s0;
      x += amps[k] * s2;
      s0 = s1;
      s1 = s2;
    }
    x /= sum;
    final b = breath.process(r.nextDouble() * 2 - 1) * (flute ? 0.12 : 0.06) * (0.4 + 0.6 * exp(-t / 0.12));
    var env = 1 - exp(-t / (flute ? 0.06 : 0.045));
    if (t > e.dur) env *= exp(-(t - e.dur) / 0.09);
    if (j >= 0) out[j] += v * env * (x + b) * _tail(i, n);
  }
}

/// Upright bass: harmonics that fade faster the higher they are, a small
/// pitch drop and a muted thump at the pluck.
void bassNote(Float64List out, Ev e, Random r) {
  final f = mtof(e.midi), v = e.vel;
  const amps = [1.0, 0.5, 0.32, 0.18, 0.1, 0.06, 0.03];
  const taus = [1.6, 1.0, 0.6, 0.4, 0.28, 0.2, 0.15];
  final decay = [for (final t in taus) exp(-1 / (t * sr))];
  final env = [...amps];
  final start = (e.t * sr).round();
  final n = ((e.dur + 0.3) * sr).round();
  final thumpLp = Biquad.lowpass(350);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final j = start + i;
    if (j >= out.length) break;
    final t = i / sr;
    phase += tau * f * (1 + 0.012 * exp(-t / 0.025)) / sr;
    var x = 0.0;
    for (var k = 0; k < amps.length; k++) {
      x += env[k] * sin((k + 1) * phase);
      env[k] *= decay[k];
    }
    x += thumpLp.process(r.nextDouble() * 2 - 1) * 0.6 * exp(-t / 0.012);
    var g = 1 - exp(-t / 0.006);
    if (t > e.dur) g *= exp(-(t - e.dur) / 0.045);
    if (j >= 0) out[j] += v * g * x * _tail(i, n);
  }
}

const _kinds = ['swish', 'tap', 'chick', 'ride', 'rim', 'kick', 'shaker'];
const _gain = {'swish': 0.55, 'tap': 0.5, 'chick': 0.3, 'ride': 0.32, 'rim': 0.3, 'kick': 0.9, 'shaker': 0.22};
const _pan = {'swish': -0.1, 'tap': -0.05, 'chick': -0.35, 'ride': 0.4, 'rim': -0.25, 'kick': 0.0, 'shaker': 0.3};

/// One drum sound, peak 1, made of filtered noise (and a few sines).
Float64List makeDrum(String kind, double len, Random r) {
  double nz() => r.nextDouble() * 2 - 1;
  final secs = switch (kind) {
    'swish' => len,
    'tap' => 0.3,
    'chick' => 0.12,
    'ride' => 1.8,
    'rim' => 0.1,
    'kick' => 0.5,
    _ => 0.14,
  };
  final n = max(1, (secs * sr).round());
  final x = Float64List(n);
  switch (kind) {
    case 'swish':
      final bp = Biquad.bandpass(2600 + 600 * r.nextDouble(), 0.5), lp = Biquad.lowpass(6500);
      for (var i = 0; i < n; i++) {
        x[i] = lp.process(bp.process(nz())) * pow(sin(pi * pow(i / n, 0.75)), 2);
      }
    case 'tap':
      final bp = Biquad.bandpass(2300, 0.8);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        x[i] = bp.process(nz()) * (1 - exp(-t / 0.0015)) * exp(-t / 0.045);
      }
    case 'chick':
      final bp = Biquad.bandpass(6000, 1.0), lp = Biquad.lowpass(8500);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        x[i] = lp.process(bp.process(nz())) * (1 - exp(-t / 0.002)) * exp(-t / 0.018);
      }
    case 'ride':
      const freqs = [3120.0, 3710.0, 4390.0, 5180.0, 6020.0, 6890.0];
      const amps = [1.0, 0.8, 0.7, 0.55, 0.4, 0.3];
      final fs = [for (final f in freqs) f * (1 + 0.01 * nz())];
      final phs = [for (final _ in freqs) tau * r.nextDouble()];
      final hp = Biquad.highpass(4500), lp = Biquad.lowpass(9000);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        var tone = 0.0;
        for (var k = 0; k < fs.length; k++) {
          tone += amps[k] * sin(tau * fs[k] * t + phs[k]);
        }
        final body = exp(-t / 0.55), stick = exp(-t / 0.006);
        x[i] = (0.35 * tone * body / 3.75 + 0.8 * lp.process(hp.process(nz())) * (0.6 * body + 1.5 * stick)) *
            (1 - exp(-t / 0.0008));
      }
    case 'rim':
      final bp = Biquad.bandpass(3000, 1.0);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        x[i] = 0.8 * sin(tau * 1700 * t) * exp(-t / 0.005) +
            0.6 * sin(tau * 820 * t) * exp(-t / 0.009) +
            0.6 * bp.process(nz()) * exp(-t / 0.003);
      }
    case 'kick':
      var ph = 0.0;
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        ph += tau * (50 + 35 * exp(-t / 0.03)) / sr;
        x[i] = sin(ph) * exp(-t / 0.18) * (1 - exp(-t / 0.002));
      }
    default: // shaker
      final hp = Biquad.highpass(5500), lp = Biquad.lowpass(9500);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        x[i] = lp.process(hp.process(nz())) * (1 - exp(-t / 0.005)) * exp(-t / 0.03);
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

Rendered render(Song s) {
  final a = Arrangement(s);
  final total = a.endTime + 8.0;
  final len = (total * sr).round();
  final rh = Float64List(len), ld = Float64List(len), bs = Float64List(len);
  final dr = Buf(len);
  final r = Random(s.seed + 4);

  for (final e in a.rhodes) {
    rhodesNote(rh, e);
  }
  for (final e in a.lead) {
    if (s.voice == 'vibes') {
      vibesNote(ld, e);
    } else {
      hornNote(ld, e, s.voice == 'flute', r);
    }
  }
  for (final e in a.bass) {
    bassNote(bs, e, r);
  }
  final cache = <String, Float64List>{};
  for (final h in a.hits) {
    final variant = r.nextInt(4);
    final lenKey = (h.len * 100).round();
    final key = '${h.kind}/$lenKey/$variant';
    final x = cache[key] ??= makeDrum(
        h.kind, lenKey / 100, Random(s.seed * 7 + _kinds.indexOf(h.kind) * 1009 + variant * 7919 + lenKey * 31));
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

  // Each part filtered soft and set to its level.
  Biquad.highpass(110).run(rh);
  Biquad.lowpass(3000, 0.6).run(rh);
  Biquad.highpass(140).run(ld);
  Biquad.lowpass(s.voice == 'vibes' ? 4500 : 3400, 0.6).run(ld);
  Biquad.highpass(40).run(bs);
  Biquad.lowpass(1100).run(bs);
  for (final c in [dr.l, dr.r]) {
    Biquad.lowpass(8000).run(c);
  }
  scaleTo([rh], -22.5);
  scaleTo([ld], s.voice == 'vibes' ? -22.5 : -22.0);
  scaleTo([bs], -22.0);
  scaleTo([dr.l, dr.r], -33.0);

  final mix = Buf(len);
  final send = Float64List(len);
  final pre = (0.025 * sr).round();
  final (ll, lr) = panGains(0.25);
  final (bl, br) = panGains(0.0);
  for (var i = 0; i < len; i++) {
    final (rl, rr) = panGains(-0.12 + 0.12 * sin(tau * 3.2 * i / sr));
    mix.l[i] = rh[i] * rl + ld[i] * ll + bs[i] * bl + dr.l[i];
    mix.r[i] = rh[i] * rr + ld[i] * lr + bs[i] * br + dr.r[i];
    if (i + pre < len) {
      send[i + pre] = rh[i] * 0.35 + ld[i] * 0.45 + bs[i] * 0.06 + (dr.l[i] + dr.r[i]) * 0.15;
    }
  }
  final wet = reverb(send);
  final wetGain = undb(-10) * activeRms([mix.l, mix.r]) / activeRms([wet.l, wet.r]);

  // Master: room, gentle high and low cut, fades, level, soft ceiling.
  final hl = Biquad.highpass(30), hr = Biquad.highpass(30);
  final ll2 = Biquad.lowpass(9500, 0.6), lr2 = Biquad.lowpass(9500, 0.6);
  final fadeIn = 1.5 * sr, fadeOut = 5.5 * sr;
  for (var i = 0; i < len; i++) {
    var g = 1.0;
    if (i < fadeIn) g = 0.5 - 0.5 * cos(pi * i / fadeIn);
    if (len - i < fadeOut) g *= 0.5 - 0.5 * cos(pi * (len - i) / fadeOut);
    mix.l[i] = ll2.process(hl.process(mix.l[i] + wet.l[i] * wetGain)) * g;
    mix.r[i] = lr2.process(hr.process(mix.r[i] + wet.r[i] * wetGain)) * g;
  }
  var sum = 0.0;
  for (var i = 0; i < len; i++) {
    sum += mix.l[i] * mix.l[i] + mix.r[i] * mix.r[i];
  }
  final gain = undb(-20) / sqrt(sum / (2 * len));
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
    mix.l[i] = limit(mix.l[i] * gain);
    mix.r[i] = limit(mix.r[i] * gain);
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
      print('${i + 1}.mp3  ${s.title}: ${s.style}, ${s.key}, ${s.bpm} BPM, '
          '${secs ~/ 60}:${(secs % 60).round().toString().padLeft(2, '0')}, '
          'RMS ${rendered.rms.toStringAsFixed(1)} dBFS, peak ${rendered.peak.toStringAsFixed(1)} dBFS');
    }
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
