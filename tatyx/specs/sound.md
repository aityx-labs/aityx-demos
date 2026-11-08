# Sound

## The soundtrack

A synthwave song, played by the browser itself with Web Audio
([audio/synthwave.ts](../tatyx_app/src/audio/synthwave.ts)): there is no
recording to license and nothing to download. 104 BPM in A minor, in
sections (`SONG`), 48 bars, about a minute and fifty seconds:

| Section | Bars | Chords | What plays |
|---|---|---|---|
| Intro | 4 | Am F C G | Pad, the arpeggio opening bar by bar, hi-hats |
| Verse | 8 | Am F C G ×2 | Bass on eighths, pad, arpeggio, the full kit |
| Verse, the lead | 8 | Am F C G ×2 | The same, another arpeggio, and the lead's melody |
| Chorus | 8 | F G Am Am F G C E | Pulsing bass, a brighter arpeggio, the chorus melody, open hats on every off-beat, a crash |
| Breakdown | 8 | Dm F Am G Dm F Am E | Held bass, the arpeggio in eighths, no kit; a snare roll over the last two bars builds back up |
| Chorus, up | 8 | F G Am Am F G C E | The chorus with the melody an octave up |
| Outro | 4 | Am F C G | Held bass, pad, arpeggio, hi-hats, a crash |

After the outro it goes round again from the verse (44 bars, about a
minute and forty), each time round with every section's arpeggio moved
on to the next of four patterns, so no two rounds sound the same. Every
section but the breakdown and the outro ends on a snare fill.

- **Bass**: a sawtooth through a lowpass that opens on each note: the
  root on eighths with the octave on the last eighth of each beat (the
  verse), on every off-beat (the chorus's pulse), or held for the bar.
- **Pad**: the chord's tones, two sawtooths each detuned 7 cents apart,
  through a lowpass, held for the bar.
- **Arpeggio**: a square wave, sixteenths (eighths in the breakdown)
  over two octaves of the chord in one of four patterns, lifted an
  octave in the second half of every other bar, through a lowpass that
  is the section's brightness, with a dotted-eighth delay (the
  synthwave echo).
- **Lead**: a sawtooth with a square an octave under it, a vibrato that
  comes in after the attack, through the same delay.
- **Drums**: a sine kick with a pitch drop on every beat, a snare (a
  bandpassed noise burst over a short sine) on two and four, hi-hats
  (highpassed noise) on eighths, open before each snare (on every
  off-beat in the chorus), a crash (a long highpassed noise) opening the
  choruses and the outro.
- A compressor and a master gain of 0.28 at full volume, scaled by the
  volume slider (so 0.14 at the default), so it sits under the game.

The bars are scheduled a little ahead with a timer, the usual Web Audio
pattern, so the song never drifts.

## When it plays

Browsers only let audio start after the user acts on the page: **Play**
on the title is that act, and starts the song. The **music** button in
the bar turns it off and on; the choice is kept in localStorage
(`tatyx.music`), and the button shows it. Off, the song fades over a
tenth of a second and the scheduler stops.

The **volume slider** beside the button, 0 to 100%, scales the master
gain while the song plays and is kept in localStorage (`tatyx.volume`).
It starts at 50%, quiet enough to sit under the game; its tooltip says
the percentage.

## Next

- Sound effects: a byte picked up, a byte dropped home, the hack's
  progress, a link gone.
- A second loop for the hack's last stretch, faster.
