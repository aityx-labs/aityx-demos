/// Triages every complaint template of every medical condition with
/// aityx, as the API triages an admission (lib/triage.dart), and compares
/// each level with the template's reference (data/conditions/*.json's
/// "triage"): the sample classifications of ../docs/aityx-triage-cases.md,
/// which it writes, and a summary on stdout. Run it with
/// scripts/triage-cases.sh, which passes the aityx key from the
/// environment or .env without printing it; after changing the triage
/// model or the complaints. Each run costs one aityx call per template.
///
///   dart run tool/triage_cases.dart [--out ../docs/aityx-triage-cases.md] [--json results.json]
library;

import 'dart:convert';
import 'dart:io';

import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/triage.dart';

/// The sample patients the templates are said by, in turn: name, sex,
/// occupation, city, hospital.
const _people = [
  ('Núria Puig Soler', 'woman', 'teacher', 'Reus', 'Hospital Universitari Sant Joan de Reus'),
  ('João Pereira Costa', 'man', 'bus driver', 'Porto', 'Hospital de Santo António'),
  ('Marta Ferreira Lopes', 'woman', 'nurse', 'Coimbra', 'Hospitais da Universidade de Coimbra'),
  ('Jordi Vidal Roca', 'man', 'retired electrician', 'Tarragona', 'Hospital Joan XXIII'),
];

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final at = args.indexOf(name);
    return at >= 0 && at + 1 < args.length ? args[at + 1] : fallback;
  }

  final key = Platform.environment['AITYX_API_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('error: AITYX_API_KEY is not set (scripts/triage-cases.sh reads it from .env)');
    exit(1);
  }
  final url = Platform.environment['AITYX_URL'] ?? '';
  final aityx = Aityx(Uri.parse(url.isEmpty ? 'https://api.aityx.ai' : url), key);
  final out = option('--out', '../docs/aityx-triage-cases.md');
  final jsonOut = args.contains('--json') ? option('--json', 'triage-cases.json') : null;

  final cases = <_Case>[];
  for (final (index, condition) in conditionSeed.indexed) {
    for (final kind in VisitKind.values) {
      for (final (position, template) in condition.templates(kind).indexed) {
        final (name, sex, occupation, city, hospital) = _people[(cases.length) % _people.length];
        // An age the condition fits, spread over its range.
        final span = condition.maxAge - condition.minAge;
        final age = condition.minAge + ((index * 17 + position * 23 + kind.index * 7) % (span + 1));
        final complaint = renderComplaint(template, {
          'name': name,
          'first_name': name.split(' ').first,
          'age': age,
          'sex': sex,
          'occupation': occupation,
          'city': city,
          'hospital': hospital,
          'visit_number': kind == VisitKind.first ? 1 : 2 + position % 2,
          'days_since_first_visit': kind == VisitKind.first ? 0 : 7 + position * 7,
        });
        cases.add(_Case(condition, kind, position, age, complaint, condition.triageOf(kind)[position]));
      }
    }
  }

  stderr.writeln('triaging ${cases.length} complaints with aityx (${aityx.systemone.host})...');
  var done = 0;
  final queue = [...cases];
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final c = queue.removeAt(0);
      c.record = await triageAdmission(aityx, {
        'eventId': '${c.condition.code}-${c.kind.json}-${c.position}',
        'complaint': c.complaint,
        'age': c.age,
        'conditionCode': c.condition.code,
        'visit': c.kind.json,
        'template': c.position,
      });
      if (++done % 25 == 0) stderr.writeln('  $done of ${cases.length}');
    }
  }

  await Future.wait([for (var i = 0; i < 6; i++) worker()]);
  aityx.close();

  final stats = _Stats(cases);
  stdout.writeln(stats.text);
  File(out).writeAsStringSync(_markdown(cases, stats));
  stderr.writeln('wrote $out');
  if (jsonOut != null) {
    File(jsonOut).writeAsStringSync(const JsonEncoder.withIndent(' ').convert([
      for (final c in cases)
        {
          'condition': c.condition.code,
          'visit': c.kind.json,
          'template': c.position,
          'age': c.age,
          'complaint': c.complaint,
          ...c.record!,
        },
    ]));
    stderr.writeln('wrote $jsonOut');
  }
}

class _Case {
  _Case(this.condition, this.kind, this.position, this.age, this.complaint, this.reference);

  final MedicalCondition condition;
  final VisitKind kind;
  final int position;
  final int age;
  final String complaint;
  final String reference;
  Map<String, Object?>? record;

  String? get level => record?['level'] as String?;

  /// How many levels less urgent than the reference aityx put it (a
  /// negative number: more urgent); null when it failed.
  int? get gap => level == null ? null : triageLevels.indexOf(level!) - triageLevels.indexOf(reference);
}

class _Stats {
  _Stats(this.cases);

  final List<_Case> cases;

  Iterable<_Case> get triaged => cases.where((c) => c.level != null);
  int get failed => cases.length - triaged.length;
  int get matched => triaged.where((c) => c.gap == 0).length;
  int get withinOne => triaged.where((c) => c.gap!.abs() <= 1).length;
  int get under => triaged.where((c) => c.gap! > 0).length;
  int get over => triaged.where((c) => c.gap! < 0).length;
  int get nurseChecks => triaged.where((c) => c.record!['nurseCheck'] == true).length;
  int get tokens => triaged.fold(0, (sum, c) => sum + ((c.record!['inputTokens'] as int?) ?? 0));
  List<int> get millis => [for (final c in triaged) c.record!['millis'] as int]..sort();

  String percent(int n) => triaged.isEmpty ? '-' : '${(100 * n / triaged.length).toStringAsFixed(1)}%';

  /// Rows: the reference level; columns: aityx's.
  Map<String, Map<String, int>> get confusion => {
    for (final r in triageLevels)
      r: {for (final l in triageLevels) l: triaged.where((c) => c.reference == r && c.level == l).length},
  };

  String get text {
    final m = millis;
    return [
      '${cases.length} complaints, ${triaged.length} triaged, $failed failed',
      'the same level as the reference: $matched (${percent(matched)})',
      'within one level: $withinOne (${percent(withinOne)})',
      'less urgent than the reference: $under (${percent(under)}); more urgent: $over (${percent(over)})',
      'for a nurse to check: $nurseChecks',
      if (m.isNotEmpty) 'time: median ${m[m.length ~/ 2]} ms, slowest ${m.last} ms',
      'input tokens: $tokens (\$${(tokens * 0.042 / 1e6).toStringAsFixed(4)} at \$0.042 per million)',
    ].join('\n');
  }
}

const _names = {
  'red': 'Immediate',
  'orange': 'Very urgent',
  'yellow': 'Urgent',
  'green': 'Standard',
  'blue': 'Non-urgent',
};

const _dots = {'red': '🔴', 'orange': '🟠', 'yellow': '🟡', 'green': '🟢', 'blue': '🔵'};

String _level(String? level) => level == null ? 'failed' : '${_dots[level]} ${_names[level]}';

String _markdown(List<_Case> cases, _Stats stats) {
  final out = StringBuffer()
    ..writeln('# Triage at the desk: every complaint, triaged by aityx')
    ..writeln()
    ..writeln('<!-- GENERATED by healthhub_api/tool/triage_cases.dart (scripts/triage-cases.sh): run it again, never edit this file. -->')
    ..writeln()
    ..writeln('Every complaint template of the ${conditionSeed.length} medical conditions '
        '([conditions.md](../specs/conditions.md)), said by a sample patient, sent to aityx as '
        'HealthHub sends an admission ([aityx.md](aityx.md#triage-at-the-desk)), and the level aityx '
        'decided set against the template\'s reference: the level a nurse applying the same policy '
        'gives what it says. Each row is one real aityx call.')
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| | Complaints | Share |')
    ..writeln('|---|---:|---:|')
    ..writeln('| Triaged | ${stats.triaged.length} of ${cases.length} | |')
    ..writeln('| The same level as the reference | ${stats.matched} | ${stats.percent(stats.matched)} |')
    ..writeln('| Within one level | ${stats.withinOne} | ${stats.percent(stats.withinOne)} |')
    ..writeln('| Less urgent than the reference | ${stats.under} | ${stats.percent(stats.under)} |')
    ..writeln('| More urgent than the reference | ${stats.over} | ${stats.percent(stats.over)} |')
    ..writeln('| For a nurse to check | ${stats.nurseChecks} | ${stats.percent(stats.nurseChecks)} |')
    ..writeln()
    ..writeln('The reference level (rows) against aityx\'s (columns):')
    ..writeln()
    ..writeln('| Reference ↓ · aityx → | ${triageLevels.map(_level).join(' | ')} |')
    ..writeln('|---|${triageLevels.map((_) => '---:').join('|')}|');
  stats.confusion.forEach((reference, row) {
    out.writeln('| ${_level(reference)} | ${triageLevels.map((l) => row[l] == 0 ? '·' : '${row[l]}').join(' | ')} |');
  });
  final m = stats.millis;
  out
    ..writeln()
    ..writeln('One call per complaint${m.isEmpty ? '' : ', median ${m[m.length ~/ 2]} ms'}, '
        '${stats.tokens} input tokens in all.')
    ..writeln()
    ..writeln('## Every complaint')
    ..writeln()
    ..writeln('"Signs" are the danger signs Jev found likely (0.35 or more: 0.7 makes one present); '
        '"Why" is the `# why` of the level table\'s rule that fired. ✅ the reference level, '
        '⬆️ more urgent than it, ⬇️ less urgent.')
    ..writeln();
  for (final condition in conditionSeed) {
    out
      ..writeln('### ${condition.name} (${condition.type})')
      ..writeln()
      ..writeln('| Visit | Age | What the patient said | Reference | aityx | Signs · pain · onset · purpose | Why | Area |')
      ..writeln('|---|---:|---|---|---|---|---|---|');
    for (final c in cases.where((c) => c.condition == condition)) {
      final r = c.record!;
      final signs = ((r['signs'] as Map?) ?? const {}).entries
          .where((e) => (e.value as num) >= 0.35)
          .map((e) => '${e.key.toString().replaceAll('_', ' ')} ${(e.value as num).toStringAsFixed(2)}');
      final choices = (r['choices'] as Map?) ?? const {};
      String choice(String name) => ((choices[name] as Map?)?['choice'] as String? ?? '-').replaceAll('_', ' ');
      final mark = switch (c.gap) {
        null => '',
        0 => ' ✅',
        > 0 => ' ⬇️',
        _ => ' ⬆️',
      };
      final read = r['error'] != null
          ? 'failed: ${r['error']}'
          : [...signs, 'pain ${choice('pain')}', choice('onset'), choice('visit_purpose')].join(' · ');
      out.writeln('| ${c.kind.json} ${c.position + 1} | ${c.age} | ${_cell(c.complaint)} | ${_level(c.reference)} | '
          '${_level(c.level)}$mark${r['nurseCheck'] == true ? ' · nurse' : ''} | ${_cell(read)} | '
          '${_cell(r['levelWhy'] as String? ?? '')} | ${(r['area'] as String? ?? '').replaceAll('_', ' ')} |');
    }
    out.writeln();
  }
  return out.toString();
}

String _cell(String text) => text.replaceAll('|', r'\|').replaceAll('\n', ' ');
