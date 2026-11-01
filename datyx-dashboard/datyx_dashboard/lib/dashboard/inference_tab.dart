import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'card_title.dart';
import 'health_tab.dart' show ApiDownLine;
import 'training_tab.dart' show StatTile, StatusChip, when;

/// The Inference tab: the account of the calls to the models datyx
/// trained (`GET /api/inference`, the last 7 days): totals, the calls per
/// hour of the last day, each model's calls and latency with **Try it**,
/// which scores series through the same accounted endpoint
/// (`POST /api/datasources/{id}/inference`), and the latest calls. What is
/// shown is the API's; the tab asks and shows.
class InferenceTab extends StatefulWidget {
  const InferenceTab({super.key, required this.api, required this.locked, required this.statusError});

  final DatyxApi api;
  final bool locked;
  final String? statusError;

  @override
  State<InferenceTab> createState() => _InferenceTabState();
}

class _InferenceTabState extends State<InferenceTab> {
  InferenceAccount? _account;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.locked) _load();
  }

  @override
  void didUpdateWidget(InferenceTab old) {
    super.didUpdateWidget(old);
    if (old.locked && !widget.locked) _load();
  }

  Future<void> _load() async {
    try {
      final account = await widget.api.inference();
      if (mounted) {
        setState(() {
          _account = account;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: spaced([
        if (widget.statusError != null) ApiDownLine(widget.statusError!),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: CardTitle('Inference', 'GET /api/inference, the last 7 days')),
                    IconButton(
                      key: const ValueKey('inference-reload'),
                      tooltip: 'Ask again',
                      onPressed: widget.locked ? null : _load,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'A trained model scores series on demand: POST /api/datasources/{id}/inference with a '
                  'table, its group and the series by their key (none: every series still observed). '
                  'Each call is accounted for: who asked, which model, how many series, how long, and '
                  'whether it failed.',
                  style: TextStyle(color: Aityx.muted),
                ),
                const SizedBox(height: 12),
                if (widget.locked)
                  const Text('Sign in to see the inference.', style: TextStyle(color: Aityx.muted))
                else if (_error != null)
                  Text(_error!, style: const TextStyle(color: Aityx.red))
                else if (a == null)
                  const Text('Loading…', style: TextStyle(color: Aityx.muted))
                else ...[
                  _Totals(totals: a.totals, lastHour: a.lastHour),
                  const SizedBox(height: 16),
                  CallsPerHour(hours: a.perHour),
                ],
              ],
            ),
          ),
        ),
        if (!widget.locked && a != null) ...[
          if (a.models.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No model yet: the Training tab trains the groups tagged for XGBoost.',
                  style: TextStyle(color: Aityx.amber),
                ),
              ),
            ),
          for (final m in a.models)
            InferenceModelCard(key: ValueKey('inference-${m.table}-${m.group}'), api: widget.api, model: m, onCalled: _load),
          _Calls(calls: a.calls),
        ],
      ]),
    );
  }
}

/// Milliseconds as text: whole ones without decimals (on the web every
/// number is a double), others to a tenth; a dash for none.
String ms(num? v) => v == null ? '–' : '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)} ms';

class _Totals extends StatelessWidget {
  const _Totals({required this.totals, required this.lastHour});
  final InferenceStats totals;
  final int lastHour;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      StatTile(key: const ValueKey('total-calls'), label: 'calls', value: '${totals.calls}', note: 'in 7 days'),
      StatTile(key: const ValueKey('total-last-hour'), label: 'last hour', value: '$lastHour', note: 'calls'),
      StatTile(
        key: const ValueKey('total-failed'),
        label: 'failed',
        value: '${totals.failed}',
        note: totals.calls == 0 ? 'none yet' : '${(100 * totals.failed / totals.calls).toStringAsFixed(0)}% of calls',
        status: totals.failed == 0 ? Aityx.green : Aityx.red,
        icon: totals.failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
      ),
      StatTile(key: const ValueKey('total-scored'), label: 'series scored', value: '${totals.scored}', note: 'in 7 days'),
      StatTile(key: const ValueKey('total-p50'), label: 'median latency', value: ms(totals.p50Millis), note: 'per call'),
      StatTile(key: const ValueKey('total-p95'), label: '95th percentile', value: ms(totals.p95Millis), note: 'per call'),
    ],
  );
}

/// The calls of each of the last 24 hours, as columns on one baseline in
/// one hue; each column's tooltip says the hour, its calls and its
/// failures; the scale's top and the hours are labelled in text.
class CallsPerHour extends StatelessWidget {
  const CallsPerHour({super.key, required this.hours, this.height = 90});

  final List<InferenceHour> hours;
  final double height;

  @override
  Widget build(BuildContext context) {
    final top = hours.fold<int>(0, (m, h) => h.calls > m ? h.calls : m);
    String hh(DateTime t) => t.toLocal().toString().substring(11, 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Calls per hour', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
          top == 0 ? 'none in the last 24 hours' : 'the last 24 hours; the tallest is $top',
          style: const TextStyle(color: Aityx.muted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final h in hours)
                Expanded(
                  child: Tooltip(
                    message:
                        '${hh(h.hour)}–${hh(h.hour.add(const Duration(hours: 1)))}: ${h.calls} calls'
                        '${h.failed == 0 ? '' : ', ${h.failed} failed'}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        key: ValueKey('hour-${h.hour.toIso8601String()}'),
                        height: top == 0 || h.calls == 0 ? 0 : (height * h.calls / top).clamp(2.0, height),
                        decoration: const BoxDecoration(
                          color: Aityx.orange,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: Aityx.border),
        const SizedBox(height: 2),
        if (hours.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(hh(hours.first.hour), style: const TextStyle(color: Aityx.muted, fontSize: 11)),
              const Text('now', style: TextStyle(color: Aityx.muted, fontSize: 11)),
            ],
          ),
      ],
    );
  }
}

/// A model: its calls' account, and **Try it**, which scores a series by
/// its key, or every series still observed, through the accounted endpoint.
class InferenceModelCard extends StatefulWidget {
  const InferenceModelCard({super.key, required this.api, required this.model, required this.onCalled});

  final DatyxApi api;
  final InferenceModel model;
  final Future<void> Function() onCalled;

  @override
  State<InferenceModelCard> createState() => _InferenceModelCardState();
}

class _InferenceModelCardState extends State<InferenceModelCard> {
  late final Map<String, TextEditingController> _key = {
    for (final k in widget.model.seriesKey) k: TextEditingController(),
  };
  InferenceAnswer? _answer;
  String? _error;
  bool _busy = false;

  InferenceModel get m => widget.model;

  @override
  void dispose() {
    for (final c in _key.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _score({required bool all}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final answer = await widget.api.score(
        m.sourceId,
        m.table,
        m.group,
        series: all ? null : [{for (final e in _key.entries) e.key: e.value.text.trim()}],
        limit: 10,
      );
      if (mounted) setState(() => _answer = answer);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      await widget.onCalled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = m.stats;
    final answer = _answer;
    final keyed = _key.values.every((c) => c.text.trim().isNotEmpty);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                const Icon(Icons.bolt, size: 20, color: Aityx.orangeLight),
                Text('XGBoost · ${m.group}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '${m.name} · ${m.source}',
                  style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Model: run ${m.runId ?? '?'}${m.trainedAt == null ? '' : ', trained ${when(m.trainedAt!)}'}. '
              'Predicts ${m.target ?? 'the Target'} over the next ${m.horizon ?? '?'}, per '
              '${m.seriesKey.isEmpty ? 'table' : m.seriesKey.join(' + ')}.',
              style: const TextStyle(color: Aityx.fg),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                StatTile(label: 'calls', value: '${s.calls}', note: s.lastCalledAt == null ? 'never called' : 'last ${when(s.lastCalledAt!)}'),
                StatTile(
                  label: 'failed',
                  value: '${s.failed}',
                  note: 'of its calls',
                  status: s.failed == 0 ? Aityx.green : Aityx.red,
                  icon: s.failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
                ),
                StatTile(label: 'series scored', value: '${s.scored}', note: 'in 7 days'),
                StatTile(label: 'median latency', value: ms(s.p50Millis), note: 'mean ${ms(s.avgMillis)}'),
                StatTile(label: '95th percentile', value: ms(s.p95Millis), note: 'per call'),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Try it', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in _key.entries)
                  SizedBox(
                    width: 160,
                    child: TextField(
                      key: ValueKey('key-${e.key}'),
                      controller: e.value,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(isDense: true, labelText: e.key),
                    ),
                  ),
                FilledButton.icon(
                  key: ValueKey('score-${m.table}-${m.group}'),
                  onPressed: _busy || !keyed ? null : () => _score(all: false),
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Score'),
                ),
                OutlinedButton(
                  key: ValueKey('score-all-${m.table}-${m.group}'),
                  onPressed: _busy ? null : () => _score(all: true),
                  child: const Text('Score all still observed'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
            ],
            if (answer != null) ...[
              const SizedBox(height: 10),
              Text(
                'Call ${answer.callId}: ${answer.scored} scored in ${answer.millis} ms by run ${answer.runId}',
                style: const TextStyle(color: Aityx.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              _Predictions(predictions: answer.predictions, keys: m.seriesKey, horizon: m.horizon),
            ],
          ],
        ),
      ),
    );
  }
}

class _Predictions extends StatelessWidget {
  const _Predictions({required this.predictions, required this.keys, required this.horizon});
  final List<Prediction> predictions;
  final List<String> keys;
  final String? horizon;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(color: Aityx.muted, fontSize: 11, fontWeight: FontWeight.bold);
    const cell = TextStyle(fontSize: 12, color: Aityx.fg, fontFamily: 'monospace');
    return SizedBox(
      width: 560,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final k in keys) Text(k, style: head),
              const Text('predicted', style: head, textAlign: TextAlign.right),
              Text('last ${horizon ?? ''}', style: head, textAlign: TextAlign.right),
            ],
          ),
          for (final p in predictions)
            TableRow(
              children: [
                for (final k in keys) Text(p.series[k] ?? '', style: cell, overflow: TextOverflow.ellipsis),
                p.predicted == null
                    ? Text(p.note ?? '', style: cell.copyWith(color: Aityx.amber), textAlign: TextAlign.right)
                    : Text(p.predicted!.toStringAsFixed(1), style: cell, textAlign: TextAlign.right),
                Text(p.last == null ? '' : p.last!.toStringAsFixed(0), style: cell.copyWith(color: Aityx.muted), textAlign: TextAlign.right),
              ],
            ),
        ],
      ),
    );
  }
}

/// The latest calls, newest first.
class _Calls extends StatelessWidget {
  const _Calls({required this.calls});
  final List<InferenceCallInfo> calls;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('Calls', 'the latest, newest first'),
          const SizedBox(height: 8),
          if (calls.isEmpty) const Text('No call yet: Try it above.', style: TextStyle(color: Aityx.muted)),
          for (final c in calls)
            Padding(
              key: ValueKey('call-${c.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          c.calledAt == null ? '' : c.calledAt!.toLocal().toString().substring(0, 19),
                          style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 80),
                        child: Align(widthFactor: 1, alignment: Alignment.centerLeft, child: StatusChip(c.status)),
                      ),
                      Text('${c.name} · ${c.group}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      Text('run ${c.runId}', style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                      Text(
                        c.requested == 0 ? 'all still observed: ${c.scored} scored' : '${c.requested} asked, ${c.scored} scored',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text('${c.millis} ms', style: const TextStyle(fontSize: 12)),
                      if (c.caller != null) Text(c.caller!, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                    ],
                  ),
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 140, top: 2),
                      child: Text(c.error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
