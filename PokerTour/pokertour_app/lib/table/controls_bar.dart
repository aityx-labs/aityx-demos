import 'package:flutter/material.dart';

import '../api/aityx_poker_api.dart';
import '../game/controller.dart';
import '../tour/tour_session.dart';

/// Play, pause and step, the pace between steps, rebuys and a reset. A
/// table on aityx in the tour waits, for Play and Step, until the
/// player's own key works.
class ControlsBar extends StatelessWidget {
  const ControlsBar({
    super.key,
    required this.controller,
    required this.onPlayers,
  });

  final GameController controller;
  final VoidCallback onPlayers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    final session = TourScope.of(context);
    final keyOk = session == null || c.api is! AityxPokerApi || session.canPlay;
    final paceLabel = c.pace == 0
        ? 'Full speed'
        : '${c.pace.toStringAsFixed(1)} s between steps';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Tooltip(
            message: keyOk ? '' : 'Set a working aityx key in Profile to play',
            child: FilledButton.icon(
              key: const Key('play'),
              onPressed: c.loaded && c.loadError == null && (keyOk || c.playing)
                  ? (c.playing ? c.pause : c.play)
                  : null,
              icon: Icon(c.playing ? Icons.pause : Icons.play_arrow),
              label: Text(c.playing ? 'Pause' : 'Play'),
            ),
          ),
          OutlinedButton.icon(
            key: const Key('step'),
            onPressed: c.loaded && !c.playing && keyOk ? c.step : null,
            icon: const Icon(Icons.skip_next),
            label: const Text('Step'),
          ),
          SizedBox(
            width: 300,
            child: Row(
              children: [
                Tooltip(
                  message: 'Slower',
                  child: Icon(
                    Icons.slow_motion_video,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Slider(
                    // Left is slow, right is fast.
                    value: GameController.maxPace - c.pace,
                    min: 0,
                    max: GameController.maxPace,
                    divisions: 40,
                    label: paceLabel,
                    onChanged: (v) => c.setPace(GameController.maxPace - v),
                  ),
                ),
                Tooltip(
                  message: 'Faster',
                  child: Icon(
                    Icons.fast_forward,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            paceLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPlayers,
            icon: const Icon(Icons.group),
            label: Text('Players (${c.game.seats.length})'),
          ),
          TextButton.icon(
            key: const Key('reset'),
            onPressed: c.game.handNumber == 0 ? null : c.reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('New tournament'),
          ),
        ],
      ),
    );
  }
}
