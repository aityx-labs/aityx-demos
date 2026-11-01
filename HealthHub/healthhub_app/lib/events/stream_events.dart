import 'dart:async';

import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../care_centers/care_center_screen.dart' show CareCenterLink;
import '../location/user_location_map.dart' show PersonLook;
import '../people/person_screen.dart';
import '../sim_clock.dart';
import '../theme.dart';
import '../triage/triage_card.dart' show levelColor;
import 'simulated_clock.dart';

/// Gives the latest records on the stream: the API's `GET /api/events`,
/// the moves and the admissions as one stream, or only one kind with
/// [type].
typedef EventsLoader = Future<StreamEvents> Function({int limit, StreamEventType? type});

/// Pauses the simulation (true) or resumes it, and says whether it is
/// paused now: the API's `POST /api/simulation/pause` and `/resume`.
typedef SimulationControl = Future<bool> Function(bool pause);

/// Sets the people a city, and says how many it is now: the API's
/// `POST /api/simulation/people`.
typedef PopulationControl = Future<int> Function(int perCity);

/// The people a city the events offer: the simulation takes up to 200.
const peopleChoices = [10, 20, 40, 80, 120, 160, 200];

/// The pills over the events, one at a time: every row ([all]), those at
/// the care center with the most people in care now ([busiest]), the
/// occupancy alarms raised, downgraded and cleared ([alarms]), the
/// admissions aityx triaged red or orange ([urgent]), every admission,
/// the people on their way to care ([onTheMove]), and the rows of an
/// acute or a chronic condition.
enum EventsFilter {
  all('All', 'Every event, newest first'),
  busiest('Busiest', 'The events at the care center with the most people in care now'),
  alarms('Alarms', 'The occupancy alarms raised, downgraded and cleared'),
  urgent('Urgent', "The admissions aityx's triage put first: red (Immediate) or orange (Very urgent)"),
  admissions('Admissions', 'The people admitted at a care center, with what they said'),
  onTheMove('On the move', 'The people who left home for a care center'),
  acute('Acute', 'The events of an acute condition, one that passes'),
  chronic('Chronic', 'The events of a chronic condition, one that stays');

  const EventsFilter(this.label, this.help);

  final String label;
  final String help;
}

/// One row of the stream: an [event] (a move or an admission) or an
/// [alarm] event, at its simulated [minutes] (-1 without a time).
typedef StreamRow = ({StreamEvent? event, OccupancyAlarm? alarm, int minutes});

/// The [events] and the [alarms] events as one stream, newest first by
/// simulated time, the kinds among each other. At the same minute, the
/// order the API gave the events (the order they were read, a record's
/// offset within its topic), and an alarm before them: its check read the
/// clock once they were in. A record without a time sorts last.
List<StreamRow> streamRows(List<StreamEvent> events, List<OccupancyAlarm> alarms) {
  final rows = <StreamRow>[
    for (final event in events) (event: event, alarm: null, minutes: SimNow.at(event.day, event.simTime)?.minutes ?? -1),
    for (final alarm in alarms) (event: null, alarm: alarm, minutes: alarm.now?.minutes ?? -1),
  ];
  final order = {for (final (i, row) in rows.indexed) row: i};
  rows.sort((a, b) {
    if (a.minutes != b.minutes) return b.minutes.compareTo(a.minutes);
    if ((a.alarm == null) != (b.alarm == null)) return a.alarm != null ? -1 : 1;
    // The sort isn't stable: the order given breaks the ties.
    return order[a]!.compareTo(order[b]!);
  });
  return rows;
}

/// Whether [row] is one [filter] keeps; [busiest] is the care center with
/// the most people in care now. At the busiest, an admission there, a
/// person going to, at or leaving it (not at home, where the record names
/// their usual hospital), and its alarms.
bool keeps(EventsFilter filter, StreamRow row, BusiestCareCenter? busiest) {
  final event = row.event;
  final alarm = row.alarm;
  return switch (filter) {
    EventsFilter.all => true,
    EventsFilter.busiest =>
      busiest != null &&
          (alarm?.careCenterId == busiest.id ||
              (event != null &&
                  event.hospitalId == busiest.id &&
                  (event.isAdmission || event.state != PersonState.home))),
    EventsFilter.alarms => alarm != null,
    EventsFilter.urgent => event?.isUrgent ?? false,
    EventsFilter.admissions => event?.isAdmission ?? false,
    EventsFilter.onTheMove => event != null && !event.isAdmission && event.state == PersonState.toHospital,
    EventsFilter.acute => event?.conditionType == ConditionType.acute,
    EventsFilter.chronic => event?.conditionType == ConditionType.chronic,
  };
}

/// The latest events on the Kafka stream as one stream, newest first by
/// simulated time, the kinds among each other: people's changes of state
/// (left home, arrived, going home, back home), their admissions at a care
/// center, marked in orange with what they said on arrival and aityx's
/// triage once it has one, and the occupancy alarms raised, downgraded and
/// cleared ([AlarmRow]); each a row of the same shape. One answer of the
/// API has them all, asked every 5 seconds while shown, like the map's
/// people; the alarms come with it (`GET /api/events` carries them): no
/// other poll. Nothing shows until the API says the simulation runs (dev
/// mode), and nothing in prod.
///
/// The header: the title, the simulated date and time beside it as the
/// map's tile has it ([SimClockText], "Paused" beside it while paused,
/// reported to [clock] too), the alarms now counted in red, and every
/// event the API read, and how many a second over the last minute. With
/// [simulation], a button pauses the simulation and resumes it; with
/// [population], beside it, how many people each city has, which anyone
/// signed in can change. Then, pinned, a banner per care center whose
/// occupancy datyx's forecast puts over its capacity ([OccupancyAlarm]):
/// red when the forecast mean goes over ("Over capacity expected"), amber
/// when only its 90th percentile does ("may exceed"). Then a row of pills
/// ([EventsFilter]), one at a time, All first, each with how many of the
/// rows read it keeps: "Busiest: Hospital X" keeps the events at the care
/// center with the most people in care now, which the API names. At most
/// [limit] rows show, of the [fetch] latest events asked.
///
/// Each row names its person, a link to their view, and the card invites
/// opening anyone's; an admission also shows datyx's prediction of the
/// person's hours of care over the next 30 days, asked once per admission
/// through [PersonOpener]. Each record says when it happened as a date on
/// the simulation's calendar.
class StreamEventsCard extends StatefulWidget {
  const StreamEventsCard({
    super.key,
    required this.events,
    this.simulation,
    this.population,
    this.clock,
    this.limit = 20,
    this.fetch = 60,
    this.alarmsLimit = 10,
  });

  final EventsLoader events;
  final SimulationControl? simulation;
  final PopulationControl? population;

  /// Where the card reports the simulated time it reads, and whether the
  /// simulation is paused, for the other headers that show it.
  final SimClock? clock;

  /// How many rows show at most, whatever the pill.
  final int limit;

  /// How many of the latest events are asked for: more than [limit], so a
  /// pill has rows to keep.
  final int fetch;

  /// How many of the latest alarm events are rows of the stream at most.
  final int alarmsLimit;

  @override
  State<StreamEventsCard> createState() => _StreamEventsCardState();
}

class _StreamEventsCardState extends State<StreamEventsCard> {
  StreamEvents _events = const StreamEvents(enabled: false);
  Timer? _poll;
  bool _asking = false;

  /// The pill chosen, All until another is.
  EventsFilter _filter = EventsFilter.all;

  /// While a pause or resume is under way, and what it said: shown until
  /// the next events say it too.
  bool _switching = false;
  bool? _pausedNow;

  bool get _paused => _pausedNow ?? _events.paused;

  /// While the people a city are being changed, and what the API said:
  /// shown until the next events say it too.
  bool _populating = false;
  int? _perCityNow;

  int? get _perCity => _perCityNow ?? _events.peoplePerCity;

  /// datyx's prediction for each admission shown, by event id, asked
  /// once; null when datyx can't say.
  final _predictions = <String, Future<Prediction?>>{};

  Future<Prediction?>? _predictionOf(StreamEvent event) {
    final eventId = event.eventId;
    final predict = PersonOpener.of(context)?.prediction;
    if (!event.isAdmission || eventId == null || predict == null) return null;
    return _predictions[eventId] ??= predict(
      event.id,
      run: runOf(eventId),
    ).then<Prediction?>((p) => p, onError: (Object _) => null);
  }

  Future<void> _switch() async {
    final control = widget.simulation;
    if (control == null || _switching) return;
    setState(() => _switching = true);
    try {
      final paused = await control(!_paused);
      if (mounted) setState(() => _pausedNow = paused);
      widget.clock?.report(null, paused: paused);
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException && error.status == 401
          ? 'Sign in to pause the simulation.'
          : 'The simulation can\'t be ${_paused ? 'resumed' : 'paused'}: '
                '${error is ApiException ? error.message : error}';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _populate(int perCity) async {
    final control = widget.population;
    if (control == null || _populating || perCity == _perCity) return;
    setState(() => _populating = true);
    try {
      final now = await control(perCity);
      if (mounted) setState(() => _perCityNow = now);
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException && error.status == 401
          ? 'Sign in to change the people of the simulation.'
          : 'The people can\'t be changed: ${error is ApiException ? error.message : error}';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _populating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // A slow answer isn't asked for again on top of itself.
    if (_asking) return;
    _asking = true;
    try {
      // One stream, every kind in it: no type.
      final events = await widget.events(limit: widget.fetch);
      if (mounted) {
        setState(() {
          _events = events;
          final read = {for (final event in _events.events) ?event.eventId};
          _predictions.removeWhere((eventId, _) => !read.contains(eventId));
          if (_pausedNow == _events.paused) _pausedNow = null;
          if (_perCityNow == _events.peoplePerCity) _perCityNow = null;
        });
        widget.clock?.report(events.clock, paused: _paused);
      }
    } catch (_) {
      // The API or Kafka may be down for a moment: keep what is shown.
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_events.enabled) return const SizedBox.shrink();
    final total = _events.total;
    final perSecond = _events.perSecond;
    final alarms = _events.alarms;
    final active = alarms.active;
    final busiest = _events.busiest;
    final stream = streamRows(_events.events, alarms.recent.take(widget.alarmsLimit).toList());
    // The busiest pill goes with the care center it names: All again once none is.
    final filter = _filter == EventsFilter.busiest && busiest == null ? EventsFilter.all : _filter;
    final kept = [for (final row in stream) if (keeps(filter, row, busiest)) row];
    return Card(
      key: const Key('stream-events'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.stream, color: Aityx.orange, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The title, the simulated date and time beside it as on the
                      // map's tile, the alarms and the total; under it when narrow.
                      Wrap(
                        spacing: 16,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Latest events', style: TextStyle(fontWeight: FontWeight.w700)),
                          if (_events.clock != null)
                            SimClockText(_events.clock, key: const Key('events-clock'), paused: _paused),
                          if (active.isNotEmpty) _AlarmsBadge(active.length),
                          if (total != null)
                            Tooltip(
                              message:
                                  'Every move and admission the API read since it started, those the events '
                                  'leave out too, and how many a second over the last minute, a moving average',
                              child: Text(
                                '${_thousands(total)} ${total == 1 ? 'event' : 'events'}'
                                '${perSecond == null ? '' : ' · ${perSecond.toStringAsFixed(1)}/s'}',
                                key: const Key('stream-events-total'),
                                style: const TextStyle(color: Aityx.muted, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        _paused
                            ? 'Paused: nobody moves, the clock stands'
                            : 'On Kafka, ${_events.topics.join(', ')}; every 5 seconds',
                        style: TextStyle(color: _paused ? Aityx.amber : Aityx.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // The simulation's controls, at the top, wrapping when narrow.
            if (widget.simulation != null || (widget.population != null && _perCity != null)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.population != null && _perCity != null)
                    _PeoplePicker(perCity: _perCity!, busy: _populating, onChanged: _populate),
                  if (widget.simulation != null)
                    OutlinedButton.icon(
                      key: const Key('simulation-pause'),
                      onPressed: _switching ? null : _switch,
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
                      label: Text(_paused ? 'Resume the simulation' : 'Pause the simulation'),
                    ),
                ],
              ),
            ],
            // The alarms now, pinned at the top; how far ahead, from the
            // clock above.
            for (final alarm in active) AlarmBanner(alarm, clock: _events.clock, stale: alarms.stale),
            // Out of date: when they were last read, and why.
            if (active.isNotEmpty && alarms.enabled && (alarms.stale || alarms.note != null))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Aityx.amber, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          'Occupancy alarms may be out of date',
                          if (_lastRead(active) case final read?) 'last checked ${simDateTime(read)}',
                          alarms.note ?? 'no check has read a forecast since',
                        ].join(' · '),
                        key: const Key('alarms-stale'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Aityx.amber, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (active.isEmpty && alarms.enabled && alarms.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Tooltip(
                  message: alarms.note!,
                  child: Text(
                    "Occupancy alarms: datyx can't forecast yet (${alarms.note})",
                    key: const Key('alarms-note'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Aityx.muted, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.touch_app_outlined, color: Aityx.orangeLight, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Open anyone by their name to see their data and statistics: their admissions, '
                    'aityx\'s triage, their days of care and datyx\'s prediction.',
                    key: Key('person-invite'),
                    style: TextStyle(color: Aityx.orangeLight, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // The pills, one at a time.
            _FilterPills(
              selected: filter,
              busiest: busiest,
              count: (pill) => pill == EventsFilter.all ? null : stream.where((row) => keeps(pill, row, busiest)).length,
              onSelected: (pill) => setState(() => _filter = pill),
            ),
            const SizedBox(height: 8),
            if (stream.isEmpty)
              const Text('Waiting for the first event…', style: TextStyle(color: Aityx.muted))
            else if (kept.isEmpty)
              Text(
                switch (filter) {
                  EventsFilter.busiest => 'Nothing at ${busiest!.name} among the latest events.',
                  _ => 'No ${filter.label.toLowerCase()} event among the latest.',
                },
                key: const Key('events-filter-empty'),
                style: const TextStyle(color: Aityx.muted),
              )
            else
              for (final row in kept.take(widget.limit))
                if (row.alarm case final alarm?)
                  AlarmRow(alarm)
                else
                  EventRow(row.event!, prediction: _predictionOf(row.event!)),
          ],
        ),
      ),
    );
  }
}

/// The pills over the events ([EventsFilter]), styled as the app's chips,
/// one [selected] at a time, each but All with how many of the rows read
/// it keeps ([count]). The busiest names its care center, "Busiest:
/// Hospital del Mar", and how many are in care there on hover; it shows
/// only once the API names one.
class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.selected, required this.busiest, required this.count, required this.onSelected});

  final EventsFilter selected;
  final BusiestCareCenter? busiest;
  final int? Function(EventsFilter pill) count;
  final ValueChanged<EventsFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget pill(EventsFilter filter) {
      final on = filter == selected;
      final n = count(filter);
      final label = filter == EventsFilter.busiest ? 'Busiest: ${busiest!.name}' : filter.label;
      final inCare = busiest?.inCare;
      return Tooltip(
        message: filter == EventsFilter.busiest
            ? '${busiest!.name}: the most people in care now${inCare == null ? '' : ', $inCare'}. Its events: '
                  'the people going to, at or leaving it, its admissions and its alarms'
            : filter.help,
        child: ChoiceChip(
          key: Key('events-filter-${filter.name}'),
          avatar: filter == EventsFilter.busiest
              ? Icon(Icons.local_fire_department, size: 16, color: on ? Aityx.orange : Aityx.muted)
              : null,
          // The busiest's count apart from its name: "Busiest: Hospital del Mar · 3".
          label: Text(
            n == null ? label : '$label${filter == EventsFilter.busiest ? ' ·' : ''} $n',
            style: const TextStyle(fontSize: 12),
          ),
          selected: on,
          onSelected: (_) => onSelected(filter),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selectedColor: Aityx.orange.withValues(alpha: 0.25),
          side: BorderSide(color: on ? Aityx.orange : Aityx.border),
        ),
      );
    }

    return Row(
      key: const Key('events-filter'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.filter_list, color: Aityx.muted, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final filter in EventsFilter.values)
                if (filter != EventsFilter.busiest || busiest != null) pill(filter),
            ],
          ),
        ),
      ],
    );
  }
}

/// How many people each city has, and a menu of [peopleChoices] to change
/// it; off while a change is under way.
class _PeoplePicker extends StatelessWidget {
  const _PeoplePicker({required this.perCity, required this.busy, required this.onChanged});

  final int perCity;
  final bool busy;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = {...peopleChoices, perCity}.toList()..sort();
    return Tooltip(
      message: 'How many simulated people live in each city; more people put more pressure on the care '
          'centers. New people join now; fewer, and the last to join leave.',
      child: PopupMenuButton<int>(
        key: const Key('simulation-people'),
        enabled: !busy,
        initialValue: perCity,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final n in choices)
            PopupMenuItem(value: n, key: Key('simulation-people-$n'), child: Text('$n people a city')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Aityx.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_outlined, size: 18, color: Aityx.muted),
              const SizedBox(width: 6),
              Text('$perCity people a city', style: const TextStyle(fontSize: 13)),
              const Icon(Icons.arrow_drop_down, size: 18, color: Aityx.muted),
            ],
          ),
        ),
      ),
    );
  }
}

String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

/// [n] with its thousands apart: "48,213".
String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');


/// When a record happened, "Jan 2, 2026 09:40".
String _when(StreamEvent event) => simWhen(event.day, event.simTime);

/// What happened, and the hospital it happened at or is headed to, a link
/// to its view, on one line: "Going to the hospital · Hospital del Mar".
class _What extends StatelessWidget {
  const _What(this.what, this.hospitalId, this.hospital, {required this.admission});

  final String what;
  final int? hospitalId;
  final String? hospital;
  final bool admission;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: admission ? Aityx.orangeLight : Aityx.muted, fontSize: 12);
    if (hospital == null) return Text(what, style: style);
    return Row(
      children: [
        Flexible(child: Text('$what · ', style: style)),
        Flexible(
          flex: 2,
          child: CareCenterLink(hospitalId, hospital!, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Where a record sits in its topic, "p0 · #67070".
String _where(StreamEvent event) => event.offset == null ? '' : 'p${event.partition ?? 0} · #${event.offset}';

/// One event, a move or an admission, always the same shape: a bar and a
/// faint tint in its colour, a mark (a dot in the person's state colour,
/// the map's, or the orange hospital of an admission), then two lines,
/// never more: who (a link to their view, with a heart monitor when
/// monitored, why on hover) with the condition, aityx's triage of an
/// admission once it has one ([_TriageMark]), and the simulated time;
/// what happened, at which hospital, with the record's partition and
/// offset. An admission's second line says which visit it is, in italics
/// as much of what the person said as fits (all of it on hover), and the
/// hours of care datyx expects of them over the next 30 days
/// ([prediction]).
class EventRow extends StatelessWidget {
  const EventRow(this.event, {super.key, this.prediction});

  final StreamEvent event;
  final Future<Prediction?>? prediction;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    final admission = event.isAdmission;
    final color = admission ? Aityx.orange : event.state.color;
    final who = [event.name ?? event.id, if (event.age != null) '${event.age}'].join(', ');
    final condition = [
      ?event.conditionName,
      if (event.conditionType != null) '(${event.conditionType!.label})',
    ].join(' ');
    final what = admission ? visitLabel(event) : event.state.labelAt(event.careCenterKind);
    // The hospital, a link to its view, where the record is about one.
    final hospital = admission || event.state == PersonState.toHospital || event.state == PersonState.atHospital
        ? event.hospitalName
        : null;
    return Container(
      key: Key(admission ? 'admission-${event.eventId ?? event.id}' : 'move-${event.id}-${event.offset}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      // One line each, whatever the text: every row is as tall as the next.
      child: DefaultTextStyle.merge(
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: admission
                  ? const Icon(Icons.local_hospital, color: Aityx.orange, size: 18)
                  : Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Who and the condition share what the time leaves, so
                      // the time ends at the row's right edge, over the offset,
                      // however long the name.
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Tooltip(
                                message: event.id,
                                // An admission's person is of its own run; a move's, of the run going on.
                                child: PersonLink(
                                  event.id,
                                  who,
                                  run: admission ? runOf(event.eventId) : null,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text(condition, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                      if (admission && event.triage != null) _TriageMark(event.triage!, eventId: event.eventId ?? event.id),
                      if (event.monitored)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Tooltip(
                            message: 'Monitored at home${event.monitoredFor == null ? '' : ': ${event.monitoredFor}'}',
                            child: const Icon(
                              Icons.monitor_heart_outlined,
                              key: Key('monitored'),
                              color: Aityx.orangeLight,
                              size: 14,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _when(event),
                        key: const Key('event-when'),
                        style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (admission && event.complaint != null) ...[
                        Flexible(flex: 2, child: _What(what, event.hospitalId, hospital, admission: true)),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: Tooltip(
                            message: event.complaint!,
                            child: Text(
                              '“${event.complaint}”',
                              style: muted.copyWith(fontStyle: FontStyle.italic, color: Aityx.fg),
                            ),
                          ),
                        ),
                      ] else
                        Expanded(child: _What(what, event.hospitalId, hospital, admission: admission)),
                      if (prediction != null) _ExpectedCare(prediction!, eventId: event.eventId ?? event.id),
                      const SizedBox(width: 8),
                      Text(_where(event), key: const Key('event-where'), style: muted.copyWith(fontFamily: 'monospace')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// aityx's triage of an admission, a small pill in the level's colour on
/// its first line: "Very urgent".
class _TriageMark extends StatelessWidget {
  const _TriageMark(this.level, {required this.eventId});

  final TriageLevel level;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    final color = levelColor(level);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: "aityx's triage at the desk: ${level.name}, ${level.label}",
        child: Container(
          key: Key('admission-triage-$eventId'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            border: Border.all(color: color.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(level.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// The hours of hospital care datyx expects of an admission's person over
/// the next 30 days, with a bed: "9 h expected in 30 days", the model on
/// hover. Nothing while it loads, nor when datyx can't say (no model, no
/// rows, not answering): the person's view says why.
class _ExpectedCare extends StatelessWidget {
  const _ExpectedCare(this.prediction, {required this.eventId});

  final Future<Prediction?> prediction;
  final String eventId;

  @override
  Widget build(BuildContext context) => FutureBuilder<Prediction?>(
    future: prediction,
    builder: (context, snapshot) {
      final p = snapshot.data;
      final predicted = p?.predicted;
      if (p == null || predicted == null) return const SizedBox.shrink();
      final model = [
        if (p.last != null) '${hoursOf(p.last!)} in the last 30 days',
        if (p.group != null) 'group ${p.group}',
        if (p.trainingRunId != null) 'training run ${p.trainingRunId}',
      ].join(' · ');
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Tooltip(
          message:
              "datyx's XGBoost prediction of the hours of hospital care over the next 30 days"
              '${model.isEmpty ? '' : '\n$model'}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bed_outlined, color: Aityx.orange, size: 14),
              const SizedBox(width: 4),
              Text(
                '${hoursOf(predicted)} expected in 30 days',
                key: Key('admission-care-$eventId'),
                style: const TextStyle(color: Aityx.fg, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Which visit of the course an admission is: "First visit", "Return
/// visit, the 2nd", "Last visit, the 3rd". A first visit needs no number.
String visitLabel(StreamEvent event) {
  final visit = event.visit;
  return visit == null ? 'Admission' : visitOf(visit, event.visitNumber);
}

/// A [visit] of the course, the [number]th: "Return visit, the 2nd".
String visitOf(VisitKind visit, int? number) {
  if (number == null || visit == VisitKind.first) return visit.label;
  return '${visit.label}, the ${_ordinal(number)}';
}

String _ordinal(int n) {
  final suffix = (n % 100 >= 11 && n % 100 <= 13)
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

/// A number of people as datyx forecasts it: whole when it is nearly
/// whole, "10", else to a tenth, "8.4".
String _people(double n) => (n - n.round()).abs() < 0.05 ? '${n.round()}' : n.toStringAsFixed(1);

/// How far ahead of [from] (a simulated moment) an alarm's overflow is:
/// "in 7 h", "in 6 h 20 min"; "now, since Jan 2, 2026 16:00" once [from] has
/// reached it. Without [from], the API's lead from the series' end.
String _lead(OccupancyAlarm alarm, SimNow? from) {
  final at = alarm.overflowAt;
  final fromMinutes = from?.minutes;
  if (at != null && fromMinutes != null) {
    final minutes = SimNow.ofHour(at)!.minutes! - fromMinutes;
    if (minutes <= 0) return 'now, since ${simDateTime(at)}';
    final (h, m) = (minutes ~/ 60, minutes % 60);
    return 'in ${[if (h > 0) '$h h', if (m > 0) '$m min'].join(' ')}';
  }
  final hours = alarm.leadHours;
  if (hours == null) return '';
  if (hours <= 0) return 'now';
  return 'in ${_people(hours)} h';
}

/// The latest simulated moment any of [active] was read at, as an hour.
DateTime? _lastRead(List<OccupancyAlarm> active) {
  int? newest;
  for (final alarm in active) {
    final minutes = alarm.now?.minutes;
    if (minutes != null && (newest == null || minutes > newest)) newest = minutes;
  }
  return newest == null ? null : simEpoch.add(Duration(minutes: newest - 24 * 60));
}

/// What the forecast says at the overflow: "10 in care of 8 beds (90%
/// range up to 12)" when expected; "7 expected in care of 8 beds, 90%
/// range up to 12" when possible.
String _forecastAt(OccupancyAlarm alarm) {
  final of = alarm.capacity == null ? '' : ' of ${alarm.capacity} ${alarm.unit ?? 'beds'}';
  final mean = alarm.mean;
  final p90 = alarm.p90;
  if (alarm.expected) {
    return [
      if (mean != null) '${_people(mean)} in care$of',
      if (p90 != null) '(90% range up to ${_people(p90)})',
    ].join(' ');
  }
  return [
    if (mean != null) '${_people(mean)} expected in care$of',
    if (p90 != null) '90% range up to ${_people(p90)}',
  ].join(', ');
}

/// The peak over the horizon: "peak 11 at Jun 3, 2026 18:00 (90% range
/// up to 13)"; null without one.
String? _peak(OccupancyAlarm alarm) {
  final mean = alarm.peakMean;
  final p90 = alarm.peakP90;
  if (mean == null && p90 == null) return null;
  return [
    'peak',
    if (mean != null) _people(mean) else 'up to ${_people(p90!)}',
    if (alarm.peakAt != null) 'at ${simDateTime(alarm.peakAt!)}',
    if (mean != null && p90 != null) '(90% range up to ${_people(p90)})',
  ].join(' ');
}

/// The colour of an alarm's level: red when the forecast mean goes over
/// the capacity, amber when only its 90th percentile does.
Color _levelColor(AlarmLevel? level) => level == AlarmLevel.expected ? Aityx.red : Aityx.amber;

/// The header's count of the alarms now, in red: "2 alarms".
class _AlarmsBadge extends StatelessWidget {
  const _AlarmsBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('alarms-badge'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Aityx.red, borderRadius: BorderRadius.circular(10)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warning_amber, color: Aityx.fg0, size: 14),
        const SizedBox(width: 4),
        Text(
          _count(count, 'alarm'),
          style: const TextStyle(color: Aityx.fg0, fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

/// A care center whose occupancy datyx's forecast puts over its capacity,
/// pinned at the top of the events, unmistakable: a banner with a strong
/// border and glow in the level's colour, a warning, and in bold "Over
/// capacity expected at Hospital X in 7 h" (red, the forecast mean over)
/// or "Over capacity possible: Hospital X may exceed its 8 beds in 7 h"
/// (amber, only the 90th percentile over), the care center a link to its
/// view; under it, the hour and what the forecast says there, "Jun 3,
/// 2026 16:00: 10 in care of 8 beds (90% range up to 12)", and the peak.
/// How far ahead is from [clock], the simulation's time now ("now, since
/// ..." once it is past); when it may be out of date ([stale], or the
/// alarm's own), "Not current: last checked Jun 3, 2026 09:00".
class AlarmBanner extends StatelessWidget {
  const AlarmBanner(this.alarm, {super.key, this.clock, this.stale = false});

  final OccupancyAlarm alarm;
  final SimNow? clock;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(alarm.level);
    final expected = alarm.expected;
    final lead = _lead(alarm, clock);
    final outOfDate = stale || alarm.stale;
    const bold = TextStyle(color: Aityx.fg0, fontSize: 15, fontWeight: FontWeight.w800);
    final capacity = alarm.capacity == null ? 'its capacity' : 'its ${alarm.capacity} ${alarm.unit ?? 'beds'}';
    final detail = [
      [
        if (alarm.overflowAt != null) simDateTime(alarm.overflowAt!),
        _forecastAt(alarm),
      ].where((part) => part.isNotEmpty).join(': '),
      ?_peak(alarm),
    ].where((part) => part.isNotEmpty).join(' · ');
    final model = [
      "datyx's DeepAR forecast of the people in care per hour",
      if (alarm.now != null) 'checked at ${simClockLabel(alarm.now!)}',
      if (alarm.trainingRun != null) 'training run ${alarm.trainingRun}',
    ].join(', ');
    return Tooltip(
      message:
          '${expected ? 'The forecast mean goes over the capacity' : "The forecast's 90th percentile goes over the capacity"}'
          '\n$model',
      child: Container(
        key: Key('alarm-banner-${alarm.careCenterId ?? alarm.careCenterName}'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14)],
        ),
        child: Row(
          children: [
            Icon(
              expected ? Icons.crisis_alert : Icons.warning_amber,
              key: Key('alarm-icon-${alarm.level?.name}'),
              color: color,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(expected ? 'Over capacity expected at ' : 'Over capacity possible: ', style: bold),
                      CareCenterLink(alarm.careCenterId, alarm.careCenterName, style: bold.copyWith(color: color)),
                      Text(
                        expected
                            ? (lead.isEmpty ? '' : ' $lead')
                            : ' may exceed $capacity${lead.isEmpty ? '' : ' $lead'}',
                        style: bold,
                      ),
                    ],
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      key: const Key('alarm-detail'),
                      style: const TextStyle(color: Aityx.fg, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (outOfDate) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Not current: ${alarm.now == null ? 'not checked again since' : 'last checked ${simClockLabel(alarm.now!)}'}',
                      key: const Key('alarm-stale'),
                      style: const TextStyle(color: Aityx.amber, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An alarm event of the stream (`healthhub.alarms`), a row of the same
/// shape as the others ([EventRow]): red when an alarm was raised, amber
/// when its level fell to possible, green when it cleared. The first line
/// says which, at which care center (a link to its view), and the
/// simulated time of the check; the second, the hour over the capacity and
/// what the forecast says there.
class AlarmRow extends StatelessWidget {
  const AlarmRow(this.alarm, {super.key});

  final OccupancyAlarm alarm;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    final (color, icon, title) = switch (alarm.kind) {
      AlarmKind.alarm => (
        Aityx.red,
        Icons.warning_amber,
        'Alarm: over capacity ${alarm.expected ? 'expected' : 'possible'}',
      ),
      AlarmKind.downgraded => (Aityx.amber, Icons.trending_down, 'Downgraded: over capacity possible'),
      AlarmKind.cleared => (Aityx.green, Icons.check_circle_outline, 'Cleared: no longer over capacity'),
    };
    final what = alarm.kind == AlarmKind.cleared
        ? "datyx's forecast stays within ${alarm.capacity == null ? 'the capacity' : '${alarm.capacity} ${alarm.unit ?? 'beds'}'}"
        : [
            // How far ahead of the check that raised it, then the hour.
            [
              _lead(alarm, alarm.now).startsWith('now') ? 'now' : _lead(alarm, alarm.now),
              if (alarm.overflowAt != null) simDateTime(alarm.overflowAt!),
            ].where((p) => p.isNotEmpty).join(', '),
            _forecastAt(alarm),
          ].where((p) => p.isNotEmpty).join(' · ');
    final now = alarm.now;
    final when = now == null ? '' : simClockLabel(now);
    final where = alarm.offset == null ? 'healthhub.alarms' : 'p${alarm.partition ?? 0} · #${alarm.offset}';
    return Container(
      key: Key('alarm-row-${alarm.id ?? '${alarm.careCenterId}-${now?.minutes}'}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: DefaultTextStyle.merge(
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        child: Row(
          children: [
            SizedBox(width: 20, child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$title · ',
                                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            Flexible(
                              child: CareCenterLink(
                                alarm.careCenterId,
                                alarm.careCenterName,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(when, style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(child: Text(what, style: muted.copyWith(color: Aityx.fg))),
                      const SizedBox(width: 8),
                      Text(where, style: muted.copyWith(fontFamily: 'monospace')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
