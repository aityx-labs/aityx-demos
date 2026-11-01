import 'dart:async';

import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../care_centers/care_center_screen.dart' show CareCenterLink;
import '../location/user_location_map.dart' show PersonLook;
import '../people/person_screen.dart';
import '../theme.dart';

/// Gives the latest records on the stream: the API's `GET /api/events`,
/// only moves or only admissions with [type].
typedef EventsLoader = Future<StreamEvents> Function({int limit, StreamEventType? type});

/// Pauses the simulation (true) or resumes it, and says whether it is
/// paused now: the API's `POST /api/simulation/pause` and `/resume`.
typedef SimulationControl = Future<bool> Function(bool pause);

/// The latest events on the Kafka stream, newest first: people's moves and
/// their admissions at a hospital, each a row of the same shape, an
/// admission marked in orange with what they said on arrival. Someone at
/// home is an event only when monitored, the high-risk (the API leaves the
/// others out); the header counts every event the API read, and how many a
/// second over the last minute. Asked every 5 seconds while shown, like
/// the map's people. Nothing shows until the API says the simulation runs
/// (dev mode), and nothing in prod. Each row names its person, a link to
/// their view, and the card invites opening anyone's; an admission also
/// shows datyx's prediction of the person's hours of care over the next 30
/// days, asked once per admission through [PersonOpener]. With
/// [simulation], a button at the top pauses the simulation and resumes it;
/// under it, a chip per condition keeps only its events.
///
/// Moves and admissions are asked for apart: every person moves every
/// second, so the latest [limit] records of the stream are nearly always
/// all moves and an admission would scroll out before it is ever seen.
class StreamEventsCard extends StatefulWidget {
  const StreamEventsCard({
    super.key,
    required this.events,
    this.simulation,
    this.limit = 12,
    this.admissionsLimit = 8,
  });

  final EventsLoader events;
  final SimulationControl? simulation;

  /// How many moves and how many admissions are shown at most.
  final int limit;
  final int admissionsLimit;

  @override
  State<StreamEventsCard> createState() => _StreamEventsCardState();
}

class _StreamEventsCardState extends State<StreamEventsCard> {
  StreamEvents _events = const StreamEvents(enabled: false);
  Timer? _poll;
  bool _asking = false;

  /// While a pause or resume is under way, and what it said: shown until
  /// the next events say it too.
  bool _switching = false;
  bool? _pausedNow;

  bool get _paused => _pausedNow ?? _events.paused;

  /// The conditions whose events are shown; all of them when empty. Kept
  /// across reads, even while a condition has no event to show.
  final Set<String> _conditions = {};

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

  bool _shown(StreamEvent event) => _conditions.isEmpty || _conditions.contains(event.conditionName);

  Future<void> _switch() async {
    final control = widget.simulation;
    if (control == null || _switching) return;
    setState(() => _switching = true);
    try {
      final paused = await control(!_paused);
      if (mounted) setState(() => _pausedNow = paused);
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
      final answers = await Future.wait([
        widget.events(limit: widget.limit, type: StreamEventType.move),
        widget.events(limit: widget.admissionsLimit, type: StreamEventType.admission),
      ]);
      if (mounted) {
        setState(() {
          _events = mergeEvents(answers[0], answers[1]);
          final read = {for (final event in _events.events) ?event.eventId};
          _predictions.removeWhere((eventId, _) => !read.contains(eventId));
          if (_pausedNow == _events.paused) _pausedNow = null;
        });
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
    final shown = _events.events.where(_shown).toList();
    final admissions = shown.where((event) => event.isAdmission).length;
    final moves = shown.length - admissions;
    final total = _events.total;
    final perSecond = _events.perSecond;
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
                      // The total beside the title, under it when narrow.
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Latest events', style: TextStyle(fontWeight: FontWeight.w700)),
                          if (total != null)
                            Tooltip(
                              message:
                                  'Every move and admission the API read since it started, those of people '
                                  "at home who aren't monitored too, and how many a second over the last "
                                  'minute, a moving average',
                              child: Text(
                                '${_thousands(total)} ${total == 1 ? 'event' : 'events'}'
                                '${perSecond == null ? '' : ' · ${perSecond.toStringAsFixed(1)}/s'}',
                                key: const Key('stream-events-total'),
                                style: const TextStyle(color: Aityx.fg, fontSize: 12, fontWeight: FontWeight.w600),
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
                if (widget.simulation != null) ...[
                  OutlinedButton.icon(
                    key: const Key('simulation-pause'),
                    onPressed: _switching ? null : _switch,
                    icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
                    label: Text(_paused ? 'Resume the simulation' : 'Pause the simulation'),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  '${_count(admissions, 'admission')} · ${_count(moves, 'move')}',
                  key: const Key('stream-events-counts'),
                  style: const TextStyle(color: Aityx.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ConditionFilter(
              events: _events.events,
              selected: _conditions,
              onChanged: (condition, on) => setState(() {
                if (condition == null) {
                  _conditions.clear();
                } else if (on) {
                  _conditions.add(condition);
                } else {
                  _conditions.remove(condition);
                }
              }),
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
            if (_events.events.isEmpty)
              const Text('Waiting for the first event…', style: TextStyle(color: Aityx.muted))
            else if (shown.isEmpty)
              const Text(
                'No event of these conditions among the latest.',
                key: Key('stream-events-none'),
                style: TextStyle(color: Aityx.muted),
              )
            else
              for (final event in shown) EventRow(event, prediction: _predictionOf(event)),
          ],
        ),
      ),
    );
  }
}

/// The filter under the pause: **All**, then a chip per condition of the
/// [events], by name, with how many of them it has; a condition [selected]
/// stays, with 0, until it is unselected. Events without a condition (a
/// healthy person's moves) show only under All.
class _ConditionFilter extends StatelessWidget {
  const _ConditionFilter({required this.events, required this.selected, required this.onChanged});

  final List<StreamEvent> events;
  final Set<String> selected;

  /// A condition chip turned [on] or off; a null condition is All.
  final void Function(String? condition, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{for (final condition in selected) condition: 0};
    for (final event in events) {
      final condition = event.conditionName;
      if (condition != null) counts[condition] = (counts[condition] ?? 0) + 1;
    }
    final conditions = counts.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    FilterChip chip(Key key, String label, bool on, ValueChanged<bool> onSelected) => FilterChip(
      key: key,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: on,
      onSelected: onSelected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: Aityx.orange.withValues(alpha: 0.25),
      side: BorderSide(color: on ? Aityx.orange : Aityx.border),
    );
    return Row(
      key: const Key('condition-filter'),
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
              chip(const Key('condition-filter-all'), 'All conditions', selected.isEmpty, (_) => onChanged(null, false)),
              for (final condition in conditions)
                chip(
                  Key('condition-filter-$condition'),
                  '$condition ${counts[condition]}',
                  selected.contains(condition),
                  (on) => onChanged(condition, on),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

/// [n] with its thousands apart: "48,213".
String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// The moves and the admissions as one stream, newest first by simulated
/// time. An admission comes before the moves of its own hour: the person
/// arrived, then the others moved on. A record without a time sorts last.
/// Either answer may hold both kinds when the API doesn't filter by type,
/// so each keeps only its own.
StreamEvents mergeEvents(StreamEvents moves, StreamEvents admissions) {
  final events = [
    ...admissions.events.where((event) => event.isAdmission),
    ...moves.events.where((event) => !event.isAdmission),
  ];
  final order = {for (final (i, event) in events.indexed) event: i};
  events.sort((a, b) {
    final byTime = _minutes(b).compareTo(_minutes(a));
    // The sort isn't stable: the order each answer gave breaks the ties.
    return byTime != 0 ? byTime : order[a]!.compareTo(order[b]!);
  });
  // Both answers count the same feed: the later one, with more, holds.
  final counts = (admissions.total ?? -1) > (moves.total ?? -1) ? admissions : moves;
  return StreamEvents(
    enabled: moves.enabled || admissions.enabled,
    topics: {...moves.topics, ...admissions.topics}.toList(),
    events: events,
    total: counts.total,
    perSecond: counts.perSecond,
  );
}

/// The simulated minutes since day 0 at 00:00, or -1 without a time.
int _minutes(StreamEvent event) {
  final parts = event.simTime?.split(':');
  final hours = parts?.length == 2 ? int.tryParse(parts![0]) : null;
  final minutes = parts?.length == 2 ? int.tryParse(parts![1]) : null;
  if (event.day == null || hours == null || minutes == null) return -1;
  return event.day! * 24 * 60 + hours * 60 + minutes;
}

/// When a record happened, "09:40, day 2".
String _when(StreamEvent event) => [?event.simTime, if (event.day != null) 'day ${event.day}'].join(', ');

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
/// monitored, why on hover) with the condition and the simulated time;
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
    final what = admission ? visitLabel(event) : event.state.label;
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
                      Expanded(child: Text(condition, style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 8),
                      Text(_when(event), style: muted),
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
                      Text(_where(event), style: muted.copyWith(fontFamily: 'monospace')),
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
