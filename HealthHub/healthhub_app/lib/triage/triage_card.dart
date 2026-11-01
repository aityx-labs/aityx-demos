import 'dart:async';

import 'package:flutter/material.dart';

import '../api/health_hub_api.dart';
import '../events/stream_events.dart' show visitOf;
import '../people/person_screen.dart';
import '../theme.dart';

/// Gives how aityx triages the admissions: the API's `GET /api/triage`.
typedef TriageLoader = Future<Triages> Function({int limit});

/// Gives one admission's triage with aityx's receipt: `GET /api/triage/{eventId}`.
typedef TriageDetailLoader = Future<Triaged> Function(String eventId);

/// The colour of each triage level.
Color levelColor(TriageLevel? level) => switch (level) {
  TriageLevel.red => Aityx.red,
  TriageLevel.orange => Aityx.orange,
  TriageLevel.yellow => Aityx.amber,
  TriageLevel.green => Aityx.green,
  TriageLevel.blue => Aityx.blue,
  null => Aityx.dim,
};

/// Triage at the desk: the latest admissions as aityx triaged them from
/// what each patient said, newest first, with the level, the longest wait,
/// the area and the rule behind it, and above them every triage so far
/// counted and set against the reference levels. A tap on one opens why
/// ([TriageDetailDialog]). Asked every 5 seconds while shown; nothing
/// shows until the API triages (it has an aityx key) or has triaged.
class TriageCard extends StatefulWidget {
  const TriageCard({super.key, required this.triage, required this.detail, this.limit = 8});

  final TriageLoader triage;
  final TriageDetailLoader detail;
  final int limit;

  @override
  State<TriageCard> createState() => _TriageCardState();
}

class _TriageCardState extends State<TriageCard> {
  Triages _triages = const Triages();
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
    if (_asking) return;
    _asking = true;
    try {
      final triages = await widget.triage(limit: widget.limit);
      if (mounted) setState(() => _triages = triages);
    } catch (_) {
      // The API or the database may be down for a moment: keep what is shown.
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _triages;
    if (!t.enabled && t.triaged.isEmpty) return const SizedBox.shrink();
    final s = t.summary;
    return Card(
      key: const Key('triage-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.medical_services_outlined, color: Aityx.orange, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Triage at the desk, by aityx', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        'Jev reads what each patient says; the triage rules decide. Tap one to see why.',
                        style: TextStyle(color: Aityx.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (s.compared > 0)
                  Text(
                    '${s.total} triaged · ${_percent(s.matched, s.compared)} at the reference level',
                    key: const Key('triage-agreement'),
                    style: const TextStyle(color: Aityx.muted, fontSize: 12),
                  ),
              ],
            ),
            if (s.total > 0) ...[const SizedBox(height: 8), _SummaryStrip(s)],
            const SizedBox(height: 8),
            if (t.triaged.isEmpty)
              const Text('Waiting for the first admission…', style: TextStyle(color: Aityx.muted))
            else
              for (final row in t.triaged)
                TriageRow(
                  row,
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => TriageDetailDialog(detail: widget.detail(row.eventId), summary: row),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

String _percent(int n, int of) => of == 0 ? '-' : '${(100 * n / of).round()}%';

/// Every triage so far: how many of each level, and against the reference.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip(this.s);

  final TriageSummary s;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    return Wrap(
      key: const Key('triage-summary'),
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final level in TriageLevel.values)
          _Chip('${level.label} ${s.levels[level] ?? 0}', levelColor(level)),
        if (s.compared > 0) ...[
          Text('within one level ${_percent(s.withinOne, s.compared)}', style: muted),
          Text('less urgent than the reference ${s.under}', style: muted),
          Text('more urgent ${s.over}', style: muted),
        ],
        Text('for a nurse ${s.nurseChecks}', style: muted),
        if (s.failed > 0) Text('failed ${s.failed}', style: muted.copyWith(color: Aityx.red)),
        if (s.medianMillis != null) Text('median ${s.medianMillis} ms', style: muted),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      border: Border.all(color: color.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

/// What aityx's level is next to the reference: the same, or how many
/// levels more or less urgent.
String againstReference(Triaged row) {
  final level = row.level;
  final reference = row.reference;
  if (level == null || reference == null) return '';
  final gap = level.below(reference);
  if (gap == 0) return 'the reference level';
  final levels = gap.abs() == 1 ? 'one level' : '${gap.abs()} levels';
  return gap > 0 ? '$levels less urgent than the reference' : '$levels more urgent than the reference';
}

/// One triaged admission: a bar and a chip in its level's colour, the
/// longest wait and the area, who arrived, what they said, the rule's
/// why, a nurse's check when the rules ask for one, and how the level
/// compares with the reference.
class TriageRow extends StatelessWidget {
  const TriageRow(this.row, {super.key, this.onTap});

  final Triaged row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Aityx.muted, fontSize: 12);
    final color = levelColor(row.level);
    final level = row.level;
    final who = [row.name ?? row.eventId, if (row.age != null) '${row.age}'].join(', ');
    final against = againstReference(row);
    return InkWell(
      key: Key('triage-${row.eventId}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
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
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (level != null)
                  _Chip('${level.label} · ${_wait(row.waitMinutes ?? level.minutes)}', color)
                else
                  _Chip('Not triaged', Aityx.red),
                if (row.area != null) Text(triageAreas[row.area] ?? row.area!, style: muted),
                if (row.nurseCheck)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_search, size: 14, color: Aityx.amber),
                      SizedBox(width: 3),
                      Text('a nurse checks', style: TextStyle(color: Aityx.amber, fontSize: 12)),
                    ],
                  ),
                if (against.isNotEmpty)
                  Text(
                    against == 'the reference level' ? '✓ $against' : against,
                    key: Key('triage-reference-${row.eventId}'),
                    style: muted.copyWith(color: against == 'the reference level' ? Aityx.green : Aityx.amber),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  if (row.personId != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: PersonLink(
                        row.personId!,
                        who,
                        run: runOf(row.eventId),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    )
                  else
                    TextSpan(text: who, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (row.hospitalName != null) TextSpan(text: '  ${row.hospitalName}', style: muted),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
            if (row.complaint != null)
              Text(
                '“${row.complaint}”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13, height: 1.35),
              ),
            if (row.levelWhy != null || row.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  row.error ?? row.levelWhy!,
                  style: muted.copyWith(color: row.error != null ? Aityx.red : Aityx.orangeLight),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _wait(int minutes) => minutes == 0 ? 'at once' : 'within $minutes min';

/// Why aityx triaged one admission as it did: what the patient said, the
/// probability Jev gave each danger sign against the two thresholds, its
/// four choices, each rule of the level and area tables tried in order up
/// to the one that fired, the nurse's check, the reference level, and
/// what aityx's receipt says came from where.
class TriageDetailDialog extends StatelessWidget {
  const TriageDetailDialog({super.key, required this.detail, required this.summary});

  final Future<Triaged> detail;

  /// The row tapped, shown while the detail loads.
  final Triaged summary;

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('triage-detail'),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: FutureBuilder<Triaged>(
        future: detail,
        builder: (context, snapshot) {
          final row = snapshot.data ?? summary;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DetailHeader(row),
                const SizedBox(height: 12),
                _Section('What the patient said', [
                  Text('“${row.complaint ?? ''}”', style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4)),
                  const SizedBox(height: 4),
                  Text(
                    'aityx gets only this and the age, ${row.age ?? '?'}: not the condition, which the desk '
                    "wouldn't know.",
                    style: const TextStyle(color: Aityx.muted, fontSize: 12),
                  ),
                ]),
                if (row.signs.isNotEmpty)
                  _Section('What Jev read', [
                    const Text(
                      'The probability of each danger sign. At 0.7 a sign counts as present; '
                      'from 0.35 it is in doubt, and a nurse checks.',
                      style: TextStyle(color: Aityx.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    for (final MapEntry(key: sign, value: name) in triageSigns.entries)
                      if (row.signs[sign] != null) _SignBar(name, row.signs[sign]!),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        for (final MapEntry(key: name, value: label) in triageChoiceNames.entries)
                          if (row.choices[name] case final c?)
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '$label: ', style: const TextStyle(color: Aityx.muted)),
                                  TextSpan(
                                    text: c.choice.replaceAll('_', ' '),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (c.confidence != null)
                                    TextSpan(
                                      text: ' (${(c.confidence! * 100).round()}%)',
                                      style: const TextStyle(color: Aityx.muted),
                                    ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                      ],
                    ),
                  ]),
                if (row.level != null)
                  _Section('What the rules decided', [
                    _RuleTrail('The level', row.rules['level'], row.levelRule, row.levelWhy),
                    const SizedBox(height: 8),
                    Text(
                      '${row.level!.label}: seen ${_wait(row.waitMinutes ?? row.level!.minutes)}.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _RuleTrail('The area', row.rules['area'], row.areaRule, row.areaWhy),
                    const SizedBox(height: 8),
                    Text(
                      row.nurseCheck
                          ? 'A nurse confirms the level before the patient waits: a danger sign is in doubt, '
                                'or a fever at 65 or older.'
                          : 'No nurse check: no danger sign is in doubt.',
                      style: TextStyle(color: row.nurseCheck ? Aityx.amber : Aityx.muted, fontSize: 13),
                    ),
                  ]),
                if (row.error != null) _Section('The triage failed', [Text(row.error!)]),
                if (row.reference != null)
                  _Section('Against the reference', [
                    Text(
                      'The simulated patient has ${row.conditionName ?? 'a condition'}'
                      '${row.visit == null ? '' : ', ${visitOf(row.visit!, row.visitNumber).toLowerCase()}'}. '
                      'A nurse applying the same rules to what they said gives '
                      '${row.reference!.label.toLowerCase()}'
                      '${row.level == null ? '' : '; aityx gave ${againstReference(row)}'}.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ]),
                if (row.receipt != null) _Receipt(row),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader(this.row);

  final Triaged row;

  @override
  Widget build(BuildContext context) {
    final level = row.level;
    final color = levelColor(level);
    return Row(
      children: [
        Container(width: 6, height: 44, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                level == null ? 'Not triaged' : '${level.label}, ${_wait(row.waitMinutes ?? level.minutes)}',
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    if (row.personId != null && row.name != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: PersonLink(
                          row.personId!,
                          [row.name!, if (row.age != null) '${row.age}'].join(', '),
                          run: runOf(row.eventId),
                          style: const TextStyle(color: Aityx.fg, fontSize: 12),
                        ),
                      ),
                    TextSpan(
                      text: [
                        if (row.personId == null || row.name == null)
                          [row.name, if (row.age != null) '${row.age}'].nonNulls.join(', ')
                        else
                          '',
                        if (row.area != null) triageAreas[row.area] ?? row.area!,
                        ?row.hospitalName,
                      ].join(' · '),
                    ),
                  ],
                ),
                style: const TextStyle(color: Aityx.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Aityx.orangeLight)),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

/// One danger sign: its name, a bar of Jev's probability with the two
/// thresholds marked, and the number; in the level colours when present,
/// amber when in doubt.
class _SignBar extends StatelessWidget {
  const _SignBar(this.name, this.probability);

  final String name;
  final double probability;

  @override
  Widget build(BuildContext context) {
    final present = probability >= triageEvidence;
    final doubt = !present && probability >= triageDoubt;
    final color = present ? Aityx.orange : (doubt ? Aityx.amber : Aityx.dim);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Text(
              name,
              style: TextStyle(fontSize: 12, color: present || doubt ? Aityx.fg : Aityx.muted),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Container(height: 8, color: Aityx.bg2),
                  Container(height: 8, width: box.maxWidth * probability.clamp(0, 1), color: color),
                  for (final at in [triageDoubt, triageEvidence])
                    Positioned(left: box.maxWidth * at, child: Container(width: 1, height: 8, color: Aityx.muted)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              '${probability.toStringAsFixed(2)}${present ? ' present' : doubt ? ' in doubt' : ''}',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: color == Aityx.dim ? Aityx.muted : color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A decision table's rules tried in order, up to the one that fired:
/// those that didn't apply crossed, the one that fired ticked.
class _RuleTrail extends StatelessWidget {
  const _RuleTrail(this.title, this.rules, this.fired, this.why);

  final String title;
  final List<String?>? rules;
  final int? fired;
  final String? why;

  @override
  Widget build(BuildContext context) {
    final rules = this.rules;
    final fired = this.fired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$title: rule ${fired ?? '?'} of ${rules?.length ?? '?'}', style: const TextStyle(fontSize: 13)),
        if (rules == null || fired == null)
          Text('✓ ${why ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))
        else
          for (var i = 1; i <= fired && i <= rules.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${i == fired ? '✓' : '✗'} $i. ${rules[i - 1] ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: i == fired ? Aityx.fg : Aityx.muted,
                  fontWeight: i == fired ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
      ],
    );
  }
}

/// What aityx's receipt says: which inputs Jev supplied and which the
/// desk did, how long it took and how many tokens it read.
class _Receipt extends StatelessWidget {
  const _Receipt(this.row);

  final Triaged row;

  @override
  Widget build(BuildContext context) {
    final provenance = (row.receipt?['provenance'] as Map?) ?? const {};
    final fromJev = provenance.values.where((source) => source == 'jev').length;
    final fromState = [
      for (final MapEntry(:key, :value) in provenance.entries)
        if (value == 'state') key,
    ];
    return _Section("aityx's receipt", [
      Text(
        '$fromJev inputs from Jev'
        '${fromState.isEmpty ? '' : ', ${fromState.join(', ')} from the desk'}; '
        'every decision traced to its rule. '
        '${row.millis == null ? '' : '${row.millis} ms, '}'
        '${row.inputTokens == null ? '' : '${row.inputTokens} input tokens.'}',
        style: const TextStyle(color: Aityx.muted, fontSize: 12, height: 1.4),
      ),
    ]);
  }
}
