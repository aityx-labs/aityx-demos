import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';
import 'card_title.dart';
import 'health_tab.dart' show ApiDownLine;
import 'hour_charts.dart';
import 'training_tab.dart' show StatTile, StatusChip, when;

/// The Inference tab, a dashboard of the calls to the models datyx
/// trained (`GET /api/inference`, the last 7 days): a row of headline
/// tiles; the hours, 24 or 168 of them, as charts (calls by model with
/// the failures, latency, series scored); one table of the models, each
/// with **Try it**, which scores series through the same accounted
/// endpoint (`POST /api/datasources/{id}/inference`); and a table of the
/// latest calls. What is shown is the API's; the tab asks and shows.
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
  bool _loading = false;

  /// The hours the charts cover: the last 24, or the 7 days' 168.
  int _hours = 24;

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
    setState(() => _loading = true);
    try {
      final account = await widget.api.inference(hours: _hours);
      if (mounted) {
        setState(() {
          _account = account;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tryIt(InferenceModel m) => showDialog<void>(
    context: context,
    builder: (_) => TryItDialog(api: widget.api, model: m, onCalled: _load),
  );

  @override
  Widget build(BuildContext context) {
    final a = _account;
    final shown = !widget.locked && _error == null && a != null;
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
                const SizedBox(height: 4),
                const Text(
                  'Each call to a trained model (POST /api/datasources/{id}/inference) is accounted for: '
                  'who asked, which model, how many series, how long, and whether it failed.',
                  style: TextStyle(color: Aityx.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (widget.locked)
                  const Text('Sign in to see the inference.', style: TextStyle(color: Aityx.muted))
                else if (_error != null)
                  Text(_error!, style: const TextStyle(color: Aityx.red))
                else if (a == null)
                  const Text('Loading…', style: TextStyle(color: Aityx.muted))
                else
                  _Kpis(account: a),
              ],
            ),
          ),
        ),
        if (shown) ...[
          // While asked again, the previous answer stays, dimmed: no jump.
          AnimatedOpacity(
            opacity: _loading ? 0.5 : 1,
            duration: const Duration(milliseconds: 150),
            child: _Hours(
              account: a,
              hours: _hours,
              onHours: (h) {
                setState(() => _hours = h);
                _load();
              },
            ),
          ),
          _Models(account: a, onTry: _tryIt),
          _Calls(calls: a.calls),
        ],
      ]),
    );
  }
}

/// Milliseconds as text: whole ones without decimals (on the web every
/// number is a double), others to a tenth; a dash for none.
String ms(num? v) => v == null ? '–' : '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)} ms';

/// A count as a headline: 1,284 below ten thousand, then 12.9K, 4.2M.
String compact(int v) {
  if (v < 10000) {
    final s = '$v';
    return s.length > 3 ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}' : s;
  }
  if (v < 1000000) return '${(v / 1000).toStringAsFixed(1)}K';
  return '${(v / 1000000).toStringAsFixed(1)}M';
}

/// How long ago [t] was, in the largest unit: just now, 5 min, 3 h, 2 d.
String ago(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// The share of failed calls, in percent: whole from 10, else to a tenth.
String failureRate(int failed, int calls) {
  if (calls == 0) return '–';
  final p = 100 * failed / calls;
  return '${p >= 10 || p == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(1)}%';
}

/// The headline tiles, one row of equal widths as the card allows.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.account});
  final InferenceAccount account;

  @override
  Widget build(BuildContext context) {
    final t = account.totals;
    final inUse = account.models.where((m) => m.stats.calls > 0).length;
    final tiles = [
      (const ValueKey('total-calls'), 'calls', compact(t.calls), 'in 7 days', null, null),
      (const ValueKey('total-last-hour'), 'last hour', compact(account.lastHour), 'calls', null, null),
      (const ValueKey('total-scored'), 'series scored', compact(t.scored), 'in 7 days', null, null),
      (const ValueKey('total-p50'), 'latency p50', ms(t.p50Millis), 'median, per call', null, null),
      (const ValueKey('total-p95'), 'latency p95', ms(t.p95Millis), '95th percentile', null, null),
      (
        const ValueKey('total-failure-rate'),
        'failure rate',
        failureRate(t.failed, t.calls),
        t.calls == 0 ? 'no call yet' : '${t.failed} of ${t.calls} calls',
        t.failed == 0 ? Aityx.green : Aityx.red,
        t.failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
      ),
      (const ValueKey('total-models'), 'models in use', '$inUse', 'of ${account.models.length} trained', null, null),
      (
        const ValueKey('total-last-call'),
        'last call',
        t.lastCalledAt == null ? 'never' : ago(t.lastCalledAt!),
        t.lastCalledAt == null ? 'none in 7 days' : when(t.lastCalledAt!),
        null,
        null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final perRow = ((box.maxWidth + gap) / (150 + gap)).floor().clamp(1, tiles.length);
        final width = (box.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (key, label, value, note, status, icon) in tiles)
              StatTile(key: key, label: label, value: value, note: note, status: status, icon: icon, width: width),
          ],
        );
      },
    );
  }
}

/// The hours as charts: the calls stacked by model with the failures,
/// then latency and series scored, side by side when there is room; the
/// range (24 hours or 7 days) in the title row, and the hours as a table.
class _Hours extends StatefulWidget {
  const _Hours({required this.account, required this.hours, required this.onHours});

  final InferenceAccount account;
  final int hours;
  final ValueChanged<int> onHours;

  @override
  State<_Hours> createState() => _HoursState();
}

class _HoursState extends State<_Hours> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final hours = a.perHour;
    final at = [for (final h in hours) h.hour];
    final models = chartModels(a);
    final period = a.hours > 24 ? 'the last 7 days' : 'the last 24 hours';
    final calls = modelSeries(models, hours, (b) => b.calls);
    final scored = modelSeries(models, hours, (b) => b.scored);
    final labels = {for (final m in models) m.key: m.label};
    final colored = {for (final m in paletteModels(models, hours)) m.key};
    // An hour's series by model, the "other models" named one by one.
    List<ReadoutRow> byModel(int i, List<ChartSeries> series, int Function(InferenceHourModel) measure) => [
      for (final s in series)
        if (s.label != otherModelsLabel && (s.values[i] ?? 0) > 0) ReadoutRow('${s.values[i]}', s.label, color: s.color),
      for (final b in hours[i].byModel)
        if (!colored.contains(modelKey(b.table, b.group, b.algorithm)) && measure(b) > 0)
          ReadoutRow(
            '${measure(b)}',
            labels[modelKey(b.table, b.group, b.algorithm)] ?? '${b.name} · ${b.group} · ${b.algorithm}',
            color: otherModelColor,
          ),
    ];
    final failed = [for (final h in hours) h.failed];
    final p50 = ChartSeries('p50', p50Color, [for (final h in hours) h.p50Millis]);
    final p95 = ChartSeries('p95', p95Color, [for (final h in hours) h.p95Millis]);
    final anyCall = hours.any((h) => h.calls > 0);
    final callScale = niceScale(hours.fold<int>(0, (m, h) => h.calls > m ? h.calls : m));
    final scoredScale = niceScale(hours.fold<int>(0, (m, h) => h.scored > m ? h.scored : m));
    final msScale = niceScale(hours.fold<int>(0, (m, h) => (h.p95Millis ?? h.p50Millis ?? 0) > m ? (h.p95Millis ?? h.p50Millis!) : m));
    final none = anyCall ? null : 'No call in $period';

    final callsChart = _Chart(
      title: 'Calls per hour',
      subtitle: 'stacked by model; a red dot: the hour\'s failed calls, on the same scale',
      legend: ChartLegend(
        chart: 'calls',
        entries: [
          for (final s in calls) LegendEntry(s.label, s.color, LegendMark.column),
          if (failed.any((f) => f > 0)) const LegendEntry('failed', failedColor, LegendMark.dot, icon: Icons.error_outline),
        ],
      ),
      chart: HourChart(
        key: const ValueKey('chart-calls'),
        name: 'calls',
        hours: at,
        empty: none,
        height: 200,
        painter: (hover) => HourColumnsPainter(
          hours: at,
          top: callScale.top,
          step: callScale.step,
          hover: hover,
          tick: compactCount,
          series: calls,
          failed: failed,
        ),
        readout: (i) => [
          ReadoutRow('${hours[i].calls}', 'calls'),
          ...byModel(i, calls, (b) => b.calls),
          if (hours[i].failed > 0) ReadoutRow('${hours[i].failed}', 'failed', color: failedColor),
        ],
      ),
    );
    final latencyChart = _Chart(
      title: 'Latency per hour',
      subtitle: 'milliseconds a call, the hour\'s median and 95th percentile',
      legend: const ChartLegend(
        chart: 'latency',
        entries: [
          LegendEntry('p50', p50Color, LegendMark.line),
          LegendEntry('p95', p95Color, LegendMark.line),
        ],
      ),
      chart: HourChart(
        key: const ValueKey('chart-latency'),
        name: 'latency',
        hours: at,
        empty: none,
        painter: (hover) => HourLinesPainter(
          hours: at,
          top: msScale.top,
          step: msScale.step,
          hover: hover,
          tick: compactCount,
          series: [p95, p50],
          unit: ' ms',
        ),
        readout: (i) => [
          if (hours[i].calls == 0) const ReadoutRow('–', 'no call'),
          if (hours[i].p95Millis != null) ReadoutRow(ms(hours[i].p95Millis), 'p95', color: p95Color),
          if (hours[i].p50Millis != null) ReadoutRow(ms(hours[i].p50Millis), 'p50', color: p50Color),
        ],
      ),
    );
    final scoredChart = _Chart(
      title: 'Series scored per hour',
      subtitle: 'stacked by model',
      legend: ChartLegend(
        chart: 'scored',
        entries: [for (final s in scored) LegendEntry(s.label, s.color, LegendMark.column)],
      ),
      chart: HourChart(
        key: const ValueKey('chart-scored'),
        name: 'scored',
        hours: at,
        empty: none,
        painter: (hover) => HourColumnsPainter(
          hours: at,
          top: scoredScale.top,
          step: scoredScale.step,
          hover: hover,
          tick: compactCount,
          series: scored,
        ),
        readout: (i) => [
          ReadoutRow('${hours[i].scored}', 'series scored'),
          ...byModel(i, scored, (b) => b.scored),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                CardTitle('Hour by hour', 'perHour, $period'),
                SegmentedButton<int>(
                  key: const ValueKey('inference-range'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 24, label: Text('24 h')),
                    ButtonSegment(value: 168, label: Text('7 d')),
                  ],
                  selected: {widget.hours},
                  onSelectionChanged: (s) => widget.onHours(s.first),
                ),
                IconButton(
                  key: const ValueKey('hours-table'),
                  tooltip: _table ? 'Show the charts' : 'Show the hours as a table',
                  onPressed: () => setState(() => _table = !_table),
                  icon: Icon(_table ? Icons.bar_chart : Icons.table_rows_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_table)
              _HoursTable(hours: hours, models: models, long: a.hours > 24)
            else ...[
              callsChart,
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: latencyChart),
                          const SizedBox(width: 24),
                          Expanded(child: scoredChart),
                        ],
                      )
                    : Column(children: [latencyChart, const SizedBox(height: 24), scoredChart]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A chart's title, what it plots, its legend and the plot.
class _Chart extends StatelessWidget {
  const _Chart({required this.title, required this.subtitle, required this.legend, required this.chart});

  final String title;
  final String subtitle;
  final Widget legend;
  final Widget chart;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(subtitle, style: const TextStyle(color: Aityx.muted, fontSize: 11)),
      const SizedBox(height: 8),
      legend,
      const SizedBox(height: 8),
      chart,
    ],
  );
}

/// The charts' numbers, as a table: the hours with a call, newest first.
class _HoursTable extends StatelessWidget {
  const _HoursTable({required this.hours, required this.models, required this.long});

  final List<InferenceHour> hours;
  final List<ChartModel> models;
  final bool long;

  @override
  Widget build(BuildContext context) {
    final called = hours.reversed.where((h) => h.calls > 0).toList();
    if (called.isEmpty) return const Text('No call in these hours.', style: TextStyle(color: Aityx.muted));
    final labels = {for (final m in models) m.key: m.label};
    return _Grid(
      minWidth: 820,
      columns: const [
        _Col('hour', 130),
        _Col('calls', 60, right: true),
        _Col('failed', 60, right: true),
        _Col('scored', 70, right: true),
        _Col('p50', 80, right: true),
        _Col('p95', 80, right: true),
        _Col('by model', 0),
      ],
      rows: [
        for (final h in called)
          _GridRow(
            key: ValueKey('hour-row-${h.hour.toIso8601String()}'),
            failed: h.failed > 0,
            cells: [
              _mono('${hourLabel(h.hour, long: true)}–${hourLabel(h.hour.add(const Duration(hours: 1)), long: false)}'),
              _num('${h.calls}'),
              _num('${h.failed}', color: h.failed > 0 ? Aityx.red : Aityx.muted),
              _num('${h.scored}'),
              _num(ms(h.p50Millis)),
              _num(ms(h.p95Millis)),
              Text(
                h.byModel.map((b) => '${labels[modelKey(b.table, b.group, b.algorithm)] ?? b.name}: ${b.calls}').join(', '),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
      ],
    );
  }
}

/// Every model (a group's algorithm), one row each: **Try it** first, its
/// chart color, table and group, algorithm, which run answers and when it
/// was trained, its calls in 7 days (failed, p50 / p95, the last).
class _Models extends StatelessWidget {
  const _Models({required this.account, required this.onTry});

  final InferenceAccount account;
  final ValueChanged<InferenceModel> onTry;

  @override
  Widget build(BuildContext context) {
    final colors = modelColors(chartModels(account), account.perHour);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardTitle('Models', 'the latest model of each group\'s algorithm, its calls in 7 days'),
            const SizedBox(height: 12),
            if (account.models.isEmpty)
              const Text(
                'No model yet: the Training tab trains the groups tagged for XGBoost or DeepAR.',
                style: TextStyle(color: Aityx.amber),
              )
            else
              _Grid(
                minWidth: 960,
                columns: const [
                  // Try it first: in sight however narrow the card, the rest scrolled sideways.
                  _Col('', 44),
                  _Col('model', 0),
                  _Col('algorithm', 90),
                  _Col('trained', 190),
                  _Col('calls', 64, right: true),
                  _Col('failed', 64, right: true),
                  _Col('p50 / p95', 120, right: true),
                  _Col('last called', 110, right: true),
                ],
                rows: [
                  for (final m in account.models)
                    _GridRow(
                      key: ValueKey('model-${m.table}-${m.group}-${m.algorithm}'),
                      cells: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            key: ValueKey('try-${m.table}-${m.group}-${m.algorithm}'),
                            tooltip: 'Try it: score series with ${m.algorithm} · ${m.group}',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onTry(m),
                            icon: const Icon(Icons.bolt, size: 20, color: Aityx.orangeLight),
                          ),
                        ),
                        Row(
                          children: [
                            // Its color in the charts; a hollow square: not called in their hours.
                            Container(
                              key: ValueKey('swatch-${m.table}-${m.group}-${m.algorithm}'),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colors[modelKey(m.table, m.group, m.algorithm)],
                                border: colors.containsKey(modelKey(m.table, m.group, m.algorithm))
                                    ? null
                                    : Border.all(color: Aityx.muted),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${m.name} · ${m.group}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                  Text(
                                    m.source.isEmpty ? m.table : '${m.source} · ${m.table}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Text(m.algorithm, style: const TextStyle(fontSize: 12)),
                        Text(
                          'run ${m.runId ?? '?'}${m.trainedAt == null ? '' : ' · ${when(m.trainedAt!)}'}',
                          style: const TextStyle(fontSize: 12, color: Aityx.muted),
                        ),
                        _num('${m.stats.calls}'),
                        _failed(m.stats.failed),
                        _num('${ms(m.stats.p50Millis)} / ${ms(m.stats.p95Millis)}'),
                        _num(m.stats.lastCalledAt == null ? 'never' : ago(m.stats.lastCalledAt!), color: Aityx.muted),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The latest calls, newest first, one row each; a failed one tinted red,
/// its error under it.
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
          CardTitle('Calls', 'the latest ${calls.length}, newest first'),
          const SizedBox(height: 12),
          if (calls.isEmpty)
            const Text('No call yet: try a model above.', style: TextStyle(color: Aityx.muted))
          else
            _Grid(
              minWidth: 900,
              columns: const [
                _Col('when', 150),
                _Col('status', 120),
                _Col('model', 0),
                _Col('series', 190),
                _Col('ms', 64, right: true),
                _Col('caller', 190),
              ],
              rows: [
                for (final c in calls)
                  _GridRow(
                    key: ValueKey('call-${c.id}'),
                    failed: c.status == 'failed',
                    below: c.error,
                    cells: [
                      _mono(c.calledAt == null ? '' : c.calledAt!.toLocal().toString().substring(0, 19)),
                      Align(alignment: Alignment.centerLeft, child: StatusChip(c.status)),
                      Text(
                        '${c.name} · ${c.group} · ${c.algorithm} · run ${c.runId}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        c.requested == 0 ? 'all still observed: ${c.scored} scored' : '${c.requested} asked, ${c.scored} scored',
                        style: const TextStyle(fontSize: 12),
                      ),
                      _num('${c.millis}'),
                      Text(c.caller ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                    ],
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

Widget _num(String s, {Color color = Aityx.fg}) => Text(
  s,
  textAlign: TextAlign.right,
  style: TextStyle(fontSize: 12, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
);

Widget _mono(String s) => Text(s, style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12));

Widget _failed(int n) => Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    if (n > 0) ...[const Icon(Icons.error_outline, size: 14, color: Aityx.red), const SizedBox(width: 4)],
    _num('$n', color: n > 0 ? Aityx.red : Aityx.muted),
  ],
);

/// A column of a [_Grid]: its heading and width (0: the rest of the row).
class _Col {
  const _Col(this.label, this.width, {this.right = false});
  final String label;
  final double width;
  final bool right;
}

class _GridRow {
  const _GridRow({required this.key, required this.cells, this.failed = false, this.below});
  final Key key;
  final List<Widget> cells;

  /// A failure: the row tinted red, [below] (its error) under it.
  final bool failed;
  final String? below;
}

/// A compact table: a heading row, then hairline-separated rows; as wide
/// as the card, scrolled sideways below [minWidth].
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.rows, required this.minWidth});

  final List<_Col> columns;
  final List<_GridRow> rows;
  final double minWidth;

  Widget _line(List<Widget> cells) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (final (i, c) in columns.indexed)
        if (c.width == 0)
          Expanded(
            child: Padding(padding: const EdgeInsets.only(right: 12), child: cells[i]),
          )
        else
          SizedBox(
            width: c.width,
            child: Padding(
              padding: EdgeInsets.only(right: c.right ? 20 : 12, left: c.right ? 12 : 0),
              child: cells[i],
            ),
          ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth < minWidth ? minWidth : box.maxWidth;
      const head = TextStyle(color: Aityx.muted, fontSize: 11, fontWeight: FontWeight.bold);
      final table = SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _line([
                for (final c in columns) Text(c.label, style: head, textAlign: c.right ? TextAlign.right : TextAlign.left),
              ]),
            ),
            for (final r in rows)
              Container(
                key: r.key,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: r.failed ? Aityx.red.withValues(alpha: 0.08) : null,
                  border: Border(
                    top: const BorderSide(color: Aityx.border),
                    left: BorderSide(color: r.failed ? Aityx.red : Colors.transparent, width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(r.cells),
                    if (r.below != null)
                      Padding(
                        padding: EdgeInsets.only(top: 2, left: columns.first.width),
                        child: Text(r.below!, style: const TextStyle(color: Aityx.red, fontSize: 12)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
      return box.maxWidth < minWidth
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)
          : table;
    },
  );
}

/// **Try it** on a model, in a dialog: a field per key column and
/// **Score** (on once the whole key is typed), or **Score all still
/// observed**, each a real call to `POST /api/datasources/{id}/inference`,
/// accounted for like any other: the answer, its predictions, and the
/// account asked again.
class TryItDialog extends StatefulWidget {
  const TryItDialog({super.key, required this.api, required this.model, required this.onCalled});

  final DatyxApi api;
  final InferenceModel model;
  final Future<void> Function() onCalled;

  @override
  State<TryItDialog> createState() => _TryItDialogState();
}

class _TryItDialogState extends State<TryItDialog> {
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
        algorithm: m.algorithm,
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
    final answer = _answer;
    final keyed = _key.values.every((c) => c.text.trim().isNotEmpty);
    return AlertDialog(
      key: const ValueKey('try-dialog'),
      title: Row(
        children: [
          const Icon(Icons.bolt, size: 20, color: Aityx.orangeLight),
          const SizedBox(width: 8),
          Expanded(child: Text('Try it: ${m.algorithm} · ${m.group}')),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m.name} · ${m.source}',
                style: const TextStyle(color: Aityx.muted, fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Model: run ${m.runId ?? '?'}${m.trainedAt == null ? '' : ', trained ${when(m.trainedAt!)}'}. '
                'Predicts ${m.target ?? 'the Target'} over the next ${m.horizon ?? '?'}, per '
                '${m.seriesKey.isEmpty ? 'table' : m.seriesKey.join(' + ')}.',
                style: const TextStyle(color: Aityx.fg),
              ),
              const SizedBox(height: 16),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
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
                const SizedBox(height: 12),
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
      ),
      actions: [
        TextButton(
          key: const ValueKey('try-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
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
    return Table(
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
    );
  }
}
