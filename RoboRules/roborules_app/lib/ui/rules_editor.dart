import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aityx/json_layout.dart';
import '../battle/model.dart';
import '../battle/predefined_robots.dart';
import '../battle/random_robots.dart';
import 'classic.dart';

/// Robot › Edit rules: a robot's name, color and rules, as cards (when,
/// then, why) or as its aityx model's JSON. Returns the edited robot, or
/// null when cancelled.
class RulesEditor extends StatefulWidget {
  const RulesEditor({super.key, required this.robot, required this.factory});

  final Robot robot;
  final RobotFactory factory;

  @override
  State<RulesEditor> createState() => _RulesEditorState();
}

const _powers = [0, 0.5, 1, 1.5, 2, 2.5, 3];

class _RulesEditorState extends State<RulesEditor>
    with SingleTickerProviderStateMixin {
  late Robot _robot = widget.robot.copy();
  late final _name = TextEditingController(text: _robot.name);
  late final _tabs = TabController(length: 3, vsync: this);
  final _json = TextEditingController();
  String? _jsonError;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_tabs.indexIsChanging) _showJson();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _tabs.dispose();
    _json.dispose();
    super.dispose();
  }

  void _showJson() {
    _robot.name = _name.text.trim().isEmpty ? _robot.name : _name.text.trim();
    // Each rule on one line: short lists stay inline.
    _json.text = layoutJson(_robot.toModel()).lines
        .map((l) => l.text)
        .join('\n');
    setState(() => _jsonError = null);
  }

  /// Reads the JSON back into the robot; false when it isn't valid.
  bool _applyJson() {
    try {
      final robot = Robot.fromModel(
        jsonDecode(_json.text),
        color: _robot.color,
      );
      setState(() {
        _robot = robot;
        _name.text = robot.name;
        _jsonError = null;
      });
      return true;
    } on FormatException catch (e) {
      setState(() => _jsonError = 'Not a robot model: ${e.message}');
      return false;
    }
  }

  void _done() {
    if (_tabs.index == 1 && !_applyJson()) return;
    _robot.name = _name.text.trim().isEmpty ? 'Robot' : _name.text.trim();
    Navigator.of(context).pop(_robot);
  }

  @override
  Widget build(BuildContext context) {
    return ClassicDialog(
      title: 'Rules of ${_robot.name}',
      width: 860,
      actions: [
        PopupMenuButton<RobotKind>(
          tooltip:
              "Replace the rules with a predefined robot's, or random ones",
          color: Classic.panelLight,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Classic.darkShadow),
          ),
          itemBuilder: (_) => [
            for (final k in robotKinds)
              PopupMenuItem(
                value: k,
                height: 28,
                child: Text(
                  k.isRandom ? 'Random rules' : "${k.name}'s rules",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
          onSelected: (k) => setState(() {
            _robot.rules = k.rules(widget.factory);
            if (_tabs.index == 1) _showJson();
          }),
          child: const Bevel(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.casino_outlined, size: 15),
                SizedBox(width: 5),
                Text('Rules from…', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        ClassicButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ClassicButton(label: 'OK', icon: Icons.check, onPressed: _done),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Name'),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              const Text('Color'),
              for (final c in robotColors)
                GestureDetector(
                  onTap: () => setState(() => _robot.color = c),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c,
                      border: Border.all(
                        color: c == _robot.color ? Colors.black : Colors.white,
                        width: c == _robot.color ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            labelColor: Classic.text,
            indicatorColor: Classic.selection,
            tabs: const [
              Tab(text: 'Rules', height: 32),
              Tab(text: 'aityx model (JSON)', height: 32),
              Tab(text: 'Sensors', height: 32),
            ],
          ),
          Flexible(
            child: Bevel(
              pressed: true,
              color: Classic.panelLight,
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                height: 480,
                child: TabBarView(
                  controller: _tabs,
                  children: [_rulesTab(), _jsonTab(), _sensorsTab()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rulesTab() {
    final rules = _robot.rules;
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Each turn the robot follows the first rule whose conditions '
            'all hold (a FIRST decision table on aityx). Put the most '
            'specific rules first; make the last one always match.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        for (var i = 0; i < rules.length; i++)
          _RuleCard(
            key: ObjectKey(rules[i]),
            index: i,
            rule: rules[i],
            count: rules.length,
            onChanged: () => setState(() {}),
            onMove: (d) => setState(() {
              final r = rules.removeAt(i);
              rules.insert(i + d, r);
            }),
            onDelete: rules.length > 1
                ? () => setState(() => rules.removeAt(i))
                : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: ClassicButton(
            label: 'Add rule',
            icon: Icons.add,
            onPressed: () => setState(
              () => rules.insert(
                rules.isEmpty ? 0 : rules.length - 1,
                Rule(why: 'A new rule.'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _jsonTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'The robot as aityx runs it: its sensors as inputs, its '
                'rules as the "action" decision table. Edit and press Apply.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            ClassicButton(
              label: 'Copy',
              icon: Icons.copy,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _json.text)),
            ),
            const SizedBox(width: 6),
            ClassicButton(label: 'Apply', onPressed: _applyJson),
          ],
        ),
        if (_jsonError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _jsonError!,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 12),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            color: Colors.white,
            child: TextField(
              controller: _json,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sensorsTab() {
    return ListView(
      children: [
        const Text(
          'What a robot senses every turn, computed by the battle model on '
          'aityx. Conditions are aityx tests: true or false for yes/no '
          'sensors; < 200, >= 50, [0..30] or not(0) for numbers; - or empty '
          'for any value.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (final MapEntry(:key, :value) in sensors.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    value.$1,
                    style: const TextStyle(fontSize: 12, color: Classic.shadow),
                  ),
                ),
                Expanded(
                  child: Text(value.$2, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One rule: its conditions, its commands and why, editable.
class _RuleCard extends StatelessWidget {
  const _RuleCard({
    super.key,
    required this.index,
    required this.rule,
    required this.count,
    required this.onChanged,
    required this.onMove,
    required this.onDelete,
  });

  final int index;
  final Rule rule;
  final int count;
  final VoidCallback onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
    Widget choice(String command, String value, ValueChanged<String> on) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$command ', style: const TextStyle(fontSize: 12)),
        DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: Classic.text),
          items: [
            for (final v in commandValues[command]!)
              DropdownMenuItem(value: v, child: Text(v)),
          ],
          onChanged: (v) {
            if (v != null) on(v);
            onChanged();
          },
        ),
      ],
    );
    final unused = sensors.keys.where((s) => !rule.when.containsKey(s));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Bevel(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Rule ${index + 1}', style: label),
                if (rule.when.isEmpty)
                  const Text(
                    '   always matches',
                    style: TextStyle(fontSize: 11, color: Classic.shadow),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Move up',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: index > 0 ? () => onMove(-1) : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move down',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: index < count - 1 ? () => onMove(1) : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Delete the rule',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('When', style: label),
                for (final s in rule.when.keys.toList())
                  _Condition(
                    key: ValueKey(s),
                    sensor: s,
                    value: rule.when[s]!,
                    onChanged: (v) {
                      rule.when[s] = v;
                      onChanged();
                    },
                    onRemove: () {
                      rule.when.remove(s);
                      onChanged();
                    },
                  ),
                if (unused.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Add a condition',
                    itemBuilder: (_) => [
                      for (final s in unused)
                        PopupMenuItem(
                          value: s,
                          height: 32,
                          child: Text(s, style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                    onSelected: (s) {
                      rule.when[s] = sensors[s]!.$1 == 'boolean'
                          ? 'true'
                          : '< 200';
                      onChanged();
                    },
                    child: const Text(
                      '+ condition',
                      style: TextStyle(fontSize: 12, color: Classic.selection),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Then', style: label),
                choice('drive', rule.drive, (v) => rule.drive = v),
                choice('turn', rule.turn, (v) => rule.turn = v),
                choice('gun', rule.gun, (v) => rule.gun = v),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('fire ', style: TextStyle(fontSize: 12)),
                    DropdownButton<num>(
                      value: _powers.contains(rule.fire) ? rule.fire : 0,
                      isDense: true,
                      style: const TextStyle(fontSize: 12, color: Classic.text),
                      items: [
                        for (final p in _powers)
                          DropdownMenuItem(
                            value: p,
                            child: Text(p == 0 ? '0 (hold fire)' : '$p'),
                          ),
                      ],
                      onChanged: (v) {
                        rule.fire = v ?? 0;
                        onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('Why  ', style: label),
                Expanded(
                  child: TextFormField(
                    initialValue: rule.why,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) => rule.why = v,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A condition on one sensor: true/false for yes/no sensors, an aityx test
/// such as `< 200` for numbers.
class _Condition extends StatelessWidget {
  const _Condition({
    super.key,
    required this.sensor,
    required this.value,
    required this.onChanged,
    required this.onRemove,
  });

  final String sensor;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final boolean = sensors[sensor]!.$1 == 'boolean';
    return Tooltip(
      message: sensors[sensor]!.$2,
      child: Container(
        padding: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Classic.shadow),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$sensor ',
              style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
            ),
            if (boolean)
              DropdownButton<String>(
                value: value == 'false' ? 'false' : 'true',
                isDense: true,
                underline: const SizedBox.shrink(),
                style: const TextStyle(fontSize: 12, color: Classic.text),
                items: const [
                  DropdownMenuItem(value: 'true', child: Text('true')),
                  DropdownMenuItem(value: 'false', child: Text('false')),
                ],
                onChanged: (v) => onChanged(v ?? 'true'),
              )
            else
              SizedBox(
                width: 70,
                child: TextFormField(
                  initialValue: value,
                  style: const TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onChanged: onChanged,
                ),
              ),
            InkWell(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
