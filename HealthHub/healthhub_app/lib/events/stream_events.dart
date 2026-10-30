import 'dart:async';

import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../location/user_location_map.dart' show PersonLook;
import '../theme.dart';

/// Gives the latest records on the stream: the API's `GET /api/events`,
/// only moves or only admissions with [type].
typedef EventsLoader = Future<StreamEvents> Function({int limit, StreamEventType? type});

/// The latest events on the Kafka stream, newest first: people's moves,
/// compact, and their admissions at a hospital, highlighted with what they
/// said on arrival. Asked every 5 seconds while shown, like the map's
/// people. Nothing shows until the API says the simulation runs (dev
/// mode), and nothing in prod.
///
/// Moves and admissions are asked for apart: every person moves every
/// second, so the latest [limit] records of the stream are nearly always
/// all moves and an admission would scroll out before it is ever seen.
class StreamEventsCard extends StatefulWidget {
  const StreamEventsCard({super.key, required this.events, this.limit = 12, this.admissionsLimit = 8});

  final EventsLoader events;

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
      if (mounted) setState(() => _events = mergeEvents(answers[0], answers[1]));
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
                        'On Kafka, ${_events.topics.join(', ')}; every 5 seconds',
                        style: const TextStyle(color: Aityx.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_count(admissions, 'admission')} · ${_count(moves, 'move')}',
                  key: const Key('stream-events-counts'),
                  style: const TextStyle(color: Aityx.muted, fontSize: 12),
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
          SizedBox(width: 190, child: Text(event.id, overflow: TextOverflow.ellipsis)),
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
                            TextSpan(text: who, style: const TextStyle(fontWeight: FontWeight.w700)),
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
  final kind = event.visit?.label ?? 'Admission';
  final n = event.visitNumber;
  if (n == null || event.visit == VisitKind.first) return kind;
  return '$kind, the ${_ordinal(n)}';
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
