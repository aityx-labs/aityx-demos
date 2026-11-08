// The match's sound effects, synthesized as the music is (Web Audio, no
// recordings): a chime when a team's new robot comes into play, an impact
// and a rising zap when a robot reaches the mainframe, a fanfare when the
// match ends. At the music's volume (its slider), whether the music plays
// or not; silent at 0. The browser lets audio start after the user acts:
// `prime` is called on Start.

import { synthwave } from './synthwave';

/** The effects' level against the music's: a little over it, short as they are. */
const LEVEL = 0.35;

let context: AudioContext | null = null;

function audio(): AudioContext | null {
  if (typeof AudioContext === 'undefined') return null;
  context ??= new AudioContext();
  if (context.state === 'suspended') void context.resume();
  return context;
}

/** Opens the audio on the user's act (Start), so the first effect is heard. */
export function prime(): void {
  audio();
}

/** One note: `type` from `from` Hz to `to` Hz over `length` s, at `gain`, starting `at` s from now. */
function tone(type: OscillatorType, from: number, to: number, length: number, gain: number, at = 0): void {
  const ctx = audio();
  const volume = synthwave.volume * LEVEL;
  if (ctx === null || volume <= 0) return;
  const start = ctx.currentTime + at;
  const osc = ctx.createOscillator();
  const amp = ctx.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(from, start);
  osc.frequency.exponentialRampToValueAtTime(Math.max(1, to), start + length);
  amp.gain.setValueAtTime(0, start);
  amp.gain.linearRampToValueAtTime(gain * volume, start + 0.01);
  amp.gain.exponentialRampToValueAtTime(0.0001, start + length);
  osc.connect(amp).connect(ctx.destination);
  osc.start(start);
  osc.stop(start + length + 0.05);
}

/** A burst of noise, low-passed from `from` Hz to `to` Hz. */
function noise(length: number, gain: number, from: number, to: number, at = 0): void {
  const ctx = audio();
  const volume = synthwave.volume * LEVEL;
  if (ctx === null || volume <= 0) return;
  const start = ctx.currentTime + at;
  const buffer = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * length), ctx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  const source = ctx.createBufferSource();
  source.buffer = buffer;
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(from, start);
  filter.frequency.exponentialRampToValueAtTime(Math.max(20, to), start + length);
  const amp = ctx.createGain();
  amp.gain.setValueAtTime(gain * volume, start);
  amp.gain.exponentialRampToValueAtTime(0.0001, start + length);
  source.connect(filter).connect(amp).connect(ctx.destination);
  source.start(start);
}

/** A team's new robot comes into play: a quick rising chime, the team's own pitch. */
export function botArrives(team: number): void {
  const root = [523.25, 587.33, 659.25][team % 3]!;
  tone('square', root, root, 0.08, 0.35);
  tone('square', root * 1.5, root * 1.5, 0.12, 0.3, 0.07);
  tone('triangle', root * 2, root * 2, 0.2, 0.25, 0.14);
}

/** A robot reaches the mainframe: a low impact and a rising zap. */
export function hackerArrives(): void {
  tone('sine', 140, 45, 0.45, 0.9);
  noise(0.3, 0.6, 3000, 200);
  tone('sawtooth', 300, 1400, 0.25, 0.25, 0.05);
}

/** The match is over: a rising fanfare over a swell. */
export function victory(): void {
  const notes = [440, 523.25, 659.25, 880, 1046.5];
  notes.forEach((f, i) => tone('square', f, f, 0.22, 0.3, i * 0.11));
  tone('sawtooth', 220, 220, 1.4, 0.25, 0.55);
  tone('sawtooth', 329.63, 329.63, 1.4, 0.2, 0.55);
  tone('triangle', 880, 880, 1.6, 0.25, 0.55);
  noise(1.2, 0.35, 8000, 400, 0.5);
}
