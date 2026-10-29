import 'package:flutter/material.dart';

import '../engine/game.dart';
import '../game/controller.dart';
import '../players/rules_sheet.dart';
import '../theme.dart';
import 'avatar.dart';

/// The tournament is over: the winner, their strategy, and where everyone
/// finished; with the winner's rules a tap away, and a new tournament.
Future<void> showWinner(
  BuildContext context,
  GameController controller,
  TournamentOver step,
) {
  final winner = step.winner;
  final strategy = controller.strategyOf(winner);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        title: const Text('🏆 Tournament over'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(seat: winner, size: 56, winner: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${winner.name} wins',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Aityx.amber,
                          ),
                        ),
                        Text(
                          'with ${winner.stack} chips, after ${controller.game.handNumber} hands',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (strategy != null) ...[
                Text(
                  'The winning strategy: ${strategy.name}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(strategy.tagline, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  _summary(strategy.decisions),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                'Standings',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              for (final s in step.standings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          s.place == null ? '' : ordinal(s.place!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: s.place == 1
                                ? Aityx.amber
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(avatarFor(s.strategyId)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.name} · ${controller.strategyOf(s)?.name ?? s.strategyId}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${s.handsWon} of ${s.handsPlayed} hands won',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              showPlayerRules(context, controller, winner);
            },
            child: const Text("The winner's rules"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            key: const Key('new-tournament'),
            onPressed: () {
              controller.reset();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('New tournament'),
          ),
        ],
      );
    },
  );
}

/// The rules in one line: how many, and what else they test.
String _summary(Map<String, Object?> decisions) {
  final table = ActionTable.from(decisions);
  final others = decisions.keys
      .where((k) => k != 'action' && k != 'raise_to')
      .toList();
  final rules = table == null
      ? 'an expression for the action'
      : '${table.rules.length} rules for the action';
  return '$rules, a raise expression'
      '${others.isEmpty ? '' : ', and ${others.join(', ')}'}.';
}
