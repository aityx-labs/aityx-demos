import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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


/// The alarms' threshold unless the API says: 90% of the capacity.
const defaultAlarmThreshold = 0.9;

/// Whether [value] reaches [limit]: at or above it, give or take the
/// rounding of a share times a capacity (0.9 × 10 is 9), as the API's
/// alarms read it.
bool reachesThreshold(num value, double limit) => value >= limit - 1e-9;

/// A share as a percentage, "90%".
String percentText(double share) => '${(share * 100).round()}%';

/// A care center's occupancy per hour, as a card: how many people were in
/// care there in each hour up to its run's end (observed, a solid line
/// with a solid point per hour), and datyx's DeepAR prediction of every
/// hour, a dashed line with hollow points in its band of the 10th to 90th
/// percentiles: over the past hours what it predicted of each before it
/// was observed (as the API keeps it, else as this view kept it: each hour
/// keeps the last forecast the view was given of it before it was
/// counted, for the hours the API keeps none of, such as with the alarms
/// off), over the next its forecast now. A vertical line marks
/// now, labelled with the simulated time; its [capacity], when known, a
/// faint line, and the alarm threshold (90% of it) a red one, every point
/// at or above it marked. Both are asked for together, now and every
/// [refresh], so the forecast starts where the line ends; a failed read
/// keeps what is shown. The history is anyone's (what datyx predicted of
/// it, a signed-in user's); the forecast, datyx's, needs a signed-in user
/// and a trained model, and without them the card says why.
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

  /// Every forecast hour this view was given in [_keptRun], by hour: the
  /// latest forecast of each, with its lead from the forecast's series'
  /// end. A forecast only reaches past its series' end, so an hour counted
  /// since keeps the last forecast made before it was; shown only where
  /// the API has no prediction of the hour ([_withKept]).
  final _kept = <DateTime, PredictedHour>{};
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
            if (_keptRun != null) _keep(forecast.steps);
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

  /// Keeps [steps], a forecast from its series' end (an hour before its
  /// first step), as each hour's prediction, its lead in hours from there.
  void _keep(List<ForecastStep> steps) {
    if (steps.isEmpty) return;
    final end = steps.first.at.subtract(const Duration(hours: 1));
    for (final step in steps) {
      _kept[step.at] = PredictedHour(mean: step.mean, p10: step.p10, p90: step.p90, leadHours: step.at.difference(end).inHours);
    }
  }

  /// [hours], each with what datyx predicted of it: the API's, else the
  /// one this view kept ([_kept]), else none.
  List<HourOccupancy> _withKept(List<HourOccupancy> hours) => [
    for (final h in hours)
      h.predicted != null || _kept[h.hour] == null
          ? h
          : HourOccupancy(hour: h.hour, occupancy: h.occupancy, predicted: _kept[h.hour]),
  ];

  double get _threshold => _history?.threshold ?? defaultAlarmThreshold;

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final forecast = _forecast;
    final theme = Theme.of(context);
    final steps = forecast?.steps ?? const <ForecastStep>[];
    final hours = history == null ? const <HourOccupancy>[] : _withKept(history.hours);
    final predictedBefore = hours.any((h) => h.predicted != null);
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
                    history!.current ? 'Now · ${simDateTime(_nowOf(history))}' : 'Ended ${simDateTime(history.end!)}',
                    key: const Key('occupancy-now'),
                    style: const TextStyle(color: Aityx.fg, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_status(history, hours, forecast), key: const Key('occupancy-status'), style: const TextStyle(color: Aityx.muted, fontSize: 12)),
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
              OccupancyTimelineChart(
                hours: hours,
                forecast: steps,
                capacity: widget.capacity,
                unit: widget.unit,
                threshold: _threshold,
                now: history.current ? _nowOf(history) : null,
              ),
              const SizedBox(height: 8),
              _Key(
                now: history.current,
                predicted: steps.isNotEmpty || predictedBefore,
                capacity: widget.capacity,
                unit: widget.unit,
                threshold: _threshold,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The simulated clock of the run going on, as the API says it; the
  /// series' end without it.
  static DateTime _nowOf(HourlyOccupancy history) {
    final now = history.now;
    final moment = now == null ? null : simMoment(now.calendarDate!.difference(simEpoch).inDays + 1, now.simTime ?? '00:00');
    final end = history.end!;
    return moment == null || moment.isBefore(end) ? end : moment;
  }

  /// The hours shown, how well datyx predicted them ([ForecastCheck]), and
  /// what the forecast is, or why there is none; the first hour ahead the
  /// threshold is reached. [hours] are the history's, with what was
  /// predicted of each ([_withKept]).
  String _status(HourlyOccupancy? history, List<HourOccupancy> hours, HourlyForecast? forecast) {
    if (history == null || hours.isEmpty) return 'The hours of the simulation, from HealthHub\'s admissions.';
    final last = hours.last;
    final peak = hours.map((h) => h.occupancy).reduce(math.max);
    final of = widget.capacity > 0 ? ' of ${widget.capacity} ${widget.unit}' : '';
    final past = '${last.occupancy} in care at ${simDateTime(last.hour)}; at most $peak$of in the last '
        '${hours.length} hours.';
    final check = ForecastCheck.of(hours);
    final accuracy = check == null ? '' : ' ${check.text}';
    if (_forecastError != null && (forecast == null || forecast.steps.isEmpty)) {
      return '$past$accuracy No forecast: $_forecastError';
    }
    if (forecast == null) return '$past$accuracy Asking datyx for its forecast…';
    if (forecast.steps.isEmpty) return '$past$accuracy No forecast: ${forecast.prediction.note ?? 'datyx has none'}.';
    final p = forecast.prediction;
    final mean = forecast.steps.fold<double>(0, (sum, s) => sum + s.mean) / forecast.steps.length;
    final high = forecast.steps.map((s) => s.mean).reduce(math.max);
    final crossing = widget.capacity > 0 ? firstCrossing(forecast.steps, _threshold * widget.capacity) : null;
    final alarm = crossing == null
        ? ''
        : ' ${percentText(_threshold)} of the capacity ${crossing.expected ? 'expected' : 'possible'} at '
            '${simDateTime(crossing.at)}.';
    return '$past$accuracy datyx\'s DeepAR expects ${expectedText(mean)} on average over the next ${forecast.steps.length} '
        'hours, ${expectedText(high)} at most'
        '${p.trainingRunId == null ? '' : ' (model of training run ${p.trainingRunId})'}.$alarm';
  }
}

/// How datyx's predictions did over the hours observed it predicted
/// before they came: how many of them, how many fell in the 80% band (the
/// 10th to 90th percentiles), and how far the mean was from what
/// happened, on average.
class ForecastCheck {
  const ForecastCheck({required this.hours, required this.inBand, required this.meanError});

  /// Of [hours]' predictions ([HourOccupancy.predicted]); null when none
  /// has one.
  static ForecastCheck? of(List<HourOccupancy> hours) {
    var n = 0;
    var inBand = 0;
    var error = 0.0;
    for (final h in hours) {
      final p = h.predicted;
      if (p == null) continue;
      n++;
      if (p.p10 != null && p.p90 != null && h.occupancy >= p.p10! && h.occupancy <= p.p90!) inBand++;
      error += (h.occupancy - p.mean).abs();
    }
    return n == 0 ? null : ForecastCheck(hours: n, inBand: inBand, meanError: error / n);
  }

  final int hours;
  final int inBand;
  final double meanError;

  String get text =>
      'datyx predicted $hours of them before they came, off by ${expectedText(meanError)} on average; '
      '$inBand fell in its 80% band.';
}

/// Where the label of the first crossing ahead goes, its top: [gap] above
/// the ring of radius [ring] around the point at [pointY] when the [pill]
/// fits there under the now label (whose bottom is [under]), else [gap]
/// below the ring. Never over the point.
double crossingLabelTop({required double pointY, required double ring, required double pill, double under = 22, double gap = 3}) {
  final above = pointY - ring - gap - pill;
  return above >= under ? above : pointY + ring + gap;
}

/// The first of [steps] whose mean reaches [limit] (expected), else whose
/// 90th percentile does (not expected: possible); null when none does.
({DateTime at, bool expected, int index})? firstCrossing(List<ForecastStep> steps, double limit) {
  for (var i = 0; i < steps.length; i++) {
    if (reachesThreshold(steps[i].mean, limit)) return (at: steps[i].at, expected: true, index: i);
  }
  for (var i = 0; i < steps.length; i++) {
    if (reachesThreshold(steps[i].p90, limit)) return (at: steps[i].at, expected: false, index: i);
  }
  return null;
}

/// The key under the chart: what the lines and the marks are.
class _Key extends StatelessWidget {
  const _Key({required this.now, required this.predicted, required this.capacity, required this.unit, required this.threshold});

  /// Whether the run is going on, and so has a now line.
  final bool now;

  final bool predicted;
  final int capacity;
  final String unit;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Aityx.muted, fontSize: 12);
    Widget entry(_KeyKind kind, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 24, height: 12, child: CustomPaint(painter: _KeyLine(kind))),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: style)),
      ],
    );
    final limit = threshold * capacity;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        entry(_KeyKind.history, 'In care (observed)'),
        if (predicted)
          entry(_KeyKind.forecast, 'Predicted by DeepAR before each hour and ahead (mean; the band, 10th to 90th percentile)'),
        if (now) entry(_KeyKind.now, 'Now'),
        if (capacity > 0) entry(_KeyKind.capacity, 'Capacity, $capacity $unit'),
        if (capacity > 0) ...[
          entry(_KeyKind.threshold, 'Alarm threshold, ${percentText(threshold)} (${_n(limit)})'),
          entry(_KeyKind.overObserved, 'In care at or above it'),
          if (predicted) entry(_KeyKind.overPredicted, 'Predicted at or above it'),
        ],
      ],
    );
  }
}

enum _KeyKind { history, forecast, now, capacity, threshold, overObserved, overPredicted }

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
        canvas.drawPath(_dash(path), _predictedPaint);
        _predictedPoint(canvas, mid, _pointRadius);
      case _KeyKind.now:
        canvas.drawLine(Offset(mid.dx, 0), Offset(mid.dx, size.height), _nowPaint);
      case _KeyKind.capacity:
        canvas.drawPath(_dash(path, on: 3, off: 3), _capacityPaint);
      case _KeyKind.threshold:
        canvas.drawPath(_dash(path, on: 5, off: 3), _thresholdPaint);
      case _KeyKind.overObserved:
        _overObserved(canvas, mid, _pointRadius);
      case _KeyKind.overPredicted:
        _overPredicted(canvas, mid, _pointRadius);
    }
  }

  @override
  bool shouldRepaint(_KeyLine old) => old.kind != kind;
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

final _historyPaint = Paint()
  ..color = Aityx.orange
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

/// The predicted series: blue, dashed, apart from the observed orange.
const _predictedColor = Aityx.blue;

final _predictedPaint = Paint()
  ..color = _predictedColor.withValues(alpha: 0.85)
  ..strokeWidth = 2
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

final _capacityPaint = Paint()
  ..color = Aityx.muted
  ..strokeWidth = 1
  ..style = PaintingStyle.stroke;

final _thresholdPaint = Paint()
  ..color = Aityx.red.withValues(alpha: 0.8)
  ..strokeWidth = 1.2
  ..style = PaintingStyle.stroke;

final _nowPaint = Paint()
  ..color = Aityx.fg
  ..strokeWidth = 1.5;

final _bandColor = _predictedColor.withValues(alpha: 0.14);

const _pointRadius = 2.5;

/// An hour observed: a solid point.
void _historyPoint(Canvas canvas, Offset at, double r) => canvas.drawCircle(at, r, Paint()..color = Aityx.orange);

/// An hour predicted: a hollow point.
void _predictedPoint(Canvas canvas, Offset at, double r) {
  canvas.drawCircle(at, r, Paint()..color = Aityx.bg1);
  canvas.drawCircle(
    at,
    r,
    Paint()
      ..color = _predictedColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke,
  );
}

/// An hour observed at or above the threshold: a red point, larger, in a
/// red halo.
void _overObserved(Canvas canvas, Offset at, double r) {
  canvas.drawCircle(at, r + 4, Paint()..color = Aityx.red.withValues(alpha: 0.28));
  canvas.drawCircle(at, r + 1.5, Paint()..color = Aityx.red);
}

/// An hour predicted at or above the threshold: a hollow red ring, in a
/// faint red halo; amber for [color] when only its 90th percentile is.
void _overPredicted(Canvas canvas, Offset at, double r, {Color color = Aityx.red}) {
  canvas.drawCircle(at, r + 4, Paint()..color = color.withValues(alpha: 0.18));
  canvas.drawCircle(at, r + 1.5, Paint()..color = Aityx.bg1);
  canvas.drawCircle(
    at,
    r + 1.5,
    Paint()
      ..color = color
      ..strokeWidth = 1.8
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

/// One hour of the chart: observed or not, and what was predicted of it
/// (before it, for an hour observed; the forecast, for one ahead).
typedef _Slot = ({DateTime at, int? occupancy, double? mean, double? p10, double? p90, int? lead, bool ahead});

/// The timeline itself: the [hours] observed, a solid line with a point
/// per hour; what datyx predicted of every hour, a dashed line with hollow
/// points in its band, over the hours observed (each hour's prediction
/// made before it) and the [forecast] after them; a vertical line at
/// [now] labelled with the simulated time (none for a run that has ended,
/// [now] null); the
/// [capacity] when known, a faint line, and the alarm [threshold] of it a
/// red one, labelled; every point at or above it marked in red (filled
/// when observed, hollow when predicted), and the first hour ahead the
/// forecast reaches it highlighted and labelled ("90% expected at Jan 19
/// 16:00", beside the point, never over it). Hovering, or touching, shows
/// the hour's numbers.
class OccupancyTimelineChart extends StatefulWidget {
  const OccupancyTimelineChart({
    super.key,
    required this.hours,
    this.forecast = const [],
    this.capacity = 0,
    this.unit = 'places',
    this.threshold = defaultAlarmThreshold,
    this.now,
    this.height = 220,
  });

  final List<HourOccupancy> hours;
  final List<ForecastStep> forecast;
  final int capacity;
  final String unit;
  final double threshold;
  final DateTime? now;
  final double height;

  @override
  State<OccupancyTimelineChart> createState() => _OccupancyTimelineChartState();
}

class _OccupancyTimelineChartState extends State<OccupancyTimelineChart> {
  /// The hour under the pointer, as hours from the first.
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final geometry = _Geometry(widget.hours, widget.forecast, widget.capacity, widget.threshold, widget.now);
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
                    if (hover != null && hover < geometry.count) _tooltip(geometry, hover, size),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tooltip(_Geometry g, int index, Size size) {
    final of = widget.capacity > 0 ? ' of ${widget.capacity} ${widget.unit}' : '';
    final slot = g.slots[index];
    final share = widget.capacity > 0;
    String pct(num v) => share ? ' (${percentText(v / widget.capacity)})' : '';
    final lines = <String>[
      slot.ahead ? '${simDateTime(slot.at)}, forecast' : simDateTime(slot.at),
      if (slot.occupancy != null) '${slot.occupancy} in care$of${pct(slot.occupancy!)}',
      if (slot.mean != null && slot.ahead) '${expectedText(slot.mean!)} expected$of${pct(slot.mean!)}',
      if (slot.mean != null && !slot.ahead)
        'predicted ${expectedText(slot.mean!)}${slot.lead == null ? '' : ', ${slot.lead} h before'}',
      if (slot.p10 != null && slot.p90 != null) '${_n(slot.p10!)} to ${_n(slot.p90!)} (80%)',
      if (g.limit != null && slot.occupancy != null && reachesThreshold(slot.occupancy!, g.limit!))
        'at or above the ${percentText(widget.threshold)} threshold',
      if (g.limit != null && slot.occupancy == null && slot.mean != null && reachesThreshold(slot.mean!, g.limit!))
        '${percentText(widget.threshold)} threshold expected'
      else if (g.limit != null && slot.occupancy == null && slot.p90 != null && reachesThreshold(slot.p90!, g.limit!))
        '${percentText(widget.threshold)} threshold possible',
    ];
    final x = g.x(index, size);
    final left = x > size.width / 2 ? null : x + 10;
    final right = x > size.width / 2 ? size.width - x + 10 : null;
    return Positioned(
      top: _Geometry.topPad + 4,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          key: const Key('occupancy-tooltip'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Aityx.bg2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Aityx.border),
          ),
          child: Text(lines.join('\n'), style: const TextStyle(color: Aityx.fg, fontSize: 12)),
        ),
      ),
    );
  }
}

/// Where everything goes: an hour per slot on x from the first hour
/// observed to the forecast's last (the forecast placed by its hours, so a
/// forecast asked a moment before starts inside the hours shown, and its
/// steps there are left out; one asked a moment after, of a series an hour
/// or more longer, starts after them, and the hours between are slots
/// without a mean), people on y from 0 to a whole number above the most,
/// or the capacity.
class _Geometry {
  _Geometry(List<HourOccupancy> hours, List<ForecastStep> forecast, this.capacity, this.threshold, this.now)
    : hoursObserved = hours.length,
      slots = _slots(hours, forecast),
      limit = capacity > 0 ? threshold * capacity : null {
    top = [
      1.0,
      capacity.toDouble(),
      for (final s in slots) ...[?s.occupancy?.toDouble(), ?s.p90, ?s.mean],
    ].reduce(math.max).ceilToDouble();
    crossing = limit == null
        ? null
        : firstCrossing([
            // An hour ahead the forecast has no step of (it starts after the hours shown) is left out.
            for (final s in slots)
              if (s.ahead && s.mean != null)
                ForecastStep(at: s.at, mean: s.mean!, p10: s.p10 ?? 0, p50: s.mean!, p90: s.p90 ?? s.mean!),
          ], limit!);
  }

  static List<_Slot> _slots(List<HourOccupancy> hours, List<ForecastStep> forecast) {
    final slots = <_Slot>[
      for (final h in hours)
        (
          at: h.hour,
          occupancy: h.occupancy,
          mean: h.predicted?.mean,
          p10: h.predicted?.p10,
          p90: h.predicted?.p90,
          lead: h.predicted?.leadHours,
          ahead: false,
        ),
    ];
    if (hours.isEmpty) return slots;
    final last = hours.last.hour;
    final ahead = {for (final s in forecast) if (s.at.isAfter(last)) s.at.difference(last).inHours: s};
    final span = ahead.keys.fold(0, math.max);
    for (var k = 1; k <= span; k++) {
      final s = ahead[k];
      final at = last.add(Duration(hours: k));
      slots.add((at: at, occupancy: null, mean: s?.mean, p10: s?.p10, p90: s?.p90, lead: k, ahead: true));
    }
    return slots;
  }

  final int hoursObserved;
  final List<_Slot> slots;
  final int capacity;
  final double threshold;

  /// The threshold in people, without a capacity none.
  final double? limit;

  /// The simulated clock of the run going on; null for a run that has
  /// ended, which has no now line.
  final DateTime? now;

  /// The top of the y axis.
  late final double top;

  /// The first hour ahead the forecast reaches the threshold.
  late final ({DateTime at, bool expected, int index})? crossing;

  static const left = 28.0;
  static const bottom = 22.0;
  static const topPad = 24.0;
  static const rightPad = 8.0;

  int get count => slots.length;

  double x(num index, Size size) =>
      left + (count <= 1 ? 0 : index / (count - 1)) * (size.width - left - rightPad);

  double y(double value, Size size) => size.height - bottom - value / top * (size.height - bottom - topPad);

  /// Where now is, in slots from the first: the clock, within the chart,
  /// else the last hour observed.
  double get nowIndex {
    final last = (hoursObserved - 1).toDouble();
    final clock = now;
    if (clock == null || slots.isEmpty) return last;
    return (clock.difference(slots.first.at).inMinutes / 60).clamp(last, (count - 1).toDouble());
  }

  /// The moment the now line stands for; the last hour observed for a run
  /// that has ended.
  DateTime get nowAt => now ?? slots[hoursObserved - 1].at;

  /// The points' radius: smaller when the hours are close together.
  double radius(Size size) =>
      (count <= 1 ? _pointRadius : (size.width - left - rightPad) / (count - 1) * 0.35).clamp(1.2, _pointRadius);

  /// The hour nearest x, or null outside the plot.
  int? hourAt(double dx, Size size) {
    if (count == 0 || dx < left - 4 || dx > size.width) return null;
    final f = (dx - left) / (size.width - left - rightPad) * (count - 1);
    return f.round().clamp(0, count - 1);
  }

  /// The hours observed at or above the threshold, and those predicted.
  int get observedOver =>
      limit == null ? 0 : slots.where((s) => s.occupancy != null && reachesThreshold(s.occupancy!, limit!)).length;
  int get predictedOver => limit == null ? 0 : slots.where((s) => s.mean != null && reachesThreshold(s.mean!, limit!)).length;

  String get summary {
    final observed = slots.take(hoursObserved);
    final now = observed.isEmpty ? 0 : observed.last.occupancy!;
    final peak = observed.isEmpty ? 0 : observed.map((s) => s.occupancy!).reduce(math.max);
    final ahead = slots.where((s) => s.ahead && s.mean != null).toList();
    final mean = ahead.isEmpty ? 0.0 : ahead.fold<double>(0, (sum, s) => sum + s.mean!) / ahead.length;
    final predicted = observed.where((s) => s.mean != null).length;
    final cross = crossing;
    final when = this.now == null ? 'at the end' : 'now';
    return 'Occupancy per hour: $now in care $when (${simDateTime(nowAt)}), at most $peak in the last $hoursObserved hours'
        '${capacity > 0 ? ', of a capacity of $capacity' : ''}'
        '${predicted == 0 ? '' : '; $predicted of them predicted before'}'
        '${ahead.isEmpty ? '' : '; ${expectedText(mean)} on average forecast over the next ${ahead.length}'}'
        '${limit == null ? '' : '; alarm threshold ${percentText(threshold)}, ${_n(limit!)}: $observedOver hours in care '
            'and $predictedOver predicted at or above it'}'
        '${cross == null ? '' : '; ${percentText(threshold)} ${cross.expected ? 'expected' : 'possible'} at ${simDateTime(cross.at)}'}';
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
    final plotBottom = size.height - _Geometry.bottom;
    final r = g.radius(size);
    final limit = g.limit;

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
      final t = g.slots[i].at;
      final midnight = t.hour == 0;
      if (!midnight && !(t.hour == 12 && perHour * 12 > 44)) continue;
      final x = g.x(i, size);
      canvas.drawLine(Offset(x, plotBottom), Offset(x, plotBottom + 4), grid);
      _text(canvas, midnight ? simDayLabel(t) : '12:00', Offset(x, plotBottom + 6), label, center: true);
    }

    // The capacity, a faint dotted line labelled above its right end; the
    // threshold, a red dashed one labelled under its left end.
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
    if (limit != null) {
      final y = g.y(limit, size);
      canvas.drawPath(
        _dash(Path()
          ..moveTo(_Geometry.left, y)
          ..lineTo(plotRight, y), on: 5, off: 3),
        _thresholdPaint,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: '${percentText(g.threshold)} · ${_n(limit)}',
          style: const TextStyle(color: Aityx.red, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(_Geometry.left + 4, y + 1));
    }

    // The predicted series: its band, then its mean, dashed, a hollow point
    // per hour, over every run of hours predicted. The forecast ahead goes
    // on from the hour observed last (from its prediction when there is
    // one, else from what was observed).
    final last = g.hoursObserved - 1;
    final runs = <List<int>>[];
    for (var i = 0; i < g.count; i++) {
      if (g.slots[i].mean == null) continue;
      if (runs.isEmpty || runs.last.last != i - 1) runs.add([]);
      runs.last.add(i);
    }
    Offset meanAt(int i) => Offset(g.x(i, size), g.y(g.slots[i].mean!, size));
    // The first run ahead goes on from the last hour observed, across the
    // hours the forecast has no step of when it starts later.
    List<int>? firstAhead;
    for (final run in runs) {
      if (run.first > last) {
        firstAhead = run;
        break;
      }
    }
    for (final run in runs) {
      final lead = identical(run, firstAhead)
          ? (g.slots[last].mean != null
              ? meanAt(last)
              : Offset(g.x(last, size), g.y(g.slots[last].occupancy!.toDouble(), size)))
          : null;
      final band = Path();
      if (lead != null) band.moveTo(lead.dx, lead.dy);
      for (final i in run) {
        final p = Offset(g.x(i, size), g.y(g.slots[i].p90 ?? g.slots[i].mean!, size));
        lead == null && i == run.first ? band.moveTo(p.dx, p.dy) : band.lineTo(p.dx, p.dy);
      }
      for (final i in run.reversed) {
        band.lineTo(g.x(i, size), g.y(g.slots[i].p10 ?? g.slots[i].mean!, size));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = _bandColor);
      final mean = Path();
      if (lead != null) mean.moveTo(lead.dx, lead.dy);
      for (final i in run) {
        final p = meanAt(i);
        lead == null && i == run.first ? mean.moveTo(p.dx, p.dy) : mean.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(_dash(mean), _predictedPaint);
    }
    for (final run in runs) {
      for (final i in run) {
        _predictedPoint(canvas, meanAt(i), r);
      }
    }

    // The hours observed, solid, a point per hour.
    final line = Path();
    final points = <Offset>[];
    for (var i = 0; i <= last; i++) {
      final p = Offset(g.x(i, size), g.y(g.slots[i].occupancy!.toDouble(), size));
      points.add(p);
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(line, _historyPaint);
    for (final p in points) {
      _historyPoint(canvas, p, r);
    }

    // Every point at or above the threshold: red, filled when observed,
    // hollow when predicted; ahead, a 90th percentile alone reaching it in
    // amber at its own height.
    if (limit != null) {
      for (var i = 0; i < g.count; i++) {
        final s = g.slots[i];
        if (s.mean != null && reachesThreshold(s.mean!, limit)) {
          _overPredicted(canvas, meanAt(i), r);
        } else if (s.ahead && s.p90 != null && reachesThreshold(s.p90!, limit)) {
          _overPredicted(canvas, Offset(g.x(i, size), g.y(s.p90!, size)), r * 0.6, color: Aityx.amber);
        }
      }
      for (var i = 0; i <= last; i++) {
        if (reachesThreshold(g.slots[i].occupancy!, limit)) _overObserved(canvas, points[i], r);
      }
    }

    // Now: a solid vertical line, labelled with the simulated time at its
    // top; none for a run that has ended (the card's header says when).
    if (g.now != null) {
      final nowX = g.x(g.nowIndex, size);
      canvas.drawLine(Offset(nowX, _Geometry.topPad - 4), Offset(nowX, plotBottom), _nowPaint);
      _pill(canvas, 'Now ${simDayTime(g.nowAt)}', Offset(nowX, 2), size, Aityx.fg, Aityx.bg2);
    }

    // The first hour ahead the forecast reaches the threshold: ringed and labelled.
    final cross = g.crossing;
    if (cross != null) {
      final i = g.slots.indexWhere((s) => s.ahead && s.at == cross.at);
      if (i >= 0) {
        final s = g.slots[i];
        final at = Offset(g.x(i, size), g.y(cross.expected ? s.mean! : s.p90!, size));
        final color = cross.expected ? Aityx.red : Aityx.amber;
        final text = '${percentText(g.threshold)} ${cross.expected ? 'expected' : 'possible'} at ${simDayTime(cross.at)}';
        // Just above the ring when there's room under the now label, else
        // just below it: never over the point it highlights. The ring last.
        final ring = r + 7;
        final top = crossingLabelTop(pointY: at.dy, ring: ring, pill: _pillHeight(text));
        _pill(canvas, text, Offset(at.dx, top), size, Aityx.fg0, color.withValues(alpha: 0.9));
        canvas.drawCircle(
          at,
          ring,
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // The hour under the pointer: a crosshair and its point, ringed with the card's colour.
    final h = hover;
    if (h != null && h < g.count) {
      final x = g.x(h, size);
      canvas.drawLine(Offset(x, _Geometry.topPad), Offset(x, plotBottom),
          Paint()
            ..color = Aityx.muted
            ..strokeWidth = 1);
      final s = g.slots[h];
      final value = s.occupancy?.toDouble() ?? s.mean;
      if (value != null) {
        final at = Offset(x, g.y(value, size));
        canvas.drawCircle(at, 6, Paint()..color = Aityx.bg1);
        canvas.drawCircle(at, 4, Paint()..color = s.occupancy != null ? Aityx.orange : _predictedColor);
      }
    }
  }

  static const _pillStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);

  /// The height of [text]'s pill.
  static double _pillHeight(String text) =>
      (TextPainter(text: TextSpan(text: text, style: _pillStyle), textDirection: TextDirection.ltr)..layout()).height + 4;

  /// [text] in a small pill centred on [at]'s x from its y, kept inside
  /// the chart.
  void _pill(Canvas canvas, String text, Offset at, Size size, Color ink, Color fill) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _pillStyle.copyWith(color: ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width + 10;
    final left = (at.dx - width / 2).clamp(0.0, math.max(0.0, size.width - width)).toDouble();
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, at.dy, width, painter.height + 4), const Radius.circular(4));
    canvas.drawRRect(rect, Paint()..color = fill);
    painter.paint(canvas, Offset(left + 5, at.dy + 2));
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style, {bool alignRight = false, bool center = false}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = alignRight ? at.dx - painter.width : (center ? at.dx - painter.width / 2 : at.dx);
    final dy = alignRight ? at.dy - painter.height / 2 : at.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.g.slots != g.slots ||
      old.g.capacity != g.capacity ||
      old.g.threshold != g.threshold ||
      old.g.now != g.now ||
      old.hover != hover;
}
