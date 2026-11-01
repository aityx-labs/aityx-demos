import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../theme.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The simulated date and time, "Day 154 · Wed 3 Jun 2026, 16:00": the
/// day (day 1 is 2026-01-01), the date of that day and the time; without
/// a time, only the day and date.
String simClockLabel(SimNow now) {
  final date = now.calendarDate;
  final day = now.day;
  return [
    if (day != null) 'Day $day',
    if (date != null)
      '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}'
      '${now.simTime == null ? '' : ', ${now.simTime}'}'
    else
      ?now.simTime,
  ].join(' · ');
}

/// The simulation's clock as the pages read it, for the headers that show
/// it: the newest simulated moment any of them read, and whether the
/// simulation is paused. The map and the events each read it on their own
/// poll and [report] it here.
class SimClock extends ChangeNotifier {
  SimNow? _now;
  bool _paused = false;

  SimNow? get now => _now;
  bool get paused => _paused;

  /// A reading: [now] moves the clock forward (an older one, read by a
  /// slower poll, doesn't move it back), or back by more than an hour, a
  /// new run started from its beginning; [paused] when the reader knows.
  void report(SimNow? now, {bool? paused}) {
    var changed = false;
    final minutes = now?.minutes;
    final current = _now?.minutes;
    if (minutes != null && (current == null || minutes > current || current - minutes > 60)) {
      _now = now;
      changed = true;
    }
    if (paused != null && paused != _paused) {
      _paused = paused;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}

/// Owns a [SimClock] for the page [builder] makes, while it is shown.
class SimClockScope extends StatefulWidget {
  const SimClockScope({super.key, required this.builder});

  final Widget Function(BuildContext context, SimClock clock) builder;

  @override
  State<SimClockScope> createState() => _SimClockScopeState();
}

class _SimClockScopeState extends State<SimClockScope> {
  final _clock = SimClock();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _clock);
}

/// The simulated date and time, prominent, with a clock: "Day 154 · Wed 3
/// Jun 2026, 16:00", and "Paused" beside it, in amber, while the
/// simulation is paused. Nothing before the first reading.
class SimClockText extends StatelessWidget {
  const SimClockText(this.now, {super.key, this.paused = false, this.size = 15});

  final SimNow? now;
  final bool paused;
  final double size;

  /// [clock]'s reading, following it.
  static Widget following(SimClock clock, {Key? key, double size = 15}) => ListenableBuilder(
    listenable: clock,
    builder: (context, _) => SimClockText(clock.now, key: key, paused: clock.paused, size: size),
  );

  @override
  Widget build(BuildContext context) {
    final now = this.now;
    if (now == null) return const SizedBox.shrink();
    return Tooltip(
      message: 'The simulated date and time: day 1 is 1 Jan 2026, and a simulated hour passes about every second',
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, color: paused ? Aityx.amber : Aityx.orange, size: size + 3),
              const SizedBox(width: 6),
              // Wraps rather than overflows where there's no room.
              Flexible(
                child: Text(
                  simClockLabel(now),
                  key: const Key('sim-clock-label'),
                  style: TextStyle(
                    color: Aityx.fg0,
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (paused)
            Container(
              key: const Key('sim-clock-paused'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Aityx.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Aityx.amber),
              ),
              child: Text(
                'Paused',
                style: TextStyle(color: Aityx.amber, fontSize: size - 3, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
