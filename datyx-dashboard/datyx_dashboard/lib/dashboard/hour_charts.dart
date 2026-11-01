import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/datyx_api.dart';
import '../theme.dart';

/// The models' colors in the charts, in this order: blue, aqua, yellow,
/// steps for the dark card checked for color blindness, every pair and
/// against the failures' red. A model called past them is gray, "other
/// models", which the readout names one by one.
const modelPalette = [Color(0xFF3987E5), Color(0xFF199E70), Color(0xFFC98500)];
const otherModelColor = Color(0xFF8B8794);
const otherModelsLabel = 'other models';

/// Latency's two lines: one hue, the median the brand orange, the 95th
/// percentile a lighter step of it.
const p50Color = Aityx.orange;
const p95Color = Color(0xFFF4A68C);

/// Failures: the status red, as dots, never a model's color.
const failedColor = Aityx.red;

/// A model as the charts know it: a group's algorithm, of a table (its FQN).
class ChartModel {
  const ChartModel(this.table, this.name, this.group, this.algorithm);

  final String table;
  final String name;
  final String group;
  final String algorithm;

  String get key => modelKey(table, group, algorithm);
  String get label => '$name · $group · $algorithm';
}

String modelKey(String table, String group, String algorithm) => '$table|$group|$algorithm';

/// The models of an account, by name (table, group, algorithm): those
/// with a model, and any the hours' calls name.
List<ChartModel> chartModels(InferenceAccount a) {
  final byKey = <String, ChartModel>{};
  for (final m in a.models) {
    byKey.putIfAbsent(modelKey(m.table, m.group, m.algorithm), () => ChartModel(m.table, m.name, m.group, m.algorithm));
  }
  for (final h in a.perHour) {
    for (final b in h.byModel) {
      byKey.putIfAbsent(modelKey(b.table, b.group, b.algorithm), () => ChartModel(b.table, b.name, b.group, b.algorithm));
    }
  }
  int by(ChartModel a, ChartModel b) => [
    a.name.compareTo(b.name),
    a.group.compareTo(b.group),
    a.algorithm.compareTo(b.algorithm),
    a.table.compareTo(b.table),
  ].firstWhere((c) => c != 0, orElse: () => 0);
  return byKey.values.toList()..sort(by);
}

/// The models the charts give a color of the palette: those called in
/// [hours], the busiest [modelPalette]'s length of them, in [models]'
/// order (by name), so each keeps its color while the models called stay
/// the same, whatever is trained or sorts before it uncalled.
List<ChartModel> paletteModels(List<ChartModel> models, List<InferenceHour> hours) {
  final calls = modelCalls(hours);
  final order = {for (final (i, m) in models.indexed) m.key: i};
  final busiest = models.where((m) => (calls[m.key] ?? 0) > 0).toList()
    ..sort((a, b) {
      final c = calls[b.key]!.compareTo(calls[a.key]!);
      return c != 0 ? c : order[a.key]!.compareTo(order[b.key]!);
    });
  final colored = busiest.take(modelPalette.length).map((m) => m.key).toSet();
  return models.where((m) => colored.contains(m.key)).toList();
}

/// Each model's calls in [hours], by its key.
Map<String, int> modelCalls(List<InferenceHour> hours) {
  final calls = <String, int>{};
  for (final h in hours) {
    for (final b in h.byModel) {
      final key = modelKey(b.table, b.group, b.algorithm);
      calls[key] = (calls[key] ?? 0) + b.calls;
    }
  }
  return calls;
}

/// Each model's color in the charts, by its key: the palette's for
/// [paletteModels], gray for the others called ("other models"), none for
/// a model not called in [hours] (it is in no chart).
Map<String, Color> modelColors(List<ChartModel> models, List<InferenceHour> hours) {
  final calls = modelCalls(hours);
  final palette = paletteModels(models, hours);
  return {
    for (final m in models)
      if ((calls[m.key] ?? 0) > 0) m.key: otherModelColor,
    for (final (i, m) in palette.indexed) m.key: modelPalette[i],
  };
}

/// A series of an hourly chart: what it is, its color and a value per hour
/// (null: none that hour, a gap in a line).
class ChartSeries {
  const ChartSeries(this.label, this.color, this.values);

  final String label;
  final Color color;
  final List<num?> values;

  bool get any => values.any((v) => v != null && v != 0);
}

/// A measure of the hours stacked by model: a series per model of
/// [paletteModels], the rest summed as "other models"; only those with any.
List<ChartSeries> modelSeries(List<ChartModel> models, List<InferenceHour> hours, int Function(InferenceHourModel) measure) {
  final shown = paletteModels(models, hours);
  final index = {for (final (i, m) in shown.indexed) m.key: i};
  final values = [for (final _ in shown) List<num?>.filled(hours.length, 0)];
  final other = List<num?>.filled(hours.length, 0);
  for (final (i, h) in hours.indexed) {
    for (final b in h.byModel) {
      final at = index[modelKey(b.table, b.group, b.algorithm)];
      final row = at == null ? other : values[at];
      row[i] = row[i]! + measure(b);
    }
  }
  return [
    for (final (i, m) in shown.indexed) ChartSeries(m.label, modelPalette[i], values[i]),
    ChartSeries(otherModelsLabel, otherModelColor, other),
  ].where((s) => s.any).toList();
}

/// An hour as the axis says it: `14:00`, with the date over more than a day (`10-27 14:00`).
String hourLabel(DateTime t, {required bool long}) {
  final l = t.toLocal().toString();
  return long ? '${l.substring(5, 10)} ${l.substring(11, 16)}' : l.substring(11, 16);
}

/// A count as an axis tick: 0, 5, 1.5K.
String compactCount(num v) {
  if (v.abs() < 1000) return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  final k = v / 1000;
  return '${k == k.roundToDouble() ? k.round() : k.toStringAsFixed(1)}K';
}

/// The y scale of [max]: a clean step (1, 2 or 5 times a power of ten,
/// at least [minStep]) and the top, a whole number of steps, about four.
({double step, double top}) niceScale(num max, {double minStep = 1}) {
  if (max <= 0) return (step: minStep, top: minStep * 4);
  final raw = max / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final step = math.max(minStep, (norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10))) * mag);
  return (step: step, top: step * (max / step).ceil());
}

/// What the readout says of a series at an hour: its value, then what it is.
class ReadoutRow {
  const ReadoutRow(this.value, this.label, {this.color});
  final String value;
  final String label;

  /// The series' color as a short line key; none for a total.
  final Color? color;
}

/// The legend of a chart, above it: a swatch shaped as the mark (a square
/// for columns, a line for lines, a dot for failures) and the name, in text ink.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.chart, required this.entries});

  final String chart;
  final List<LegendEntry> entries;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (final e in entries)
        Row(
          key: ValueKey('legend-$chart-${e.label}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            switch (e.mark) {
              LegendMark.column => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: e.color, borderRadius: BorderRadius.circular(2)),
              ),
              LegendMark.line => Container(width: 14, height: 2, color: e.color),
              LegendMark.dot => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
              ),
            },
            const SizedBox(width: 6),
            if (e.icon != null) ...[Icon(e.icon, size: 12, color: e.color), const SizedBox(width: 3)],
            // A long name wraps on a narrow card.
            Flexible(child: Text(e.label, style: const TextStyle(color: Aityx.muted, fontSize: 12))),
          ],
        ),
    ],
  );
}

enum LegendMark { column, line, dot }

class LegendEntry {
  const LegendEntry(this.label, this.color, this.mark, {this.icon});
  final String label;
  final Color color;
  final LegendMark mark;
  final IconData? icon;
}

/// A chart over the hours: the plot its [painter] draws (one y axis from
/// zero, the hours along x), a crosshair that follows the pointer (or a
/// tap) to the nearest hour, and a readout of every series at that hour.
/// With nothing to plot, [empty] says so over the empty axes.
class HourChart extends StatefulWidget {
  const HourChart({
    super.key,
    required this.name,
    required this.hours,
    required this.painter,
    required this.readout,
    this.empty,
    this.height = 180,
  });

  final String name;
  final List<DateTime> hours;
  final HourPainter Function(int? hover) painter;
  final List<ReadoutRow> Function(int hour) readout;
  final String? empty;

  /// The plot's height, its x axis's labels included.
  final double height;

  @override
  State<HourChart> createState() => _HourChartState();
}

class _HourChartState extends State<HourChart> {
  int? _hover;

  void _point(Offset at, double width) {
    final p = widget.painter(null);
    final plot = width - p.left - p.right;
    final n = widget.hours.length;
    if (n == 0 || plot <= 0) return;
    final i = ((at.dx - p.left) / plot * n).floor().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth;
      final painter = widget.painter(_hover);
      final n = widget.hours.length;
      final long = n > 24;
      final hover = _hover != null && _hover! < n ? _hover : null;
      Widget? readout;
      if (hover != null) {
        final plot = width - painter.left - painter.right;
        final x = painter.left + (hover + 0.5) * plot / n;
        final from = widget.hours[hover];
        final rows = widget.readout(hover);
        readout = Positioned(
          top: 0,
          left: x < width / 2 ? x + 10 : null,
          right: x < width / 2 ? null : width - x + 10,
          child: IgnorePointer(
            child: Container(
              key: ValueKey('readout-${widget.name}'),
              // On the side of the crosshair with more room, and no wider than it.
              constraints: BoxConstraints(maxWidth: math.max(120.0, (x < width / 2 ? width - x : x) - 10)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Aityx.bg2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Aityx.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${hourLabel(from, long: long)}–${hourLabel(from.add(const Duration(hours: 1)), long: false)}',
                    style: const TextStyle(color: Aityx.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 14, child: r.color == null ? null : Container(height: 2, color: r.color)),
                          const SizedBox(width: 6),
                          Text(
                            r.value,
                            style: const TextStyle(
                              color: Aityx.fg0,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              r.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Aityx.muted, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
      return MouseRegion(
        onHover: (e) => _point(e.localPosition, width),
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          onTapDown: (e) => _point(e.localPosition, width),
          onHorizontalDragUpdate: (e) => _point(e.localPosition, width),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(key: ValueKey('plot-${widget.name}'), painter: painter),
                ),
                if (widget.empty != null)
                  Positioned.fill(
                    left: painter.left,
                    bottom: painter.bottom,
                    child: Center(
                      child: Text(widget.empty!, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
                    ),
                  ),
                ?readout,
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// What the hourly charts share: the plot's insets, the y ticks (hairline
/// gridlines one step off the card, the baseline a step more), the hours'
/// labels, and the crosshair.
abstract class HourPainter extends CustomPainter {
  HourPainter({required this.hours, required this.top, required this.step, required this.hover, required this.tick});

  final List<DateTime> hours;
  final double top;
  final double step;
  final int? hover;
  final String Function(num) tick;

  double get left => 44;
  double get right => 8;
  double get bottom => 20;
  double get topInset => 8;

  static const _axis = TextStyle(color: Aityx.muted, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]);

  Rect plotOf(Size size) => Rect.fromLTRB(left, topInset, size.width - right, size.height - bottom);

  double y(Rect plot, num v) => plot.bottom - (v / top) * plot.height;

  double x(Rect plot, int i) => plot.left + (i + 0.5) * plot.width / hours.length;

  void text(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.left, TextStyle style = _axis}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  /// Gridlines and ticks, the hours' labels, and the crosshair at [hover].
  void frame(Canvas canvas, Size size, Rect plot) {
    final grid = Paint()
      ..color = Aityx.bg2
      ..strokeWidth = 1;
    for (var v = 0.0; v <= top + step / 2; v += step) {
      final yy = y(plot, v).roundToDouble() + 0.5;
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), v == 0 ? (Paint()..color = Aityx.border) : grid);
      text(canvas, tick(v), Offset(plot.left - 6, yy), align: TextAlign.right);
    }
    final n = hours.length;
    if (n == 0) return;
    final long = n > 24;
    final slot = plot.width / n;
    final need = long ? 92.0 : 46.0;
    final every = [1, 2, 3, 6, 12, 24, 48].firstWhere((s) => s * slot >= need, orElse: () => 48);
    // The current hour labelled, and every so many hours back from it.
    for (var i = n - 1; i >= 0; i -= every) {
      final at = Offset(x(plot, i), size.height - bottom / 2 + 2);
      final label = hourLabel(hours[i], long: long);
      final tp = TextPainter(text: TextSpan(text: label, style: _axis), textDirection: TextDirection.ltr)..layout();
      final dx = (at.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }
    if (hover != null && hover! < n) {
      final xx = x(plot, hover!).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(xx, plot.top),
        Offset(xx, plot.bottom),
        Paint()
          ..color = Aityx.muted.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

/// Columns, one per hour, its [series] stacked from the baseline with a
/// 2 px gap of the card between segments and between columns, the top
/// segment's end rounded; [failed], when given, a red dot per hour at its
/// count on the same scale, ringed in the card's color.
class HourColumnsPainter extends HourPainter {
  HourColumnsPainter({
    required super.hours,
    required super.top,
    required super.step,
    required super.hover,
    required super.tick,
    required this.series,
    this.failed,
  });

  final List<ChartSeries> series;
  final List<int>? failed;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotOf(size);
    frame(canvas, size, plot);
    final n = hours.length;
    if (n == 0) return;
    final slot = plot.width / n;
    final w = slot >= 4 ? math.min(24.0, slot - 2) : math.max(1.0, slot - 1);
    final radius = math.min(4.0, w / 2);
    for (var i = 0; i < n; i++) {
      final cx = x(plot, i);
      final last = series.lastIndexWhere((s) => (s.values[i] ?? 0) > 0);
      var base = plot.bottom;
      var first = true;
      for (final (k, s) in series.indexed) {
        final v = s.values[i] ?? 0;
        if (v <= 0) continue;
        final h = v / top * plot.height;
        final bottom = first ? base : base - 2;
        final topY = math.min(bottom - 1, base - h);
        final rect = Rect.fromLTRB(cx - w / 2, topY, cx + w / 2, bottom);
        final paint = Paint()..color = s.color;
        canvas.drawRRect(
          k == last
              ? RRect.fromRectAndCorners(rect, topLeft: Radius.circular(radius), topRight: Radius.circular(radius))
              : RRect.fromRectAndCorners(rect),
          paint,
        );
        if (i == hover) canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.14));
        base -= h;
        first = false;
      }
    }
    final f = failed;
    if (f != null) {
      for (var i = 0; i < n && i < f.length; i++) {
        if (f[i] <= 0) continue;
        final at = Offset(x(plot, i), y(plot, f[i]));
        canvas.drawCircle(at, 6, Paint()..color = Aityx.bg1);
        canvas.drawCircle(at, 4, Paint()..color = failedColor);
      }
    }
  }
}

/// Lines over the hours, 2 px, broken where an hour has no value; a dot
/// (ringed in the card's color) on each hour when there are few, else on
/// an hour alone between gaps; each line's name and last value at its end
/// when they don't collide.
class HourLinesPainter extends HourPainter {
  HourLinesPainter({
    required super.hours,
    required super.top,
    required super.step,
    required super.hover,
    required super.tick,
    required this.series,
    this.unit = '',
  });

  final List<ChartSeries> series;
  final String unit;

  @override
  double get right => 76;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotOf(size);
    frame(canvas, size, plot);
    final n = hours.length;
    if (n == 0) return;
    final ends = <(double, String)>[];
    for (final s in series) {
      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final valued = s.values.where((v) => v != null).length;
      final path = Path();
      var open = false;
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null) {
          open = false;
          continue;
        }
        final p = Offset(x(plot, i), y(plot, v));
        open ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        open = true;
      }
      canvas.drawPath(path, line);
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final alone = (i == 0 || s.values[i - 1] == null) && (i == n - 1 || s.values[i + 1] == null);
        if (valued <= 48 || alone || i == hover) {
          final p = Offset(x(plot, i), y(plot, v));
          canvas.drawCircle(p, i == hover ? 7 : 6, Paint()..color = Aityx.bg1);
          canvas.drawCircle(p, i == hover ? 5 : 4, Paint()..color = s.color);
        }
      }
      final lastAt = s.values.lastIndexWhere((v) => v != null);
      if (lastAt >= 0) ends.add((y(plot, s.values[lastAt]!), '${s.label} ${compactCount(s.values[lastAt]!)}$unit'));
    }
    // End labels only when they stand apart; else the legend and the readout say it.
    final apart = ends.every((a) => ends.every((b) => identical(a, b) || (a.$1 - b.$1).abs() >= 14));
    if (apart) {
      for (final (yy, label) in ends) {
        text(canvas, label, Offset(plot.right + 8, yy), style: const TextStyle(color: Aityx.fg, fontSize: 11));
      }
    }
  }
}
