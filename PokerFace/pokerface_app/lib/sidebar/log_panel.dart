import 'package:flutter/material.dart';

import '../api/poker_api.dart';
import '../engine/game.dart';
import '../game/controller.dart';
import '../players/rules_sheet.dart';
import '../theme.dart';
import 'calls_panel.dart';

/// The hands' story, newest first: deals, actions, showdowns. An action
/// expands, when tapped, into why: the rule that fired, its conditions,
/// and the situation that met them; and the whole call is a tap further.
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, required this.controller});

  final GameController controller;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _open = <LogEntry>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final log = widget.controller.game.log;
    if (log.isEmpty) {
      return Center(
        child: Text(
          'Nothing has happened yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: log.length,
      itemBuilder: (context, i) {
        final e = log[log.length - 1 - i];
        final color = switch (e.kind) {
          'hand' => scheme.primary,
          'deal' => Aityx.amber,
          'showdown' => Aityx.green,
          'info' => scheme.onSurfaceVariant,
          _ => scheme.onSurface,
        };
        final call = e.call == null
            ? null
            : widget.controller.calls
                  .where((c) => c.number == e.call)
                  .firstOrNull;
        final line = Text(
          e.text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: e.kind == 'hand' ? FontWeight.bold : null,
          ),
        );
        if (call == null) {
          return Padding(
            padding: EdgeInsets.fromLTRB(12, e.kind == 'hand' ? 10 : 2, 12, 2),
            child: line,
          );
        }
        final open = _open.contains(e);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: Key('log-${log.length - 1 - i}'),
              onTap: () => setState(() {
                if (!_open.remove(e)) _open.add(e);
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
                child: Row(
                  children: [
                    Expanded(child: line),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: scheme.outlineVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (open) _Why(call: call),
          ],
        );
      },
    );
  }
}

/// Why a player did what they did: the rule that fired, with its
/// conditions; the situation that met them, the numbers the rules turn
/// on first; and the strategy's other decisions.
class _Why extends StatelessWidget {
  const _Why({required this.call});

  final AityxCall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = call.result;
    final s = call.situation;
    final table = ActionTable.from(call.strategy.decisions);
    final rule =
        r?.rule != null && table != null && r!.rule! <= table.rules.length
        ? table.rules[r.rule! - 1]
        : null;
    Widget chip(String text, {Color? color}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color ?? scheme.outlineVariant),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: 11.5,
          color: color,
        ),
      ),
    );
    String pct(Object? v) => v is num ? '${(v * 100).round()}%' : '?';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (call.error != null)
            Text(
              call.error!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            )
          else if (r == null)
            Text('Still deciding…', style: theme.textTheme.bodySmall)
          else ...[
            Text(
              '${call.strategy.name}, rule ${r.rule ?? '?'}'
              '${rule != null && rule.isElse ? ' (otherwise)' : ''}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (r.why != null) ...[
              const SizedBox(height: 2),
              Text(r.why!, style: theme.textTheme.bodySmall),
            ],
            if (rule != null && !rule.isElse) ...[
              const SizedBox(height: 6),
              Text(
                'The rule matched because',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in rule.when.entries)
                    chip(
                      '${c.key} ${_condition(c.value)}  ← ${_valueOf(c.key, s, r)}',
                      color: scheme.primary,
                    ),
                ],
              ),
            ],
            if (call.taken?.note != null) ...[
              const SizedBox(height: 4),
              Text(
                'The table played it as ${call.taken!.label.toLowerCase()}: ${call.taken!.note}',
                style: theme.textTheme.bodySmall?.copyWith(color: Aityx.amber),
              ),
            ],
          ],
          const SizedBox(height: 6),
          Text(
            'The situation',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              chip(
                '${(s['hole'] as List).join(' ')}${(s['board'] as List).isEmpty ? '' : ' on ${(s['board'] as List).join(' ')}'}',
              ),
              chip('${s['street']} · ${s['position']}'),
              chip('hand ${s['hand']}'),
              chip('made ${s['made_hand']}'),
              if (s['flush_draw'] == true) chip('flush draw'),
              if (s['straight_draw'] != 'none')
                chip('${s['straight_draw']} straight draw'),
              chip('equity ${pct(s['equity'])}'),
              chip(
                'pot ${s['pot']} · to call ${s['to_call']} · pot odds ${pct(s['pot_odds'])}',
              ),
              chip('bet ${s['current_bet']} · raises ${s['raises']}'),
              chip('stack ${s['stack']} (${s['stack_bb']} bb)'),
              chip('min raise ${s['min_raise']} · max ${s['max_raise']}'),
              chip(
                '${s['players_in_hand']} in hand · ${s['players_after']} after',
              ),
              chip('random ${s['random']}'),
            ],
          ),
          if (r != null && r.decisions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              "The strategy's own decisions",
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in r.decisions.entries)
                  chip('${d.key} = ${_fmt(d.value)}'),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: call.pending ? null : () => showCall(context, call),
              icon: const Icon(Icons.receipt_long, size: 16),
              label: const Text('The whole call'),
            ),
          ),
        ],
      ),
    );
  }

  /// The value the condition saw: the situation's input, or the
  /// strategy's own decision.
  static String _valueOf(String name, Map<String, Object?> s, ActResult r) {
    if (s.containsKey(name)) return _fmt(s[name]);
    if (r.decisions.containsKey(name)) return _fmt(r.decisions[name]);
    return '?';
  }

  static String _fmt(Object? v) => switch (v) {
    1.0 || 1 when v is! bool => '1',
    num n when n == n.roundToDouble() => '${n.round()}',
    _ => '$v',
  };

  static String _condition(String cell) {
    final c = cell.trim();
    if (c.startsWith('<') ||
        c.startsWith('>') ||
        c.startsWith('[') ||
        c.startsWith('=') ||
        c.startsWith('not(')) {
      return c;
    }
    if (c.contains(',')) return 'in $c';
    return '= $c';
  }
}
