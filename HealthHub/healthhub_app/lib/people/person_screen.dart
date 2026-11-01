import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../care_centers/care_center_screen.dart' show CareCenterLink, CareCenterOpener;
import '../events/stream_events.dart' show visitOf;
import '../location/user_location_map.dart' show PersonLook;
import '../screens/explainers.dart' show Explainer;
import '../screens/link_text.dart';
import '../sim_clock.dart';
import '../theme.dart';
import '../triage/triage_card.dart' show levelColor;

/// How the person view asks the API: one person of a run, and datyx's
/// prediction for them.
typedef PersonLoader = Future<PersonDetail> Function(String id, {String? run});
typedef PredictionLoader = Future<Prediction> Function(String id, {String? run});

/// Makes the people named under it links to their person view: home puts
/// it over its tiles. Without one (the index), a [PersonLink] is plain text.
class PersonOpener extends InheritedWidget {
  const PersonOpener({super.key, required this.person, required this.prediction, required super.child});

  final PersonLoader person;
  final PredictionLoader prediction;

  static PersonOpener? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PersonOpener>();

  /// Opens the view of person [id] of [run] (the current run unless given),
  /// whose hospitals are links too when [context] has a [CareCenterOpener].
  void open(BuildContext context, String id, {String? run}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => withOpeners(context, PersonScreen(id: id, run: run, person: person, prediction: prediction)),
    ),
  );

  @override
  bool updateShouldNotify(PersonOpener oldWidget) =>
      person != oldWidget.person || prediction != oldWidget.prediction;
}

/// A person's id or name that opens their view, underlined on hover; plain
/// text where there is no [PersonOpener]. [run] says which run's person
/// (an admission's own); the current one when null.
class PersonLink extends StatelessWidget {
  const PersonLink(this.id, this.text, {super.key, this.run, this.style, this.overflow});

  final String id;
  final String text;
  final String? run;
  final TextStyle? style;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final opener = PersonOpener.of(context);
    if (opener == null) return Text(text, style: style, overflow: overflow);
    return LinkText(
      text,
      key: Key('person-link-$id'),
      onTap: () => opener.open(context, id, run: run),
      style: style,
      overflow: overflow,
    );
  }
}

/// One person of one run, as HealthHub knows them: who they are, what they
/// do now, datyx's prediction of their care over the next 30 days (the
/// highlighted card), their admissions with aityx's triage, and their days
/// of care. A person's id comes back in every run, a new person each time:
/// the view is of [run], the current one unless given.
class PersonScreen extends StatefulWidget {
  const PersonScreen({super.key, required this.id, this.run, required this.person, required this.prediction});

  final String id;
  final String? run;
  final PersonLoader person;
  final PredictionLoader prediction;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late Future<PersonDetail> _person = widget.person(widget.id, run: widget.run);
  late Future<Prediction> _prediction = widget.prediction(widget.id, run: widget.run);

  void _reload() => setState(() {
    _person = widget.person(widget.id, run: widget.run);
    _prediction = widget.prediction(widget.id, run: widget.run);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: FutureBuilder<PersonDetail>(
        future: _person,
        builder: (context, snapshot) => Text(snapshot.data?.name ?? widget.id),
      ),
      actions: [IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<PersonDetail>(
      future: _person,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _Message(
            error is ApiException && error.status == 404
                ? 'Nobody with the id ${widget.id} in this run.'
                : 'The person can\'t be read: ${error is ApiException ? error.message : error}',
          );
        }
        final person = snapshot.data;
        if (person == null) return const Center(child: CircularProgressIndicator());
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(person),
                const SizedBox(height: 16),
                PredictionCard(prediction: _prediction),
                const SizedBox(height: 16),
                const PredictionExplainer(),
                const SizedBox(height: 16),
                _Summary(person.summary),
                const SizedBox(height: 16),
                _Admissions(person.admissions),
                const SizedBox(height: 16),
                _Days(person.days),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Aityx.muted)),
    ),
  );
}

/// A card of the view: an icon and a title over its content.
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, this.subtitle, required this.child});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Aityx.orange, size: 20),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Aityx.muted, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// Who they are, and what they do now.
class _Header extends StatelessWidget {
  const _Header(this.person);
  final PersonDetail person;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 13);
    final facts = [
      if (person.age != null) '${person.age}',
      ?person.sex,
      ?person.occupation,
      ?person.city,
    ].join(' · ');
    final now = person.now;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: (now?.state.color ?? Aityx.muted).withValues(alpha: 0.2),
              child: Icon(Icons.person, color: now?.state.color ?? Aityx.muted, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name ?? person.id,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Aityx.fg0),
                  ),
                  if (facts.isNotEmpty) Text(facts, style: muted),
                  const SizedBox(height: 4),
                  Text(
                    [
                      person.id,
                      if (person.run != null) 'run ${person.run}',
                      if (!person.current) 'a past run',
                    ].join(' · '),
                    style: muted.copyWith(fontFamily: 'monospace', fontSize: 12),
                  ),
                  if (now != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(
                          [
                            now.state.labelAt(now.careCenterKind),
                            if (now.state == PersonState.toHospital || now.state == PersonState.atHospital)
                              ?now.hospitalName,
                          ].join(' · '),
                          now.state.color,
                          careCenter: now.state == PersonState.toHospital || now.state == PersonState.atHospital
                              ? now.hospitalId
                              : null,
                        ),
                        if (now.conditionName != null)
                          _Pill(
                            [now.conditionName!, if (now.conditionType != null) '(${now.conditionType!.label})'].join(' '),
                            Aityx.muted,
                          ),
                        if (now.simTime != null)
                          Text(
                            simWhen(now.day, now.simTime),
                            style: muted.copyWith(fontSize: 12),
                          ),
                      ],
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

/// A pill of [text] in [color]; with a [careCenter], a tap opens its view.
class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.careCenter});
  final String text;
  final Color color;
  final int? careCenter;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600);
    final opener = CareCenterOpener.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: careCenter == null || opener == null
          ? Text(text, style: style)
          : LinkText(text, key: Key('care-center-link-$careCenter'), onTap: () => opener.open(context, careCenter!), style: style),
    );
  }
}

/// datyx's prediction of the person's hours of care over the next 30 days
/// (XGBoost, trained on patient_days), set apart from the rest of the
/// view: the number large, against the 30 days just gone, and which model
/// said it. While it loads, a spinner; without a model or an answer, why.
class PredictionCard extends StatelessWidget {
  const PredictionCard({super.key, required this.prediction});

  final Future<Prediction> prediction;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('prediction-card'),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Aityx.orange.withValues(alpha: 0.22), Aityx.bg1],
      ),
      border: Border.all(color: Aityx.orange, width: 1.5),
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.insights, color: Aityx.orange, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Return in the next 30 days',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Aityx.fg0),
              ),
            ),
            Text('XGBoost · datyx', style: TextStyle(color: Aityx.orangeLight, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<Prediction>(
          future: prediction,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Text(
                error is ApiException ? error.message : 'datyx can\'t be asked: $error',
                style: const TextStyle(color: Aityx.amber),
              );
            }
            final p = snapshot.data;
            if (p == null) {
              return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
            }
            return _PredictionBody(p);
          },
        ),
      ],
    ),
  );
}

/// Under the prediction: how datyx's XGBoost model makes it, from the
/// person's own history, and why Jev, which reads text, can't.
class PredictionExplainer extends StatelessWidget {
  const PredictionExplainer({super.key});

  @override
  Widget build(BuildContext context) => const Explainer(
    key: Key('prediction-explainer'),
    icon: Icons.account_tree_outlined,
    title: 'How this prediction is made',
    points: [
      (
        'XGBoost, on their history',
        'datyx trained an XGBoost model on patient_days, every simulated patient\'s hours of hospital care, day '
            'by day. For this person it builds the same features from their own days up to now: the hours of '
            'care over the last day, 30, 90 and 360 days, the days since their last stay, how much history '
            'there is. Its trees add up to the hours expected over the next 30 days.',
      ),
      (
        'Learned from everyone',
        'What the trees know is what followed histories like this one in every other patient\'s days; the line '
            'above says which training run made them, and when.',
      ),
      (
        'Why not Jev',
        'Jev reads text: it answers questions about what someone says, as at the triage desk. This number isn\'t '
            'in anything the person says. It comes from their own history of stays, and from patterns in '
            'everyone else\'s: rows of numbers Jev never sees. So the history goes to a model trained on it, '
            'and Jev stays at the desk.',
      ),
    ],
  );
}

class _PredictionBody extends StatelessWidget {
  const _PredictionBody(this.p);
  final Prediction p;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    final predicted = p.predicted;
    final model = [
      if (p.group != null) 'group ${p.group}',
      if (p.target != null) '${p.target} over ${p.horizon ?? 'the horizon'}',
      if (p.trainingRunId != null) 'training run ${p.trainingRunId}',
      if (p.trainedAt != null) 'trained ${_date(p.trainedAt!)}',
      if (p.millis != null) '${p.millis} ms',
    ].join(' · ');
    if (predicted == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.note ?? 'No prediction for this person.', style: const TextStyle(color: Aityx.amber)),
          if (model.isNotEmpty) ...[const SizedBox(height: 6), Text(model, style: muted)],
        ],
      );
    }
    final last = p.last;
    final change = last == null ? null : predicted - last;
    final up = change != null && change > 0.05;
    final down = change != null && change < -0.05;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              hoursOf(predicted),
              key: const Key('prediction-value'),
              style: const TextStyle(fontSize: 40, height: 1, fontWeight: FontWeight.w800, color: Aityx.fg0),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('of hospital care expected', style: TextStyle(color: Aityx.fg, fontSize: 14)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (last != null)
          Row(
            children: [
              Icon(
                up ? Icons.trending_up : (down ? Icons.trending_down : Icons.trending_flat),
                size: 18,
                color: up ? Aityx.amber : (down ? Aityx.green : Aityx.muted),
              ),
              const SizedBox(width: 6),
              Text(
                '${hoursOf(last)} in the last 30 days',
                style: const TextStyle(color: Aityx.fg, fontSize: 13),
              ),
            ],
          ),
        if (model.isNotEmpty) ...[const SizedBox(height: 8), Text(model, style: muted)],
      ],
    );
  }

  static String _date(DateTime t) => t.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ');
}

/// Hours as the prediction shows them: "9 h", "9.5 h".
String hoursOf(num h) => '${h == h.roundToDouble() ? h.toInt() : h.toStringAsFixed(1)} h';

/// Their admissions and days, counted.
class _Summary extends StatelessWidget {
  const _Summary(this.s);
  final PersonSummary s;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      _Stat('${s.admissions}', 'admissions'),
      _Stat('${s.acute} · ${s.chronic}', 'acute · chronic'),
      _Stat('${s.triaged}', 'triaged by aityx'),
      _Stat('${s.days}', 'days of care'),
      _Stat('${s.stayHours}', 'hours of care'),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 170,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Aityx.bg1,
      border: Border.all(color: Aityx.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Aityx.fg0)),
        Text(label, style: const TextStyle(color: Aityx.muted, fontSize: 12)),
      ],
    ),
  );
}

/// Each admission, newest first: when, which visit of what, where, what
/// they said, and aityx's triage in its level's colour.
class _Admissions extends StatelessWidget {
  const _Admissions(this.admissions);
  final List<PersonAdmission> admissions;

  @override
  Widget build(BuildContext context) => _Section(
    icon: Icons.local_hospital,
    title: 'Admissions',
    subtitle: 'newest first, with aityx\'s triage at the desk',
    child: admissions.isEmpty
        ? const Text('No admissions in this run yet.', style: TextStyle(color: Aityx.muted))
        : Column(children: [for (final a in admissions) AdmissionRow(a)]),
  );
}

/// One admission: when, which visit of what, what they said, aityx's
/// triage in its level's colour, and where (a link to the care center); or,
/// with [showPerson] (in a care center's view), who (a link to them).
class AdmissionRow extends StatelessWidget {
  const AdmissionRow(this.a, {super.key, this.showPerson = false});
  final PersonAdmission a;
  final bool showPerson;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    final color = a.triaged ? levelColor(a.level) : Aityx.border;
    final level = a.level;
    final triage = !a.triaged
        ? 'Not triaged yet'
        : level == null
        ? 'Triage failed'
        : '${level.label} · ${_wait(a.waitMinutes ?? level.minutes)}'
              '${a.area == null ? '' : ' · ${triageAreas[a.area] ?? a.area}'}';
    return Container(
      key: Key('person-admission-${a.eventId}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                simWhen(a.day, a.simTime),
                style: muted,
              ),
              Text(
                [
                  ?a.conditionName,
                  if (a.conditionType != null) '(${a.conditionType!.label})',
                ].join(' '),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              if (showPerson && a.personId != null)
                PersonLink(
                  a.personId!,
                  [a.name ?? a.personId!, if (a.age != null) '${a.age}'].join(', '),
                  run: runOf(a.eventId),
                  style: const TextStyle(color: Aityx.fg, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              if (a.visit != null)
                Text(visitOf(a.visit!, a.visitNumber), style: const TextStyle(color: Aityx.orangeLight, fontSize: 12)),
              if (!showPerson && a.hospitalName != null)
                CareCenterLink(
                  a.hospitalId,
                  a.hospitalName!,
                  style: const TextStyle(color: Aityx.orangeLight, fontSize: 12),
                ),
              Text(triage, style: TextStyle(color: a.triaged ? color : Aityx.muted, fontSize: 12)),
              if (a.nurseCheck) const Text('a nurse checks', style: TextStyle(color: Aityx.amber, fontSize: 12)),
            ],
          ),
          if (a.complaint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '“${a.complaint}”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Aityx.fg),
              ),
            ),
        ],
      ),
    );
  }

  static String _wait(int minutes) =>
      minutes == 0 ? 'now' : (minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h${minutes % 60 == 0 ? '' : ' ${minutes % 60} min'}');
}

/// Their days of care, the latest first: patient_days, what datyx trains on.
class _Days extends StatelessWidget {
  const _Days(this.days);
  final List<PersonDay> days;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(color: Aityx.muted, fontSize: 12, fontWeight: FontWeight.w600);
    const cell = TextStyle(fontSize: 13);
    return _Section(
      icon: Icons.calendar_month,
      title: 'Days of care',
      subtitle: 'patient_days, the series datyx predicts from',
      child: days.isEmpty
          ? const Text('No days of care in this run yet.', style: TextStyle(color: Aityx.muted))
          : Table(
              columnWidths: const {0: FixedColumnWidth(120)},
              children: [
                const TableRow(
                  children: [
                    Text('Date', style: head),
                    Text('Visits', style: head),
                    Text('Acute · chronic', style: head),
                    Text('Hours of care', style: head),
                  ],
                ),
                for (final d in days)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          simDateOf(d.day),
                          style: cell,
                        ),
                      ),
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text('${d.visits}', style: cell)),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${d.acuteVisits} · ${d.chronicVisits}', style: cell),
                      ),
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text('${d.stayHours} h', style: cell)),
                    ],
                  ),
              ],
            ),
    );
  }
}
