import 'package:flutter/material.dart';

import '../api/poker_api.dart';
import '../engine/game.dart';
import '../game/controller.dart';
import '../theme.dart';
import 'rules_sheet.dart';
import 'strategy_editor.dart';

/// The players at the table and their strategies: add one, change a
/// strategy, remove one; and the strategies themselves, to read or to
/// write new ones.
class PlayersPanel extends StatefulWidget {
  const PlayersPanel({super.key, required this.controller});

  final GameController controller;

  @override
  State<PlayersPanel> createState() => _PlayersPanelState();
}

class _PlayersPanelState extends State<PlayersPanel> {
  late final _name = TextEditingController();
  Strategy? _strategy;

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _strategy = c.strategies.firstOrNull;
    if (_strategy != null) _name.text = c.suggestName(_strategy!);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _name.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _add() {
    final strategy = _strategy;
    if (strategy == null) return;
    final name = _name.text.trim().isEmpty
        ? c.suggestName(strategy)
        : _name.text.trim();
    final seat = c.addPlayer(name, strategy);
    if (seat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The table is full: nine seats.')),
      );
      return;
    }
    _name.text = c.suggestName(strategy);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strategies = c.strategies;
    if (_strategy != null && !strategies.contains(_strategy)) {
      _strategy = strategies.firstOrNull;
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('At the table', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (c.game.seats.isEmpty)
          Text(
            'Nobody yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        for (final seat in c.game.seats) _SeatRow(seat: seat, controller: c),
        const SizedBox(height: 20),
        Text('Add a player', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                key: const Key('new-player-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<Strategy>(
                key: const Key('new-player-strategy'),
                initialValue: _strategy,
                decoration: const InputDecoration(
                  labelText: 'Strategy',
                  isDense: true,
                ),
                items: [
                  for (final s in strategies)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (s) => setState(() {
                  _strategy = s;
                  if (s != null) _name.text = c.suggestName(s);
                }),
              ),
            ),
            FilledButton.icon(
              key: const Key('add-player'),
              onPressed:
                  _strategy == null || c.game.seats.length >= PokerGame.maxSeats
                  ? null
                  : _add,
              icon: const Icon(Icons.person_add),
              label: const Text('Add'),
            ),
          ],
        ),
        if (_strategy != null) ...[
          const SizedBox(height: 6),
          Text(
            _strategy!.tagline,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (c.game.handInProgress) ...[
          const SizedBox(height: 6),
          Text(
            'A player added now is dealt in at the next hand.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text('Strategies', style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              key: const Key('new-strategy'),
              onPressed: strategies.isEmpty
                  ? null
                  : () => showStrategyEditor(
                      context,
                      c,
                      from: strategies.first,
                      writing: true,
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Write one'),
            ),
          ],
        ),
        Text(
          'A strategy is a set of rules, run on aityx for every decision: a '
          'table that picks the action from the situation, and an expression '
          'for the raise. Read the presets, or write your own from one.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final s in strategies) _StrategyRow(strategy: s, controller: c),
      ],
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({required this.seat, required this.controller});

  final Seat seat;
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strategy = controller.strategyOf(seat);
    final net = seat.net;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => showPlayerRules(context, controller, seat),
                    child: Text(
                      seat.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    '${seat.stack} chips · '
                    '${net >= 0 ? '+' : ''}$net net · '
                    '${seat.handsWon} of ${seat.handsPlayed} hands won'
                    '${seat.place != null ? ' · ${ordinal(seat.place!)}' : ''}'
                    '${seat.leaving ? ' · leaving' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: DropdownButton<Strategy>(
                value: strategy,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final s in controller.strategies)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (s) {
                  if (s != null) controller.setStrategy(seat, s);
                },
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: seat.leaving
                  ? null
                  : () => controller.removePlayer(seat),
              icon: const Icon(Icons.person_remove_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrategyRow extends StatelessWidget {
  const _StrategyRow({required this.strategy, required this.controller});

  final Strategy strategy;
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inUse = controller.game.seats.any((s) => s.strategyId == strategy.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Text(
              strategy.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (strategy.custom) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Aityx.green),
                ),
                child: const Text(
                  'yours',
                  style: TextStyle(fontSize: 10, color: Aityx.green),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          strategy.tagline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => showStrategyEditor(
                context,
                controller,
                from: strategy,
                editing: strategy.custom ? strategy : null,
              ),
              child: Text(strategy.custom ? 'Edit' : 'Rules'),
            ),
            if (strategy.custom)
              IconButton(
                tooltip: inUse ? 'In use at the table' : 'Delete',
                onPressed: inUse
                    ? null
                    : () => controller.removeCustom(strategy),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    );
  }
}

/// The players panel as a side sheet.
Future<void> showPlayers(BuildContext context, GameController controller) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Column(
          children: [
            AppBar(
              title: const Text('Players and strategies'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Expanded(child: PlayersPanel(controller: controller)),
          ],
        ),
      ),
    ),
  );
}
