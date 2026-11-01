/// The simulation's calendar: day 1 is 2026-01-01, and its clock runs
/// from there, a simulated hour every real second unless set otherwise.
/// The app shows every simulated time as a date on it, "Jan 19, 2026
/// 09:40", never as a day number.
library;

/// The calendar's first moment, day 1 at 00:00.
final simEpoch = DateTime.utc(2026, 1, 1);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// The moment of [simTime] ("09:40") on [day] (from 1); null without
/// either, or for a time that isn't one.
DateTime? simMoment(int? day, String? simTime) {
  final parts = simTime?.split(':');
  final hours = parts?.length == 2 ? int.tryParse(parts![0]) : null;
  final minutes = parts?.length == 2 ? int.tryParse(parts![1]) : null;
  if (day == null || hours == null || minutes == null) return null;
  return simEpoch.add(Duration(days: day - 1, hours: hours, minutes: minutes));
}

/// "Jan 19, 2026".
String simDate(DateTime t) => '${_months[t.month - 1]} ${t.day}, ${t.year}';

/// "Jan 19, 2026 09:40".
String simDateTime(DateTime t) => '${simDate(t)} ${_two(t.hour)}:${_two(t.minute)}';

/// [date], `YYYY-MM-DD` as the API writes a day, as "Jan 19, 2026"; as it
/// is when it isn't one.
String simDateOf(String date) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  return parsed == null ? date : simDate(parsed);
}

/// "Jan 19": a day on a chart's axis.
String simDayLabel(DateTime t) => '${_months[t.month - 1]} ${t.day}';

/// When a record says it happened, "Jan 19, 2026 09:40"; just its time
/// without a day, and nothing without a time.
String simWhen(int? day, String? simTime) {
  final moment = simMoment(day, simTime);
  return moment != null ? simDateTime(moment) : (simTime ?? '');
}
