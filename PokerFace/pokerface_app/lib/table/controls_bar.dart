import 'package:flutter/material.dart';

import '../game/controller.dart';

/// Play, pause and step, the pace between steps, rebuys and a reset.
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
          FilledButton.icon(
            key: const Key('play'),
            onPressed: c.loaded && c.loadError == null
                ? (c.playing ? c.pause : c.play)
                : null,
            icon: Icon(c.playing ? Icons.pause : Icons.play_arrow),
            label: Text(c.playing ? 'Pause' : 'Play'),
          ),
          OutlinedButton.icon(
            key: const Key('step'),
            onPressed: c.loaded && !c.playing ? c.step : null,
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
