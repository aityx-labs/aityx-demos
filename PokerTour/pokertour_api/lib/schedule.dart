/// When the leaderboard plays on its own: at fixed hours of the day,
/// UTC (POKERTOUR_SCHEDULE_HOURS, `0,6,12,18` by default: four times a
/// day, every six hours). On AWS an EventBridge schedule fires the runner
/// at those hours; on a laptop the server keeps a timer. The API tells the
/// app when the next one is.
library;

class Schedule {
  const Schedule(this.hoursUtc);

  /// POKERTOUR_SCHEDULE_HOURS: hours of the day, comma separated (UTC);
  /// `off` for none; unset for the default.
  factory Schedule.fromEnvironment(Map<String, String> env) {
    final text = (env['POKERTOUR_SCHEDULE_HOURS'] ?? '').trim();
    if (text.isEmpty) return defaultSchedule;
    if (text.toLowerCase() == 'off') return const Schedule([]);
    final hours = text
        .split(',')
        .map((h) => int.tryParse(h.trim()))
        .whereType<int>()
        .where((h) => h >= 0 && h < 24)
        .toSet()
        .toList()
      ..sort();
    return Schedule(hours);
  }

  static const defaultSchedule = Schedule([0, 6, 12, 18]);

  /// The hours of the day, UTC, sorted.
  final List<int> hoursUtc;

  bool get enabled => hoursUtc.isNotEmpty;

  /// The next scheduled time after [now]; null when there is none.
  DateTime? next(DateTime now) {
    if (hoursUtc.isEmpty) return null;
    final utc = now.toUtc();
    final today = DateTime.utc(utc.year, utc.month, utc.day);
    for (final h in hoursUtc) {
      final at = today.add(Duration(hours: h));
      if (at.isAfter(utc)) return at;
    }
    return today.add(Duration(days: 1, hours: hoursUtc.first));
  }

  /// As an EventBridge cron expression: `cron(0 0,6,12,18 * * ? *)`.
  String get cron => 'cron(0 ${hoursUtc.join(',')} * * ? *)';

  Map<String, Object?> toJson(DateTime now) => {'hoursUtc': hoursUtc, 'nextRunAt': next(now)?.toIso8601String()};
}
