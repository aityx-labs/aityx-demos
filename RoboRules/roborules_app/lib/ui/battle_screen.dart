import 'package:flutter/material.dart';

import '../aityx/aityx_call_view.dart';
import '../aityx/theme.dart';
import '../battle/controller.dart';
import '../battle/model.dart';
import '../battle/painter.dart';
import '../battle/predefined_robots.dart';
import 'classic.dart';
import 'dialogs.dart';
import 'rules_editor.dart';

/// The battle window, in Robocode's layout: a menu bar, the battlefield,
/// the robots on the right, the controls below.
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key, required this.controller});

  final BattleController controller;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  BattleController get c => widget.controller;
  int? _selected;
  BattleState _lastState = BattleState.setup;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (c.state == BattleState.over && _lastState != BattleState.over) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showResults());
    }
    _lastState = c.state;
    setState(() {});
  }

  /// Whether robots can be added or removed: not during a battle.
  bool get _idle => c.state == BattleState.setup || c.state == BattleState.over;

  Future<void> _newBattle() async {
    final setup = await showDialog<BattleSetup>(
      context: context,
      builder: (_) => NewBattleDialog(
        robots: c.robots,
        rounds: c.rounds,
        factory: c.factory,
      ),
    );
    if (setup == null) return;
    c.rounds = setup.rounds;
    c.setRobots(setup.robots);
    _selected = null;
    c.start();
  }

  Future<void> _addRobot() async {
    final kind = await showDialog<RobotKind>(
      context: context,
      builder: (_) => const AddRobotDialog(),
    );
    if (kind == null || !_idle) return;
    c.addRobot(kind.make(taken: c.robots, factory: c.factory));
    setState(() => _selected = c.robots.length - 1);
  }

  void _removeRobot(int index) {
    if (!_idle) return;
    c.removeRobot(index);
    setState(() => _selected = null);
  }

  Future<void> _editRobot(int index) async {
    setState(() => _selected = index);
    final wasRunning = c.state == BattleState.running;
    if (wasRunning) c.pause();
    final robot = await showDialog<Robot>(
      context: context,
      builder: (_) => RulesEditor(robot: c.robots[index], factory: c.factory),
    );
    if (robot != null) c.replaceRobot(index, robot);
    if (wasRunning) c.resume();
  }

  Future<void> _showResults() => showDialog<void>(
    context: context,
    builder: (_) => ResultsDialog(controller: c),
  );

  /// Shows [call], or the last one, in the viewer.
  Future<void> _showCall([AityxCall? call]) => showDialog<void>(
    context: context,
    builder: (context) => ClassicDialog(
      title: call == null
          ? 'The last aityx call'
          : 'aityx call ${call.number}: ${call.what}',
      width: 1100,
      actions: [
        ClassicButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: !((call ?? c.lastCall)?.kept ?? false)
          ? Text(
              call == null
                  ? 'No call yet: start a battle.'
                  : 'Only the last ${c.keptCalls} calls are kept.',
            )
          // The viewer in aityx's own dark theme, as in the other samples.
          : Theme(
              data: aityxDarkTheme(),
              child: Builder(
                builder: (context) => Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyMedium!,
                      child: AityxCallView(
                        request: (call ?? c.lastCall)!.request,
                        response: (call ?? c.lastCall)!.response,
                        responseSubtitle: 'what aityx answered',
                        targets: callTargets(c.robots),
                        height: MediaQuery.sizeOf(context).height * 0.55,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final field = _Battlefield(controller: c, selected: _selected);
    final robotsPanel = _RobotList(
      controller: c,
      selected: _selected,
      onSelect: _editRobot,
      onAdd: _idle && c.robots.length < maxRobots ? _addRobot : null,
      onRemove: _idle ? _removeRobot : null,
      onCall: _showCall,
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TitleBar(
              'RoboRules: Robocode-style battles, every turn played by aityx',
            ),
            _MenuBar(
              controller: c,
              onNew: _newBattle,
              onAdd: _idle && c.robots.length < maxRobots ? _addRobot : null,
              onEdit: _editRobot,
              onRemove: _idle ? _removeRobot : null,
              onResults: _showResults,
              onCall: _showCall,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: field),
                          const SizedBox(width: 4),
                          SizedBox(width: 240, child: robotsPanel),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: field),
                          const SizedBox(height: 4),
                          Expanded(flex: 2, child: robotsPanel),
                        ],
                      ),
              ),
            ),
            _Controls(controller: c, onNew: _newBattle, onCall: _showCall),
          ],
        ),
      ),
    );
  }
}

/// The parts of a turn's call worth jumping to: the world model's pieces
/// and each robot's rules.
List<JsonTarget> callTargets(List<Robot> robots) {
  const req = CallSide.request;
  const res = CallSide.response;
  return [
    const JsonTarget(
      req,
      'decision.types',
      'Types',
      'The world, its robots (Bot), bullets, what a robot senses (Sense) and what it does (Act).',
    ),
    const JsonTarget(
      req,
      'decision.functions.step',
      'One turn',
      'Every robot senses, decides with its own rules and moves; bullets fly; hits, rams and losses are settled.',
    ),
    const JsonTarget(
      req,
      'decision.functions.sense_with',
      'Sensors',
      "What a robot senses: the nearest enemy's distance and bearings, walls, energy, gun heat.",
    ),
    for (var i = 0; i < robots.length; i++)
      JsonTarget(
        req,
        'decision.functions.brain_r${i + 1}',
        "${robots[i].name}'s rules",
        "${robots[i].name}'s rules, as a FIRST decision table: the robot's behavior, run every turn.",
      ),
    const JsonTarget(
      req,
      'decision.functions.brain_of',
      'Whose rules',
      "Calls each robot's own rules.",
    ),
    const JsonTarget(
      req,
      'decision.functions.walled',
      'Moving',
      'Speed, turning, the gun and firing as Robocode does them, and the walls.',
    ),
    const JsonTarget(
      req,
      'decision.functions.settle',
      'Hits and rams',
      'Bullet damage, energy gained by the shooter, rams and which robots are lost.',
    ),
    const JsonTarget(
      req,
      'decision.functions.sin_r',
      'Trigonometry',
      "aityx's expressions have no sine: a series computes it.",
    ),
    const JsonTarget(
      req,
      'state.world',
      'The world now',
      'Where every robot and bullet is, as the battle continues from.',
    ),
    const JsonTarget(
      res,
      'answers.frames',
      'The turns played',
      'The world after each turn, which the battlefield animates.',
    ),
    const JsonTarget(
      res,
      'answers.scores',
      'Scores',
      "The round's scores: 50 per robot outlived, the last survivor's bonus, bullet damage.",
    ),
    const JsonTarget(
      res,
      'usage',
      'Tokens',
      "The call's tokens: one System One call plays all these turns.",
    ),
  ];
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({
    required this.controller,
    required this.onNew,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onResults,
    required this.onCall,
  });

  final BattleController controller;
  final VoidCallback onNew;
  final VoidCallback? onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int>? onRemove;
  final VoidCallback onResults;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget menu(String label, List<(String, VoidCallback?)> items) =>
        PopupMenuButton<int>(
          tooltip: '',
          offset: const Offset(0, 24),
          color: Classic.panelLight,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Classic.darkShadow),
          ),
          itemBuilder: (_) => [
            for (var i = 0; i < items.length; i++)
              PopupMenuItem(
                value: i,
                enabled: items[i].$2 != null,
                height: 28,
                child: Text(items[i].$1, style: const TextStyle(fontSize: 13)),
              ),
          ],
          onSelected: (i) => items[i].$2?.call(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
        );
    final running = c.state == BattleState.running;
    final paused = c.state == BattleState.paused;
    return Container(
      color: Classic.panel,
      child: Row(
        children: [
          menu('Battle', [
            ('New…', onNew),
            ('Start', c.robots.length >= 2 ? c.start : null),
            (
              running ? 'Pause' : 'Resume',
              running
                  ? c.pause
                  : paused
                  ? c.resume
                  : null,
            ),
            ('Stop', running || paused ? c.stop : null),
            ('Results…', c.roundScores.isNotEmpty ? onResults : null),
          ]),
          menu('Robot', [
            ('Add a robot…', onAdd),
            for (var i = 0; i < c.robots.length; i++)
              ('Edit ${c.robots[i].name}’s rules…', () => onEdit(i)),
            for (var i = 0; i < c.robots.length; i++)
              (
                'Remove ${c.robots[i].name}',
                onRemove == null ? null : () => onRemove!(i),
              ),
          ]),
          menu('Options', [
            for (final s in [2.0, 5.0, 15.0, 30.0, 0.0])
              (
                s == 0
                    ? 'Speed: as fast as aityx'
                    : 'Speed: ${s.toInt()} turns a second',
                () => c.setSpeed(s),
              ),
          ]),
          menu('Help', [
            ('View the last aityx call…', onCall),
            (
              'About RoboRules…',
              () => showAboutDialog(
                context: context,
                applicationName: 'RoboRules',
                children: const [
                  Text(
                    'A web take on the old Robocode. Every robot is an aityx '
                    'decision model, and every turn of the battle (sensors, '
                    'decisions, movement, bullets, collisions, damage) and '
                    'every round\'s score is played by aityx.',
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Battlefield extends StatelessWidget {
  const _Battlefield({required this.controller, required this.selected});

  final BattleController controller;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final now = DateTime.now();
    final interval = c.turnsPerSecond <= 0 ? 1 : 1000 / c.turnsPerSecond;
    final t = c.state == BattleState.running
        ? (now.difference(c.shownAt).inMilliseconds / interval).clamp(0.0, 1.0)
        : 1.0;
    return Bevel(
      pressed: true,
      color: Colors.black,
      padding: const EdgeInsets.all(1),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: BattlefieldPainter(
              previous: c.previous,
              current: c.world,
              t: t.toDouble(),
              robots: c.robots,
              explosions: c.explosions,
              selected: selected,
              now: now,
            ),
          ),
          if (c.state == BattleState.setup)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black54,
                child: Text(
                  c.robots.length < 2
                      ? 'At least two robots fight: add them on the right, '
                            'or Battle › New…'
                      : 'Press Start. Select a robot on the right to change '
                            'its rules.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          if (c.waitingForAityx)
            const Positioned(
              left: 8,
              top: 8,
              child: Text(
                'aityx is playing the next turns…',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          if (c.state == BattleState.scoring)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black54,
                child: Text(
                  'Round ${c.round} is over: aityx is scoring it…',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The robots, as Robocode's buttons on the right: color, name, energy and
/// the rule they follow now. Selecting one opens its rules; between
/// battles, each can be removed and more added.
class _RobotList extends StatelessWidget {
  const _RobotList({
    required this.controller,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onCall,
  });

  final BattleController controller;
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;
  final ValueChanged<AityxCall> onCall;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Bevel(
      pressed: true,
      color: Classic.panelLight,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            flex: 3,
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                  child: Text(
                    c.state == BattleState.setup
                        ? 'Robots'
                        : 'Round ${c.round} of ${c.rounds} · turn ${c.world?.tick ?? 0}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                for (var i = 0; i < c.robots.length; i++)
                  _RobotButton(
                    robot: c.robots[i],
                    bot: c.world?.bots.elementAtOrNull(i),
                    total: c.totals['r${i + 1}']?.total ?? 0,
                    selected: selected == i,
                    onTap: () => onSelect(i),
                    onRemove: onRemove == null ? null : () => onRemove!(i),
                  ),
                if (onAdd != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: ClassicButton(
                      label: 'Add robot…',
                      icon: Icons.add,
                      tooltip:
                          'Add one of the predefined robots, or a random one',
                      onPressed: onAdd,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            flex: 2,
            child: _EventLog(controller: c, onCall: onCall),
          ),
        ],
      ),
    );
  }
}

/// Everything that happened in the battle, newest at the bottom: rule
/// changes, hits, losses, rounds and scores, and every aityx call, the
/// kept ones opening in the viewer.
class _EventLog extends StatelessWidget {
  const _EventLog({required this.controller, required this.onCall});

  final BattleController controller;
  final ValueChanged<AityxCall> onCall;

  @override
  Widget build(BuildContext context) {
    final events = controller.events;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text(
            events.isEmpty ? 'Events' : 'Events (${events.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        Expanded(
          child: Bevel(
            pressed: true,
            color: Colors.white,
            padding: const EdgeInsets.all(2),
            child: events.isEmpty
                ? const Center(
                    child: Text(
                      'What happens in the battle, turn by turn, and every '
                      'call to aityx.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Classic.shadow),
                    ),
                  )
                // Reversed, so the newest line stays in view at the bottom.
                : ListView.builder(
                    reverse: true,
                    itemCount: events.length,
                    itemBuilder: (_, i) {
                      final e = events[events.length - 1 - i];
                      final call = e.call;
                      final text = Text(
                        e.text,
                        style: TextStyle(
                          fontSize: 11,
                          color: call == null
                              ? Classic.text
                              : call.kept
                              ? Classic.selection
                              : Classic.shadow,
                          decoration: call != null && call.kept
                              ? TextDecoration.underline
                              : null,
                        ),
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: call == null
                            ? text
                            : Tooltip(
                                message: call.kept
                                    ? 'See what was sent to aityx and what '
                                          'it answered'
                                    : 'Only the last ${controller.keptCalls} '
                                          'calls are kept',
                                child: InkWell(
                                  onTap: call.kept ? () => onCall(call) : null,
                                  child: text,
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _RobotButton extends StatelessWidget {
  const _RobotButton({
    required this.robot,
    required this.bot,
    required this.total,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final Robot robot;
  final Bot? bot;
  final int total;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final energy = bot?.energy ?? 100;
    final alive = bot?.alive ?? true;
    final rule = bot != null && bot!.rule > 0 && bot!.rule <= robot.rules.length
        ? robot.rules[bot!.rule - 1]
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message:
            'Click to change ${robot.name}\'s rules\n\n${rulesSummary(robot)}',
        child: InkWell(
          onTap: onTap,
          child: Bevel(
            pressed: selected,
            color: selected ? const Color(0xFFC9D8F0) : Classic.panel,
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(width: 12, height: 12, color: robot.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        robot.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          decoration: alive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    Text(
                      alive ? energy.toStringAsFixed(1) : 'lost',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (onRemove != null) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Remove ${robot.name} from the battle',
                        child: InkWell(
                          onTap: onRemove,
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Classic.shadow, width: 0.5),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (energy / 100).clamp(0.0, 1.0),
                    child: Container(
                      color: energy > 50
                          ? const Color(0xFF2E9E4F)
                          : energy > 20
                          ? const Color(0xFFE0A100)
                          : const Color(0xFFD03030),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rule == null
                      ? '${robot.rules.length} rules · score $total'
                      : 'Rule ${bot!.rule}: ${rule.why}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.onNew,
    required this.onCall,
  });

  final BattleController controller;
  final VoidCallback onNew;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final running = c.state == BattleState.running;
    final paused = c.state == BattleState.paused;
    final speed = c.turnsPerSecond <= 0 ? 61.0 : c.turnsPerSecond;
    return Container(
      color: Classic.panel,
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (c.canRetryScore)
            ClassicButton(
              label: 'Retry scoring',
              icon: Icons.refresh,
              onPressed: c.retryScore,
            ),
          ClassicButton(
            label: c.state == BattleState.setup || c.state == BattleState.over
                ? 'Start'
                : running
                ? 'Pause'
                : 'Resume',
            icon: running ? Icons.pause : Icons.play_arrow,
            onPressed: c.robots.length < 2
                ? null
                : running
                ? c.pause
                : paused
                ? c.resume
                : c.state == BattleState.scoring
                ? null
                : c.start,
          ),
          ClassicButton(
            label: 'Next turn',
            icon: Icons.skip_next,
            onPressed: paused ? c.nextTurn : null,
          ),
          ClassicButton(
            label: 'Stop',
            icon: Icons.stop,
            onPressed: running || paused ? c.stop : null,
          ),
          ClassicButton(
            label: 'Restart',
            icon: Icons.replay,
            onPressed: c.robots.length >= 2 ? c.start : null,
          ),
          ClassicButton(
            label: 'New battle…',
            icon: Icons.add,
            onPressed: onNew,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 320,
            child: Row(
              children: [
                const Text('Speed', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: speed,
                    min: 1,
                    max: 61,
                    onChanged: (v) =>
                        c.setSpeed(v >= 60.5 ? 0 : v.roundToDouble()),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    c.turnsPerSecond <= 0
                        ? 'Max'
                        : '${c.turnsPerSecond.toInt()} turns/s',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (c.aityxTurnsPerSecond != null)
            Text(
              'aityx: ${c.aityxTurnsPerSecond!.toStringAsFixed(0)} turns/s',
              style: const TextStyle(fontSize: 12),
            ),
          ClassicButton(
            label: 'aityx call',
            icon: Icons.data_object,
            tooltip: 'See the last call to aityx: the battle model and what it answered',
            onPressed: c.lastRequest == null ? null : () => onCall(),
          ),
          if (c.error != null)
            Text(
              c.error!,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 12),
            ),
        ],
      ),
    );
  }
}
