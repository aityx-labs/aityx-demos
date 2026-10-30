import 'package:flutter/material.dart';

import '../life/board.dart';
import '../life/generation.dart';
import '../theme.dart';
import 'call_json_view.dart';

/// One generation's call to aityx, as the app made it, with the
/// clusters that were sent (in the order aityx named them).
class CallRecord {
  const CallRecord(this.id, this.outcome, this.clusters, this.at);

  final int id;
  final GenerationOutcome outcome;
  final List<Cluster> clusters;
  final DateTime at;

  Generation get generation => outcome.generation;
}

/// A pattern noticed on the board: what appeared, at which generation.
class PatternNote {
  const PatternNote(
    this.callId,
    this.generation,
    this.text,
    this.about,
    this.at,
  );

  final int callId;
  final int generation;

  /// "A glider appeared", "2 blocks appeared".
  final String text;

  /// What the pattern is, from the model's kinds table.
  final String? about;
  final DateTime at;
}

/// The patterns' names as the notes and labels say them.
const patternNames = {
  'block': 'block',
  'beehive': 'beehive',
  'loaf': 'loaf',
  'boat': 'boat',
  'tub': 'tub',
  'blinker': 'blinker',
  'toad': 'toad',
  'beacon': 'beacon',
  'pulsar': 'pulsar',
  'pentadecathlon': 'penta-decathlon',
  'glider': 'glider',
  'lwss': 'light-weight spaceship',
  'mwss': 'middle-weight spaceship',
  'hwss': 'heavy-weight spaceship',
  'r_pentomino': 'R-pentomino',
  'diehard': 'diehard',
  'acorn': 'acorn',
};

String patternName(String id) => patternNames[id] ?? id;

/// The key parts of the request, by path.
const requestHighlights = {
  'state.rules': 'The rules that are on',
  'state.situations': 'The board\'s situations',
  'state.clusters': 'The clusters and their shapes',
  'decision.functions.fate.body': 'The rules of Life',
  'decision.functions.identify.body': 'The pattern catalogue',
  'decision.decisions.fates': 'What is asked',
};

/// The key parts of the response, by path.
const responseHighlights = {
  'answers.fates': 'The fate of each situation',
  'answers.alive_next': 'Alive next, per situation',
  'answers.patterns': 'The pattern of each cluster',
  'answers.population_next': 'Cells alive next',
  'receipt.functions.fate': 'The rule that fired, per situation',
  'receipt.functions.identify': 'The catalogue row that matched',
};

/// The side panel: the patterns noticed, then every call to aityx,
/// newest first, each with what it decided and its request and response.
/// Tapping a pattern noticed scrolls to the call that noticed it, opens
/// it and marks it.
class CallsPanel extends StatefulWidget {
  const CallsPanel({
    super.key,
    required this.calls,
    required this.notes,
    this.onClear,
  });

  final List<CallRecord> calls;
  final List<PatternNote> notes;
  final VoidCallback? onClear;

  @override
  State<CallsPanel> createState() => _CallsPanelState();
}

class _CallsPanelState extends State<CallsPanel> {
  final _scroll = ScrollController();

  /// The calls whose cards are open, and the one just jumped to.
  final _open = <int>{};
  int? _marked;
  final _cardKeys = <int, GlobalKey>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int callId) => _cardKeys.putIfAbsent(callId, GlobalKey.new);

  /// Scrolls to [callId], opens its card and marks it.
  void _jumpTo(int callId) {
    final index = widget.calls.indexWhere((call) => call.id == callId);
    if (index < 0) return;
    setState(() {
      _open
        ..clear()
        ..add(callId);
      _marked = callId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCall(callId));
  }

  Future<void> _revealCall(int callId) async {
    if (!mounted || !_scroll.hasClients) return;
    final key = _keyFor(callId);
    _scroll.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    while (mounted && _scroll.hasClients && key.currentContext == null) {
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) break;
      _scroll.jumpTo(
        (position.pixels + position.viewportDimension * 0.8).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    final context = key.currentContext;
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        alignment: 0,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final calls = widget.calls;
    final notes = widget.notes;
    final onClear = widget.onClear;
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
                '${calls.length}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: 'Clear the calls',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: calls.isEmpty && notes.isEmpty ? null : onClear,
              ),
            ],
          ),
        ),
        Expanded(
          child: calls.isEmpty && notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Every generation is one call to aityx: the board\'s '
                      'situations go in, and the rules decide what lives. '
                      'The calls show here as they happen.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: calls.length + (notes.isEmpty ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (notes.isNotEmpty && i == 0) {
                      return _NotesCard(notes: notes, onTap: _jumpTo);
                    }
                    final call = calls[i - (notes.isEmpty ? 0 : 1)];
                    return CallCard(
                      key: _keyFor(call.id),
                      call: call,
                      expanded: _open.contains(call.id),
                      marked: _marked == call.id,
                      onToggle: () => setState(() {
                        if (!_open.remove(call.id)) _open.add(call.id);
                        if (_marked == call.id) _marked = null;
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes, required this.onTap});

  final List<PatternNote> notes;

  /// Tapping a note: the ID of the call that noticed it.
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: Aityx.amber,
                ),
                const SizedBox(width: 8),
                Text(
                  'Patterns noticed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final note in notes.take(8))
              InkWell(
                onTap: () => onTap(note.callId),
                borderRadius: BorderRadius.circular(4),
                child: Tooltip(
                  message: 'Go to the call that noticed it',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Generation ${note.generation}: ',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              TextSpan(
                                text: note.text,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Icon(
                                    Icons.arrow_downward,
                                    size: 14,
                                    color: Aityx.amber,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (note.about case final about?)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              about,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One call: the generation, the counts and the patterns in its header;
/// expanded, what aityx decided for each situation and cluster, and the
/// request and the response. The panel holds whether it's open, and
/// marks it after a jump.
class CallCard extends StatelessWidget {
  const CallCard({
    super.key,
    required this.call,
    required this.expanded,
    required this.onToggle,
    this.marked = false,
  });

  final CallRecord call;
  final bool expanded;
  final VoidCallback onToggle;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final g = call.generation;
    final recognized = <String, int>{};
    for (final p in g.patterns) {
      if (p.recognized) {
        recognized[p.pattern] = (recognized[p.pattern] ?? 0) + 1;
      }
    }
    final facts = [
      '${g.situations.length} situations',
      '${g.patterns.length} clusters',
      if (call.outcome.tookMs case final ms?) '$ms ms',
      if (call.outcome.inputTokens case final tokens?) '$tokens tokens',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerLow,
      shape: marked
          ? RoundedRectangleBorder(
              side: const BorderSide(color: Aityx.amber, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Generation ${g.generation} → ${g.nextGeneration}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  Text(
                    facts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Pill(
                        '${g.population} → ${g.populationNext} cells',
                        scheme.onSurface,
                      ),
                      _Pill('+${g.births} born', Aityx.green),
                      _Pill('−${g.deaths} died', Aityx.red),
                      _Pill('${g.survivors} live on', Aityx.orange),
                      for (final MapEntry(key: id, value: n)
                          in recognized.entries)
                        _Pill(
                          n == 1 ? patternName(id) : '${patternName(id)} ×$n',
                          Aityx.amber,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Decided(generation: g),
                  CallJsonView(
                    title: 'REQUEST',
                    subtitle: 'POST /v1/systemone: the rules, and the board',
                    json: call.outcome.aityxRequest,
                    highlights: requestHighlights,
                  ),
                  CallJsonView(
                    title: 'RESPONSE',
                    subtitle: 'what aityx answered',
                    json: call.outcome.aityxResponse,
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

/// What aityx decided: a row per situation, then per cluster.
class _Decided extends StatelessWidget {
  const _Decided({required this.generation});

  final Generation generation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What aityx decided',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        for (final s in generation.situations)
          Tooltip(
            message: s.why ?? '',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.alive ? 'Live' : 'Dead'} cell, ${s.neighbours} '
                      'neighbour${s.neighbours == 1 ? '' : 's'} × ${s.cells}',
                      style: small,
                    ),
                  ),
                  Text(
                    _fateLabel(s.fate),
                    style: small?.copyWith(
                      color: s.aliveNext ? Aityx.green : Aityx.red,
                    ),
                  ),
                  if (s.rule case final rule?)
                    Text('  rule $rule', style: muted),
                ],
              ),
            ),
          ),
        if (generation.patterns.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final c in generation.patterns)
            Tooltip(
              message: c.about ?? '',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cluster of ${c.cells} cells, ${c.width}×${c.height}: '
                        '${c.shape}',
                        style: small,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      c.recognized
                          ? patternName(c.pattern)
                          : 'not a known pattern',
                      style: small?.copyWith(
                        color: c.recognized
                            ? Aityx.amber
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (c.rule case final rule?)
                      Text('  row $rule', style: muted),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  static String _fateLabel(String fate) => switch (fate) {
    'survives' => 'survives',
    'dies_lonely' => 'dies, lonely',
    'dies_crowded' => 'dies, crowded',
    'is_born' => 'is born',
    'stays_empty' => 'stays empty',
    _ => fate,
  };
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
