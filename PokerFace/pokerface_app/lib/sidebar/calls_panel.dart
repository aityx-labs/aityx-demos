import 'package:flutter/material.dart';

import '../calls/aityx_call_view.dart';
import '../engine/game.dart';
import '../game/controller.dart';
import '../theme.dart';

/// Every decision asked of aityx, newest first: who, the situation in a
/// line, what the rules said and why. Tap one for the whole call.
class CallsPanel extends StatelessWidget {
  const CallsPanel({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calls = controller.calls;
    if (calls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Every decision at the table is one call to aityx: the '
            "player's strategy, as rules, run on their situation. The calls "
            'appear here as they are made.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: calls.length,
      itemBuilder: (context, i) => _CallTile(call: calls[i]),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});

  final AityxCall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = call.situation;
    final result = call.result;
    final taken = call.taken;
    final Widget outcome;
    if (call.error != null) {
      outcome = Text(
        call.error!,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
      );
    } else if (result == null) {
      outcome = Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text('Asking aityx…', style: theme.textTheme.bodySmall),
        ],
      );
    } else {
      outcome = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ActionBadge(
                kind: taken?.kind ?? result.kind,
                label: taken?.label ?? result.kind.label,
              ),
              const SizedBox(width: 8),
              if (result.rule != null)
                Text(
                  'rule ${result.rule}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              const Spacer(),
              if (result.tookMs != null)
                Text(
                  '${result.tookMs} ms',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.outlineVariant,
                  ),
                ),
            ],
          ),
          if (result.why != null) ...[
            const SizedBox(height: 4),
            Text(
              result.why!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (taken?.note != null) ...[
            const SizedBox(height: 2),
            Text(
              taken!.note!,
              style: theme.textTheme.bodySmall?.copyWith(color: Aityx.amber),
            ),
          ],
        ],
      );
    }
    return InkWell(
      onTap: call.pending ? null : () => showCall(context, call),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${call.number}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${call.seat.name} · ${call.strategy.name}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  'hand ${call.hand} · ${call.street.label.toLowerCase()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${(s['hole'] as List).join(' ')}'
              '${(s['board'] as List).isEmpty ? '' : ' on ${(s['board'] as List).join(' ')}'}'
              ' · ${s['made_hand'].toString().replaceAll('_', ' ')}'
              ' · equity ${_pct(s['equity'])}'
              ' · to call ${s['to_call']} of pot ${s['pot']}'
              '${s['to_call'] == 0 ? '' : ' (odds ${_pct(s['pot_odds'])})'}',
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            outcome,
          ],
        ),
      ),
    );
  }

  static String _pct(Object? v) => v is num ? '${(v * 100).round()}%' : '?';
}

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.kind, required this.label});

  final ActionKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      ActionKind.fold => Aityx.muted,
      ActionKind.check => Aityx.green,
      ActionKind.call => Aityx.green,
      ActionKind.raise => Aityx.orange,
      ActionKind.allIn => Aityx.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// The whole call, full screen: the request and the response, with the
/// key parts marked.
Future<void> showCall(BuildContext context, AityxCall call) {
  final result = call.result;
  final request = result?.request;
  final response = result?.response;
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Call #${call.number}: ${call.seat.name}, ${call.strategy.name}, '
            'hand ${call.hand} ${call.street.label.toLowerCase()}',
          ),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: request == null || response == null
              ? Center(
                  child: Text(
                    call.error ?? 'The API did not include the aityx call.',
                  ),
                )
              : AityxCallView(
                  request: request,
                  response: response,
                  responseSubtitle: 'the action, and the rule that chose it',
                  targets: callTargets(call),
                  fullScreen: true,
                ),
        ),
      ),
    ),
  );
}

/// The key parts of a call: highlighted in the pane and in its "Jump to"
/// bar.
List<JsonTarget> callTargets(AityxCall call) {
  const req = CallSide.request;
  const res = CallSide.response;
  final rule = call.result?.rule;
  return [
    const JsonTarget(
      req,
      'decision.inputs',
      'The situation, declared',
      "The table model's inputs: everything a strategy may look at, with "
          'its type and where the app takes it from.',
    ),
    JsonTarget(
      req,
      'decision.decisions',
      '${call.strategy.name}: the rules',
      "The player's strategy: the decisions of the model. aityx runs them, "
          'deterministically, on the situation.',
    ),
    const JsonTarget(
      req,
      'decision.decisions.action',
      'The action table',
      'The rules that pick the action, tried top to bottom: the first row '
          'that matches wins, and its "why" says why.',
    ),
    if (rule != null)
      JsonTarget(
        req,
        'decision.decisions.action.table.$rule',
        'Rule $rule, the one that fired',
        'The first row of the action table that matched the situation.',
      ),
    const JsonTarget(
      req,
      'decision.decisions.raise_to',
      'The raise amount',
      'How much to make it when raising, as an expression over the '
          'situation; the table keeps it between the minimum raise and the '
          'stack.',
    ),
    const JsonTarget(
      req,
      'state',
      'The situation',
      "The player's situation as the app computed it: cards, hand, equity, "
          'the pot, what it costs to call, position, and a random number for '
          'strategies that mix their play.',
    ),
    const JsonTarget(
      req,
      'state.equity',
      'Equity',
      'The chance of winning at showdown, estimated by the app with random '
          'run-outs against the players still in the hand.',
    ),
    const JsonTarget(
      req,
      'state.pot_odds',
      'Pot odds',
      'The share of the pot a call costs: the equity must beat it for a '
          'call to be profitable.',
    ),
    const JsonTarget(
      res,
      'answers.action',
      'The action',
      "aityx's answer: what the player does.",
    ),
    const JsonTarget(
      res,
      'answers.raise_to',
      'Raise to',
      'The total bet when raising, from the strategy\'s raise_to.',
    ),
    const JsonTarget(
      res,
      'receipt.decisions.action',
      'The receipt',
      'Which row of the action table fired (rule), and which cells of each '
          'row matched.',
    ),
  ];
}
