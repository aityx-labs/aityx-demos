import 'dart:async';

import 'package:flutter/material.dart';
import 'package:poker_core/table.dart' show Strategy;

import '../game/controller.dart';
import '../theme.dart';
import 'enter.dart';
import 'files.dart';
import 'tour_api.dart';
import 'tour_session.dart';

/// The leaderboard: every strategy in the tour with its wins, and the
/// tournament being played now (or when the next is), each strategy over
/// its owner (their alias, else their name; a preset is a template
/// strategy).
/// Signed in, you can withdraw your own and download any (uploads are in
/// Players and Profile); an admin can start a tournament now.
class LeaderboardView extends StatefulWidget {
  const LeaderboardView({super.key, required this.session, this.controller, this.compact = false});

  final TourSession session;

  /// The table, whose presets a template strategy's download is read
  /// from, when there is one.
  final GameController? controller;

  /// For the sidebar: fewer columns (no best place) and the actions under
  /// the title.
  final bool compact;

  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> {
  TourSession get s => widget.session;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    s.refreshLeaderboard();
    s.poll(true);
  }

  @override
  void dispose() {
    s.poll(false);
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    String message;
    try {
      message = switch (await s.startTournament()) {
        'queued' => 'A tournament is queued: it starts when the one being played ends.',
        'waiting' => 'A tournament you asked for is waiting its turn already.',
        _ => 'A tournament is starting; the standings follow it here.',
      };
    } on TourException catch (e) {
      message = e.message;
    }
    if (!mounted) return;
    setState(() => _starting = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _withdraw(Standing row) async {
    try {
      await s.withdraw(row.id);
    } on TourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// The strategy's rules, for a download: the tour's, read
  /// once signed in, or a preset from the table.
  Strategy? _rules(Standing row) {
    if (row.preset) {
      return widget.controller?.strategies.where((x) => x.id == row.id).firstOrNull;
    }
    return s.tourStrategies.where((t) => t.id == row.id).firstOrNull?.strategy;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final board = s.leaderboard;
        final signedIn = s.player != null;
        final actions = <Widget>[
          if (signedIn && s.admin && board != null && board.runnerEnabled)
            FilledButton.tonalIcon(
              key: const Key('run-now'),
              onPressed: _starting || board.queue.contains('admin') ? null : _start,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Play a tournament now'),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Leaderboard', style: theme.textTheme.titleMedium)),
                if (!widget.compact) ...actions,
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: s.refreshLeaderboard,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            // In the sidebar, the buttons under the title: it is narrow.
            if (widget.compact && actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, children: actions),
            if (board == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(s.error ?? 'Loading…', style: muted),
              )
            else ...[
              _RunnerLine(board: board),
              if (board.runnerEnabled && board.nextRunAt != null) ...[
                const SizedBox(height: 6),
                _Countdown(at: board.nextRunAt!),
              ],
              const SizedBox(height: 8),
              _Standings(
                board: board,
                session: s,
                compact: widget.compact,
                rules: _rules,
                onWithdraw: _withdraw,
              ),
              if (board.current != null) ...[
                const SizedBox(height: 16),
                _Current(current: board.current!),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _RunnerLine extends StatelessWidget {
  const _RunnerLine({required this.board});

  final Leaderboard board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = board.nextRunAt;
    final waiting = board.queue.isEmpty
        ? ''
        : ' Waiting their turn: ${board.queue.map(_asker).join(', ')}.';
    final coming = !board.runnerEnabled
        ? ''
        : next == null
        ? '$waiting No tournament is scheduled; an admin can start one, and every new strategy does.'
        : waiting;
    final (color, text) = switch (board.runnerState) {
      'playing' => (Aityx.green, 'The leaderboard is playing: ${board.runnerDetail}.$waiting'),
      'waiting' => (Aityx.amber, 'Latest: ${board.runnerDetail}.$coming'),
      'error' => (scheme.error, 'The leaderboard stopped: ${board.runnerDetail}.$coming'),
      _ => (scheme.outline, board.runnerEnabled ? 'The leaderboard is idle: ${board.runnerDetail}.$coming' : 'The leaderboard is off on this server.'),
    };
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
      ],
    );
  }

  /// Who asked for a waiting tournament.
  static String _asker(String source) => switch (source) {
    'schedule' => "the schedule's",
    'admin' => "an admin's",
    'strategy' => "a new strategy's",
    _ => source,
  };
}

/// The time to the next scheduled tournament, counting down by the
/// second, and when it is.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.at});

  final DateTime at;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final left = widget.at.difference(DateTime.now());
    return Row(
      key: const Key('countdown'),
      children: [
        Icon(Icons.timer_outlined, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Next tournament '),
                TextSpan(
                  text: left.isNegative ? 'any moment now' : 'in ${timeLeft(left)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                TextSpan(text: ', ${localWhen(widget.at)}'),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// [left] for people: "5 h 02 min", "12 min 05 s", "45 s".
String timeLeft(Duration left) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = left.inHours, m = left.inMinutes % 60, s = left.inSeconds % 60;
  if (h > 0) return '$h h ${two(m)} min';
  if (m > 0) return '$m min ${two(s)} s';
  return '$s s';
}

/// [at] in local time: "today at 18:00", "tomorrow at 00:00", or the
/// date.
String localWhen(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return switch (day.difference(today).inDays) {
    0 => 'today at $time',
    1 => 'tomorrow at $time',
    _ => 'on ${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} at $time',
  };
}

class _Standings extends StatelessWidget {
  const _Standings({
    required this.board,
    required this.session,
    required this.compact,
    required this.rules,
    required this.onWithdraw,
  });

  final Leaderboard board;
  final TourSession session;
  final bool compact;
  final Strategy? Function(Standing) rules;
  final Future<void> Function(Standing) onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (board.standings.isEmpty) {
      return Text('Nobody is in the tour yet.', style: theme.textTheme.bodySmall);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: const Key('standings'),
        columnSpacing: compact ? 12 : 18,
        horizontalMargin: compact ? 4 : 24,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 52,
        headingTextStyle: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        columns: [
          const DataColumn(label: Text('#')),
          const DataColumn(label: Text('Strategy')),
          const DataColumn(label: Text('Wins'), numeric: true),
          const DataColumn(label: Text('Played'), numeric: true),
          if (!compact) const DataColumn(label: Text('Best'), numeric: true),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final (i, row) in board.standings.indexed)
            DataRow(
              cells: [
                DataCell(Text('${i + 1}')),
                DataCell(
                  Tooltip(
                    message: row.broken != null ? 'Left out: ${row.broken}' : row.tagline,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _name(row, theme, scheme),
                        Text(
                          row.preset ? 'template strategy' : row.owner,
                          key: Key('owner-${row.id}'),
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(Text('${row.wins}')),
                DataCell(Text('${row.tournaments}')),
                if (!compact) DataCell(Text(row.best == null ? '–' : '${row.best}')),
                DataCell(_Actions(
                  row: row,
                  rules: rules(row),
                  mine: session.mine(row),
                  onWithdraw: onWithdraw,
                )),
              ],
            ),
        ],
      ),
    );
  }

  Widget _name(Standing row, ThemeData theme, ColorScheme scheme) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        row.name,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: row.broken != null ? scheme.outline : null,
        ),
      ),
      if (session.mine(row)) ...[
        const SizedBox(width: 6),
        const Text('yours', style: TextStyle(fontSize: 10, color: Aityx.green)),
      ],
      if (row.broken != null) ...[
        const SizedBox(width: 6),
        Icon(Icons.error_outline, size: 14, color: scheme.error),
      ],
    ],
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.row,
    required this.rules,
    required this.mine,
    required this.onWithdraw,
  });

  final Standing row;
  final Strategy? rules;
  final bool mine;
  final Future<void> Function(Standing) onWithdraw;

  @override
  Widget build(BuildContext context) {
    final r = rules;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r != null && filesSupported)
          IconButton(
            tooltip: 'Download as JSON',
            visualDensity: VisualDensity.compact,
            onPressed: () => saveTextFile(strategyFileName(r), r.toEditable()),
            icon: const Icon(Icons.download_outlined, size: 18),
          ),
        if (mine)
          IconButton(
            tooltip: 'Withdraw from the tour',
            visualDensity: VisualDensity.compact,
            onPressed: () => onWithdraw(row),
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
      ],
    );
  }
}

class _Current extends StatelessWidget {
  const _Current({required this.current});

  final LiveTournament current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seats = [...current.seats]..sort((a, b) {
      if (a.place != null || b.place != null) {
        if (a.place == null) return -1;
        if (b.place == null) return 1;
        return a.place!.compareTo(b.place!);
      }
      return b.stack.compareTo(a.stack);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tournament #${current.number}, hand ${current.hand}, ${current.calls} aityx calls',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final seat in seats)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  seat.place != null ? '${seat.name}: out, ${seat.place}${_th(seat.place!)}' : '${seat.name}: ${seat.stack}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: seat.place != null ? scheme.outline : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _th(int n) => switch (n % 10) {
    1 when n % 100 != 11 => 'st',
    2 when n % 100 != 12 => 'nd',
    3 when n % 100 != 13 => 'rd',
    _ => 'th',
  };
}
