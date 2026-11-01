import 'dart:async';

import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'card_title.dart';
import 'health_tab.dart' show ApiDownLine;

/// The retraining intervals offered; any other span can be typed.
const retrainChoices = ['1h', '6h', '1D', '1W', 'never'];

/// The Training tab: each group tagged for XGBoost (`GET /api/training`),
/// how often it is trained again (its table's timeSeriesRetrain, set here
/// or in OpenMetadata), when next (a disabled group: never, until it is
/// enabled on the Catalog tab), **Train now**, and what its latest
/// success found: its test metrics against the naive forecast, the
/// features that weighed most, and the highest scores; then the runs of
/// them all, newest first. While a run is queued or running it asks again
/// every [busyEvery]. What is shown is the API's; the tab asks and shows.
class TrainingTab extends StatefulWidget {
  const TrainingTab({
    super.key,
    required this.api,
    required this.locked,
    required this.statusError,
    this.busyEvery = const Duration(seconds: 3),
  });

  final DatyxApi api;
  final bool locked;
  final String? statusError;
  final Duration busyEvery;

  @override
  State<TrainingTab> createState() => _TrainingTabState();
}

class _TrainingTabState extends State<TrainingTab> {
  TrainingOverview? _overview;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.locked) _load();
  }

  @override
  void didUpdateWidget(TrainingTab old) {
    super.didUpdateWidget(old);
    if (old.locked && !widget.locked) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    try {
      final overview = await widget.api.training();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _error = null;
      });
      if (overview.busy) _timer = Timer(widget.busyEvery, _load);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.statusError != null) ApiDownLine(widget.statusError!),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: CardTitle('Training', 'GET /api/training')),
                    IconButton(
                      key: const ValueKey('training-reload'),
                      tooltip: 'Ask again',
                      onPressed: widget.locked ? null : _load,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'datyx trains each group tagged for XGBoost on the Catalog tab: '
                  'when the API starts, if it never was, then again as often as '
                  'its table says (timeSeriesRetrain in OpenMetadata, 1D when '
                  'not set), when asked, and when the group is enabled (its '
                  'Disabled tag removed in OpenMetadata). A disabled group isn\'t '
                  'trained. Each model scores its series: the Target summed over '
                  'the horizon ahead.',
                  style: TextStyle(color: Aityx.muted),
                ),
                if (widget.locked) ...[
                  const SizedBox(height: 12),
                  const Text('Sign in to see the training.', style: TextStyle(color: Aityx.muted)),
                ] else if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Aityx.red)),
                ] else if (overview == null) ...[
                  const SizedBox(height: 12),
                  const Text('Loading…', style: TextStyle(color: Aityx.muted)),
                ] else if (overview.models.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'No group is tagged for XGBoost yet: on the Catalog tab, tag a '
                    'table\'s group and pick XGBoost, with a horizon.',
                    style: TextStyle(color: Aityx.amber),
                  ),
                ],
                if (overview != null)
                  for (final e in overview.errors)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(e, style: const TextStyle(color: Aityx.amber, fontSize: 12)),
                    ),
              ],
            ),
          ),
        ),
        if (!widget.locked && overview != null) ...[
          for (final m in overview.models)
            ModelCard(key: ValueKey('model-${m.table}-${m.group}'), api: widget.api, model: m, onChanged: _load),
          _Activity(runs: overview.runs),
        ],
      ],
    );
  }
}

/// One group tagged for XGBoost: its schedule, Train now, and its latest success.
class ModelCard extends StatefulWidget {
  const ModelCard({super.key, required this.api, required this.model, required this.onChanged});

  final DatyxApi api;
  final TrainingModel model;
  final Future<void> Function() onChanged;

  @override
  State<ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<ModelCard> {
  late final TextEditingController _retrain = TextEditingController(text: widget.model.retrain ?? '');
  TrainingRunDetail? _detail;
  String? _error;
  String? _note;
  bool _busy = false;

  TrainingModel get m => widget.model;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void didUpdateWidget(ModelCard old) {
    super.didUpdateWidget(old);
    if (old.model.lastSucceeded?.id != m.lastSucceeded?.id) _loadDetail();
    if (old.model.retrain != m.retrain) _retrain.text = m.retrain ?? '';
  }

  @override
  void dispose() {
    _retrain.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    final run = m.lastSucceeded;
    if (run == null) {
      setState(() => _detail = null);
      return;
    }
    try {
      final detail = await widget.api.trainingRun(run.id);
      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _act(Future<void> Function() action, String note) async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      await action();
      _note = note;
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trainNow() => _act(() => widget.api.trainNow(m.sourceId, m.table, m.group), 'Queued: training now.');

  Future<void> _saveRetrain() {
    final value = _retrain.text.trim();
    return _act(
      () => widget.api.setRetrain(m.sourceId, m.table, value.isEmpty ? null : value),
      'Saved in OpenMetadata: retrain ${value.isEmpty ? 'every 1D (the default)' : (value == 'never' ? 'never' : 'every $value')}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = m.latest;
    final succeeded = m.lastSucceeded;
    final active = latest?.active ?? false;
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
                const Icon(Icons.account_tree_outlined, size: 20, color: Aityx.orangeLight),
                Text('${m.algorithm} · ${m.group}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '${m.qualifiedName} · ${m.source}',
                  style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
                ),
                if (latest != null) StatusChip(latest.status),
                if (!m.ready) const StatusChip('not ready'),
                if (!m.enabled)
                  Tooltip(
                    message: 'The table has ${disabledTag(m.group)} in OpenMetadata: datyx doesn\'t train the group. '
                        'Enable it on the Catalog tab.',
                    child: const StatusChip('disabled'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Scores ${m.target ?? '?'} summed over the next ${m.horizon ?? '?'}, per '
              '${m.seriesKey.isEmpty ? 'table' : m.seriesKey.join(' + ')}, from steps of ${m.frequency ?? '?'}.',
              style: const TextStyle(color: Aityx.fg),
            ),
            for (final p in m.problems)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $p', style: const TextStyle(color: Aityx.amber, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text('Retrain every', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: ValueKey('retrain-${m.table}-${m.group}'),
                    controller: _retrain,
                    decoration: const InputDecoration(isDense: true, hintText: '1D'),
                  ),
                ),
                for (final r in retrainChoices)
                  ActionChip(
                    key: ValueKey('retrain-$r'),
                    label: Text(r),
                    onPressed: () => setState(() => _retrain.text = r),
                  ),
                OutlinedButton(
                  key: ValueKey('save-retrain-${m.table}-${m.group}'),
                  onPressed: _busy ? null : _saveRetrain,
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: ValueKey('train-now-${m.table}-${m.group}'),
                  onPressed: _busy || active || !m.ready || !m.enabled ? null : _trainNow,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Train now'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Now every ${m.retrainEvery}${m.retrain == null ? ' (the default)' : ''}, the table\'s '
              'timeSeriesRetrain in OpenMetadata, for all its groups. ${_next()}',
              style: const TextStyle(color: Aityx.muted, fontSize: 12),
            ),
            if (_note != null) ...[
              const SizedBox(height: 6),
              Text(_note!, style: const TextStyle(color: Aityx.green, fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
            ],
            if (latest != null && latest.triggerNote != null) ...[
              const SizedBox(height: 6),
              Text(
                'The latest run (${latest.trigger}): ${latest.triggerNote}',
                style: const TextStyle(color: Aityx.muted, fontSize: 12),
              ),
            ],
            if (latest != null && latest.status == 'failed' && latest.error != null) ...[
              const SizedBox(height: 8),
              Text('The latest run failed: ${latest.error}', style: const TextStyle(color: Aityx.red, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            if (succeeded == null)
              Text(
                active ? 'Training for the first time…' : 'Not trained yet.',
                style: const TextStyle(color: Aityx.muted),
              )
            else
              _Results(model: m, run: succeeded, detail: _detail),
          ],
        ),
      ),
    );
  }

  String _next() {
    final latest = m.latest;
    if (latest != null && latest.active) return 'A run is ${latest.status}.';
    if (!m.enabled) {
      return 'Disabled: not trained until enabled on the Catalog tab, which removes its ${disabledTag(m.group)} tag.';
    }
    final next = m.nextAt;
    if (next == null) return m.ready ? 'Not trained again (never).' : 'Not trained until the group is ready.';
    final wait = next.difference(DateTime.now());
    return wait.isNegative ? 'Due now: the trainer checks every minute.' : 'Next in ${span(wait)}, at ${when(next)}.';
  }
}

/// A duration in its largest whole unit: 3 d, 5 h, 12 min, 40 s.
String span(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

String when(DateTime t) => t.toLocal().toString().substring(0, 16);

/// What the latest success found: tiles of its test metrics, its features' weights, and its highest scores.
class _Results extends StatelessWidget {
  const _Results({required this.model, required this.run, required this.detail});

  final TrainingModel model;
  final TrainingRunInfo run;
  final TrainingRunDetail? detail;

  @override
  Widget build(BuildContext context) {
    final test = run.test ?? const TestMetrics();
    final unit = model.target ?? '';
    final better = test.improvement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Latest model: run ${run.id}, trained ${run.finishedAt == null ? '' : when(run.finishedAt!)} '
          '(${run.trigger}${run.seconds == null ? '' : ', ${run.seconds!.toStringAsFixed(1)} s'}), '
          'tested on ${test.examples} examples it never saw',
          style: const TextStyle(color: Aityx.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatTile(
              key: const ValueKey('tile-mae'),
              label: 'mean error (MAE)',
              value: test.mae.toStringAsFixed(2),
              note: '$unit over ${model.horizon ?? '?'}',
            ),
            StatTile(
              key: const ValueKey('tile-naive'),
              label: 'naive forecast\'s error',
              value: test.naiveMae.toStringAsFixed(2),
              note: 'the next ${model.horizon ?? '?'} like the last',
            ),
            StatTile(
              key: const ValueKey('tile-better'),
              label: 'better than naive',
              value: '${(better * 100).toStringAsFixed(0)}%',
              note: 'of its error saved',
              status: better > 0 ? Aityx.green : Aityx.amber,
              icon: better > 0 ? Icons.trending_down : Icons.trending_flat,
            ),
            StatTile(
              key: const ValueKey('tile-mean'),
              label: 'actual, on average',
              value: test.meanLabel.toStringAsFixed(2),
              note: '$unit over ${model.horizon ?? '?'}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (detail == null)
          const Text('Loading what it found…', style: TextStyle(color: Aityx.muted))
        else
          Wrap(
            spacing: 32,
            runSpacing: 16,
            children: [
              SizedBox(width: 460, child: FeatureWeights(weights: detail!.importance)),
              SizedBox(
                width: 460,
                child: TopScores(scores: detail!.scores, model: model),
              ),
            ],
          ),
      ],
    );
  }
}

/// A headline number: its value large, what it is above, and a note below.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, required this.note, this.status, this.icon});

  final String label;
  final String value;
  final String note;

  /// A status color, with [icon], for a value that says good or not; never alone.
  final Color? status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Aityx.bg0,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Aityx.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: status), const SizedBox(width: 6)],
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Aityx.fg0)),
          ],
        ),
        Text(note, style: const TextStyle(color: Aityx.muted, fontSize: 11)),
      ],
    ),
  );
}

/// The features that weighed most, as bars of their share of the model's
/// SHAP weight, one hue, the share in text beside each; each row's tooltip
/// says it in words.
class FeatureWeights extends StatelessWidget {
  const FeatureWeights({super.key, required this.weights});

  final List<FeatureWeight> weights;

  @override
  Widget build(BuildContext context) {
    final top = weights.isEmpty ? 1.0 : weights.map((w) => w.share).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What weighed most', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text(
          'each feature\'s share of how much it moved the test predictions (mean |SHAP|)',
          style: TextStyle(color: Aityx.muted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        for (final w in weights)
          Tooltip(
            message: '${w.feature}: ${(w.share * 100).toStringAsFixed(1)}% of the weight',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 190,
                    child: Text(
                      w.feature,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Aityx.fg),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          key: ValueKey('weight-${w.feature}'),
                          width: (box.maxWidth * w.share / top).clamp(2.0, box.maxWidth),
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Aityx.orange,
                            borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(w.share * 100).toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Aityx.muted),
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

/// The series still observed with the highest scores: their key, the
/// prediction for the horizon ahead and the Target over the last one.
class TopScores extends StatelessWidget {
  const TopScores({super.key, required this.scores, required this.model, this.shown = 10});

  final List<SeriesScore> scores;
  final TrainingModel model;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final keys = scores.isEmpty ? model.seriesKey : scores.first.series.keys.toList();
    const head = TextStyle(color: Aityx.muted, fontSize: 11, fontWeight: FontWeight.bold);
    const cell = TextStyle(fontSize: 12, color: Aityx.fg, fontFamily: 'monospace');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Highest scores now', style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
          '${model.target ?? 'the Target'} predicted for the next ${model.horizon ?? '?'}, of the series still observed',
          style: const TextStyle(color: Aityx.muted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                for (final k in keys) Text(k, style: head),
                const Text('predicted', style: head, textAlign: TextAlign.right),
                Text('last ${model.horizon ?? ''}', style: head, textAlign: TextAlign.right),
              ],
            ),
            for (final s in scores.take(shown))
              TableRow(
                children: [
                  for (final k in keys) Text(s.series[k] ?? '', style: cell, overflow: TextOverflow.ellipsis),
                  Text(s.predicted.toStringAsFixed(1), style: cell, textAlign: TextAlign.right),
                  Text(s.last.toStringAsFixed(0), style: cell.copyWith(color: Aityx.muted), textAlign: TextAlign.right),
                ],
              ),
          ],
        ),
        if (scores.isEmpty) const Text('No series is still observed.', style: TextStyle(color: Aityx.muted)),
      ],
    );
  }
}

/// A run's or a call's status as an icon and a word, in a status color:
/// succeeded and ok green, queued and running amber, failed red, not ready
/// amber; a disabled group's in gray.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      'succeeded' || 'ok' => (Aityx.green, Icons.check_circle_outline),
      'failed' => (Aityx.red, Icons.error_outline),
      'running' => (Aityx.amber, Icons.sync),
      'queued' => (Aityx.amber, Icons.schedule),
      'disabled' => (Aityx.muted, Icons.pause_circle_outline),
      _ => (Aityx.amber, Icons.warning_amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(status, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

/// Every model's runs, the newest first: when, which, why (with the API's
/// note, for a group enabled), how it went, how long, and its error against
/// the naive one's.
class _Activity extends StatelessWidget {
  const _Activity({required this.runs});
  final List<TrainingRunInfo> runs;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardTitle('Activity', 'the latest runs, newest first'),
          const SizedBox(height: 8),
          if (runs.isEmpty) const Text('No run yet.', style: TextStyle(color: Aityx.muted)),
          for (final r in runs)
            Padding(
              key: ValueKey('run-${r.id}'),
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
                          r.queuedAt == null ? '' : when(r.queuedAt!),
                          style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 112),
                        child: Align(widthFactor: 1, alignment: Alignment.centerLeft, child: StatusChip(r.status)),
                      ),
                      Text('${r.name} · ${r.group}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      Text(r.trigger, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                      if (r.seconds != null)
                        Text('${r.seconds!.toStringAsFixed(1)} s', style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                      if (r.test != null)
                        Text(
                          'MAE ${r.test!.mae.toStringAsFixed(2)} vs naive ${r.test!.naiveMae.toStringAsFixed(2)}, '
                          '${r.examples ?? 0} examples',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                  if (r.triggerNote != null)
                    Padding(
                      key: ValueKey('run-note-${r.id}'),
                      padding: const EdgeInsets.only(left: 260, top: 2),
                      child: Text(r.triggerNote!, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                    ),
                  if (r.error != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 260, top: 2),
                      child: Text(r.error!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
