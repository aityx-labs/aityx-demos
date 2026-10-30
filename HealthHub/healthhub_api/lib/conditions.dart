/// Medical conditions: the common acute and chronic diseases the simulated
/// people have, with their treatment, how they bring someone to the
/// hospital (how many visits, how far apart, how long each stay), and
/// what a patient says on arrival. The data is data/conditions/acute.json
/// and chronic.json, compiled in as lib/conditions_seed.dart by
/// tool/generate_conditions.dart, since the API ships as a single native
/// executable; the API seeds it into its database (lib/db.dart) and the
/// simulation (lib/simulation.dart) draws people's conditions from it.
library;

import 'dart:math';

/// Whether a condition passes (acute) or stays (chronic).
const conditionTypes = {'acute', 'chronic'};

/// Which visit of a course a complaint is said at: the first time with
/// this complaint, a follow-up, or the last visit of the course. A course
/// of one visit uses the first.
enum VisitKind {
  first('first'),
  repeat('repeat'),
  last('last');

  const VisitKind(this.json);

  final String json;

  /// The kind of visit [number] (from 1) of a course of [count] visits.
  static VisitKind of(int number, int count) => number <= 1 || count <= 1
      ? first
      : number >= count
      ? last
      : repeat;
}

/// The placeholders a complaint template may use, replaced by the
/// simulation with the person's details ([renderComplaint]).
const complaintPlaceholders = {
  'name',
  'first_name',
  'age',
  'sex',
  'occupation',
  'city',
  'hospital',
  'visit_number',
  'days_since_first_visit',
};

/// How many templates each visit kind has.
const templatesPerVisit = 3;

/// The ages people are simulated at: adults.
const minAdultAge = 18;
const maxAdultAge = 90;

final _code = RegExp(r'^[a-z0-9_]+$');
final _placeholder = RegExp(r'\{([^{}]*)\}');

/// One condition, as the seed holds it.
class MedicalCondition {
  const MedicalCondition({
    required this.code,
    required this.name,
    required this.type,
    required this.prevalence,
    required this.minAge,
    required this.maxAge,
    required this.summary,
    required this.treatment,
    required this.treatmentDurationDays,
    required this.duration,
    required this.visitCount,
    required this.visitIntervalDays,
    required this.stayHours,
    required this.first,
    required this.repeat,
    required this.last,
    this.femaleShare = 0.5,
    this.urgent = false,
    this.followUpStayHours,
    this.courseGapDays,
  });

  /// An element of data/conditions/[type].json; throws a FormatException
  /// listing every [problems] when it isn't valid.
  factory MedicalCondition.fromJson(Map<String, Object?> json, {required String type}) {
    final found = problems(json, type: type);
    if (found.isNotEmpty) {
      throw FormatException('condition ${json['code'] ?? '(no code)'}: ${found.join('; ')}');
    }
    final visits = json['visits'] as Map;
    final templates = json['templates'] as Map;
    List<String> texts(String kind) => List.unmodifiable((templates[kind] as List).cast<String>());
    return MedicalCondition(
      code: json['code'] as String,
      name: (json['name'] as String).trim(),
      type: type,
      prevalence: (json['prevalence'] as num).toDouble(),
      minAge: json['min_age'] as int,
      maxAge: json['max_age'] as int,
      summary: (json['summary'] as String).trim(),
      treatment: (json['treatment'] as String).trim(),
      treatmentDurationDays: json['treatment_duration_days'] as int?,
      duration: (json['duration'] as String).trim(),
      visitCount: visits['count'] as int,
      visitIntervalDays: visits['interval_days'] as int,
      stayHours: visits['stay_hours'] as int,
      first: texts('first'),
      repeat: texts('repeat'),
      last: texts('last'),
      femaleShare: (json['female_share'] as num? ?? 0.5).toDouble(),
      urgent: json['urgent'] as bool? ?? false,
      followUpStayHours: json['follow_up_stay_hours'] as int?,
      courseGapDays: json['course_gap_days'] as int?,
    );
  }

  /// What is wrong with [json] as a condition of [type] (none when it is
  /// valid), so the generator can report every problem at once.
  static List<String> problems(Map<String, Object?> json, {required String type}) {
    final found = <String>[];
    String? text(String field) {
      final value = json[field];
      if (value is! String || value.trim().isEmpty) {
        found.add('"$field" is not a non-empty string');
        return null;
      }
      return value;
    }

    int? integer(Map<Object?, Object?> from, String field, String where, {int? least, int? most}) {
      final value = from[field];
      if (value is! int) {
        found.add('"$where" is not an integer');
        return null;
      }
      if ((least != null && value < least) || (most != null && value > most)) {
        found.add('"$where" is $value, not ${least ?? '-'} to ${most ?? '-'}');
      }
      return value;
    }

    final code = text('code');
    if (code != null && !_code.hasMatch(code)) found.add('"code" "$code" is not lowercase [a-z0-9_]');
    text('name');
    if (json['type'] != type) found.add('"type" is ${json['type']}, but the file is $type');
    final prevalence = json['prevalence'];
    if (prevalence is! num || prevalence <= 0 || !prevalence.isFinite) {
      found.add('"prevalence" is not a positive number');
    }
    final minAge = integer(json, 'min_age', 'min_age', least: minAdultAge, most: maxAdultAge);
    final maxAge = integer(json, 'max_age', 'max_age', least: minAdultAge, most: maxAdultAge);
    if (minAge != null && maxAge != null && minAge > maxAge) found.add('"min_age" is above "max_age"');
    text('summary');
    text('treatment');
    text('duration');
    final days = json['treatment_duration_days'];
    if (type == 'acute' && (days is! int || days < 1)) {
      found.add('"treatment_duration_days" is not a positive integer, as an acute condition needs');
    }
    if (type == 'chronic' && days != null) {
      found.add('"treatment_duration_days" is not null, as a chronic condition needs');
    }

    // The optional fields: absent means the default.
    final femaleShare = json['female_share'];
    if (femaleShare != null && (femaleShare is! num || !femaleShare.isFinite || femaleShare < 0 || femaleShare > 1)) {
      found.add('"female_share" is not a number from 0 to 1');
    }
    if (json['urgent'] != null && json['urgent'] is! bool) found.add('"urgent" is not true or false');
    if (json['follow_up_stay_hours'] != null) {
      integer(json, 'follow_up_stay_hours', 'follow_up_stay_hours', least: 1, most: 72);
    }
    if (json['course_gap_days'] != null) {
      if (type == 'acute') {
        found.add('"course_gap_days" is set, but only a chronic condition has courses that repeat');
      } else {
        integer(json, 'course_gap_days', 'course_gap_days', least: 0, most: 3650);
      }
    }

    final visits = json['visits'];
    if (visits is! Map) {
      found.add('"visits" is not an object');
    } else {
      integer(visits, 'count', 'visits.count', least: 1);
      integer(visits, 'interval_days', 'visits.interval_days', least: 1);
      integer(visits, 'stay_hours', 'visits.stay_hours', least: 1, most: 72);
    }

    final templates = json['templates'];
    if (templates is! Map) {
      found.add('"templates" is not an object');
    } else {
      for (final kind in VisitKind.values) {
        final list = templates[kind.json];
        if (list is! List || list.length != templatesPerVisit || list.any((t) => t is! String || t.trim().isEmpty)) {
          found.add('"templates.${kind.json}" is not $templatesPerVisit non-empty strings');
          continue;
        }
        if (list.toSet().length != list.length) found.add('"templates.${kind.json}" repeats a template');
        for (final (index, template) in list.cast<String>().indexed) {
          for (final problem in templateProblems(template)) {
            found.add('"templates.${kind.json}[$index]" $problem');
          }
        }
      }
      final extra = templates.keys.where((k) => !VisitKind.values.any((v) => v.json == k));
      if (extra.isNotEmpty) found.add('"templates" has unknown kinds $extra');
    }
    return found;
  }

  /// What is wrong with [template]'s placeholders: one outside
  /// [complaintPlaceholders], or a brace that opens or closes none.
  static List<String> templateProblems(String template) {
    final found = <String>[];
    for (final match in _placeholder.allMatches(template)) {
      if (!complaintPlaceholders.contains(match[1])) found.add('uses an unknown placeholder {${match[1]}}');
    }
    final rest = template.replaceAll(_placeholder, '');
    if (rest.contains('{') || rest.contains('}')) found.add('has a stray brace');
    return found;
  }

  final String code;
  final String name;

  /// acute or chronic.
  final String type;

  /// How common it is, relative to the others: only the ratios matter.
  final double prevalence;
  final int minAge;
  final int maxAge;
  final String summary;
  final String treatment;

  /// For an acute condition, about how many days treatment and recovery
  /// take; null for a chronic one, which is ongoing.
  final int? treatmentDurationDays;

  /// The duration, as people say it.
  final String duration;

  /// The visits of one course: how many, how many days apart, and how
  /// many hours each stay lasts.
  final int visitCount;
  final int visitIntervalDays;
  final int stayHours;

  /// The share of its patients who are women, 0 to 1: [pickCondition]
  /// weighs it by the person's sex.
  final double femaleShare;

  /// Whether its first visit is an emergency, made at any hour of day or
  /// night as soon as it starts, rather than at a daytime slot.
  final bool urgent;

  /// The stay of the visits after the first, in hours; null when it is
  /// [stayHours], as for the first. An appendicitis stays two days, its
  /// wound checks an hour.
  final int? followUpStayHours;

  /// A chronic condition's days between the last visit of a course and
  /// the first of the next: null for a random 30 to 120, 0 for no gap at
  /// all (dialysis), the next course starting [visitIntervalDays] after
  /// the last visit as if the course went on.
  final int? courseGapDays;

  /// What a patient says on arrival, [templatesPerVisit] of each kind.
  final List<String> first;
  final List<String> repeat;
  final List<String> last;

  bool get isChronic => type == 'chronic';

  /// The templates of [kind].
  List<String> templates(VisitKind kind) => switch (kind) {
    VisitKind.first => first,
    VisitKind.repeat => repeat,
    VisitKind.last => last,
  };

  /// How many hours a visit of [kind] lasts.
  int stayHoursOf(VisitKind kind) => kind == VisitKind.first ? stayHours : followUpStayHours ?? stayHours;

  /// How much more (above 1) or less likely than average a person of
  /// [sex] is to have it: twice the share of their sex, so a condition
  /// with an even share weighs 1 for both.
  double sexWeight(String? sex) => switch (sex) {
    'woman' => 2 * femaleShare,
    'man' => 2 * (1 - femaleShare),
    _ => 1,
  };

  /// Whether someone [age] years old may have it.
  bool fits(int age) => minAge <= age && age <= maxAge;

  /// The columns of medical_conditions, in [values] order.
  static const columns = [
    'code',
    'name',
    'type',
    'prevalence',
    'min_age',
    'max_age',
    'summary',
    'treatment',
    'treatment_duration_days',
    'duration',
    'visit_count',
    'visit_interval_days',
    'stay_hours',
    'female_share',
    'urgent',
    'follow_up_stay_hours',
    'course_gap_days',
  ];

  List<Object?> get values => [
    code,
    name,
    type,
    prevalence,
    minAge,
    maxAge,
    summary,
    treatment,
    treatmentDurationDays,
    duration,
    visitCount,
    visitIntervalDays,
    stayHours,
    femaleShare,
    urgent,
    followUpStayHours ?? stayHours,
    courseGapDays,
  ];
}

/// A condition for someone [age] years old of [sex], drawn by prevalence,
/// weighed by the share of its patients of that sex
/// ([MedicalCondition.sexWeight]), among the [conditions] whose ages fit
/// (among all of them when none does); null when there are none, or when
/// none can happen to that sex at all.
MedicalCondition? pickCondition(List<MedicalCondition> conditions, int age, Random random, {String? sex}) {
  if (conditions.isEmpty) return null;
  final fitting = conditions.where((c) => c.fits(age)).toList();
  final pool = fitting.isEmpty ? conditions : fitting;
  double weight(MedicalCondition c) => c.prevalence * c.sexWeight(sex);
  final total = pool.fold<double>(0, (sum, c) => sum + weight(c));
  if (total <= 0) return null;
  var draw = random.nextDouble() * total;
  for (final condition in pool) {
    draw -= weight(condition);
    if (draw < 0) return condition;
  }
  return pool.lastWhere((c) => weight(c) > 0);
}

/// [template] with each placeholder replaced by its value in [values];
/// a placeholder without one stays as it is, which a test catches.
String renderComplaint(String template, Map<String, Object> values) =>
    template.replaceAllMapped(_placeholder, (m) => values[m[1]]?.toString() ?? m[0]!);
