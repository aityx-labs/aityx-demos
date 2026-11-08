// The soundtrack: a synthwave song played by the browser itself, with
// Web Audio oscillators and noise, so there is no recording to license
// and nothing to download. 104 BPM in A minor, in sections (SONG): an
// intro, a verse, the verse with a lead melody, a chorus, a breakdown
// that builds back up, the chorus again with the lead an octave up, and
// an outro, about a minute and fifty seconds, then round again from the
// verse, each time round with the arpeggios moved on a pattern. The
// voices: a sawtooth bass, a sixteenth-note arpeggio with a delay, a
// detuned pad, a lead with vibrato, and a drum kit of a sine kick, a
// noise snare, hi-hats and a crash. Scheduled a little ahead with a
// timer, the usual Web Audio pattern.
//
// Browsers only let audio start after the user acts on the page: the
// Play button is that act, and the Music button in the bar turns it off
// and on, with a slider for the volume beside it; both choices are kept
// in localStorage.

const BPM = 104;
const BEAT = 60 / BPM;
const BAR = BEAT * 4;
const LOOKAHEAD_S = 0.12;
const TIMER_MS = 30;
const PREFERENCE = 'tatyx.music';
const VOLUME = 'tatyx.volume';
/** The volume to begin with: half of the slider, quiet enough to sit under the game. */
const DEFAULT_VOLUME = 0.5;
/** The master gain at full volume. */
const MAX_GAIN = 0.28;

/** MIDI note to Hz. */
const hz = (note: number): number => 440 * 2 ** ((note - 69) / 12);

interface Chord {
  /** The root, in octave 2, for the bass; the pad plays an octave up, the arpeggio two. */
  readonly root: number;
  readonly tones: readonly number[];
}

// The chords (MIDI).
const A2 = 45;
const MINOR = [0, 3, 7];
const MAJOR = [0, 4, 7];
const Am: Chord = { root: A2, tones: MINOR };
const F: Chord = { root: A2 - 4, tones: MAJOR };
const C: Chord = { root: A2 + 3, tones: MAJOR };
const G: Chord = { root: A2 - 2, tones: MAJOR };
const Dm: Chord = { root: A2 - 7, tones: MINOR };
const E: Chord = { root: A2 - 5, tones: MAJOR };

/** A note of the lead: its beat in the bar, its length in beats, the MIDI note. */
type Note = readonly [beat: number, beats: number, note: number];

/** The lead over the verse, a bar a line. */
const VERSE_LEAD: readonly (readonly Note[])[] = [
  [[0, 2, 76], [2, 1, 74], [3, 1, 72]],
  [[0, 1.5, 72], [1.5, 0.5, 69], [2, 1, 72], [3, 1, 77]],
  [[0, 3, 76], [3, 1, 79]],
  [[0, 2, 74], [2, 1, 71], [3, 1, 74]],
  [[0, 2, 76], [2, 1, 79], [3, 1, 81]],
  [[0, 2, 77], [2, 1, 76], [3, 1, 74]],
  [[0, 1.5, 72], [1.5, 0.5, 74], [2, 2, 76]],
  [[0, 3, 74], [3, 1, 71]],
];

/** The lead over the chorus. */
const CHORUS_LEAD: readonly (readonly Note[])[] = [
  [[0, 2, 81], [2, 1, 79], [3, 1, 77]],
  [[0, 2, 79], [2, 2, 74]],
  [[0, 3, 76], [3, 1, 72]],
  [[0, 4, 69]],
  [[0, 2, 77], [2, 1, 76], [3, 1, 77]],
  [[0, 2, 79], [2, 1, 81], [3, 1, 83]],
  [[0, 3, 84], [3, 1, 79]],
  [[0, 2, 80], [2, 2, 76]],
];

/** The arpeggios: steps through two octaves of the chord, sixteenths. */
const ARPS: readonly (readonly number[])[] = [
  [0, 1, 2, 3, 2, 1, 0, 2, 3, 4, 5, 4, 3, 2, 1, 0],
  [0, 2, 4, 2, 1, 3, 5, 3, 0, 2, 4, 2, 1, 3, 5, 3],
  [5, 4, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 4],
  [0, 3, 1, 4, 2, 5, 3, 4, 0, 3, 1, 4, 2, 5, 4, 3],
];

interface Section {
  readonly name: string;
  /** A chord a bar: the section's length. */
  readonly chords: readonly Chord[];
  readonly bass: 'eighths' | 'pulse' | 'held' | 'none';
  readonly drums: 'none' | 'hats' | 'full' | 'drive';
  /** Which arpeggio, null for none; `eighths` plays it at half speed. */
  readonly arp: number | null;
  readonly eighths?: boolean;
  /** The arpeggio's lowpass, in Hz; the intro's opens bar by bar. */
  readonly bright: number;
  readonly lead?: readonly (readonly Note[])[];
  /** Semitones to move the lead by. */
  readonly leadShift?: number;
  /** A crash on the first beat. */
  readonly crash?: boolean;
  /** A snare fill at the end; `build`, a roll over the last two bars. */
  readonly ending?: 'fill' | 'build';
}

const VERSE = [Am, F, C, G, Am, F, C, G];
const CHORUS = [F, G, Am, Am, F, G, C, E];

/** The song: played through once, then round again from the verse. */
const SONG: readonly Section[] = [
  { name: 'intro', chords: [Am, F, C, G], bass: 'none', drums: 'hats', arp: 0, bright: 700, ending: 'fill' },
  { name: 'verse', chords: VERSE, bass: 'eighths', drums: 'full', arp: 0, bright: 2400, ending: 'fill' },
  { name: 'verse, the lead', chords: VERSE, bass: 'eighths', drums: 'full', arp: 1, bright: 2000, lead: VERSE_LEAD, ending: 'fill' },
  { name: 'chorus', chords: CHORUS, bass: 'pulse', drums: 'drive', arp: 2, bright: 2800, lead: CHORUS_LEAD, crash: true, ending: 'fill' },
  { name: 'breakdown', chords: [Dm, F, Am, G, Dm, F, Am, E], bass: 'held', drums: 'none', arp: 3, eighths: true, bright: 1400, ending: 'build' },
  { name: 'chorus, up', chords: CHORUS, bass: 'pulse', drums: 'drive', arp: 1, bright: 3200, lead: CHORUS_LEAD, leadShift: 12, crash: true, ending: 'fill' },
  { name: 'outro', chords: [Am, F, C, G], bass: 'held', drums: 'hats', arp: 0, bright: 1600, crash: true },
];

/** Where the song goes round to after the outro: the verse. */
const LOOP_FROM = 1;

/** Each bar of the song, in order, with its section and its bar in the section. */
const BARS: readonly { section: Section; bar: number }[] = SONG.flatMap((section) => section.chords.map((_, bar) => ({ section, bar })));
const LOOP_START = SONG.slice(0, LOOP_FROM).reduce((n, s) => n + s.chords.length, 0);

/** The bar the song plays at a count of bars since the start, and how many times it has gone round. */
function barAt(index: number): { section: Section; bar: number; round: number } {
  if (index < BARS.length) return { ...BARS[index]!, round: 0 };
  const looped = BARS.length - LOOP_START;
  const past = index - LOOP_START;
  return { ...BARS[LOOP_START + (past % looped)]!, round: Math.floor(past / looped) };
}

export class Synthwave {
  private context: AudioContext | null = null;
  private master: GainNode | null = null;
  private delay: DelayNode | null = null;
  private noise: AudioBuffer | null = null;
  private timer: number | null = null;
  private nextBar = 0;
  private nextBarAt = 0;
  private listeners = new Set<(on: boolean) => void>();

  /** Whether music should play, as the user chose (on unless turned off). */
  get enabled(): boolean {
    try {
      return localStorage.getItem(PREFERENCE) !== 'off';
    } catch {
      return true;
    }
  }

  /** Whether it is playing now. */
  get playing(): boolean {
    return this.timer !== null;
  }

  /** The volume, 0 to 1, as the user set it (DEFAULT_VOLUME until then). */
  get volume(): number {
    try {
      const stored = Number(localStorage.getItem(VOLUME));
      return Number.isFinite(stored) && localStorage.getItem(VOLUME) !== null ? clamp(stored) : DEFAULT_VOLUME;
    } catch {
      return DEFAULT_VOLUME;
    }
  }

  /** Sets the volume, 0 to 1, remembers it, and applies it to what's playing. */
  setVolume(value: number): void {
    const volume = clamp(value);
    try {
      localStorage.setItem(VOLUME, String(volume));
    } catch {
      // No storage: the choice lasts the page.
    }
    if (this.master !== null && this.context !== null) {
      this.master.gain.setTargetAtTime(MAX_GAIN * volume, this.context.currentTime, 0.03);
    }
  }

  onChange(listener: (on: boolean) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Turns the music off or on, remembers it, and starts or stops it. */
  toggle(): void {
    const on = !this.enabled;
    try {
      localStorage.setItem(PREFERENCE, on ? 'on' : 'off');
    } catch {
      // No storage: the choice lasts the page.
    }
    if (on) this.start();
    else this.stop();
    for (const listener of this.listeners) listener(on);
  }

  /** Starts the loop, if enabled. Call it from a user action the first time. */
  start(): void {
    if (!this.enabled || this.playing || typeof AudioContext === 'undefined') return;
    const context = (this.context ??= new AudioContext());
    if (context.state === 'suspended') void context.resume();
    if (this.master === null) this.wire(context);
    this.nextBar = 0;
    this.nextBarAt = context.currentTime + 0.05;
    this.timer = window.setInterval(() => this.schedule(), TIMER_MS);
    this.schedule();
  }

  stop(): void {
    if (this.timer !== null) {
      window.clearInterval(this.timer);
      this.timer = null;
    }
    // Let what's scheduled fade: a new master for the next start.
    if (this.master !== null && this.context !== null) {
      const now = this.context.currentTime;
      this.master.gain.setTargetAtTime(0, now, 0.08);
      const old = this.master;
      window.setTimeout(() => old.disconnect(), 600);
      this.master = null;
      this.delay = null;
    }
  }

  private wire(context: AudioContext): void {
    const compressor = context.createDynamicsCompressor();
    compressor.threshold.value = -18;
    compressor.ratio.value = 4;
    compressor.connect(context.destination);
    const master = context.createGain();
    master.gain.value = MAX_GAIN * this.volume;
    master.connect(compressor);
    // A dotted-eighth delay for the arpeggio, the synthwave echo.
    const delay = context.createDelay(1);
    delay.delayTime.value = BEAT * 0.75;
    const feedback = context.createGain();
    feedback.gain.value = 0.32;
    const wet = context.createGain();
    wet.gain.value = 0.35;
    delay.connect(feedback).connect(delay);
    delay.connect(wet).connect(master);
    this.master = master;
    this.delay = delay;
    if (this.noise === null) {
      const buffer = context.createBuffer(1, context.sampleRate, context.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      this.noise = buffer;
    }
  }

  /** Schedules the bars that start within the lookahead. */
  private schedule(): void {
    const context = this.context;
    if (context === null || this.master === null) return;
    while (this.nextBarAt < context.currentTime + LOOKAHEAD_S + BAR) {
      this.bar(this.nextBar, this.nextBarAt);
      this.nextBar++;
      this.nextBarAt += BAR;
    }
  }

  private bar(index: number, at: number): void {
    const { section, bar, round } = barAt(index);
    const chord = section.chords[bar]!;
    const eighth = BEAT / 2;
    const sixteenth = BEAT / 4;
    const last = bar === section.chords.length - 1;
    // Bass: the root on eighths, the octave on the last of each beat; or on every off-beat (the chorus's pulse); or held for the bar.
    if (section.bass === 'held') {
      this.saw(chord.root, at, BAR * 0.95, 0.45, 260);
    } else if (section.bass !== 'none') {
      for (let i = 0; i < 8; i++) {
        const up = section.bass === 'pulse' ? i % 2 === 1 : i % 4 === 3;
        this.saw(chord.root + (up ? 12 : 0), at + i * eighth, eighth * 0.85, 0.5, section.bass === 'pulse' ? 520 : 380);
      }
    }
    // Pad: the chord tones, two detuned saws each, for the bar.
    for (const tone of chord.tones) this.pad(chord.root + 12 + tone, at, BAR);
    // Arpeggio: the section's pattern, moved on one each time round; lifted an octave in the second half of every other bar.
    if (section.arp !== null) {
      const pattern = ARPS[(section.arp + round) % ARPS.length]!;
      const tones = [...chord.tones, ...chord.tones.map((t) => t + 12)];
      const step = section.eighths ? eighth : sixteenth;
      const steps = section.eighths ? 8 : 16;
      const bright = section.name === 'intro' ? section.bright + bar * 500 : section.bright;
      for (let i = 0; i < steps; i++) {
        const tone = tones[pattern[i]! % tones.length]!;
        const octave = bar % 2 === 1 && i >= steps / 2 ? 12 : 0;
        this.arp(chord.root + 24 + tone + octave, at + i * step, step * 0.9, bright);
      }
    }
    // Lead: the section's melody, if it has one.
    for (const [beat, beats, note] of section.lead?.[bar] ?? []) {
      this.lead(note + (section.leadShift ?? 0), at + beat * BEAT, beats * BEAT * 0.95);
    }
    // Drums.
    if (section.crash === true && bar === 0) this.crash(at);
    const roll = section.ending === 'build' && bar >= section.chords.length - 2;
    for (let beat = 0; beat < 4; beat++) {
      const t = at + beat * BEAT;
      const fill = last && section.ending === 'fill' && beat === 3;
      if (section.drums === 'full' || section.drums === 'drive') {
        this.kick(t);
        if (beat % 2 === 1 && !fill) this.snare(t, 0.5);
      }
      if (section.drums !== 'none') {
        this.hat(t, false);
        this.hat(t + eighth, section.drums === 'drive' || beat % 2 === 0);
      }
      if (fill) for (let i = 0; i < 4; i++) this.snare(t + i * sixteenth, 0.25 + i * 0.08);
      if (roll) {
        // Eighths over the first bar of the roll, sixteenths over the second, louder as it goes.
        const hits = bar === section.chords.length - 1 ? 4 : 2;
        for (let i = 0; i < hits; i++) this.snare(t + (i * BEAT) / hits, 0.12 + 0.05 * beat + (hits === 4 ? 0.12 : 0));
      }
    }
  }

  private saw(note: number, at: number, length: number, gain: number, cutoff: number): void {
    const context = this.context!;
    const osc = context.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.value = hz(note);
    const filter = context.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(cutoff * 2.2, at);
    filter.frequency.exponentialRampToValueAtTime(cutoff, at + length * 0.6);
    const env = context.createGain();
    env.gain.setValueAtTime(0, at);
    env.gain.linearRampToValueAtTime(gain, at + 0.01);
    env.gain.setTargetAtTime(0, at + length * 0.7, length * 0.12);
    osc.connect(filter).connect(env).connect(this.master!);
    osc.start(at);
    osc.stop(at + length + 0.3);
  }

  private pad(note: number, at: number, length: number): void {
    const context = this.context!;
    const env = context.createGain();
    env.gain.setValueAtTime(0, at);
    env.gain.linearRampToValueAtTime(0.055, at + 0.35);
    env.gain.setValueAtTime(0.055, at + length - 0.3);
    env.gain.linearRampToValueAtTime(0, at + length);
    const filter = context.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 900;
    filter.connect(env).connect(this.master!);
    for (const detune of [-7, 7]) {
      const osc = context.createOscillator();
      osc.type = 'sawtooth';
      osc.frequency.value = hz(note);
      osc.detune.value = detune;
      osc.connect(filter);
      osc.start(at);
      osc.stop(at + length + 0.05);
    }
  }

  private arp(note: number, at: number, length: number, bright: number): void {
    const context = this.context!;
    const osc = context.createOscillator();
    osc.type = 'square';
    osc.frequency.value = hz(note);
    const filter = context.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = bright;
    const env = context.createGain();
    env.gain.setValueAtTime(0, at);
    env.gain.linearRampToValueAtTime(0.09, at + 0.005);
    env.gain.exponentialRampToValueAtTime(0.001, at + length);
    osc.connect(filter).connect(env);
    env.connect(this.master!);
    env.connect(this.delay!);
    osc.start(at);
    osc.stop(at + length + 0.05);
  }

  /** The lead: a saw and a square an octave apart, with vibrato, held for the note, into the delay as well. */
  private lead(note: number, at: number, length: number): void {
    const context = this.context!;
    const filter = context.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 2600;
    const env = context.createGain();
    env.gain.setValueAtTime(0, at);
    env.gain.linearRampToValueAtTime(0.07, at + 0.03);
    env.gain.setValueAtTime(0.07, at + Math.max(0.03, length - 0.08));
    env.gain.linearRampToValueAtTime(0, at + length);
    filter.connect(env);
    env.connect(this.master!);
    env.connect(this.delay!);
    // Vibrato: a slow sine on the pitch, in cents, coming in after the attack.
    const lfo = context.createOscillator();
    lfo.frequency.value = 5.5;
    const depth = context.createGain();
    depth.gain.setValueAtTime(0, at);
    depth.gain.linearRampToValueAtTime(12, at + Math.min(0.4, length));
    lfo.connect(depth);
    for (const [type, octave, gain] of [['sawtooth', 0, 1], ['square', -12, 0.4]] as const) {
      const osc = context.createOscillator();
      osc.type = type;
      osc.frequency.value = hz(note + octave);
      depth.connect(osc.detune);
      const level = context.createGain();
      level.gain.value = gain;
      osc.connect(level).connect(filter);
      osc.start(at);
      osc.stop(at + length + 0.05);
    }
    lfo.start(at);
    lfo.stop(at + length + 0.05);
  }

  private kick(at: number): void {
    const context = this.context!;
    const osc = context.createOscillator();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(150, at);
    osc.frequency.exponentialRampToValueAtTime(42, at + 0.12);
    const env = context.createGain();
    env.gain.setValueAtTime(0.9, at);
    env.gain.exponentialRampToValueAtTime(0.001, at + 0.3);
    osc.connect(env).connect(this.master!);
    osc.start(at);
    osc.stop(at + 0.32);
  }

  private snare(at: number, gain: number): void {
    const context = this.context!;
    const burst = context.createBufferSource();
    burst.buffer = this.noise;
    const filter = context.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.value = 1800;
    filter.Q.value = 0.8;
    const env = context.createGain();
    env.gain.setValueAtTime(gain, at);
    env.gain.exponentialRampToValueAtTime(0.001, at + 0.18);
    burst.connect(filter).connect(env).connect(this.master!);
    burst.start(at);
    burst.stop(at + 0.2);
    // The body: a short sine.
    const osc = context.createOscillator();
    osc.frequency.setValueAtTime(200, at);
    osc.frequency.exponentialRampToValueAtTime(120, at + 0.08);
    const body = context.createGain();
    body.gain.setValueAtTime(gain * 0.7, at);
    body.gain.exponentialRampToValueAtTime(0.001, at + 0.1);
    osc.connect(body).connect(this.master!);
    osc.start(at);
    osc.stop(at + 0.12);
  }

  private hat(at: number, open: boolean): void {
    const context = this.context!;
    const burst = context.createBufferSource();
    burst.buffer = this.noise;
    const filter = context.createBiquadFilter();
    filter.type = 'highpass';
    filter.frequency.value = 7000;
    const env = context.createGain();
    const length = open ? 0.12 : 0.04;
    env.gain.setValueAtTime(open ? 0.16 : 0.1, at);
    env.gain.exponentialRampToValueAtTime(0.001, at + length);
    burst.connect(filter).connect(env).connect(this.master!);
    burst.start(at);
    burst.stop(at + length + 0.01);
  }

  /** A crash: a long highpassed noise, to open a section. */
  private crash(at: number): void {
    const context = this.context!;
    const burst = context.createBufferSource();
    burst.buffer = this.noise;
    const filter = context.createBiquadFilter();
    filter.type = 'highpass';
    filter.frequency.value = 5000;
    const env = context.createGain();
    env.gain.setValueAtTime(0.14, at);
    env.gain.exponentialRampToValueAtTime(0.001, at + 0.95);
    burst.connect(filter).connect(env).connect(this.master!);
    burst.start(at);
    burst.stop(at + 1);
  }
}

function clamp(value: number): number {
  return Math.min(1, Math.max(0, Number.isFinite(value) ? value : DEFAULT_VOLUME));
}

/** The one soundtrack, shared by the shell's controls and the scenes. */
export const synthwave = new Synthwave();
