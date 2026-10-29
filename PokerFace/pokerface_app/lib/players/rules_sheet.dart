import 'package:flutter/material.dart';

import '../api/poker_api.dart';
import '../engine/game.dart';
import '../game/controller.dart';
import '../theme.dart';
import 'strategy_editor.dart';

/// The situation's inputs a rule may test, for the add-rule form.
const situationInputs = [
  'street',
  'position',
  'hand',
  'made_hand',
  'flush_draw',
  'straight_draw',
  'equity',
  'pot',
  'current_bet',
  'to_call',
  'pot_odds',
  'can_check',
  'can_raise',
  'raises',
  'stack',
  'big_blind',
  'stack_bb',
  'min_raise',
  'max_raise',
  'players_in_hand',
  'players_after',
  'random',
];

/// A player's strategy, as rules: the action table one rule a row, each
/// with its conditions, its action and its why, to remove, move or add
/// to; and the raise expression. Saving gives the player a strategy of
/// their own (unless they already have one), so a preset stays as it is.
Future<void> showPlayerRules(
  BuildContext context,
  GameController controller,
  Seat seat,
) {
  final strategy = controller.strategyOf(seat);
  if (strategy == null) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: RulesSheet(
          controller: controller,
          seat: seat,
          strategy: strategy,
        ),
      ),
    ),
  );
}

/// One rule of the action table, however the table writes it: the
/// conditions by column, the action, and the why.
class Rule {
  Rule({required this.when, required this.then, required this.why});

  final Map<String, String> when;
  String then;
  String why;

  bool get isElse => when.isEmpty;
}

/// The action table taken apart: its input columns, its rules, and how
/// its rows are written (objects, or arrays under the header).
class ActionTable {
  ActionTable._(this.columns, this.rules, this.arrayRows, this.outputColumn);

  /// Reads `action` from [decisions]: an object with a `table`, or the
  /// table itself. Null when it's an expression.
  static ActionTable? from(Map<String, Object?> decisions) {
    final action = decisions['action'];
    final table = action is Map ? action['table'] : action;
    if (table is! List || table.isEmpty || table.first is! List) return null;
    final header = (table.first as List).map((h) => '$h').toList();
    final arrow = header.indexWhere((h) => h.startsWith('=>'));
    final columns = [
      for (final h in header)
        if (!h.startsWith('=>') && !h.startsWith('#')) h,
    ];
    final whyColumn = header.indexWhere((h) => h.startsWith('#'));
    var arrays = false;
    final rules = <Rule>[];
    for (final row in table.skip(1)) {
      if (row is Map) {
        final when = (row['when'] as Map?) ?? const {};
        rules.add(
          Rule(
            when: {for (final e in when.entries) '${e.key}': '${e.value}'},
            then: '${row['then'] ?? ''}',
            why: '${row['why'] ?? ''}',
          ),
        );
      } else if (row is List) {
        arrays = true;
        final when = <String, String>{};
        for (var i = 0; i < columns.length && i < row.length; i++) {
          final cell = '${row[i]}';
          if (cell != '-') when[columns[i]] = cell;
        }
        rules.add(
          Rule(
            when: when,
            then: arrow >= 0 && arrow < row.length ? '${row[arrow]}' : '',
            why: whyColumn >= 0 && whyColumn < row.length
                ? '${row[whyColumn]}'
                : '',
          ),
        );
      }
    }
    return ActionTable._(
      columns,
      rules,
      arrays,
      arrow >= 0 ? header[arrow] : '=>',
    );
  }

  final List<String> columns;
  final List<Rule> rules;
  final bool arrayRows;
  final String outputColumn;

  /// The table as JSON, in the form it was read: every column a rule
  /// tests is in the header.
  List<Object?> toJson() {
    final columns = [...this.columns];
    for (final r in rules) {
      for (final c in r.when.keys) {
        if (!columns.contains(c)) columns.add(c);
      }
    }
    final header = [...columns, outputColumn, '# why'];
    return [
      header,
      for (final r in rules)
        if (arrayRows)
          [for (final c in columns) r.when[c] ?? '-', r.then, r.why]
        else
          {
            if (r.when.isNotEmpty) 'when': {...r.when},
            'then': r.then,
            'why': r.why,
          },
    ];
  }

  /// [decisions] with this table in place of the action's.
  Map<String, Object?> applyTo(Map<String, Object?> decisions) {
    final action = decisions['action'];
    return {
      ...decisions,
      'action': action is Map
          ? {...action.cast<String, Object?>(), 'table': toJson()}
          : toJson(),
    };
  }
}

/// The raise expression, wherever `raise_to` keeps it.
String raiseExpression(Map<String, Object?> decisions) {
  final raise = decisions['raise_to'];
  if (raise is Map) return '${raise['expr'] ?? ''}';
  return raise is String ? raise : '';
}

Map<String, Object?> withRaiseExpression(
  Map<String, Object?> decisions,
  String expr,
) {
  final raise = decisions['raise_to'];
  return {
    ...decisions,
    'raise_to': raise is Map
        ? {...raise.cast<String, Object?>(), 'expr': expr}
        : {
            'type': 'number',
            'desc': 'The total bet when raising',
            'expr': expr,
          },
  };
}

class RulesSheet extends StatefulWidget {
  const RulesSheet({
    super.key,
    required this.controller,
    required this.seat,
    required this.strategy,
  });

  final GameController controller;
  final Seat seat;
  final Strategy strategy;

  @override
  State<RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<RulesSheet> {
  late final ActionTable? _table = ActionTable.from(widget.strategy.decisions);
  late final _raise = TextEditingController(
    text: raiseExpression(widget.strategy.decisions),
  );
  bool _dirty = false;
  String? _message;
  bool _failed = false;
  bool _trying = false;

  // The add-rule form.
  final List<(String, TextEditingController)> _conditions = [];
  String _action = 'raise';
  final _why = TextEditingController();

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _addCondition();
  }

  @override
  void dispose() {
    _raise.dispose();
    _why.dispose();
    for (final (_, t) in _conditions) {
      t.dispose();
    }
    super.dispose();
  }

  /// Every name a condition may test: the table's columns, the strategy's
  /// own decisions, and the situation's inputs.
  List<String> get _testable {
    final names = <String>[...?_table?.columns];
    for (final name in widget.strategy.decisions.keys) {
      if (name != 'action' && name != 'raise_to' && !names.contains(name)) {
        names.add(name);
      }
    }
    for (final name in situationInputs) {
      if (!names.contains(name)) names.add(name);
    }
    return names;
  }

  void _addCondition() {
    final names = _testable;
    _conditions.add((names.first, TextEditingController()));
  }

  Map<String, Object?> _decisions() {
    var d = widget.strategy.decisions;
    final table = _table;
    if (table != null) d = table.applyTo(d);
    if (_raise.text.trim() != raiseExpression(widget.strategy.decisions)) {
      d = withRaiseExpression(d, _raise.text.trim());
    }
    return d;
  }

  void _changed() => setState(() {
    _dirty = true;
    _message = null;
  });

  void _remove(int i) {
    _table!.rules.removeAt(i);
    _changed();
  }

  void _move(int i, int by) {
    final rules = _table!.rules;
    final j = i + by;
    if (j < 0 || j >= rules.length) return;
    final r = rules.removeAt(i);
    rules.insert(j, r);
    _changed();
  }

  void _add() {
    final when = <String, String>{};
    for (final (column, text) in _conditions) {
      final v = text.text.trim();
      if (v.isNotEmpty) when[column] = v;
    }
    final rules = _table!.rules;
    final rule = Rule(when: when, then: _action, why: _why.text.trim());
    // Above the else row, so it's still the last.
    if (rules.isNotEmpty && rules.last.isElse && !rule.isElse) {
      rules.insert(rules.length - 1, rule);
    } else {
      rules.add(rule);
    }
    for (final (_, t) in _conditions) {
      t.dispose();
    }
    _conditions.clear();
    _addCondition();
    _why.clear();
    _changed();
  }

  Future<void> _tryIt() async {
    setState(() {
      _trying = true;
      _message = null;
    });
    final strategy = Strategy(
      id: 'try',
      name: widget.strategy.name,
      tagline: '',
      decisions: _decisions(),
      custom: true,
    );
    try {
      final r = await c.api.act(strategy, sampleSituation);
      setState(() {
        _failed = false;
        _message =
            'On the sample (A♥ K♦ on K♠ 7♣ 2♦, top pair, 40 to call into a '
            'pot of 120, 78% equity): ${r.kind.label.toLowerCase()}'
            '${r.kind.id == 'raise' ? ' to ${r.raiseTo}' : ''}'
            '${r.rule == null ? '' : ', rule ${r.rule}'}'
            '${r.why == null ? '' : ': ${r.why}'}';
      });
    } on ApiException catch (e) {
      setState(() {
        _failed = true;
        _message = e.message;
      });
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  void _save() {
    c.personalize(widget.seat, _decisions());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final table = _table;
    final own = widget.strategy.id == GameController.ownStrategyId(widget.seat);
    return Column(
      children: [
        AppBar(
          title: Text('${widget.seat.name} · ${widget.strategy.name}'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text(
                widget.strategy.tagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                own
                    ? "These rules are ${widget.seat.name}'s own; saving changes "
                          'them in place.'
                    : 'Saving a change gives ${widget.seat.name} a copy of these '
                          'rules to play with; the preset stays as it is.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'The action: the first rule that matches wins',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (table == null)
                Text(
                  'This strategy decides the action with an expression, not a '
                  'table; edit it as JSON.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                for (var i = 0; i < table.rules.length; i++)
                  _RuleRow(
                    key: ValueKey(table.rules[i]),
                    index: i,
                    rule: table.rules[i],
                    count: table.rules.length,
                    onRemove: () => _remove(i),
                    onUp: i == 0 ? null : () => _move(i, -1),
                    onDown: i == table.rules.length - 1
                        ? null
                        : () => _move(i, 1),
                  ),
              if (table != null) ...[
                const SizedBox(height: 16),
                Text('Add a rule', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'When every condition holds (a value like preflop or true, '
                  'alternatives like "premium, strong", a range like ">= 0.5" '
                  'or "<= 3 * big_blind"), the player does the action. It goes '
                  'in above the last rule, the one for everything else; move it '
                  'from there.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _conditions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            key: Key('condition-column-$i'),
                            initialValue: _conditions[i].$1,
                            isExpanded: true,
                            isDense: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final n in _testable)
                                DropdownMenuItem(value: n, child: Text(n)),
                            ],
                            onChanged: (v) => setState(() {
                              if (v != null) {
                                _conditions[i] = (v, _conditions[i].$2);
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: Key('condition-value-$i'),
                            controller: _conditions[i].$2,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              hintText: 'is …',
                            ),
                            style: const TextStyle(
                              fontFamily: 'RobotoMono',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove this condition',
                          onPressed: _conditions.length == 1
                              ? null
                              : () => setState(() {
                                  _conditions.removeAt(i).$2.dispose();
                                }),
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(_addCondition),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Condition'),
                    ),
                    const Spacer(),
                    const Text('then'),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      key: const Key('new-rule-action'),
                      value: _action,
                      items: [
                        for (final k in ActionKind.values)
                          DropdownMenuItem(value: k.id, child: Text(k.label)),
                      ],
                      onChanged: (v) => setState(() => _action = v ?? _action),
                    ),
                  ],
                ),
                TextField(
                  key: const Key('new-rule-why'),
                  controller: _why,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Why (shown with the action)',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    key: const Key('add-rule'),
                    onPressed: _add,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Add the rule'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'The raise: the total bet when raising',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('raise-expr'),
                controller: _raise,
                maxLines: null,
                onChanged: (_) => _changed(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  helperText: 'An expression over the situation; kept between the minimum raise and the stack.',
                ),
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 13),
              ),
              if (widget.strategy.decisions.keys.any(
                (k) => k != 'action' && k != 'raise_to',
              )) ...[
                const SizedBox(height: 16),
                Text(
                  'What the rules can also test',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                for (final e in widget.strategy.decisions.entries)
                  if (e.key != 'action' && e.key != 'raise_to')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${e.key}  ',
                              style: const TextStyle(
                                fontFamily: 'RobotoMono',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: e.value is Map
                                  ? '${(e.value as Map)['expr'] ?? ''}'
                                  : '${e.value}',
                              style: TextStyle(
                                fontFamily: 'RobotoMono',
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
              ],
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_failed ? scheme.error : Aityx.green).withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: _failed ? scheme.error : Aityx.green,
                    width: 3,
                  ),
                ),
              ),
              child: Text(_message!, style: theme.textTheme.bodySmall),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _trying ? null : _tryIt,
                icon: _trying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.science_outlined),
                label: const Text('Try it on aityx'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  showStrategyEditor(
                    context,
                    c,
                    from: widget.strategy,
                    editing: widget.strategy.custom ? widget.strategy : null,
                  );
                },
                icon: const Icon(Icons.data_object),
                label: const Text('As JSON'),
              ),
              TextButton.icon(
                key: const Key('remove-player'),
                onPressed: () {
                  c.removePlayer(widget.seat);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.person_remove_outlined),
                label: Text('Remove ${widget.seat.name}'),
              ),
              FilledButton.icon(
                key: const Key('save-rules'),
                onPressed: _dirty ? _save : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  own ? 'Save' : "Save as ${widget.seat.name}'s rules",
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    super.key,
    required this.index,
    required this.rule,
    required this.count,
    required this.onRemove,
    required this.onUp,
    required this.onDown,
  });

  final int index;
  final Rule rule;
  final int count;
  final VoidCallback onRemove;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = ActionKind.parse(rule.then);
    final color = switch (kind) {
      ActionKind.fold => Aityx.muted,
      ActionKind.check => Aityx.green,
      ActionKind.call => Aityx.green,
      ActionKind.raise => Aityx.orange,
      ActionKind.allIn => Aityx.red,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.outlineVariant,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (rule.isElse)
                      Text(
                        'otherwise',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      for (final e in rule.when.entries)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            '${e.key} ${_condition(e.value)}',
                            style: const TextStyle(
                              fontFamily: 'RobotoMono',
                              fontSize: 12,
                            ),
                          ),
                        ),
                    const Icon(Icons.arrow_forward, size: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color),
                      ),
                      child: Text(
                        kind.id == rule.then ? kind.label : rule.then,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (rule.why.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rule.why,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Up',
            onPressed: onUp,
            icon: const Icon(Icons.arrow_upward, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Down',
            onPressed: onDown,
            icon: const Icon(Icons.arrow_downward, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            key: Key('remove-rule-$index'),
            tooltip: 'Remove this rule',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// A cell's condition in words: `= preflop`, `>= 0.5`, `in premium, strong`.
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
