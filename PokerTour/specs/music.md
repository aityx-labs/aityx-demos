# Music

The table plays jazz: five soft lounge-trio tracks in
[assets/music/](../pokertour_app/assets/music) (their titles, styles,
keys and tempos in its README), about 2½ minutes each, 11 MB together.
They are made by [scripts/jazz.dart](../scripts/jazz.dart), from nothing:
an FM electric piano, an additive upright bass, vibraphone, soft sax or
flute, and brushes and cymbals of filtered noise, playing notes the
script composes with a seeded random generator, so every run makes the
same files. No samples, no recordings, no third-party music. It renders
WAV and encodes MP3 with ffmpeg (112 kbps, 44.1 kHz stereo), peaks under
−3 dBFS and about −18 LUFS, the five within a decibel of each other.
`pubspec.yaml` lists the five files, so the folder's README stays out of
the bundle.

## Playing

[Soundtrack](../pokertour_app/lib/music/soundtrack.dart) starts when the
table opens and plays the five in a random order, round and round: every
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
one visit to the next; a muted player stays silent until unmuted.
