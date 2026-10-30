import 'dart:async';
import 'dart:math' as math;

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';

import '../aityx/generation_stepper.dart';
import '../app_version.dart';
import '../calls/calls_panel.dart';
import '../theme.dart';
import 'board.dart';
import 'board_view.dart';
import 'generation.dart';
import 'rules.dart';

/// The accelerations: generations per second, the last as fast as aityx
/// answers.
const accelerations = [0.5, 1.0, 2.0, 4.0, 8.0, double.infinity];

String accelerationLabel(double perSecond) => switch (perSecond) {
  0.5 => '½ generation/s',
  1.0 => '1 generation/s',
  double.infinity => 'as fast as aityx answers',
  _ => '${perSecond.toInt()} generations/s',
};

/// The most clusters sent with a generation (the limit stateFrom
/// checks, lib/aityx/life.dart).
const maxClustersSent = 24;

/// The widest or tallest cluster described to aityx.
const maxClusterSide = 64;

/// How long a notice stays over the board.
const noticeFor = Duration(seconds: 8);

/// The app's one screen: the board, its controls, and the side panel with
/// the aityx calls.
class LifeScreen extends StatefulWidget {
  const LifeScreen({
    super.key,
    this.stepper,
    this.random,
    this.start = StartKind.sparse,
  });

  /// Runs the generations: aityx unless a test says.
  final GenerationStepper? stepper;

  /// For the random start: a seeded one in tests.
  final math.Random? random;

  /// What the board opens with, over the cells in view: empty if null.
  final StartKind? start;

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  late final GenerationStepper _stepper =
      widget.stepper ?? AityxGenerationStepper();
  final _camera = BoardCamera();

  Board _board = const Board();
  final Map<String, bool> _rules = defaultRules;
  bool _playing = false;
  bool _stepping = false;
  Future<void>? _activeStep;
  Timer? _noticeTimer;
  int _playbackRevision = 0;
  int _boardRevision = 0;
  int _nextCallId = 0;
  int _acceleration = 1;
  final _calls = <CallRecord>[];
  final _notes = <PatternNote>[];
  var _labels = const <BoardLabel>[];

  /// How many of each pattern the last generation had, to notice new ones.
  var _patternCounts = const <String, int>{};

  /// Cells flipped while a generation was being asked of aityx: applied
  /// again on top of the answer.
  final _editsInFlight = <Cell, bool>{};
  int? _lastTookMs;

  @override
  void initState() {
    super.initState();
    final start = widget.start;
    if (start == null) return;
    // After the first layout, once the camera knows the view's size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _board.alive.isEmpty) _randomStart(start);
    });
  }

  @override
  void dispose() {
    _playing = false;
    _playbackRevision++;
    _noticeTimer?.cancel();
    _camera.dispose();
    super.dispose();
  }

  Duration get _interval {
    final perSecond = accelerations[_acceleration];
    return perSecond.isInfinite
        ? Duration.zero
        : Duration(milliseconds: (1000 / perSecond).round());
  }

  Future<void> _play() async {
    if (_playing) return;
    final playbackRevision = ++_playbackRevision;
    setState(() => _playing = true);
    while (_playing && playbackRevision == _playbackRevision && mounted) {
      final started = DateTime.now();
      await _step();
      if (!_playing ||
          playbackRevision != _playbackRevision ||
          !mounted) {
        break;
      }
      final wait = _interval - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  void _pause() {
    _playbackRevision++;
    setState(() => _playing = false);
  }

  /// One generation: the board's situations and clusters go to aityx,
  /// and the answer becomes the next board, a call in the panel, and the
  /// patterns noticed.
  Future<void> _step() {
    final active = _activeStep;
    if (active != null) return active;
    late final Future<void> task;
    task = _runStep().whenComplete(() {
      if (identical(_activeStep, task)) _activeStep = null;
    });
    _activeStep = task;
    return task;
  }

  Future<void> _runStep() async {
    final board = _board;
    if (board.alive.isEmpty) {
      _pause();
      return;
    }
    final boardRevision = _boardRevision;
    final groups = board.situations;
    final clusters = board.clusters
        .where((c) => c.width <= maxClusterSide && c.height <= maxClusterSide)
        .take(maxClustersSent)
        .toList();
    setState(() => _stepping = true);
    _editsInFlight.clear();
    final GenerationOutcome outcome;
    try {
      outcome = await _stepper.step(
        board.generation,
        {..._rules},
        groups,
        clusters,
      );
    } on GenerationException catch (error) {
      if (!mounted) return;
      if (boardRevision != _boardRevision) {
        setState(() => _stepping = false);
        return;
      }
      setState(() {
        _stepping = false;
        _playing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          // Without a key: the index page's key section, in this tab.
          action: error.noKey
              ? SnackBarAction(
                  label: 'Set your key',
                  onPressed: () => openAityxKeyPage(),
                )
              : null,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (boardRevision != _boardRevision) {
      setState(() => _stepping = false);
      return;
    }
    var next = board.next(groups, outcome.generation.aliveNext);
    for (final MapEntry(key: cell, value: alive) in _editsInFlight.entries) {
      if (alive != next.alive.contains(cell)) next = next.toggled(cell);
    }
    final patterns = outcome.generation.patterns;
    final callId = ++_nextCallId;
    final labels = <BoardLabel>[];
    final counts = <String, int>{};
    final about = <String, String?>{};
    for (var i = 0; i < patterns.length && i < clusters.length; i++) {
      final p = patterns[i];
      if (!p.recognized) continue;
      counts[p.pattern] = (counts[p.pattern] ?? 0) + 1;
      about[p.pattern] ??= p.about;
    }
    final nextClusters = next.clusters;
    final labeledClusters = <Cluster>{};
    for (var i = 0; i < patterns.length && i < clusters.length; i++) {
      final pattern = patterns[i];
      if (!pattern.recognized) continue;
      for (final cluster in nextClusters) {
        final overlapsOrTouches =
            cluster.maxX >= clusters[i].minX - 1 &&
            cluster.minX <= clusters[i].maxX + 1 &&
            cluster.maxY >= clusters[i].minY - 1 &&
            cluster.minY <= clusters[i].maxY + 1;
        if (!labeledClusters.contains(cluster) &&
            overlapsOrTouches &&
            isPatternPhase(pattern.pattern, cluster.shape)) {
          labels.add(BoardLabel(cluster, patternName(pattern.pattern)));
          labeledClusters.add(cluster);
          break;
        }
      }
    }
    final now = DateTime.now();
    final notes = <PatternNote>[];
    for (final MapEntry(key: id, value: n) in counts.entries) {
      final more = n - (_patternCounts[id] ?? 0);
      if (more <= 0) continue;
      final name = patternName(id);
      notes.add(
        PatternNote(
          callId,
          board.generation,
          more == 1
              ? 'A $name appeared'
              : '$more ${name.endsWith('s') ? name : '${name}s'} appeared',
          about[id],
          now,
        ),
      );
    }
    setState(() {
      _board = next;
      _stepping = false;
      _lastTookMs = outcome.tookMs;
      _labels = labels;
      _patternCounts = counts;
      _calls.insert(0, CallRecord(callId, outcome, clusters, now));
      if (_calls.length > 100) _calls.removeLast();
      _notes.insertAll(0, notes);
      if (_notes.length > 100) _notes.removeRange(100, _notes.length);
    });
    if (notes.isNotEmpty) {
      // Rebuild once the notices have expired, to take them off the board.
      _noticeTimer?.cancel();
      _noticeTimer = Timer(noticeFor + const Duration(milliseconds: 100), () {
        if (mounted) setState(() {});
      });
    }
  }

  /// A start of [kind] over the cells in view (at most 100 × 70), at
  /// generation 0.
  void _randomStart(StartKind kind) {
    final visible = _camera.visible;
    final width = math.min(visible.right - visible.left - 1, 100);
    final height = math.min(visible.bottom - visible.top - 1, 70);
    final x = (_camera.centerX - width / 2).round();
    final y = (_camera.centerY - height / 2).round();
    _reset(
      startBoard(
        kind,
        x: x,
        y: y,
        width: math.max(width, 8),
        height: math.max(height, 8),
        random: widget.random,
      ),
    );
  }

  void _reset(Board board) {
    _boardRevision++;
    setState(() {
      _board = board;
      _labels = const [];
      _patternCounts = const {};
      _editsInFlight.clear();
    });
  }

  void _toggle(Cell cell) {
    setState(() => _board = _board.toggled(cell));
    if (_stepping) _editsInFlight[cell] = _board.alive.contains(cell);
  }

  void _clearCalls() => setState(() {
    _calls.clear();
    _notes.clear();
  });

  /// The Rules dialog: a switch per rule the model knows, applied from
  /// the next generation on.
  Future<void> _editRules() => showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Rules'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Each rule is rows of the decision table aityx runs; a '
                'switch tells it which rows may fire. A live cell no '
                'enabled rule keeps alive dies.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final rule in lifeRules)
                CheckboxListTile(
                  value: _rules[rule.id] ?? false,
                  title: Text(rule.name),
                  subtitle: Text(rule.summary),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (on) {
                    setState(() => _rules[rule.id] = on ?? false);
                    setDialogState(() {});
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );

  /// Where the board stands: the generation, the cells, and how aityx
  /// answered the last one.
  String get _status => [
    'Generation ${_board.generation}',
    '${_board.population} cells',
    if (_stepping)
      'asking aityx…'
    else if (_lastTookMs case final ms?)
      'aityx answered in $ms ms',
  ].join(' · ');

  void _zoomBy(double factor) =>
      _camera.zoomAt(_camera.viewport.center(Offset.zero), factor);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final panel = CallsPanel(
      calls: _calls,
      notes: _notes,
      status: _status,
      onClear: _clearCalls,
    );
    final now = DateTime.now();
    final notices = _notes
        .where((n) => now.difference(n.at) < noticeFor)
        .take(3)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(AppVersion.title),
            const SizedBox(width: 16),
            Expanded(
              child: _Controls(
                playing: _playing,
                stepping: _stepping,
                acceleration: _acceleration,
                board: _board,
                rulesOn: _rules.values.where((on) => on).length,
                onRules: _editRules,
                onPlay: _play,
                onPause: _pause,
                onStep: _step,
                onRandom: _randomStart,
                onClear: () => _reset(const Board()),
                onAcceleration: (value) =>
                    setState(() => _acceleration = value),
              ),
            ),
          ],
        ),
        actions: [
          if (!wide)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Calls (${_calls.length})',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: Badge(
                  isLabelVisible: _calls.isNotEmpty,
                  label: Text('${_calls.length}'),
                  child: const Icon(Icons.receipt_long_outlined),
                ),
              ),
            ),
          // Clear of the aityx status light in the corner.
          const SizedBox(width: 16),
        ],
      ),
      endDrawer: wide
          ? null
          : Drawer(
              width: math.min(440, MediaQuery.sizeOf(context).width * 0.92),
              child: SafeArea(child: panel),
            ),
      body: Column(
        children: [
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      BoardView(
                        board: _board,
                        camera: _camera,
                        labels: _labels,
                        onToggle: _toggle,
                        hint: 'Press Random start, or tap cells to draw.\n'
                            'Drag to move around the infinite board; scroll or pinch to zoom.',
                      ),
                      if (notices.isNotEmpty)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: IgnorePointer(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final note in notices)
                                  _Notice(note: note),
                              ],
                            ),
                          ),
                        ),
                      // The calls panel shows the status; without it, the
                      // board does.
                      if (!wide)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: IgnorePointer(
                            child: _Overlay(
                              child: Text(
                                _status,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        right: 72,
                        bottom: 10,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: IgnorePointer(child: _Legend()),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _MapButtons(
                          onZoomIn: () => _zoomBy(1.5),
                          onZoomOut: () => _zoomBy(1 / 1.5),
                          onCenter: _camera.reset,
                        ),
                      ),
                    ],
                  ),
                ),
                if (wide) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 440, child: panel),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The controls, on the right of the title: play, step, random start,
/// clear, the rules and the acceleration. Without room for their labels
/// the buttons are icons, with the labels as tooltips; without room for
/// those either, they scroll.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.playing,
    required this.stepping,
    required this.acceleration,
    required this.board,
    required this.rulesOn,
    required this.onRules,
    required this.onPlay,
    required this.onPause,
    required this.onStep,
    required this.onRandom,
    required this.onClear,
    required this.onAcceleration,
  });

  /// The width the controls take with their labels (about 890 px in the
  /// browser; more with the test font).
  static const labeledWidth = 900.0;

  final bool playing;
  final bool stepping;
  final int acceleration;
  final Board board;

  /// How many rules are on, of [lifeRules].
  final int rulesOn;
  final VoidCallback onRules;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStep;
  final ValueChanged<StartKind> onRandom;
  final VoidCallback onClear;
  final ValueChanged<int> onAcceleration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final labeled = constraints.maxWidth >= labeledWidth;
        final rules = 'Rules ($rulesOn of ${lifeRules.length})';
        final controls = [
          labeled
              ? FilledButton.icon(
                  onPressed: playing ? onPause : onPlay,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  label: Text(playing ? 'Pause' : 'Play'),
                )
              : IconButton.filled(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: playing ? onPause : onPlay,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
          labeled
              ? OutlinedButton.icon(
                  onPressed: playing || stepping ? null : onStep,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Step'),
                )
              : IconButton.outlined(
                  tooltip: 'Step',
                  onPressed: playing || stepping ? null : onStep,
                  icon: const Icon(Icons.skip_next),
                ),
          MenuAnchor(
            menuChildren: [
              for (final kind in StartKind.values)
                MenuItemButton(
                  onPressed: () => onRandom(kind),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kind.label),
                      Text(
                        kind.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            builder: (context, controller, child) {
              void toggle() =>
                  controller.isOpen ? controller.close() : controller.open();
              return labeled
                  ? OutlinedButton.icon(
                      onPressed: toggle,
                      icon: const Icon(Icons.casino_outlined),
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Random start'),
                          Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    )
                  : IconButton.outlined(
                      tooltip: 'Random start',
                      onPressed: toggle,
                      icon: const Icon(Icons.casino_outlined),
                    );
            },
          ),
          labeled
              ? TextButton.icon(
                  onPressed: board.alive.isEmpty ? null : onClear,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear'),
                )
              : IconButton(
                  tooltip: 'Clear',
                  onPressed: board.alive.isEmpty ? null : onClear,
                  icon: const Icon(Icons.clear_all),
                ),
          labeled
              ? OutlinedButton.icon(
                  onPressed: onRules,
                  icon: const Icon(Icons.rule),
                  label: Text(rules),
                )
              : IconButton.outlined(
                  tooltip: rules,
                  onPressed: onRules,
                  icon: const Icon(Icons.rule),
                ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: labeled ? 170 : 110,
                child: Tooltip(
                  message: 'Acceleration',
                  child: Slider(
                    value: acceleration.toDouble(),
                    min: 0,
                    max: (accelerations.length - 1).toDouble(),
                    divisions: accelerations.length - 1,
                    label: accelerationLabel(accelerations[acceleration]),
                    onChanged: (value) => onAcceleration(value.round()),
                  ),
                ),
              ),
              Text(
                accelerationLabel(accelerations[acceleration]),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ];
        return Align(
          alignment: Alignment.centerRight,
          // Scrolled from the start, so Play shows on a phone.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, control) in controls.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  control,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A translucent box over the board, for the legend and the status.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Aityx.bg.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
}

/// The map buttons at the bottom right of the board, as on a map: back to
/// the origin, and zoom in and out around the center.
class _MapButtons extends StatelessWidget {
  const _MapButtons({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenter,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    Widget box(Widget child) => Material(
      color: Aityx.bg1,
      elevation: 2,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Aityx.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        box(
          IconButton(
            tooltip: 'Back to the origin',
            onPressed: onCenter,
            icon: const Icon(Icons.center_focus_strong_outlined),
          ),
        ),
        const SizedBox(height: 8),
        box(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Zoom in',
                onPressed: onZoomIn,
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 32, child: Divider(height: 1)),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: onZoomOut,
                icon: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.note});

  final PatternNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: Aityx.bg1.withValues(alpha: 0.95),
        border: Border.all(color: Aityx.amber),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 16, color: Aityx.amber),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Generation ${note.generation}: ${note.text}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (note.about case final about?)
            Text(
              about,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    Widget swatch(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: style)),
      ],
    );
    return _Overlay(
      child: Wrap(
        spacing: 10,
        children: [
          swatch(Aityx.orange, 'alive'),
          swatch(Aityx.green, 'born this generation'),
          swatch(Aityx.dim, 'died this generation'),
          swatch(Aityx.amber, 'pattern aityx recognized'),
        ],
      ),
    );
  }
}
