/// Occupancy alarms: every care center's occupancy per hour (the view
/// occupancy_hourly), observed and as datyx's DeepAR forecasts it (group
/// default), against a threshold of its capacity in the simulation (90%
/// unless HEALTHHUB_ALARM_THRESHOLD says), kept per care center of the run
/// going on; an event when a care center's level rises, falls or clears
/// (specs/occupancy-alarms.md).
///
/// datyx needs a user's token and the API keeps none: a request carrying
/// the caller's token sets a check off ([OccupancyAlarms.poke]), at most
/// once every [OccupancyAlarms.every], in the background, the token used
/// for that check's datyx calls only. Each care center of the run is
/// asked for by name (datyx answers every series still observed only for
/// the run whose series end the latest, which an older, longer run would
/// be), [datyxMaxSeries] a call.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' show min;

import 'care_centers.dart' show simulatedCapacity;
import 'simulation.dart' show simEpoch;

/// The topic every alarm event goes to, keyed by the care center's id.
const alarmsTopic = 'healthhub.alarms';

/// How often a check may run unless HEALTHHUB_ALARM_EVERY_MS says.
const alarmEveryDefault = Duration(seconds: 5);

/// HEALTHHUB_ALARM_EVERY_MS: real milliseconds between two checks at
/// least, [alarmEveryDefault] when empty, zero to turn the alarms off.
/// Throws a FormatException for anything but a whole number from 0.
Duration alarmEveryOf(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return alarmEveryDefault;
  final ms = int.tryParse(text);
  if (ms == null || ms < 0) throw FormatException('HEALTHHUB_ALARM_EVERY_MS must be a whole number from 0', raw);
  return Duration(milliseconds: ms);
}

/// The share of a care center's capacity whose reaching is an alarm unless
/// HEALTHHUB_ALARM_THRESHOLD says: 90%.
const alarmThresholdDefault = 0.9;

/// HEALTHHUB_ALARM_THRESHOLD: the share of a care center's capacity whose
/// reaching is an alarm, a number above 0 and at most 2 ("0.9", or "90%"),
/// [alarmThresholdDefault] when empty. Throws a FormatException for
/// anything else.
double alarmThresholdOf(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return alarmThresholdDefault;
  final percent = text.endsWith('%');
  final number = double.tryParse(percent ? text.substring(0, text.length - 1).trim() : text);
  final share = number == null ? null : (percent ? number / 100 : number);
  if (share == null || !share.isFinite || share <= 0 || share > 2) {
    throw FormatException('HEALTHHUB_ALARM_THRESHOLD must be a share of the capacity above 0 and at most 2, such as 0.9 or 90%', raw);
  }
  return share;
}

/// How bad it looks, against the threshold: the forecast's 90th
/// percentile reaches it at some hour ahead ([possible]), its mean does
/// ([expected]), or the occupancy observed now does ([actual]). Ordered:
/// actual is the worst.
enum AlarmLevel { possible, expected, actual }

AlarmLevel? alarmLevelNamed(Object? name) => switch (name) {
  'possible' => AlarmLevel.possible,
  'expected' => AlarmLevel.expected,
  'actual' => AlarmLevel.actual,
  _ => null,
};

/// Whether [value] reaches [limit]: at or above it, give or take the
/// rounding of a share times a capacity (0.9 × 10 is 9).
bool reaches(num value, double limit) => value >= limit - 1e-9;

/// The simulated [day] (from 1) as a date on the simulation's calendar
/// ([simEpoch]), YYYY-MM-DD.
String simDateOf(int day) => simEpoch.add(Duration(days: day - 1)).toIso8601String().substring(0, 10);

/// The simulated day (from 1) of [hour].
int simDayOfHour(DateTime hour) => hour.difference(simEpoch).inDays + 1;

/// The simulated clock of the newest of [moves] (the people feed's latest
/// moves): `{"day", "simTime", "date"}`, null before the first.
Map<String, Object?>? simNowOf(List<Map<String, Object?>> moves) {
  Map<String, Object?>? newest;
  for (final move in moves) {
    final turn = move['turn'];
    if (turn is num && (newest == null || turn > (newest['turn'] as num))) newest = move;
  }
  final day = newest?['day'];
  if (newest == null || day is! int) return null;
  return {'day': day, 'simTime': newest['simTime'], 'date': simDateOf(day)};
}

/// A forecast hour, `YYYY-MM-DDTHH:MM` as datyx answers it (no zone,
/// simulated time), as a UTC DateTime; null when it isn't one.
DateTime? _hourOf(Object? at) {
  if (at is! String || at.isEmpty) return null;
  final zoned = at.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(at) ? at : '${at}Z';
  return DateTime.tryParse(zoned)?.toUtc();
}

String _hourKey(DateTime hour) => hour.toUtc().toIso8601String().substring(0, 16);

/// One step of a forecast.
typedef ForecastStep = ({DateTime at, double mean, double p90});

/// What a care center's forecast says against its threshold.
class OccupancyReading {
  const OccupancyReading({
    this.level,
    this.overflowAt,
    this.leadHours,
    this.mean,
    this.p90,
    this.peak,
    this.end,
    this.horizonHours = 0,
  });

  /// None when neither the mean nor the 90th percentile ever reaches the
  /// threshold; never actual (the forecast doesn't observe).
  final AlarmLevel? level;

  /// The earliest hour at or above the threshold for [level] (the mean's
  /// for expected, the p90's for possible), the simulated hours from
  /// [end] to it, and the forecast's mean and p90 then; null without a
  /// level.
  final DateTime? overflowAt;
  final int? leadHours;
  final double? mean;
  final double? p90;

  /// The step with the highest mean (the highest p90 for possible), the
  /// earliest of equals; null without steps.
  final ForecastStep? peak;

  /// The series' end, where the forecast starts from: an hour before its
  /// first step (a step before, for another frequency).
  final DateTime? end;
  final int horizonHours;
}

/// The steps of datyx's [forecast] (each `{"at", "mean", "p10", "p50",
/// "p90"}`) that are steps, in time order, with their p10 (0 when missing).
List<({DateTime at, double mean, double p10, double p90})> forecastSteps(List<Object?> forecast) {
  final steps = <({DateTime at, double mean, double p10, double p90})>[];
  for (final step in forecast) {
    if (step is! Map) continue;
    final at = _hourOf(step['at']);
    final mean = step['mean'];
    final p10 = step['p10'];
    final p90 = step['p90'];
    if (at == null || mean is! num || p90 is! num) continue;
    steps.add((at: at, mean: mean.toDouble(), p10: p10 is num ? p10.toDouble() : 0, p90: p90.toDouble()));
  }
  return steps..sort((a, b) => a.at.compareTo(b.at));
}

/// Reads datyx's [forecast] (its steps, each `{"at", "mean", "p10",
/// "p50", "p90"}`) against [limit], the threshold in people (the
/// threshold's share of the capacity): expected when the mean reaches it
/// (at or above) at any step, else possible when the p90 does, else none.
OccupancyReading readForecast(List<Object?> forecast, double limit) {
  final steps = <ForecastStep>[for (final s in forecastSteps(forecast)) (at: s.at, mean: s.mean, p90: s.p90)];
  if (steps.isEmpty) return const OccupancyReading();
  final stride = steps.length > 1 ? steps[1].at.difference(steps[0].at) : const Duration(hours: 1);
  final end = steps.first.at.subtract(stride);
  ForecastStep? first(double Function(ForecastStep) of) {
    for (final step in steps) {
      if (reaches(of(step), limit)) return step;
    }
    return null;
  }

  final byMean = first((s) => s.mean);
  final byP90 = byMean == null ? first((s) => s.p90) : null;
  final level = byMean != null ? AlarmLevel.expected : (byP90 != null ? AlarmLevel.possible : null);
  final over = byMean ?? byP90;
  double measure(ForecastStep s) => level == AlarmLevel.possible ? s.p90 : s.mean;
  var peak = steps.first;
  for (final step in steps.skip(1)) {
    if (measure(step) > measure(peak)) peak = step;
  }
  return OccupancyReading(
    level: level,
    overflowAt: over?.at,
    leadHours: over?.at.difference(end).inHours,
    mean: over?.mean,
    p90: over?.p90,
    peak: peak,
    end: end,
    horizonHours: steps.length,
  );
}

/// What the alarms need of a care center: its name, kind and seed key
/// (its capacity in the simulation is drawn from the key and the kind).
typedef AlarmCareCenter = ({String name, String kind, String key});

/// An answer of datyx's: its status and its JSON body.
typedef DatyxAnswer = ({int status, Object? body});

/// How many series datyx scores in one call at most.
const datyxMaxSeries = 100;

/// How many checks in a row must read a care center lower before its
/// level falls (a downgrade, or cleared), unless [OccupancyAlarms] is
/// told otherwise: DeepAR draws its sample paths again at every call, so
/// a forecast at the threshold reaches it at one check and not at the
/// next; a rise is at once.
const alarmLowerAfter = 3;

/// What GET /api/alarms and GET /api/events say of the alarms.
class AlarmsSnapshot {
  const AlarmsSnapshot({
    this.enabled = false,
    this.everyMs = 0,
    this.checkedAt,
    this.status,
    this.note,
    this.stale = false,
    this.trainingRun,
    this.active = const [],
    this.recent = const [],
    this.signInRequired = false,
    this.threshold = alarmThresholdDefault,
  });

  /// Off: in prod, or with HEALTHHUB_ALARM_EVERY_MS at 0.
  static const off = AlarmsSnapshot();

  /// What a caller who isn't signed in sees of [alarms] once sign-in is
  /// on: whether they are on, nothing of datyx's forecast (as its route
  /// answers them 401), nor of datyx's words to whoever's check it was.
  factory AlarmsSnapshot.signIn(AlarmsSnapshot alarms) =>
      AlarmsSnapshot(enabled: alarms.enabled, everyMs: alarms.everyMs, signInRequired: true, threshold: alarms.threshold);

  final bool enabled;
  final int everyMs;

  /// The share of the capacity whose reaching is an alarm (0.9).
  final double threshold;

  /// The latest check that got an answer from datyx, real time, ISO 8601.
  final String? checkedAt;

  /// datyx's status at the latest check (502 when it didn't answer), and
  /// why there is no forecast (datyx's words), null with one.
  final int? status;
  final String? note;

  /// Whether the active alarms may be out of date: the latest check got
  /// no forecast, or none got one for a while
  /// ([OccupancyAlarms.staleAfter]).
  final bool stale;
  final Object? trainingRun;

  /// The care centers with a level, the worst first, then the soonest;
  /// each `stale` when it may be out of date (its own forecast missing
  /// from the latest answer, or [stale] for a forecast's level; for an
  /// actual one, no occupancy read for a while).
  final List<Map<String, Object?>> active;

  /// The latest events, newest first.
  final List<Map<String, Object?>> recent;

  /// Whether the caller must sign in to see them: [active] and [recent]
  /// are then empty.
  final bool signInRequired;
}

/// The occupancy of a run's care centers observed at its latest hour:
/// the hour (the series' end, null before any) and each care center's
/// people in care then (none: nobody).
typedef ObservedOccupancy = ({DateTime? end, Map<int, int> occupancy});

/// The alarms of the run going on, from the occupancy observed and
/// datyx's forecast of it against [threshold] of each care center's
/// capacity, checked when [poke]d, at most once every [every].
class OccupancyAlarms {
  OccupancyAlarms({
    required this.infer,
    required this.careCenters,
    required this.run,
    required this.clock,
    this.observed,
    this.paused,
    this.onEvent,
    this.onForecasts,
    this.every = alarmEveryDefault,
    this.lowerAfter = alarmLowerAfter,
    this.threshold = alarmThresholdDefault,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The occupancy of [run]'s care centers at its latest hour, for the
  /// actual level; throws when the database doesn't answer. None: no
  /// actual level.
  final Future<ObservedOccupancy> Function(String run)? observed;

  /// Each check's forecasts, from the datyx source the alarms read: per
  /// care center of [run], datyx's steps, and the training run that
  /// answered. To keep what was predicted of each hour (occupancy_forecast).
  final void Function(String run, Map<int, List<Object?>> forecasts, Object? trainingRun)? onForecasts;

  /// The share of each care center's capacity whose reaching is an alarm
  /// ([alarmThresholdDefault]).
  final double threshold;

  /// datyx's inference of [series] (each `{"run_id", "hospital_id"}`, at
  /// most [datyxMaxSeries]), asked with the token given for this one
  /// call; null when datyx doesn't answer. Its body carries the datyx
  /// data source it read (`sourceId`).
  final Future<DatyxAnswer?> Function(String? token, List<Map<String, String>> series) infer;

  /// The care centers of [run] (those with an admission in it, which
  /// occupancy_hourly has series of); throws when the database doesn't
  /// answer.
  final Future<Map<int, AlarmCareCenter>> Function(String run) careCenters;

  /// The run going on, null before the simulation starts.
  final String? Function() run;

  /// The simulated clock now (simNowOf), null before the first move.
  final Map<String, Object?>? Function() clock;

  /// Whether the simulation is paused: nothing moves, so once a check has
  /// read the run there is none until it resumes.
  final bool Function()? paused;

  /// Each event, as it fires: to be stored and published.
  final void Function(Map<String, Object?> event)? onEvent;

  final Duration every;

  /// How many checks in a row must read a care center lower before its
  /// level falls ([alarmLowerAfter]).
  final int lowerAfter;
  final DateTime Function() _now;

  /// How many events [recent] keeps.
  static const recentLimit = 100;

  bool get enabled => every > Duration.zero;

  /// How long after the latest check that got a forecast the alarms are
  /// said to be stale: four intervals, 30 s at least (two datyx calls of
  /// a few seconds each fit in an interval).
  Duration get staleAfter {
    final four = every * 4;
    return four > const Duration(seconds: 30) ? four : const Duration(seconds: 30);
  }

  String? _run;

  /// The run a check last read a forecast of.
  String? _read;
  final _active = <int, _Alarm>{};
  final _recent = ListQueue<Map<String, Object?>>();
  final _centers = <int, AlarmCareCenter>{};
  DateTime? _lastStart;
  DateTime? _lastRead;

  /// The latest check that read the occupancy observed.
  DateTime? _lastObserved;
  bool _checking = false;
  int _events = 0;
  String? _checkedAt;
  int? _status;
  String? _note;
  Object? _trainingRun;

  /// The datyx data source the alarms read: the first that answered. A
  /// check whose caller's datyx answers from another (their own source of
  /// a database of that name) is ignored, so one caller's datyx can't
  /// change what everyone sees.
  Object? _sourceId;

  /// Whether a check is under way.
  bool get checking => _checking;

  /// Whether a forecast from datyx data source [sourceId] is the one the
  /// alarms read: theirs, or any before they have one.
  bool acceptsSource(Object? sourceId) => _sourceId == null || _sourceId == sourceId;

  /// Sets a check off in the background, with [token] for its datyx calls
  /// only, unless the alarms are off, the simulation hasn't started, one
  /// is under way, one started less than [every] ago, or the simulation
  /// is paused and a check has read this run already. Returns at once:
  /// true when it set one off.
  bool poke(String? token) {
    if (!enabled || _checking) return false;
    final current = run();
    if (current == null || current.isEmpty) return false;
    if ((paused?.call() ?? false) && _read == current) return false;
    final now = _now();
    final last = _lastStart;
    if (last != null && now.difference(last) < every) return false;
    _lastStart = now;
    _checking = true;
    unawaited(check(token).whenComplete(() => _checking = false));
    return true;
  }

  /// One check: datyx's forecast of each care center of the run, asked
  /// with [token] by name, [datyxMaxSeries] a call, against each one's
  /// capacity. The token goes to [infer] and nowhere else. Never throws:
  /// a failure is logged.
  Future<void> check(String? token) async {
    final current = run();
    if (current == null || current.isEmpty) return;
    try {
      final Map<int, AlarmCareCenter> centers;
      try {
        centers = await careCenters(current);
      } catch (error) {
        stderr.writeln('occupancy alarms: care centers: $error');
        _status = 503;
        _note = 'the database is not answering';
        return;
      }
      ObservedOccupancy? seen;
      try {
        seen = await observed?.call(current);
      } catch (error) {
        stderr.writeln('occupancy alarms: occupancy observed: $error');
      }
      final ids = centers.keys.toList()..sort();
      final forecasts = <int, List<Object?>>{};
      ({int status, String note})? failure;
      Object? source;
      Object? trainingRun;
      for (var from = 0; from < ids.length; from += datyxMaxSeries) {
        final chunk = ids.sublist(from, min(ids.length, from + datyxMaxSeries));
        final answer = await infer(token, [
          for (final id in chunk) {'run_id': current, 'hospital_id': '$id'},
        ]);
        if (answer == null) {
          failure = (status: 502, note: 'the datyx API is not answering');
          break;
        }
        final body = answer.body;
        if (answer.status != 200 || body is! Map) {
          failure = (
            status: answer.status,
            note: body is Map ? '${body['error'] ?? body['message'] ?? 'datyx answered ${answer.status}'}' : 'datyx answered ${answer.status}',
          );
          break;
        }
        // Another data source than the one the alarms read: not this caller's to decide.
        final answered = body['sourceId'];
        if ((_sourceId != null && answered != _sourceId) || (from > 0 && answered != source)) {
          stderr.writeln('occupancy alarms: datyx answered from data source $answered, not ${_sourceId ?? source}: ignored');
          return;
        }
        source = answered;
        trainingRun = body['runId'];
        for (final prediction in body['predictions'] as List? ?? const []) {
          if (prediction is! Map || prediction['series'] is! Map) continue;
          final series = prediction['series'] as Map;
          if ('${series['run_id']}' != current) continue;
          final id = int.tryParse('${series['hospital_id']}');
          final forecast = prediction['forecast'];
          // A series datyx has no forecast of (no rows yet) is left as it was.
          if (id == null || forecast is! List || forecast.isEmpty) continue;
          forecasts[id] = forecast;
        }
      }
      _apply(
        current,
        centers,
        forecasts,
        failure,
        source: source,
        trainingRun: trainingRun,
        answered: ids.isEmpty || forecasts.isNotEmpty || failure == null,
        observed: seen,
      );
    } catch (error) {
      stderr.writeln('occupancy alarms: $error');
    }
  }

  void _apply(
    String current,
    Map<int, AlarmCareCenter> centers,
    Map<int, List<Object?>> forecasts,
    ({int status, String note})? failure, {
    Object? source,
    Object? trainingRun,
    required bool answered,
    ObservedOccupancy? observed,
  }) {
    // The run moved on while datyx answered: the next check reads the new one.
    if (run() != current) return;
    if (_run != current) {
      _run = current;
      _active.clear();
    }
    _status = failure?.status ?? 200;
    _note = failure?.note;
    final checkedAt = _now().toUtc().toIso8601String();
    _centers.addAll(centers);
    if (answered) {
      _sourceId ??= source;
      _read = current;
      _lastRead = _now();
      _checkedAt = checkedAt;
      _trainingRun = trainingRun ?? _trainingRun;
      if (forecasts.isNotEmpty) {
        try {
          onForecasts?.call(current, forecasts, trainingRun);
        } catch (error) {
          stderr.writeln('occupancy alarms: forecasts: $error');
        }
      }
    }
    final seenAt = observed?.end;
    if (seenAt != null) _lastObserved = _now();
    final now = clock();
    // Without a forecast (datyx refused or didn't answer) only the occupancy observed is read.
    final ids = {...forecasts.keys, ..._active.keys, if (seenAt != null) ...observed!.occupancy.keys};
    for (final id in ids.toList()..sort()) {
      final center = _centers[id];
      final before = _active[id];
      final forecast = answered ? forecasts[id] : null;
      if (center == null) continue;
      final capacity = simulatedCapacity(center.key, center.kind);
      final limit = threshold * capacity.places;
      // Nobody in care at the latest hour has no row: zero, once the hour is known.
      final occupancy = seenAt == null ? null : observed!.occupancy[id] ?? 0;
      final actual = occupancy != null && reaches(occupancy, limit);
      // No forecast of it this time (datyx left it out, or failed) and not
      // reached now: kept, marked stale, never cleared.
      if (forecast == null && !actual) {
        if (before != null) before.json = {...before.json, 'stale': true};
        continue;
      }
      final reading = forecast == null ? const OccupancyReading() : readForecast(forecast, limit);
      final level = actual ? AlarmLevel.actual : reading.level;
      final fields = _fieldsOf(
        current,
        id,
        center,
        capacity,
        reading,
        trainingRun ?? _trainingRun,
        now,
        level: level,
        threshold: threshold,
        occupancy: occupancy,
        observedAt: seenAt,
      );
      if (before == null) {
        if (level != null) _raise(id, null, level, fields, checkedAt);
      } else if (level != null && level.index > before.level.index) {
        _raise(id, before, level, fields, checkedAt);
      } else if (level == before.level) {
        // The same level, other numbers: updated, no event.
        before
          ..lower = 0
          ..fallTo = null
          ..json = {...fields, 'previous': before.json['previous'], 'since': before.since, 'checkedAt': checkedAt, 'stale': false};
      } else {
        // Lower: it falls only after [lowerAfter] checks in a row read it
        // lower, to the highest of what they read.
        before.lower++;
        final fallTo = before.fallTo;
        if (fallTo == null || _rank(level) >= _rank(fallTo.level)) before.fallTo = (level: level, fields: fields);
        if (before.lower < lowerAfter) {
          before.json = {...before.json, 'checkedAt': checkedAt, 'stale': false};
        } else {
          final fall = before.fallTo!;
          _fire(fall.level == null ? 'cleared' : 'downgraded', current, id, fall.fields, before.level, checkedAt);
          if (fall.level == null) {
            _active.remove(id);
          } else {
            _active[id] = _Alarm(fall.level!, checkedAt, {
              ...fall.fields,
              'previous': before.level.name,
              'since': checkedAt,
              'checkedAt': checkedAt,
              'stale': false,
            });
          }
        }
      }
    }
  }

  static int _rank(AlarmLevel? level) => level == null ? -1 : level.index;

  void _raise(int id, _Alarm? before, AlarmLevel level, Map<String, Object?> fields, String checkedAt) {
    _fire('alarm', _run!, id, fields, before?.level, checkedAt);
    _active[id] = _Alarm(level, checkedAt, {
      ...fields,
      'previous': before?.level.name,
      'since': checkedAt,
      'checkedAt': checkedAt,
      'stale': false,
    });
  }

  /// What an event and an active alarm say of a care center at [level]:
  /// the occupancy observed at [observedAt] and the forecast's [reading]
  /// against [threshold] of its capacity. For actual, the hour reached is
  /// the one observed, 0 hours ahead of the series' end.
  static Map<String, Object?> _fieldsOf(
    String current,
    int id,
    AlarmCareCenter center,
    ({int places, String unit}) capacity,
    OccupancyReading reading,
    Object? trainingRun,
    Map<String, Object?>? now, {
    required AlarmLevel? level,
    required double threshold,
    int? occupancy,
    DateTime? observedAt,
  }) {
    final actual = level == AlarmLevel.actual;
    final overflowAt = actual ? observedAt : reading.overflowAt;
    final clockHour = _clockHour(now);
    double? share(num? people) => people == null || capacity.places == 0 ? null : (people / capacity.places * 1000).round() / 1000;
    return {
      'run': current,
      'hospitalId': id,
      'hospitalName': center.name,
      'careCenterKind': center.kind,
      'level': level?.name,
      'threshold': threshold,
      'thresholdPlaces': (threshold * capacity.places * 100).round() / 100,
      'occupancy': occupancy,
      'occupancyShare': share(occupancy),
      'observedAt': observedAt == null ? null : _hourKey(observedAt),
      'overflowAt': overflowAt == null ? null : _hourKey(overflowAt),
      'overflowDay': overflowAt == null ? null : simDayOfHour(overflowAt),
      'leadHours': actual ? 0 : reading.leadHours,
      // From the simulated clock at the check, which is past the series' end.
      'leadFromNowHours': overflowAt == null || clockHour == null
          ? null
          : (overflowAt.difference(clockHour).inMinutes / 6).round() / 10,
      'mean': actual ? null : reading.mean,
      'p90': actual ? null : reading.p90,
      'peak': reading.peak == null
          ? null
          : {
              'at': _hourKey(reading.peak!.at),
              'day': simDayOfHour(reading.peak!.at),
              'mean': reading.peak!.mean,
              'p90': reading.peak!.p90,
            },
      'capacity': capacity.places,
      'unit': capacity.unit,
      'end': reading.end == null ? (observedAt == null ? null : _hourKey(observedAt)) : _hourKey(reading.end!),
      'horizonHours': reading.horizonHours,
      'trainingRun': trainingRun,
      'now': now,
    };
  }

  void _fire(String kind, String current, int id, Map<String, Object?> fields, AlarmLevel? previous, String raisedAt) {
    final event = {
      'kind': kind,
      'id': '$current-$id-${++_events}',
      ...fields,
      'previous': previous?.name,
      'raisedAt': raisedAt,
    };
    _recent.addFirst(event);
    while (_recent.length > recentLimit) {
      _recent.removeLast();
    }
    try {
      onEvent?.call(event);
    } catch (error) {
      stderr.writeln('occupancy alarms: ${event['id']}: $error');
    }
  }

  /// The alarms as GET /api/alarms answers them: the active, the worst
  /// first, then the soonest overflow, then by care center; the recent
  /// events, newest first.
  AlarmsSnapshot get snapshot {
    if (!enabled) return AlarmsSnapshot(threshold: threshold);
    final last = _lastRead;
    final stale = _status != 200 || last == null || _now().difference(last) > staleAfter;
    final seen = _lastObserved;
    final unseen = seen == null || _now().difference(seen) > staleAfter;
    final active = _active.values.toList()
      ..sort((a, b) {
        final byLevel = b.level.index.compareTo(a.level.index);
        if (byLevel != 0) return byLevel;
        final byOverflow = '${a.json['overflowAt']}'.compareTo('${b.json['overflowAt']}');
        if (byOverflow != 0) return byOverflow;
        return (a.json['hospitalId'] as int).compareTo(b.json['hospitalId'] as int);
      });
    return AlarmsSnapshot(
      enabled: true,
      everyMs: every.inMilliseconds,
      checkedAt: _checkedAt,
      status: _status,
      note: _note,
      stale: stale && (_status != null || last != null),
      trainingRun: _trainingRun,
      threshold: threshold,
      active: [
        // An actual level is the database's, not datyx's: stale only when no occupancy was read for a while.
        for (final alarm in active)
          {...alarm.json, 'stale': alarm.json['stale'] == true || (alarm.level == AlarmLevel.actual ? unseen : stale)},
      ],
      recent: _recent.toList(),
    );
  }
}

/// The simulated clock [now] (`{"day", "simTime"}`) as an hour of the
/// forecast's calendar; null without one.
DateTime? _clockHour(Map<String, Object?>? now) {
  final day = now?['day'];
  if (day is! int) return null;
  final parts = '${now?['simTime'] ?? ''}'.split(':');
  final hours = parts.length == 2 ? int.tryParse(parts[0]) ?? 0 : 0;
  final minutes = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;
  return simEpoch.add(Duration(days: day - 1, hours: hours, minutes: minutes));
}

class _Alarm {
  _Alarm(this.level, this.since, this.json);

  final AlarmLevel level;
  final String since;
  Map<String, Object?> json;

  /// The checks in a row that read it lower, and the highest they read.
  int lower = 0;
  ({AlarmLevel? level, Map<String, Object?> fields})? fallTo;
}

/// [event] as its Kafka record on [alarmsTopic]: keyed by the care
/// center's id, as text.
Map<String, Object?> alarmRecord(Map<String, Object?> event) => {'key': '${event['hospitalId']}', 'value': event};

/// A queue that does [action] to each item in turn, in the background,
/// retrying a failure after [retryAfter] until it succeeds, unless
/// [isPermanent] says a retry can't help (the item is dropped and
/// logged). At most [limit] wait; beyond that the oldest is dropped and
/// logged. For the alarm events' storing and publishing: a failure never
/// stops the API, nor holds the checks up.
class RetryQueue<T> {
  RetryQueue(
    this.name,
    this._action, {
    this.retryAfter = const Duration(seconds: 3),
    this.limit = 1000,
    bool Function(Object error)? isPermanent,
    String Function(T item)? describe,
  }) : _isPermanent = isPermanent ?? _never,
       _describe = describe ?? ((item) => '$item');

  /// What the queue does, for the logs.
  final String name;
  final Future<void> Function(T item) _action;
  final bool Function(Object error) _isPermanent;
  final String Function(T item) _describe;
  final Duration retryAfter;
  final int limit;

  final _queue = ListQueue<T>();
  Completer<void>? _draining;
  bool _stopped = false;

  int get pending => _queue.length;

  /// Queues [item]; returns at once.
  void add(T item) {
    if (_stopped) return;
    _queue.addLast(item);
    if (_queue.length > limit) stderr.writeln('$name: dropped ${_describe(_queue.removeFirst())}, too many waiting');
    if (_draining == null) unawaited(_drain());
  }

  /// Completes once every queued item is done.
  Future<void> get idle => _draining?.future ?? Future<void>.value();

  Future<void> _drain() async {
    final draining = _draining = Completer<void>();
    var failures = 0;
    while (_queue.isNotEmpty && !_stopped) {
      final item = _queue.first;
      try {
        await _action(item);
        if (_queue.isNotEmpty && identical(_queue.first, item)) _queue.removeFirst();
        if (failures > 0) stdout.writeln('$name: going again after $failures failures');
        failures = 0;
      } catch (error) {
        if (_isPermanent(error)) {
          if (_queue.isNotEmpty && identical(_queue.first, item)) _queue.removeFirst();
          stderr.writeln('$name: dropped ${_describe(item)}: $error');
          continue;
        }
        if (failures++ % 10 == 0) {
          stderr.writeln('$name: ${_describe(item)} failed, ${_queue.length} waiting, retrying: $error');
        }
        await Future<void>.delayed(retryAfter);
      }
    }
    _draining = null;
    draining.complete();
  }

  /// Stops; logs what is still waiting, which is lost.
  void stop() {
    _stopped = true;
    if (_queue.isNotEmpty) stderr.writeln('$name: stopping with ${_queue.length} waiting');
  }
}

bool _never(Object error) => false;
