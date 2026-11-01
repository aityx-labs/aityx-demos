import 'dart:async';

import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../location/user_location_map.dart' show PersonLook;
import '../people/person_screen.dart';
import '../theme.dart';

/// Gives the latest records on the stream: the API's `GET /api/events`,
/// only moves or only admissions with [type].
typedef EventsLoader = Future<StreamEvents> Function({int limit, StreamEventType? type});

/// Pauses the simulation (true) or resumes it, and says whether it is
/// paused now: the API's `POST /api/simulation/pause` and `/resume`.
typedef SimulationControl = Future<bool> Function(bool pause);

/// The latest events on the Kafka stream, newest first: people's moves,
/// compact, and their admissions at a hospital, highlighted with what they
/// said on arrival. Asked every 5 seconds while shown, like the map's
/// people. Nothing shows until the API says the simulation runs (dev
/// mode), and nothing in prod. Each row names its person, a link to
/// their view, and the card invites opening anyone's. With [simulation],
/// a button at the top pauses the simulation and resumes it.
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
    final admissions = _events.events.where((event) => event.isAdmission).length;
    final moves = _events.events.length - admissions;
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
                      const Text('Latest events', style: TextStyle(fontWeight: FontWeight.w700)),
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
            const SizedBox(height: 6),
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
            else
              for (final event in _events.events) event.isAdmission ? AdmissionRow(event) : _EventRow(event),
          ],
        ),
      ),
    );
  }
}

String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

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
  return StreamEvents(
    enabled: moves.enabled || admissions.enabled,
    topics: {...moves.topics, ...admissions.topics}.toList(),
    events: events,
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

/// Where a record sits in its topic, "p0 · #67070".
String _where(StreamEvent event) => event.offset == null ? '' : 'p${event.partition ?? 0} · #${event.offset}';

/// One move: a dot in the state's colour (the map's), the simulated time,
/// who, what and where to, and the record's partition and offset.
class _EventRow extends StatelessWidget {
  const _EventRow(this.event);

  final StreamEvent event;

  @override
  Widget build(BuildContext context) {
    final what = [
      event.state.label,
      if (event.state == PersonState.toHospital || event.state == PersonState.atHospital) ?event.hospitalName,
    ].join(' · ');
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: event.state.color),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 96, child: Text(_when(event), style: muted)),
          SizedBox(
            width: 190,
            child: Tooltip(
              message: event.id,
              child: PersonLink(event.id, event.name ?? event.id, overflow: TextOverflow.ellipsis),
            ),
          ),
          Expanded(child: Text(what, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          Text(_where(event), style: muted.copyWith(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

/// One admission, set apart from the moves by an orange bar and tint: who
/// arrived (name and age), with what condition and whether it is acute or
/// chronic, which visit of the course, at which hospital, and in full what
/// they said on arrival, the text a triage would route on.
class AdmissionRow extends StatelessWidget {
  const AdmissionRow(this.event, {super.key});

  final StreamEvent event;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    final who = [event.name ?? event.id, if (event.age != null) '${event.age}'].join(', ');
    final condition = [
      ?event.conditionName,
      if (event.conditionType != null) '(${event.conditionType!.label})',
    ].join(' ');
    final visit = [visitLabel(event), ?event.hospitalName].join(' · ');
    return Container(
      key: Key('admission-${event.eventId ?? event.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Aityx.orange.withValues(alpha: 0.10),
        border: const Border(left: BorderSide(color: Aityx.orange, width: 4)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.local_hospital, color: Aityx.orange, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            // The person of this admission's run.
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: PersonLink(
                                event.id,
                                who,
                                run: runOf(event.eventId),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            if (condition.isNotEmpty) TextSpan(text: '  $condition'),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(_when(event), style: muted),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(child: Text(visit, style: muted.copyWith(color: Aityx.orangeLight))),
                    Text(_where(event), style: muted.copyWith(fontFamily: 'monospace')),
                  ],
                ),
                if (event.complaint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '“${event.complaint}”',
                    softWrap: true,
                    style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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
