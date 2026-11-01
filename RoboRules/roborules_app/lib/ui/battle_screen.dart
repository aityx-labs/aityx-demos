import 'package:flutter/material.dart';

import '../aityx/aityx_call_view.dart';
import '../aityx/theme.dart';
import '../battle/controller.dart';
import '../battle/model.dart';
import '../battle/painter.dart';
import '../battle/predefined_robots.dart';
import '../battle/robot_files.dart';
import '../files/files.dart';
import 'classic.dart';
import 'dialogs.dart';
import 'rules_editor.dart';

/// The battle window, in Robocode's layout: a menu bar, the battlefield,
/// the robots on the right, the controls below.
class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key, required this.controller, this.files});

  final BattleController controller;

  /// Downloads and uploads: the browser's unless a test says.
  final Files? files;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  BattleController get c => widget.controller;
  late final Files _files = widget.files ?? Files();
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

  /// Adds the robots in the files the user picks, between battles, up to
  /// [maxRobots]; says what it couldn't read, and why.
  Future<void> _uploadRobots() async {
    if (!_idle) return;
    final picked = await _files.pick();
    if (!mounted || picked.isEmpty || !_idle) return;
    final added = <Robot>[];
    final problems = <String>[];
    for (final file in picked) {
      if (file.text == null) {
        problems.add('${file.name}: ${file.error}');
        continue;
      }
      try {
        final robots = robotsFromFile(
          file.text!,
          taken: [...c.robots, ...added],
        );
        final room = maxRobots - c.robots.length - added.length;
        added.addAll(robots.take(room));
        if (robots.length > room) {
          problems.add(
            '${file.name}: a battle takes at most $maxRobots robots; '
            '${robots.length - room} left out',
          );
        }
      } on FormatException catch (e) {
        problems.add('${file.name}: not a robot: ${e.message}');
      }
    }
    for (final r in added) {
      c.addRobot(r);
    }
    if (added.isNotEmpty) setState(() => _selected = c.robots.length - 1);
    if (problems.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ClassicDialog(
        title: added.isEmpty
            ? 'No robot uploaded'
            : 'Uploaded ${added.map((r) => r.name).join(', ')}',
        actions: [
          ClassicButton(
            label: 'OK',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        child: Text(problems.join('\n'), style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  /// Downloads the battle's robots as one file.
  void _downloadAll() => _files.save(allRobotsFileName, robotsFile(c.robots));

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
      builder: (_) => RulesEditor(
        robot: c.robots[index],
        factory: c.factory,
        files: _files,
        onRemove: _idle ? () => _removeRobot(index) : null,
      ),
    );
    if (robot != null) c.replaceRobot(index, robot);
    if (wasRunning) c.resume();
  }

  Future<void> _showResults() => showDialog<void>(
    context: context,
    builder: (_) => ResultsDialog(controller: c),
  );

  /// Shows [call], or the last one, in the viewer. From the event log,
  /// shows the [event]'s line above the call behind it, if any.
  Future<void> _showCall([AityxCall? call, BattleEvent? event]) {
    final shown = event == null ? call ?? c.lastCall : call;
    final Widget body = shown == null || !shown.kept
        ? Text(
            shown != null
                ? 'Only the last ${c.keptCalls} calls are kept.'
                : event != null
                ? 'This happened in the app, not on aityx: no aityx call is '
                      'behind it.'
                : 'No call yet: start a battle.',
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
                      request: shown.request,
                      response: shown.response,
                      responseSubtitle: 'what aityx answered',
                      targets: callTargets(c.robots),
                      height: MediaQuery.sizeOf(context).height * 0.55,
                    ),
                  ),
                ),
              ),
            ),
          );
    return showDialog<void>(
      context: context,
      builder: (context) => ClassicDialog(
        title: call != null
            ? 'aityx call ${call.number}: ${call.what}'
            : event != null
            ? 'A battle event'
            : 'The last aityx call',
        width: 1100,
        actions: [
          ClassicButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        child: event == null
            ? body
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    event.text,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(child: body),
                ],
              ),
      ),
    );
  }

  /// Shows an event of the log, and the aityx call behind it.
  Future<void> _showEvent(BattleEvent event) => _showCall(event.call, event);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final field = _Battlefield(controller: c, selected: _selected);
    final robotsPanel = _RobotList(
      controller: c,
      selected: _selected,
      onSelect: _editRobot,
      onAdd: _idle && c.robots.length < maxRobots ? _addRobot : null,
      onUpload: _idle && c.robots.length < maxRobots ? _uploadRobots : null,
      onRemove: _idle ? _removeRobot : null,
      onEvent: _showEvent,
      onCall: (call) => _showCall(call),
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
              onUpload: _idle && c.robots.length < maxRobots
                  ? _uploadRobots
                  : null,
              onDownloadAll: c.robots.isEmpty ? null : _downloadAll,
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
    required this.onUpload,
    required this.onDownloadAll,
    required this.onResults,
    required this.onCall,
  });

  final BattleController controller;
  final VoidCallback onNew;
  final VoidCallback? onAdd;
  final VoidCallback? onUpload;
  final VoidCallback? onDownloadAll;
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
            ('Upload robots…', onUpload),
            ('Download all robots', onDownloadAll),
          ]),
          menu('Options', [
            for (final s in [2.0, 5.0, 10.0, 20.0, 30.0, 0.0])
              (
                s == 0
                    ? 'Speed: as fast as aityx'
                    : 'Speed: ${s.toInt()} turns a second',
                () => c.setSpeed(s),
              ),
            (
              c.soundOn ? 'Sound: on (turn it off)' : 'Sound: off (turn it on)',
              () => c.setSound(!c.soundOn),
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
    final interval = c.pace <= 0 ? 1 : 1000 / c.pace;
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
          if (c.roundWinner case final w?
              when c.state == BattleState.scoring ||
                  c.state == BattleState.over)
            Center(
              child: _WinnerBanner(winner: w, robots: c.robots),
            )
          else if (c.state == BattleState.scoring)
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

/// The event log's alternating line backgrounds: white, then light gray.
const eventStripes = [Colors.white, Color(0xFFEBEBEB)];

/// A shot's line in the event log: a red tone, and darker red text.
const shotBackground = Color(0xFFFFD9D6);
const shotText = Color(0xFFB3261E);

/// The round's winner, announced on the battlefield: a trophy, the
/// winner's name in its color, and its points.
class _WinnerBanner extends StatelessWidget {
  const _WinnerBanner({required this.winner, required this.robots});

  final RoundWinner winner;
  final List<Robot> robots;

  @override
  Widget build(BuildContext context) {
    final i = winner.robot;
    final robot = i != null && i < robots.length ? robots[i] : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black87,
        border: Border.all(color: robot?.color ?? Colors.white54, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events,
            color: robot?.color ?? Colors.white54,
            size: 40,
          ),
          const SizedBox(height: 6),
          Text(
            robot == null
                ? 'Round ${winner.round}: no winner'
                : '${robot.name} wins round ${winner.round}!',
            style: TextStyle(
              color: robot?.color ?? Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (robot != null) ...[
            const SizedBox(height: 4),
            Text(
              '${winner.points} points',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
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
    required this.onUpload,
    required this.onRemove,
    required this.onEvent,
    required this.onCall,
  });

  final BattleController controller;
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback? onAdd;
  final VoidCallback? onUpload;
  final ValueChanged<int>? onRemove;
  final ValueChanged<BattleEvent> onEvent;
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
                if (onUpload != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: ClassicButton(
                      label: 'Upload robots…',
                      icon: Icons.upload_file,
                      tooltip:
                          'Add robots from files downloaded from RoboRules '
                          '(Robot › Download)',
                      onPressed: onUpload,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            flex: 2,
            child: _EventLog(controller: c, onEvent: onEvent),
          ),
          const SizedBox(height: 4),
          _LastCall(call: c.lastCall, onCall: onCall),
        ],
      ),
    );
  }
}

/// Everything that happened in the battle, newest at the bottom: rule
/// changes, shots, hits, losses, rounds and winners. Each line opens in
/// the viewer, with the aityx call behind it; the calls themselves show
/// below, in [_LastCall].
class _EventLog extends StatelessWidget {
  const _EventLog({required this.controller, required this.onEvent});

  final BattleController controller;
  final ValueChanged<BattleEvent> onEvent;

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
                      'What happens in the battle, turn by turn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Classic.shadow),
                    ),
                  )
                // Reversed, so the newest line stays in view at the bottom.
                : ListView.builder(
                    reverse: true,
                    itemCount: events.length,
                    itemBuilder: (_, i) {
                      final n = events.length - 1 - i;
                      final e = events[n];
                      final call = e.call;
                      return Tooltip(
                        message: call == null
                            ? 'This happened in the app, not on aityx'
                            : call.kept
                            ? 'See aityx call ${call.number}, behind this '
                                  'line: what was sent and what it answered'
                            : 'Only the last ${controller.keptCalls} '
                                  'calls are kept',
                        // Zebra stripes, by the line's place in the whole
                        // log, so a line keeps its shade as more arrive.
                        child: Material(
                          color: e.isShot
                              ? shotBackground
                              : eventStripes[n % 2],
                          child: InkWell(
                            onTap: () => onEvent(e),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                e.text,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: e.isShot ? shotText : Classic.text,
                                ),
                              ),
                            ),
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

/// The latest call to aityx, below the event log: what it was for, how
/// long aityx took, and a round's scores; it opens the call.
class _LastCall extends StatelessWidget {
  const _LastCall({required this.call, required this.onCall});

  final AityxCall? call;
  final ValueChanged<AityxCall> onCall;

  @override
  Widget build(BuildContext context) {
    final call = this.call;
    return Bevel(
      pressed: true,
      color: Colors.white,
      padding: EdgeInsets.zero,
      child: Tooltip(
        message: call == null
            ? 'Each call to aityx shows here'
            : 'See what was sent to aityx and what it answered',
        child: InkWell(
          onTap: call == null ? null : () => onCall(call),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last aityx call',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                if (call == null)
                  const Text(
                    'None yet',
                    style: TextStyle(fontSize: 11, color: Classic.shadow),
                  )
                else ...[
                  Text(
                    'Call ${call.number}: ${call.what}'
                    '${call.millis == null ? '' : ', in ${call.millis} ms'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Classic.selection,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  if (call.result case final result?)
                    Text(result, style: const TextStyle(fontSize: 11)),
                ],
              ],
            ),
          ),
        ),
      ),
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
            width: 380,
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
                if (c.pace > c.turnsPerSecond)
                  Tooltip(
                    message:
                        'The battle speeds up as it goes: every '
                        '${c.speedUpEvery.inSeconds} s of play, '
                        '${c.speedUpBy.toInt()} turns a second more, up to '
                        '${c.speedUpTo.toInt()}',
                    child: Text(
                      'now ${c.pace.toInt()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          ClassicButton(
            label: c.soundOn ? 'Sound on' : 'Sound off',
            icon: c.soundOn ? Icons.volume_up : Icons.volume_off,
            tooltip: c.soundOn
                ? 'Turn off the sounds of collisions, hits and robots lost'
                : 'Turn on the sounds of collisions, hits and robots lost',
            onPressed: () => c.setSound(!c.soundOn),
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
