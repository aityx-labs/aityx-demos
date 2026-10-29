import 'package:flutter/material.dart';

import '../game/race.dart';
import '../theme.dart';
import 'strategy.dart';

/// An aityx pilot's card: its plane's score, lives and fuel, and its
/// strategy's rules, the one that fired last marked. Rules can be added,
/// edited, moved and removed, and the whole strategy swapped for another;
/// changes reach aityx with the next decision.
class PilotCard extends StatelessWidget {
  const PilotCard({
    super.key,
    required this.title,
    required this.color,
    required this.strategy,
    required this.onChanged,
    this.plane,
  });

  final String title;
  final Color color;
  final Strategy strategy;
  final Plane? plane;

  /// After any change to [strategy] (which is changed in place).
  final VoidCallback onChanged;

  Future<void> _edit(BuildContext context, int? index) async {
    final rule = await showDialog<Rule>(
      context: context,
      builder: (_) => RuleEditor(
        rule: index == null ? Rule() : strategy.rules[index].copy(),
        title: index == null ? 'New rule' : 'Rule ${index + 1}',
        color: color,
      ),
    );
    if (rule == null) return;
    if (index == null) {
      strategy.rules.add(rule);
    } else {
      strategy.rules[index] = rule;
    }
    onChanged();
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: strategy.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name the strategy'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    strategy.name = name.trim();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fired = plane?.action.rule;
    return Card(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _PlaneDot(color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _rename(context),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: strategy.name,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: '  $title · aityx',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
                MenuAnchor(
                  menuChildren: [
                    for (final make in presets)
                      Builder(
                        builder: (context) {
                          final preset = make();
                          return MenuItemButton(
                            onPressed: () {
                              strategy
                                ..name = preset.name
                                ..rules = preset.rules;
                              onChanged();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(preset.name),
                                Text(
                                  preset.about,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                  builder: (context, controller, _) => TextButton.icon(
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Strategy'),
                  ),
                ),
              ],
            ),
            if (plane case final p?) _Stats(plane: p, color: color),
            const SizedBox(height: 6),
            for (final (i, rule) in strategy.rules.indexed)
              _RuleRow(
                number: i + 1,
                rule: rule,
                color: color,
                fired: fired == i + 1,
                onEdit: () => _edit(context, i),
                onDelete: () {
                  strategy.rules.removeAt(i);
                  onChanged();
                },
                onUp: i == 0
                    ? null
                    : () {
                        strategy.rules.insert(
                          i - 1,
                          strategy.rules.removeAt(i),
                        );
                        onChanged();
                      },
                onDown: i == strategy.rules.length - 1
                    ? null
                    : () {
                        strategy.rules.insert(
                          i + 1,
                          strategy.rules.removeAt(i),
                        );
                        onChanged();
                      },
              ),
            if (fired == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No rule matched: flying straight on.',
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: strategy.rules.length >= 40
                    ? null
                    : () => _edit(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaneDot extends StatelessWidget {
  const _PlaneDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.flight, size: 18, color: color);
}

/// Score, lives, fuel, bridges, and what happened last.
class _Stats extends StatelessWidget {
  const _Stats({required this.plane, required this.color});

  final Plane plane;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final state = switch (plane.state) {
      PlaneState.out => 'out of the race',
      PlaneState.exploding => 'lost: ${plane.lastLost}',
      PlaneState.flying =>
        plane.refueling ? 'refueling' : 'flying ${plane.throttle}',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${plane.score}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${plane.lives} ${plane.lives == 1 ? 'plane' : 'planes'} · '
                  'bridge ${plane.bridges} · lost ${plane.lost}× · $state',
                  style: muted,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FuelGauge(fuel: plane.fuel, color: color),
        ],
      ),
    );
  }
}

/// The fuel gauge, E to F, red when low.
class FuelGauge extends StatelessWidget {
  const FuelGauge({super.key, required this.fuel, required this.color});

  final double fuel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final low = fuel < 25;
    return Row(
      children: [
        const Text('E', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fuel / 100,
              minHeight: 6,
              color: low ? Aityx.red : color,
              backgroundColor: Aityx.bg2,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Text('F', style: TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.number,
    required this.rule,
    required this.color,
    required this.fired,
    required this.onEdit,
    required this.onDelete,
    this.onUp,
    this.onDown,
  });

  final int number;
  final Rule rule;
  final Color color;
  final bool fired;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: fired
            ? color.withValues(alpha: 0.16)
            : scheme.surfaceContainerHigh,
        border: Border.all(color: fired ? color : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$number',
                  style: small?.copyWith(
                    color: fired ? color : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'when ',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          TextSpan(text: rule.whenText),
                          TextSpan(
                            text: '  → ',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          TextSpan(
                            text: rule.thenText,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      style: small,
                    ),
                    if (rule.why.isNotEmpty)
                      Text(
                        rule.why,
                        style: small?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              _Tiny(Icons.arrow_upward, 'Move up', onUp),
              _Tiny(Icons.arrow_downward, 'Move down', onDown),
              _Tiny(Icons.close, 'Remove the rule', onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tiny extends StatelessWidget {
  const _Tiny(this.icon, this.tooltip, this.onPressed);

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    padding: EdgeInsets.zero,
  );
}

/// A rule's editor: a test per sensor (blank for any), what the plane
/// then does, and why. Returns the rule, or null when cancelled.
class RuleEditor extends StatefulWidget {
  const RuleEditor({
    super.key,
    required this.rule,
    required this.title,
    required this.color,
  });

  final Rule rule;
  final String title;
  final Color color;

  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  late final Rule _rule = widget.rule;
  late final _numbers = {
    for (final s in sensors)
      if (s.kind == SensorKind.number)
        s.id: TextEditingController(text: _rule.when[s.id] ?? ''),
  };
  late final _why = TextEditingController(text: _rule.why);

  /// A number test aityx reads: `< 40`, `>= 10`, `= 0`, `[10..50]`, `40`.
  static final _numberTest = RegExp(
    r'^\s*((<=|>=|<|>|=)?\s*-?\d+(\.\d+)?|\[\s*-?\d+(\.\d+)?\s*\.\.\s*-?\d+(\.\d+)?\s*\])\s*$',
  );

  @override
  void dispose() {
    for (final c in _numbers.values) {
      c.dispose();
    }
    _why.dispose();
    super.dispose();
  }

  bool get _valid => _numbers.values.every(
    (c) => c.text.trim().isEmpty || _numberTest.hasMatch(c.text),
  );

  void _save() {
    for (final MapEntry(:key, :value) in _numbers.entries) {
      final cell = value.text.trim();
      if (cell.isEmpty) {
        _rule.when.remove(key);
      } else {
        _rule.when[key] = cell;
      }
    }
    _rule.why = _why.text.trim();
    Navigator.pop(context, _rule);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'WHEN (leave a sensor blank to match anything)',
                style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              for (final s in sensors) _sensorRow(s, theme, scheme),
              const Divider(height: 24),
              Text(
                'THEN',
                style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownMenu<String>(
                    label: const Text('steer'),
                    initialSelection: _rule.steer,
                    width: 210,
                    onSelected: (v) => setState(() => _rule.steer = v!),
                    dropdownMenuEntries: [
                      for (final MapEntry(:key, :value) in steers.entries)
                        DropdownMenuEntry(
                          value: key,
                          label: key,
                          trailingIcon: Tooltip(
                            message: value,
                            child: const Icon(Icons.info_outline, size: 16),
                          ),
                        ),
                    ],
                  ),
                  DropdownMenu<String>(
                    label: const Text('throttle'),
                    initialSelection: _rule.throttle,
                    width: 150,
                    onSelected: (v) => setState(() => _rule.throttle = v!),
                    dropdownMenuEntries: [
                      for (final t in throttles.keys)
                        DropdownMenuEntry(value: t, label: t),
                    ],
                  ),
                  FilterChip(
                    label: const Text('fire'),
                    selected: _rule.fire,
                    onSelected: (v) => setState(() => _rule.fire = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _why,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Why',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _valid ? _save : null, child: const Text('OK')),
      ],
    );
  }

  Widget _sensorRow(Sensor s, ThemeData theme, ColorScheme scheme) {
    final label = SizedBox(
      width: 130,
      child: Tooltip(
        message: s.description,
        child: Text(s.id, style: theme.textTheme.bodyMedium),
      ),
    );
    final Widget test = switch (s.kind) {
      SensorKind.number => TextField(
        controller: _numbers[s.id],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'any  (e.g. < 40, >= 10, [10..50])',
          errorText:
              _numbers[s.id]!.text.trim().isEmpty ||
                  _numberTest.hasMatch(_numbers[s.id]!.text)
              ? null
              : 'Use < 40, >= 10, = 0 or [10..50]',
        ),
      ),
      SensorKind.boolean => SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: '-', label: Text('any')),
          ButtonSegment(value: 'true', label: Text('yes')),
          ButtonSegment(value: 'false', label: Text('no')),
        ],
        selected: {_rule.when[s.id] ?? '-'},
        onSelectionChanged: (v) => setState(() {
          if (v.first == '-') {
            _rule.when.remove(s.id);
          } else {
            _rule.when[s.id] = v.first;
          }
        }),
      ),
      SensorKind.words => Wrap(
        spacing: 6,
        children: [
          for (final w in s.words)
            FilterChip(
              label: Text(w),
              selected: _words(s).contains(w),
              onSelected: (on) => setState(() {
                final words = _words(s);
                on ? words.add(w) : words.remove(w);
                final ordered = [
                  for (final x in s.words)
                    if (words.contains(x)) x,
                ];
                if (ordered.isEmpty || ordered.length == s.words.length) {
                  _rule.when.remove(s.id);
                } else {
                  _rule.when[s.id] = ordered.join(', ');
                }
              }),
            ),
        ],
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          label,
          Expanded(child: test),
        ],
      ),
    );
  }

  Set<String> _words(Sensor s) => {
    for (final w in (_rule.when[s.id] ?? '').split(','))
      if (w.trim().isNotEmpty) w.trim(),
  };
}
