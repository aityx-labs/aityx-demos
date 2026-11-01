import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../theme.dart';

/// Simulated time has days, not dates: day 1 is 2026-01-01.
final _day1 = DateTime.utc(2026, 1, 1);

/// "Day 19, 17:00": a simulated hour as the rest of the app names it.
String simHour(DateTime hour) {
  final day = hour.difference(_day1).inDays + 1;
  return 'Day $day, ${hour.hour.toString().padLeft(2, '0')}:00';
}

/// An expected number of admissions: one decimal, two below one.
String expectedText(double v) => v < 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(1);

/// How the timeline asks the API for a care center's admissions per hour:
/// `GET /api/care-centers/{id}/admissions`.
typedef HourlyAdmissionsLoader = Future<HourlyAdmissions> Function(int id, {String? run, int? hours});

/// How the timeline asks for datyx's forecast of them:
/// `GET /api/care-centers/{id}/admissions/forecast`.
typedef AdmissionsForecastLoader = Future<AdmissionsForecast> Function(int id, {String? run});

/// A hospital's admissions per hour, as a card: the hours up to its run's
/// end as a solid line, and datyx's DeepAR forecast of the hours after as
/// a dashed, lighter line in its band of the 10th to 90th percentiles.
/// Both are asked for together, now and every [refresh], so the forecast
/// starts where the line ends; a failed read keeps what is shown. The
/// history is anyone's; the forecast, datyx's, needs a signed-in user and
/// a trained model, and without them the card says why.
class AdmissionsTimelineCard extends StatefulWidget {
  const AdmissionsTimelineCard({
    super.key,
    required this.admissions,
    required this.forecast,
    required this.hospitalId,
    this.run,
    this.hours = 72,
    this.refresh = const Duration(seconds: 10),
  });

  final HourlyAdmissionsLoader admissions;
  final AdmissionsForecastLoader forecast;
  final int hospitalId;

  /// The run to show; the current one (else the newest with admissions there) when null.
  final String? run;
  final int hours;
  final Duration refresh;

  @override
  State<AdmissionsTimelineCard> createState() => _AdmissionsTimelineCardState();
}

class _AdmissionsTimelineCardState extends State<AdmissionsTimelineCard> {
  HourlyAdmissions? _history;
  AdmissionsForecast? _forecast;
  String? _historyError;
  String? _forecastError;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(widget.refresh, (_) => _load());
  }

  @override
  void didUpdateWidget(AdmissionsTimelineCard old) {
    super.didUpdateWidget(old);
    if (old.hospitalId != widget.hospitalId || old.run != widget.run || old.hours != widget.hours) {
      _history = null;
      _forecast = null;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final id = widget.hospitalId;
    try {
      final results = await Future.wait([
        widget.admissions(id, run: widget.run, hours: widget.hours).then<Object>((h) => h, onError: (Object e) => e),
        widget.forecast(id, run: widget.run).then<Object>((f) => f, onError: (Object e) => e),
      ]);
      if (!mounted || id != widget.hospitalId) return;
      setState(() {
        switch (results[0]) {
          case final HourlyAdmissions history:
            _history = history;
            _historyError = null;
          case final error:
            _historyError = _reason(error);
        }
        switch (results[1]) {
          case final AdmissionsForecast forecast:
            _forecast = forecast;
            _forecastError = null;
          case final error:
            _forecastError = _reason(error);
        }
      });
    } finally {
      _loading = false;
    }
  }

  static String _reason(Object error) => error is ApiException ? error.message : '$error';

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final forecast = _forecast;
    final theme = Theme.of(context);
    final steps = forecast?.steps ?? const <ForecastStep>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline, color: Aityx.orange, size: 20),
                const SizedBox(width: 8),
                Text('Admissions per hour', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (history?.run != null)
                  Text(
                    history!.current ? 'run ${history.run}, now' : 'run ${history.run}',
                    style: const TextStyle(color: Aityx.muted, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_status(history, forecast), style: const TextStyle(color: Aityx.muted, fontSize: 12)),
            const SizedBox(height: 12),
            if (history == null)
              SizedBox(
                height: 200,
                child: Center(
                  child: _historyError == null
                      ? const CircularProgressIndicator()
                      : Text(_historyError!, style: const TextStyle(color: Aityx.muted)),
                ),
              )
            else if (history.hours.isEmpty)
              const SizedBox(
                height: 80,
                child: Center(child: Text('Nobody has been admitted here yet.', style: TextStyle(color: Aityx.muted))),
              )
            else ...[
              AdmissionsTimelineChart(hours: history.hours, forecast: steps),
              const SizedBox(height: 8),
              _Key(forecast: steps.isNotEmpty),
            ],
          ],
        ),
      ),
    );
  }

  /// What the forecast is, or why there is none.
  String _status(HourlyAdmissions? history, AdmissionsForecast? forecast) {
    if (history == null || history.hours.isEmpty) return 'The hours of the simulation, from HealthHub\'s admissions.';
    final last = history.hours.fold<int>(0, (sum, h) => sum + h.admissions);
    final past = '$last admitted in the last ${history.hours.length} hours, to ${simHour(history.hours.last.hour)}.';
    if (_forecastError != null && (forecast == null || forecast.steps.isEmpty)) return '$past No forecast: $_forecastError';
    if (forecast == null) return '$past Asking datyx for its forecast…';
    if (forecast.steps.isEmpty) return '$past No forecast: ${forecast.prediction.note ?? 'datyx has none'}.';
    final p = forecast.prediction;
    final expected = forecast.steps.fold<double>(0, (sum, s) => sum + s.mean);
    return '$past datyx\'s DeepAR expects ${expectedText(expected)} in the next ${forecast.steps.length} hours'
        '${p.trainingRunId == null ? '' : ' (model of training run ${p.trainingRunId})'}.';
  }
}

/// The key under the chart: what the solid and the dashed lines are.
class _Key extends StatelessWidget {
  const _Key({required this.forecast});

  final bool forecast;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Aityx.muted, fontSize: 12);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 24, height: 10, child: CustomPaint(painter: _KeyLine(dashed: false))),
            SizedBox(width: 6),
            Text('Admitted', style: style),
          ],
        ),
        if (forecast)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 10, child: CustomPaint(painter: _KeyLine(dashed: true))),
              SizedBox(width: 6),
              Flexible(child: Text('DeepAR forecast (mean; the band, 10th to 90th percentile)', style: style)),
            ],
          ),
      ],
    );
  }
}

class _KeyLine extends CustomPainter {
  const _KeyLine({required this.dashed});

  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    if (dashed) {
      canvas.drawRect(Rect.fromLTRB(0, y - 4, size.width, y + 4), Paint()..color = _bandColor);
    }
    canvas.drawPath(dashed ? _dash(path) : path, dashed ? _forecastPaint : _historyPaint);
  }

  @override
  bool shouldRepaint(_KeyLine old) => old.dashed != dashed;
}

final _historyPaint = Paint()
  ..color = Aityx.orange
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

final _forecastPaint = Paint()
  ..color = Aityx.orange.withValues(alpha: 0.6)
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

final _bandColor = Aityx.orange.withValues(alpha: 0.12);

/// [path] as dashes of 6 px with gaps of 4.
Path _dash(Path path) {
  final dashed = Path();
  for (final ui.PathMetric metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += 10) {
      dashed.addPath(metric.extractPath(d, math.min(d + 6, metric.length)), Offset.zero);
    }
  }
  return dashed;
}

/// The timeline itself: [hours] as a solid line, the [forecast] after them
/// dashed and lighter from the last hour, in its band; a faint line where
/// the hours end ("now"). Hovering, or touching, shows the hour's numbers.
class AdmissionsTimelineChart extends StatefulWidget {
  const AdmissionsTimelineChart({super.key, required this.hours, this.forecast = const [], this.height = 200});

  final List<HourCount> hours;
  final List<ForecastStep> forecast;
  final double height;

  @override
  State<AdmissionsTimelineChart> createState() => _AdmissionsTimelineChartState();
}

class _AdmissionsTimelineChartState extends State<AdmissionsTimelineChart> {
  /// The hour under the pointer, as hours from the first.
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final geometry = _Geometry(widget.hours, _ahead(widget.hours, widget.forecast));
    return Semantics(
      container: true,
      label: geometry.summary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          void point(Offset at) => setState(() => _hover = geometry.hourAt(at.dx, size));
          final hover = _hover;
          return MouseRegion(
            onHover: (e) => point(e.localPosition),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              onTapDown: (e) => point(e.localPosition),
              onHorizontalDragUpdate: (e) => point(e.localPosition),
              child: SizedBox.fromSize(
                size: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(size: size, painter: _TimelinePainter(geometry, hover)),
                    if (hover != null) _tooltip(geometry, hover, size),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The forecast's steps after the last hour (a forecast asked a moment
  /// before may start inside the hours shown).
  static List<ForecastStep> _ahead(List<HourCount> hours, List<ForecastStep> forecast) =>
      hours.isEmpty ? forecast : forecast.where((s) => s.at.isAfter(hours.last.hour)).toList();

  Widget _tooltip(_Geometry g, int index, Size size) {
    final String text;
    if (index < g.hours.length) {
      final h = g.hours[index];
      text = '${simHour(h.hour)}\n${h.admissions} admitted'
          '${h.admissions == 0 ? '' : ' (${h.acute} acute, ${h.chronic} chronic)'}';
    } else {
      final s = g.forecast[index - g.hours.length];
      text = '${simHour(s.at)}, forecast\n${s.mean.toStringAsFixed(2)} expected'
          '\n${_n(s.p10)} to ${_n(s.p90)} (80%)';
    }
    final x = g.x(index, size);
    final left = x > size.width / 2 ? null : x + 10;
    final right = x > size.width / 2 ? size.width - x + 10 : null;
    return Positioned(
      top: 4,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Aityx.bg2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Aityx.border),
          ),
          child: Text(text, style: const TextStyle(color: Aityx.fg, fontSize: 12)),
        ),
      ),
    );
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Where everything goes: hours from the first on x (the forecast's after
/// the hours), admissions on y from 0 to a whole number above the most.
class _Geometry {
  _Geometry(this.hours, this.forecast)
    : top = [
        1.0,
        for (final h in hours) h.admissions.toDouble(),
        for (final s in forecast) ...[s.mean, s.p90],
      ].reduce(math.max).ceilToDouble();

  final List<HourCount> hours;
  final List<ForecastStep> forecast;

  /// The top of the y axis.
  final double top;

  static const left = 28.0;
  static const bottom = 22.0;
  static const topPad = 8.0;
  static const rightPad = 8.0;

  int get count => hours.length + forecast.length;

  double x(int index, Size size) =>
      left + (count <= 1 ? 0 : index / (count - 1)) * (size.width - left - rightPad);

  double y(double value, Size size) => size.height - bottom - value / top * (size.height - bottom - topPad);

  /// The hour nearest x, or null outside the plot.
  int? hourAt(double dx, Size size) {
    if (count == 0 || dx < left - 4 || dx > size.width) return null;
    final f = (dx - left) / (size.width - left - rightPad) * (count - 1);
    return f.round().clamp(0, count - 1);
  }

  DateTime timeOf(int index) =>
      index < hours.length ? hours[index].hour : forecast[index - hours.length].at;

  String get summary {
    final admitted = hours.fold<int>(0, (sum, h) => sum + h.admissions);
    final expected = forecast.fold<double>(0, (sum, s) => sum + s.mean);
    return 'Admissions per hour: $admitted in the last ${hours.length} hours'
        '${forecast.isEmpty ? '' : '; ${expectedText(expected)} forecast over the next ${forecast.length}'}';
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.g, this.hover);

  final _Geometry g;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    if (g.count == 0) return;
    final grid = Paint()
      ..color = Aityx.border
      ..strokeWidth = 1;
    const label = TextStyle(color: Aityx.muted, fontSize: 11);
    final plotRight = size.width - _Geometry.rightPad;

    // Whole admissions on y, at most five lines.
    final every = math.max(1, (g.top / 4).ceil());
    for (var v = 0; v <= g.top; v += every) {
      final y = g.y(v.toDouble(), size);
      canvas.drawLine(Offset(_Geometry.left, y), Offset(plotRight, y), grid);
      _text(canvas, '$v', Offset(_Geometry.left - 6, y), label, alignRight: true);
    }

    // Days on x: each simulated midnight, and noon when there's room.
    final perHour = (plotRight - _Geometry.left) / math.max(1, g.count - 1);
    for (var i = 0; i < g.count; i++) {
      final t = g.timeOf(i);
      final midnight = t.hour == 0;
      if (!midnight && !(t.hour == 12 && perHour * 12 > 44)) continue;
      final x = g.x(i, size);
      canvas.drawLine(Offset(x, size.height - _Geometry.bottom), Offset(x, size.height - _Geometry.bottom + 4), grid);
      _text(canvas, midnight ? 'Day ${t.difference(_day1).inDays + 1}' : '12:00',
          Offset(x, size.height - _Geometry.bottom + 6), label, center: true);
    }

    // Where the hours end and the forecast begins.
    final now = g.x(g.hours.length - 1, size);
    if (g.forecast.isNotEmpty) {
      canvas.drawPath(
        _dash(Path()
          ..moveTo(now, _Geometry.topPad)
          ..lineTo(now, size.height - _Geometry.bottom)),
        Paint()
          ..color = Aityx.dim
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // The forecast: its band, then its mean, dashed, from the last hour.
    if (g.forecast.isNotEmpty) {
      final last = Offset(now, g.y(g.hours.last.admissions.toDouble(), size));
      final band = Path()..moveTo(last.dx, last.dy);
      for (var k = 0; k < g.forecast.length; k++) {
        band.lineTo(g.x(g.hours.length + k, size), g.y(g.forecast[k].p90, size));
      }
      for (var k = g.forecast.length - 1; k >= 0; k--) {
        band.lineTo(g.x(g.hours.length + k, size), g.y(g.forecast[k].p10, size));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = _bandColor);
      final mean = Path()..moveTo(last.dx, last.dy);
      for (var k = 0; k < g.forecast.length; k++) {
        mean.lineTo(g.x(g.hours.length + k, size), g.y(g.forecast[k].mean, size));
      }
      canvas.drawPath(_dash(mean), _forecastPaint);
    }

    // The hours, solid.
    final line = Path();
    for (var i = 0; i < g.hours.length; i++) {
      final p = Offset(g.x(i, size), g.y(g.hours[i].admissions.toDouble(), size));
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(line, _historyPaint);

    // The hour under the pointer: a crosshair and its point, ringed with the card's colour.
    final h = hover;
    if (h != null) {
      final x = g.x(h, size);
      canvas.drawLine(Offset(x, _Geometry.topPad), Offset(x, size.height - _Geometry.bottom),
          Paint()
            ..color = Aityx.muted
            ..strokeWidth = 1);
      final value = h < g.hours.length ? g.hours[h].admissions.toDouble() : g.forecast[h - g.hours.length].mean;
      final at = Offset(x, g.y(value, size));
      canvas.drawCircle(at, 6, Paint()..color = Aityx.bg1);
      canvas.drawCircle(at, 4, Paint()..color = h < g.hours.length ? Aityx.orange : Aityx.orangeLight);
    }
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style, {bool alignRight = false, bool center = false}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = alignRight ? at.dx - painter.width : (center ? at.dx - painter.width / 2 : at.dx);
    final dy = alignRight ? at.dy - painter.height / 2 : at.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.g.hours != g.hours || old.g.forecast != g.forecast || old.hover != hover;
}
