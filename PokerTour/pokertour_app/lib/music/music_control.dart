import 'package:flutter/material.dart';

import 'soundtrack.dart';

/// The soundtrack's controls, for the app bar: a mute button and, on a
/// wide enough window, a volume slider.
class MusicControl extends StatelessWidget {
  const MusicControl({super.key, required this.soundtrack});

  final Soundtrack soundtrack;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return ListenableBuilder(
      listenable: soundtrack,
      builder: (context, _) {
        final m = soundtrack;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('music-mute'),
              tooltip: m.muted ? 'Play the music' : 'Mute the music',
              onPressed: m.toggleMute,
              icon: Icon(m.muted ? Icons.music_off_outlined : Icons.music_note_outlined),
            ),
            if (wide)
              SizedBox(
                width: 110,
                child: Slider(
                  key: const Key('music-volume'),
                  value: m.volume,
                  onChanged: m.muted ? null : m.setVolume,
                  semanticFormatterCallback: (v) => 'Music volume ${(v * 100).round()}%',
                ),
              ),
          ],
        );
      },
    );
  }
}
