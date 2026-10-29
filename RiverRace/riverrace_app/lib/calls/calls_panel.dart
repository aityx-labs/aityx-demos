import 'package:flutter/material.dart';

import '../strategy/decide.dart';
import 'call_json_view.dart';

/// A pilot as the calls show it: its name and color at the time.
class PilotLabel {
  const PilotLabel(this.name, this.color);

  final String name;
  final Color color;
}

/// One decision's call to aityx, as the API answered it, or the error it
/// answered instead.
class CallRecord {
  const CallRecord(
    this.id,
    this.frame,
    this.at, {
    this.decision,
    this.error,
    this.pilots = const {},
    this.senses = const {},
  });

  final int id;

  /// The race's frame the decision was asked at.
  final int frame;
  final DateTime at;
  final Decision? decision;
  final String? error;

  /// By pilot id: who, and what its plane sensed.
  final Map<String, PilotLabel> pilots;
  final Map<String, Map<String, Object>> senses;
}

/// The key parts of the request, by path.
const requestHighlights = {
  'state.p1': 'What pilot 1 senses',
  'state.p2': 'What pilot 2 senses',
  'decision.functions.strategy_p1.body': "Pilot 1's rules",
  'decision.functions.strategy_p2.body': "Pilot 2's rules",
  'decision.decisions': 'What is asked',
};

/// The key parts of the response, by path.
const responseHighlights = {
  'answers.p1_action': 'What pilot 1 does',
  'answers.p2_action': 'What pilot 2 does',
  'receipt.functions.strategy_p1': 'The rule that fired, pilot 1',
  'receipt.functions.strategy_p2': 'The rule that fired, pilot 2',
};

/// The side panel: every call to aityx, newest first, each with what it
/// decided for each pilot, and the request sent and the response received.
class CallsPanel extends StatefulWidget {
  const CallsPanel({
    super.key,
    required this.calls,
    required this.total,
    this.onClear,
  });

  final List<CallRecord> calls;

  /// Calls made since the last clear (the panel keeps the latest).
  final int total;
  final VoidCallback? onClear;

  @override
  State<CallsPanel> createState() => _CallsPanelState();
}

class _CallsPanelState extends State<CallsPanel> {
  final _open = <int>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final calls = widget.calls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'aityx calls',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${widget.total}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: 'Clear the calls',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: calls.isEmpty ? null : widget.onClear,
              ),
            ],
          ),
        ),
        Expanded(
          child: calls.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Every few frames the race asks aityx what the two '
                      'aityx pilots do: what each plane senses and its '
                      'rules go in, and the rule that fires comes back. '
                      'The calls show here as they happen.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: calls.length,
                  itemBuilder: (context, i) {
                    final call = calls[i];
                    return CallCard(
                      key: ValueKey(call.id),
                      call: call,
                      expanded: _open.contains(call.id),
                      onToggle: () => setState(() {
                        if (!_open.remove(call.id)) _open.add(call.id);
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// One call: the frame, how long aityx took, and per pilot the rule that
/// fired and what it does; expanded, what each plane sensed, and the
/// request and the response.
class CallCard extends StatelessWidget {
  const CallCard({
    super.key,
    required this.call,
    required this.expanded,
    required this.onToggle,
  });

  final CallRecord call;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final decision = call.decision;
    final facts = [
      'frame ${call.frame}',
      if (decision?.tookMs case final ms?) '$ms ms',
      if (decision?.inputTokens case final tokens?) '$tokens tokens',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: decision == null ? null : onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Decision ${call.id}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        facts.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (decision != null)
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (call.error case final error?)
                    Text(
                      error,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  if (decision != null)
                    for (final MapEntry(key: id, value: action)
                        in decision.actions.entries)
                      _ActionLine(
                        label: call.pilots[id],
                        rule: action.rule,
                        text:
                            '${action.steer} · ${action.throttle}'
                            '${action.fire ? ' · fire' : ''}',
                        why: action.why,
                      ),
                ],
              ),
            ),
          ),
          if (expanded && decision != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final MapEntry(key: id, value: sense)
                      in call.senses.entries)
                    _Senses(label: call.pilots[id], sense: sense),
                  CallJsonView(
                    title: 'REQUEST',
                    subtitle: 'sent: POST /v1/systemone, rules and senses',
                    json: decision.aityxRequest,
                    highlights: requestHighlights,
                  ),
                  CallJsonView(
                    title: 'RESPONSE',
                    subtitle: 'received: what aityx answered',
                    json: decision.aityxResponse,
                    highlights: responseHighlights,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionLine extends StatelessWidget {
  const _ActionLine({
    required this.label,
    required this.rule,
    required this.text,
    this.why,
  });

  final PilotLabel? label;
  final int? rule;
  final String text;
  final String? why;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = label?.color ?? theme.colorScheme.onSurface;
    return Tooltip(
      message: why ?? '',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label?.name ?? '?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              rule == null || rule == 0 ? '  no rule' : '  rule $rule',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Text(' → '),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Senses extends StatelessWidget {
  const _Senses({required this.label, required this.sense});

  final PilotLabel? label;
  final Map<String, Object> sense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${label?.name ?? '?'} sensed  ',
              style: TextStyle(
                color: label?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: [
                for (final MapEntry(:key, :value) in sense.entries)
                  '$key $value',
              ].join(' · '),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
