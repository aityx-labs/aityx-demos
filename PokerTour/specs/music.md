# Music

The table plays lo-fi jazz, minimal: five tracks in
[assets/music/](../pokertour_app/assets/music) (their titles, keys,
tempos, loops and lead voices in its README), 70 to 84 BPM, about 2½
minutes each, 11 MB together. They are made by
[scripts/jazz.dart](../scripts/jazz.dart), from nothing, with a seeded
random generator, so every run makes the same files. No samples, no
recordings, no third-party music.

- **One loop a track**: four bars of extended chords (ninths,
  thirteenths), played the same each time round.
- **Keys**: a mellow FM electric piano, laid back and softly rolled,
  through a lowpass that opens through the intro, dims in the break and
  closes through the outro.
- **Bass**: a round sub bass, mostly the roots, now and then a fifth,
  an octave or a step into the next chord.
- **Motif**: a few notes from the key's pentatonic scale over four
  bars, then its answer, played only in the theme sections, on nylon
  guitar (a plucked string), vibraphone or high keys.
- **Drums**: lazy boom-bap, a soft kick, a dusty snare late on two and
  four, swung hats; sines and filtered noise, crushed to ten bits and
  dulled. The kick ducks the rest a little.
- **Form**: intro (keys alone), groove (keys, bass, drums), theme (and
  the motif), groove, break (keys and bass, no drums), theme, and an
  outro on the keys alone.
- **Lo-fi**: everything goes through a wobbling tape delay (a slow wow
  and a faint flutter, about ten cents at the most), a dark master
  lowpass, and vinyl hiss, crackle and the odd pop.

It renders WAV and encodes MP3 with ffmpeg (112 kbps, 44.1 kHz stereo),
peaks under −3 dBFS and about −19 LUFS, the five within a decibel of
each other.
`pubspec.yaml` lists the five files, so the folder's README stays out of
the bundle.

## Playing

[Soundtrack](../pokertour_app/lib/music/soundtrack.dart) starts when the
table opens, stops when it closes (a sign-out: the sign-in page has no
controls), and plays the five in a random order, round and round: every
round has each track once, in a new order, and a round never starts
with the track that ended the last, so none plays twice in a row. On the
web the player is the browser's audio element
([track_player_web.dart](../pokertour_app/lib/music/track_player_web.dart));
elsewhere (the tests) it is silent. A browser that refuses to play
before the user has touched the page (a reload, already signed in) gets
the music at the first click or key.

## Controls

On the app bar's right, before the version
([music_control.dart](../pokertour_app/lib/music/music_control.dart)):

- a **note** button that mutes the music and plays it again (a crossed
  note while muted), pausing the track where it is;
- on a window at least 700 px wide, a **volume slider**, 0 to 100%,
  30% at first: background music. Disabled while muted.

The volume and the mute are kept in the browser's localStorage
(`pokertour.music.volume`, `pokertour.music.muted`), so they last from
one visit to the next; a muted player stays silent until unmuted. When
the browser blocks storage the music starts at the defaults and the
settings last the visit.
