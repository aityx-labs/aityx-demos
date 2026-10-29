import 'dart:math';

import 'package:flutter/material.dart';

import '../battle/controller.dart';
import '../battle/model.dart';
import '../battle/predefined_robots.dart';
import '../battle/random_robots.dart';
import 'classic.dart';
import 'rules_editor.dart';

/// What New Battle sets: the robots, as picked and customized, and how
/// many rounds.
typedef BattleSetup = ({List<Robot> robots, int rounds});

/// Battle › New, as Robocode's: the available robots on the left (a random
/// one and Robocode's samples, as rules), the selected ones on the right,
/// Add, Remove, Remove all and Edit rules between, what the highlighted
/// one does below, and the number of rounds. It opens with the battle's
/// current robots, customizations and all.
class NewBattleDialog extends StatefulWidget {
  const NewBattleDialog({
    super.key,
    required this.robots,
    required this.rounds,
    required this.factory,
  });

  final List<Robot> robots;
  final int rounds;
  final RobotFactory factory;

  @override
  State<NewBattleDialog> createState() => _NewBattleDialogState();
}

class _NewBattleDialogState extends State<NewBattleDialog> {
  late final List<Robot> _robots = [for (final r in widget.robots) r.copy()];
  late double _rounds = widget.rounds.toDouble();

  /// The highlighted available kind, and the highlighted selected robot:
  /// the last one touched is described below the lists.
  int _kind = 0;
  int? _picked;
  bool _describeKind = true;

  bool get _full => _robots.length >= maxRobots;

  void _add(RobotKind kind) {
    if (_full) return;
    setState(() {
      _robots.add(kind.make(taken: _robots, factory: widget.factory));
      _picked = _robots.length - 1;
      _describeKind = false;
    });
  }

  void _remove(int i) => setState(() {
    _robots.removeAt(i);
    _picked = _robots.isEmpty ? null : min(i, _robots.length - 1);
  });

  Future<void> _edit(int i) async {
    final robot = await showDialog<Robot>(
      context: context,
      builder: (_) => RulesEditor(robot: _robots[i], factory: widget.factory),
    );
    if (robot != null && mounted) setState(() => _robots[i] = robot);
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final description = _describeKind || picked == null
        ? robotKinds[_kind].description
        : '${_robots[picked].name}: ${_robots[picked].rules.length} rules.\n'
              '${rulesSummary(_robots[picked])}';
    return ClassicDialog(
      title: 'New Battle',
      width: 760,
      actions: [
        ClassicButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ClassicButton(
          label: 'Start Battle',
          icon: Icons.play_arrow,
          onPressed: _robots.length < 2
              ? null
              : () => Navigator.of(
                  context,
                ).pop<BattleSetup>((robots: _robots, rounds: _rounds.toInt())),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 250,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListBox(
                    title: 'Available robots',
                    items: [
                      for (final k in robotKinds)
                        RobotRow(color: k.color, name: k.name),
                    ],
                    selected: _kind,
                    onSelect: (i) => setState(() {
                      _kind = i;
                      _describeKind = true;
                    }),
                    onActivate: (i) => _add(robotKinds[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClassicButton(
                        label: 'Add →',
                        tooltip:
                            'Add the highlighted robot (or double-click it)',
                        onPressed: _full ? null : () => _add(robotKinds[_kind]),
                      ),
                      const SizedBox(height: 6),
                      ClassicButton(
                        label: '← Remove',
                        onPressed: picked == null
                            ? null
                            : () => _remove(picked),
                      ),
                      const SizedBox(height: 6),
                      ClassicButton(
                        label: '← Remove all',
                        onPressed: _robots.isEmpty
                            ? null
                            : () => setState(() {
                                _robots.clear();
                                _picked = null;
                              }),
                      ),
                      const SizedBox(height: 18),
                      ClassicButton(
                        label: 'Edit rules…',
                        icon: Icons.edit,
                        tooltip: "Change the highlighted robot's name, color and rules",
                        onPressed: picked == null ? null : () => _edit(picked),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListBox(
                    title: 'Selected robots (${_robots.length} of $maxRobots)',
                    items: [
                      for (final r in _robots)
                        RobotRow(
                          color: r.color,
                          name: r.name,
                          detail: '${r.rules.length} rules',
                        ),
                    ],
                    selected: picked,
                    onSelect: (i) => setState(() {
                      _picked = i;
                      _describeKind = false;
                    }),
                    onActivate: _edit,
                    empty: 'No robots yet: add at least two.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Bevel(
            pressed: true,
            color: Classic.panelLight,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: 64,
              child: SingleChildScrollView(
                child: Text(description, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 150, child: Text('Number of rounds')),
              Expanded(
                child: Slider(
                  value: _rounds,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '${_rounds.toInt()}',
                  onChanged: (v) => setState(() => _rounds = v),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text('${_rounds.toInt()}', textAlign: TextAlign.right),
              ),
            ],
          ),
          const Text(
            'Every robot is an aityx decision model you can edit; every '
            'turn of the battle is played by aityx.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Add robot…: pick one of the available robots for the current battle.
/// Returns the kind, or null when cancelled.
class AddRobotDialog extends StatefulWidget {
  const AddRobotDialog({super.key});

  @override
  State<AddRobotDialog> createState() => _AddRobotDialogState();
}

class _AddRobotDialogState extends State<AddRobotDialog> {
  int _kind = 0;

  void _add(int i) => Navigator.of(context).pop<RobotKind>(robotKinds[i]);

  @override
  Widget build(BuildContext context) {
    return ClassicDialog(
      title: 'Add a robot',
      width: 420,
      actions: [
        ClassicButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ClassicButton(
          label: 'Add',
          icon: Icons.add,
          onPressed: () => _add(_kind),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 250,
            child: ListBox(
              title: 'Available robots',
              items: [
                for (final k in robotKinds)
                  RobotRow(color: k.color, name: k.name),
              ],
              selected: _kind,
              onSelect: (i) => setState(() => _kind = i),
              onActivate: _add,
            ),
          ),
          const SizedBox(height: 8),
          Bevel(
            pressed: true,
            color: Classic.panelLight,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: 48,
              child: Text(
                robotKinds[_kind].description,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select the robot once added to change its rules.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// A Swing list: a title, a white box of rows, the selected row in blue.
/// A click selects a row at once; a second click on it within half a
/// second activates it.
class ListBox extends StatefulWidget {
  const ListBox({
    super.key,
    required this.title,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.onActivate,
    this.empty,
  });

  final String title;
  final List<Widget> items;
  final int? selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<int>? onActivate;
  final String? empty;

  @override
  State<ListBox> createState() => _ListBoxState();
}

class _ListBoxState extends State<ListBox> {
  int? _lastTapped;
  DateTime? _lastTapAt;

  void _tap(int i) {
    final now = DateTime.now();
    final again =
        _lastTapped == i &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!).inMilliseconds < 500;
    _lastTapped = i;
    _lastTapAt = now;
    widget.onSelect(i);
    if (again && widget.onActivate != null) {
      _lastTapAt = null;
      widget.onActivate!(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final selected = widget.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        Expanded(
          child: Bevel(
            pressed: true,
            color: Colors.white,
            padding: EdgeInsets.zero,
            child: items.isEmpty && widget.empty != null
                ? Center(
                    child: Text(
                      widget.empty!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Classic.shadow,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        InkWell(
                          onTap: () => _tap(i),
                          child: Container(
                            color: selected == i
                                ? Classic.selection
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: DefaultTextStyle(
                              style: TextStyle(
                                fontSize: 12,
                                color: selected == i
                                    ? Colors.white
                                    : Classic.text,
                              ),
                              child: items[i],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// A row of a robot list: its color, its name, and a detail on the right.
class RobotRow extends StatelessWidget {
  const RobotRow({
    super.key,
    required this.color,
    required this.name,
    this.detail,
  });

  final Color color;
  final String name;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
        if (detail != null) Text(detail!, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

/// Battle › Results: each robot's totals over the rounds, ranked, as
/// Robocode's results table has them.
class ResultsDialog extends StatelessWidget {
  const ResultsDialog({super.key, required this.controller});

  final BattleController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    const head = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    const cell = TextStyle(fontSize: 12);
    final ranking = c.ranking;
    String ord(int n) => switch (n) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      _ => '${n}th',
    };
    return ClassicDialog(
      title:
          'Results for ${c.roundScores.length} '
          'round${c.roundScores.length == 1 ? '' : 's'}',
      width: 640,
      actions: [
        ClassicButton(
          label: 'OK',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Bevel(
        pressed: true,
        color: Colors.white,
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 30,
            dataRowMinHeight: 26,
            dataRowMaxHeight: 30,
            columnSpacing: 18,
            headingRowColor: const WidgetStatePropertyAll(Classic.panel),
            columns: const [
              DataColumn(label: Text('Rank', style: head)),
              DataColumn(label: Text('Robot Name', style: head)),
              DataColumn(
                label: Text('Total Score', style: head),
                numeric: true,
              ),
              DataColumn(label: Text('Survival', style: head), numeric: true),
              DataColumn(label: Text('Surv Bonus', style: head), numeric: true),
              DataColumn(label: Text('Bullet Dmg', style: head), numeric: true),
              DataColumn(label: Text('1sts', style: head), numeric: true),
            ],
            rows: [
              for (var k = 0; k < ranking.length; k++)
                () {
                  final i = ranking[k];
                  final r = c.robots[i];
                  final t = c.totals['r${i + 1}'] ?? Totals();
                  return DataRow(
                    color: WidgetStatePropertyAll(
                      k == 0 ? const Color(0xFFFFF6C8) : Colors.white,
                    ),
                    cells: [
                      DataCell(Text(ord(k + 1), style: cell)),
                      DataCell(
                        Row(
                          children: [
                            Container(width: 10, height: 10, color: r.color),
                            const SizedBox(width: 6),
                            Text(r.name, style: cell),
                          ],
                        ),
                      ),
                      DataCell(Text('${t.total}', style: cell)),
                      DataCell(Text('${t.survival}', style: cell)),
                      DataCell(Text('${t.lastSurvivor}', style: cell)),
                      DataCell(Text('${t.bulletDamage}', style: cell)),
                      DataCell(Text('${t.firsts}', style: cell)),
                    ],
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A short summary of a robot's rules, for its tooltip.
String rulesSummary(Robot r) => [
  for (var i = 0; i < r.rules.length; i++)
    '${i + 1}. ${r.rules[i].why.isEmpty ? '(no reason)' : r.rules[i].why}',
].join('\n');
