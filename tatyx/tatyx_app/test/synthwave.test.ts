import { describe, expect, it } from 'vitest';
import { SONGS, barsOf, nextSong } from '../src/audio/synthwave';

describe('the soundtrack', () => {
  it('is five songs: Neon Drive and four soft ones, slower', () => {
    expect(SONGS.map((s) => s.name)).toEqual(['Neon Drive', 'Night Drive', 'Palm Shadows', 'Pastel Horizon', 'Afterglow']);
    for (const song of SONGS.slice(1)) {
      expect(song.voice).toBe('soft');
      expect(song.bpm).toBeLessThan(SONGS[0]!.bpm);
      expect(song.level).toBeLessThan(1);
    }
  });

  it('has songs of whole bars, each lead line under a chord, each lasting about a minute or more', () => {
    for (const song of SONGS) {
      const bars = barsOf(song);
      expect(bars.length).toBeGreaterThanOrEqual(24);
      expect((bars.length * 4 * 60) / song.bpm).toBeGreaterThan(60);
      for (const section of song.sections) {
        expect(section.chords.length).toBeGreaterThan(0);
        if (section.lead) expect(section.lead.length).toBeLessThanOrEqual(section.chords.length);
        for (const line of section.lead ?? []) {
          for (const [beat, beats] of line) expect(beat + beats).toBeLessThanOrEqual(4);
        }
      }
    }
  });

  it('goes from song to song at random, never the same one twice in a row, and reaches them all', () => {
    let seed = 7;
    const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    let song = nextSong(null, SONGS, random);
    const heard = new Set([song.name]);
    for (let i = 0; i < 200; i++) {
      const next = nextSong(song, SONGS, random);
      expect(next).not.toBe(song);
      heard.add(next.name);
      song = next;
    }
    expect(heard.size).toBe(SONGS.length);
    // With one song only, it plays again.
    expect(nextSong(SONGS[0]!, [SONGS[0]!])).toBe(SONGS[0]);
  });
});
