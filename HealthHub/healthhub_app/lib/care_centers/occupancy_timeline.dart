import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../sim_clock.dart';
import '../theme.dart';

/// An expected number of people: one decimal, two below one.
String expectedText(double v) => v < 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(1);

/// How the timeline asks the API for a care center's people in care per
/// hour: `GET /api/care-centers/{id}/occupancy`.
typedef HourlyOccupancyLoader = Future<HourlyOccupancy> Function(int id, {String? run, int? hours});

/// How the timeline asks for datyx's forecast of them:
/// `GET /api/care-centers/{id}/occupancy/forecast`.
typedef OccupancyForecastLoader = Future<HourlyForecast> Function(int id, {String? run});

/// A care center's occupancy per hour, as a card: how many people were in
/// care there in each hour up to its run's end, a solid line with a solid
/// point per hour, and datyx's DeepAR forecast of the hours after, a
/// dashed, lighter line with hollow, translucent points in its band of the
/// 10th to 90th percentiles; its [capacity], when known, a faint line.
/// Both are asked for together, now and every [refresh], so the forecast
/// starts where the line ends; a failed read keeps what is shown. Each
/// hour keeps the last forecast made of it before it was counted, so as the
/// hours pass the forecast stays on the chart over what happened. The
/// history is anyone's; the forecast, datyx's, needs a signed-in user and
/// a trained model, and without them the card says why.
class OccupancyTimelineCard extends StatefulWidget {
  const OccupancyTimelineCard({
    super.key,
    required this.occupancy,
    required this.forecast,
    required this.hospitalId,
    this.capacity = 0,
    this.unit = 'places',
    this.run,
    this.hours = 72,
    this.refresh = const Duration(seconds: 10),
  });

  final HourlyOccupancyLoader occupancy;
  final OccupancyForecastLoader forecast;
  final int hospitalId;

  /// Its places in the simulation ("8 beds"); 0 when unknown, and not drawn.
  final int capacity;
  final String unit;

  /// The run to show; the current one (else the newest with admissions there) when null.
  final String? run;
  final int hours;
  final Duration refresh;

  @override
  State<OccupancyTimelineCard> createState() => _OccupancyTimelineCardState();
}

class _OccupancyTimelineCardState extends State<OccupancyTimelineCard> {
  HourlyOccupancy? _history;
  HourlyForecast? _forecast;

  /// Every forecast hour seen in [_keptRun], by hour: the latest forecast
  /// of each. A forecast only reaches past its series' end, so an hour
  /// counted since keeps the last forecast made before it was.
  final _kept = <DateTime, ForecastStep>{};
  String? _keptRun;
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
  void didUpdateWidget(OccupancyTimelineCard old) {
    super.didUpdateWidget(old);
    if (old.hospitalId != widget.hospitalId || old.run != widget.run || old.hours != widget.hours) {
      _history = null;
      _forecast = null;
      _kept.clear();
      _keptRun = null;
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
        widget.occupancy(id, run: widget.run, hours: widget.hours).then<Object>((h) => h, onError: (Object e) => e),
        widget.forecast(id, run: widget.run).then<Object>((f) => f, onError: (Object e) => e),
      ]);
      if (!mounted || id != widget.hospitalId) return;
      setState(() {
        switch (results[0]) {
          case final HourlyOccupancy history:
            _history = history;
            _historyError = null;
            if (history.run != _keptRun) {
              _kept.clear();
              _keptRun = history.run;
            }
          case final error:
            _historyError = _reason(error);
        }
        switch (results[1]) {
          case final HourlyForecast forecast:
            _forecast = forecast;
            _forecastError = null;
            // Kept once the run is known, and only for it.
            if (_keptRun != null) {
              for (final step in forecast.steps) {
                _kept[step.at] = step;
              }
            }
          case final error:
            _forecastError = _reason(error);
        }
        // Only the hours shown, and those ahead, are kept.
        final first = _history?.hours.firstOrNull?.hour;
        if (first != null) _kept.removeWhere((hour, _) => hour.isBefore(first));
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
    final kept = [for (final hour in _kept.keys.toList()..sort()) _kept[hour]!];
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
                Text('Occupancy per hour', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                // Where the series end, as a simulated date and time: now,
                // or when a past run ended. Never the run's id.
                if (history?.end != null)
                  Text(
                    history!.current ? 'Now · ${simDateTime(history.end!)}' : 'Ended ${simDateTime(history.end!)}',
                    key: const Key('occupancy-now'),
                    style: const TextStyle(color: Aityx.fg, fontSize: 12, fontWeight: FontWeight.w600),
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
              OccupancyTimelineChart(hours: history.hours, forecast: kept, capacity: widget.capacity, unit: widget.unit),
              const SizedBox(height: 8),
              _Key(forecast: kept.isNotEmpty, capacity: widget.capacity, unit: widget.unit),
            ],
          ],
        ),
      ),
    );
  }

  /// The hours shown, and what the forecast is, or why there is none; then
  /// how the forecast of the hours gone did against them.
  String _status(HourlyOccupancy? history, HourlyForecast? forecast) {
    final now = _now(history, forecast);
    final gone = history == null ? null : ForecastCheck.of(history.hours, _kept);
    return gone == null ? now : '$now ${gone.text}';
  }

  String _now(HourlyOccupancy? history, HourlyForecast? forecast) {
    if (history == null || history.hours.isEmpty) return 'The hours of the simulation, from HealthHub\'s admissions.';
    final last = history.hours.last;
    final peak = history.hours.map((h) => h.occupancy).reduce(math.max);
    final of = widget.capacity > 0 ? ' of ${widget.capacity} ${widget.unit}' : '';
    final past = '${last.occupancy} in care at ${simDateTime(last.hour)}; at most $peak$of in the last '
        '${history.hours.length} hours.';
    if (_forecastError != null && (forecast == null || forecast.steps.isEmpty)) return '$past No forecast: $_forecastError';
    if (forecast == null) return '$past Asking datyx for its forecast…';
    if (forecast.steps.isEmpty) return '$past No forecast: ${forecast.prediction.note ?? 'datyx has none'}.';
    final p = forecast.prediction;
    final mean = forecast.steps.fold<double>(0, (sum, s) => sum + s.mean) / forecast.steps.length;
    final high = forecast.steps.map((s) => s.mean).reduce(math.max);
    return '$past datyx\'s DeepAR expects ${expectedText(mean)} on average over the next ${forecast.steps.length} '
        'hours, ${expectedText(high)} at most'
        '${p.trainingRunId == null ? '' : ' (model of training run ${p.trainingRunId})'}.';
  }
}

/// How a forecast did over the hours it was made of and that have since
/// been counted: how many of them, how many fell in its 80% band, and how
/// far its mean was from what happened, on average.
class ForecastCheck {
  const ForecastCheck({required this.hours, required this.inBand, required this.meanError});

  /// Null when no hour shown has a forecast yet.
  static ForecastCheck? of(List<HourOccupancy> hours, Map<DateTime, ForecastStep> forecast) {
    var n = 0;
    var inBand = 0;
    var error = 0.0;
    for (final h in hours) {
      final s = forecast[h.hour];
      if (s == null) continue;
      n++;
      if (h.occupancy >= s.p10 && h.occupancy <= s.p90) inBand++;
      error += (h.occupancy - s.mean).abs();
    }
    return n == 0 ? null : ForecastCheck(hours: n, inBand: inBand, meanError: error / n);
  }

  final int hours;
  final int inBand;
  final double meanError;

  String get text =>
      'Of the $hours ${hours == 1 ? 'hour' : 'hours'} forecast and gone, $inBand fell in the 80% band; '
      'the mean was off by ${expectedText(meanError)} on average.';
}

/// The key under the chart: what the solid and the dashed lines are, and
/// the capacity's.
class _Key extends StatelessWidget {
  const _Key({required this.forecast, required this.capacity, required this.unit});

  final bool forecast;
  final int capacity;
  final String unit;

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
            SizedBox(width: 24, height: 10, child: CustomPaint(painter: _KeyLine(_KeyKind.history))),
            SizedBox(width: 6),
            Text('In care', style: style),
          ],
        ),
        if (forecast)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 10, child: CustomPaint(painter: _KeyLine(_KeyKind.forecast))),
              SizedBox(width: 6),
              Flexible(
                child: Text('DeepAR forecast, kept as the hours pass (mean; the band, 10th to 90th percentile)', style: style),
              ),
            ],
          ),
        if (capacity > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 24, height: 10, child: CustomPaint(painter: _KeyLine(_KeyKind.capacity))),
              const SizedBox(width: 6),
              Text('Capacity, $capacity $unit', style: style),
            ],
          ),
      ],
    );
  }
}

enum _KeyKind { history, forecast, capacity }

class _KeyLine extends CustomPainter {
  const _KeyLine(this.kind);

  final _KeyKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    final mid = Offset(size.width / 2, y);
    switch (kind) {
      case _KeyKind.history:
        canvas.drawPath(path, _historyPaint);
        _historyPoint(canvas, mid, _pointRadius);
      case _KeyKind.forecast:
        canvas.drawRect(Rect.fromLTRB(0, y - 4, size.width, y + 4), Paint()..color = _bandColor);
        canvas.drawPath(_dash(path), _forecastPaint);
        _forecastPoint(canvas, mid, _pointRadius);
      case _KeyKind.capacity:
        canvas.drawPath(_dash(path, on: 3, off: 3), _capacityPaint);
    }
  }

  @override
  bool shouldRepaint(_KeyLine old) => old.kind != kind;
}

final _historyPaint = Paint()
  ..color = Aityx.orange
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

final _forecastPaint = Paint()
  ..color = Aityx.orange.withValues(alpha: 0.55)
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

final _capacityPaint = Paint()
  ..color = Aityx.muted
  ..strokeWidth = 1
  ..style = PaintingStyle.stroke;

final _bandColor = Aityx.orange.withValues(alpha: 0.12);

const _pointRadius = 2.5;

/// An hour gone: a solid point.
void _historyPoint(Canvas canvas, Offset at, double r) => canvas.drawCircle(at, r, Paint()..color = Aityx.orange);

/// A forecast hour: a hollow, translucent point.
void _forecastPoint(Canvas canvas, Offset at, double r) {
  canvas.drawCircle(at, r, Paint()..color = Aityx.bg1);
  canvas.drawCircle(
    at,
    r,
    Paint()
      ..color = Aityx.orange.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke,
  );
}

/// [path] as dashes of [on] px with gaps of [off].
Path _dash(Path path, {double on = 6, double off = 4}) {
  final dashed = Path();
  for (final ui.PathMetric metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += on + off) {
      dashed.addPath(metric.extractPath(d, math.min(d + on, metric.length)), Offset.zero);
    }
  }
  return dashed;
}

/// The timeline itself: [hours] as a solid line with a point per hour, the
/// [forecast] dashed and lighter, with hollow points, in its band: over the
/// hours it has a step for, to compare, and after them from the last hour;
/// a faint line where the hours end ("now"), and one at the [capacity] when
/// known. Hovering, or touching, shows the hour's numbers.
class OccupancyTimelineChart extends StatefulWidget {
  const OccupancyTimelineChart({
    super.key,
    required this.hours,
    this.forecast = const [],
    this.capacity = 0,
    this.unit = 'places',
    this.height = 200,
  });

  final List<HourOccupancy> hours;
  final List<ForecastStep> forecast;
  final int capacity;
  final String unit;
  final double height;

  @override
  State<OccupancyTimelineChart> createState() => _OccupancyTimelineChartState();
}

class _OccupancyTimelineChartState extends State<OccupancyTimelineChart> {
  /// The hour under the pointer, as hours from the first.
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final geometry = _Geometry(
      widget.hours,
      _ahead(widget.hours, widget.forecast),
      widget.capacity,
      _past(widget.hours, widget.forecast),
    );
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
                    CustomPaint(size: size, painter: _TimelinePainter(geometry, hover, widget.unit)),
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

  /// The forecast's steps after the last hour.
  static List<ForecastStep> _ahead(List<HourOccupancy> hours, List<ForecastStep> forecast) =>
      hours.isEmpty ? forecast : forecast.where((s) => s.at.isAfter(hours.last.hour)).toList();

  /// The forecast's step of each of the [hours], null where it has none.
  static List<ForecastStep?> _past(List<HourOccupancy> hours, List<ForecastStep> forecast) {
    final byHour = {for (final s in forecast) s.at: s};
    return [for (final h in hours) byHour[h.hour]];
  }

  Widget _tooltip(_Geometry g, int index, Size size) {
    final of = widget.capacity > 0 ? ' of ${widget.capacity} ${widget.unit}' : '';
    final String text;
    if (index < g.hours.length) {
      final h = g.hours[index];
      final s = g.past[index];
      text = '${simDateTime(h.hour)}\n${h.occupancy} in care$of'
          '${s == null ? '' : '\nforecast ${expectedText(s.mean)}, ${_n(s.p10)} to ${_n(s.p90)} (80%)'}';
    } else {
      final s = g.forecast[index - g.hours.length];
      text = '${simDateTime(s.at)}, forecast\n${expectedText(s.mean)} expected$of'
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
/// the hours), people on y from 0 to a whole number above the most, or
/// the capacity.
class _Geometry {
  _Geometry(this.hours, this.forecast, this.capacity, this.past)
    : top = [
        1.0,
        capacity.toDouble(),
        for (final h in hours) h.occupancy.toDouble(),
        for (final s in [...forecast, ...past.nonNulls]) ...[s.mean, s.p90],
      ].reduce(math.max).ceilToDouble();

  final List<HourOccupancy> hours;

  /// The forecast after the hours.
  final List<ForecastStep> forecast;
  final int capacity;

  /// The forecast of each of the hours, as it was before they were counted.
  final List<ForecastStep?> past;

  /// The forecast's step at [index], of the hours or after them; null where none.
  ForecastStep? stepAt(int index) => index < hours.length ? past[index] : forecast[index - hours.length];

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

  /// The points' radius: smaller when the hours are close together.
  double radius(Size size) =>
      (count <= 1 ? _pointRadius : (size.width - left - rightPad) / (count - 1) * 0.35).clamp(1.2, _pointRadius);

  /// The hour nearest x, or null outside the plot.
  int? hourAt(double dx, Size size) {
    if (count == 0 || dx < left - 4 || dx > size.width) return null;
    final f = (dx - left) / (size.width - left - rightPad) * (count - 1);
    return f.round().clamp(0, count - 1);
  }

  DateTime timeOf(int index) =>
      index < hours.length ? hours[index].hour : forecast[index - hours.length].at;

  String get summary {
    final now = hours.isEmpty ? 0 : hours.last.occupancy;
    final peak = hours.isEmpty ? 0 : hours.map((h) => h.occupancy).reduce(math.max);
    final mean = forecast.isEmpty ? 0.0 : forecast.fold<double>(0, (sum, s) => sum + s.mean) / forecast.length;
    final gone = past.nonNulls.length;
    return 'Occupancy per hour: $now in care now, at most $peak in the last ${hours.length} hours'
        '${capacity > 0 ? ', of a capacity of $capacity' : ''}'
        '${forecast.isEmpty ? '' : '; ${expectedText(mean)} on average forecast over the next ${forecast.length}'}'
        '${gone == 0 ? '' : '; the forecast kept over $gone of them'}';
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.g, this.hover, this.unit);

  final _Geometry g;
  final int? hover;
  final String unit;

  @override
  void paint(Canvas canvas, Size size) {
    if (g.count == 0) return;
    final grid = Paint()
      ..color = Aityx.border
      ..strokeWidth = 1;
    const label = TextStyle(color: Aityx.muted, fontSize: 11);
    final plotRight = size.width - _Geometry.rightPad;
    final r = g.radius(size);

    // Whole people on y, at most five lines.
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
      _text(canvas, midnight ? simDayLabel(t) : '12:00',
          Offset(x, size.height - _Geometry.bottom + 6), label, center: true);
    }

    // The capacity, a faint dotted line labelled at its right end.
    if (g.capacity > 0) {
      final y = g.y(g.capacity.toDouble(), size);
      canvas.drawPath(
        _dash(Path()
          ..moveTo(_Geometry.left, y)
          ..lineTo(plotRight, y), on: 3, off: 3),
        _capacityPaint,
      );
      final painter = TextPainter(text: TextSpan(text: '${g.capacity} $unit', style: label), textDirection: TextDirection.ltr)
        ..layout();
      painter.paint(canvas, Offset(plotRight - painter.width, y - painter.height - 1));
    }

    // Where the hours end and the forecast begins.
    final now = g.x(g.hours.length - 1, size);
    if (g.forecast.isNotEmpty || g.past.any((s) => s != null)) {
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

    // The forecast, kept over the hours and ahead of them: each run of
    // hours it has a step for, its band, then its mean, dashed, a hollow
    // point per hour. Without a forecast of the last hour, the run ahead
    // starts from what was counted then.
    for (final run in _runs(g)) {
      final anchor = run.first == g.hours.length && g.hours.isNotEmpty
          ? Offset(now, g.y(g.hours.last.occupancy.toDouble(), size))
          : null;
      Offset at(int i, double v) => Offset(g.x(i, size), g.y(v, size));
      final band = Path();
      final mean = Path();
      if (anchor != null) {
        band.moveTo(anchor.dx, anchor.dy);
        mean.moveTo(anchor.dx, anchor.dy);
      }
      for (final i in run) {
        final p90 = at(i, g.stepAt(i)!.p90);
        final m = at(i, g.stepAt(i)!.mean);
        if (anchor == null && i == run.first) {
          band.moveTo(p90.dx, p90.dy);
          mean.moveTo(m.dx, m.dy);
        } else {
          band.lineTo(p90.dx, p90.dy);
          mean.lineTo(m.dx, m.dy);
        }
      }
      for (final i in run.reversed) {
        final p10 = at(i, g.stepAt(i)!.p10);
        band.lineTo(p10.dx, p10.dy);
      }
      band.close();
      canvas.drawPath(band, Paint()..color = _bandColor);
      canvas.drawPath(_dash(mean), _forecastPaint);
      for (final i in run) {
        _forecastPoint(canvas, at(i, g.stepAt(i)!.mean), r);
      }
    }

    // The hours, solid, a point per hour.
    final line = Path();
    final points = <Offset>[];
    for (var i = 0; i < g.hours.length; i++) {
      final p = Offset(g.x(i, size), g.y(g.hours[i].occupancy.toDouble(), size));
      points.add(p);
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(line, _historyPaint);
    for (final p in points) {
      _historyPoint(canvas, p, r);
    }

    // The hour under the pointer: a crosshair and its point, ringed with the card's colour.
    final h = hover;
    if (h != null) {
      final x = g.x(h, size);
      canvas.drawLine(Offset(x, _Geometry.topPad), Offset(x, size.height - _Geometry.bottom),
          Paint()
            ..color = Aityx.muted
            ..strokeWidth = 1);
      final value = h < g.hours.length ? g.hours[h].occupancy.toDouble() : g.forecast[h - g.hours.length].mean;
      final at = Offset(x, g.y(value, size));
      canvas.drawCircle(at, 6, Paint()..color = Aityx.bg1);
      canvas.drawCircle(at, 4, Paint()..color = h < g.hours.length ? Aityx.orange : Aityx.orangeLight);
    }
  }

  /// The indexes with a forecast step, in runs of consecutive hours.
  static List<List<int>> _runs(_Geometry g) {
    final runs = <List<int>>[];
    for (var i = 0; i < g.count; i++) {
      if (g.stepAt(i) == null) continue;
      if (runs.isEmpty || runs.last.last != i - 1) {
        runs.add([i]);
      } else {
        runs.last.add(i);
      }
    }
    return runs;
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style, {bool alignRight = false, bool center = false}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = alignRight ? at.dx - painter.width : (center ? at.dx - painter.width / 2 : at.dx);
    final dy = alignRight ? at.dy - painter.height / 2 : at.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.g.hours != g.hours ||
      old.g.forecast != g.forecast ||
      !listEquals(old.g.past, g.past) ||
      old.g.capacity != g.capacity ||
      old.hover != hover;
}
