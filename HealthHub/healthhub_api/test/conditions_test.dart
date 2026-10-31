import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:test/test.dart';

import '../tool/generate_conditions.dart';

void main() {
  const fixtures = 'test/fixtures/conditions';
  Map<String, Object?> influenza() =>
      ((jsonDecode(File('$fixtures/acute.json').readAsStringSync()) as List).single as Map).cast();

  test('the fixture reads into conditions, acute then chronic', () {
    final conditions = readConditions(fixtures);
    expect(conditions.map((c) => c.code), ['influenza', 'type_2_diabetes']);
    final flu = conditions.first;
    expect(flu.type, 'acute');
    expect(flu.treatmentDurationDays, 7);
    expect((flu.visitCount, flu.visitIntervalDays, flu.stayHours), (2, 3, 3));
    expect(flu.templates(VisitKind.repeat), hasLength(3));
    expect(flu.values, hasLength(MedicalCondition.columns.length));
    expect(conditions.last.isChronic, true);
    expect(conditions.last.treatmentDurationDays, isNull);
  });

  test('a missing or empty directory is no conditions', () {
    final empty = Directory.systemTemp.createTempSync('conditions');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(readConditions(empty.path), isEmpty);
    expect(readConditions('${empty.path}/none'), isEmpty);
  });

  test('every problem of an element is reported', () {
    final bad = {
      ...influenza(),
      'code': 'Influenza!',
      'type': 'chronic',
      'prevalence': 0,
      'min_age': 10,
      'treatment_duration_days': null,
      'visits': {'count': 0, 'interval_days': 1, 'stay_hours': 100},
      'templates': {
        'first': ['Hi {nickname}', 'a {name', 'a'],
        'repeat': ['x', 'x', 'y'],
        'last': ['only one'],
      },
    };
    final problems = MedicalCondition.problems(bad, type: 'acute');
    expect(
      problems.join('\n'),
      allOf([
        contains('"code"'),
        contains('"type"'),
        contains('"prevalence"'),
        contains('"min_age"'),
        contains('"treatment_duration_days"'),
        contains('visits.count'),
        contains('visits.stay_hours'),
        contains('{nickname}'),
        contains('stray brace'),
        contains('repeats a template'),
        contains('"templates.last"'),
      ]),
    );
    expect(() => MedicalCondition.fromJson(bad, type: 'acute'), throwsFormatException);
    expect(MedicalCondition.problems(influenza(), type: 'acute'), isEmpty);
    // A chronic condition has no treatment duration.
    expect(MedicalCondition.problems({...influenza(), 'type': 'chronic'}, type: 'chronic'), isNotEmpty);
  });

  test('a duplicate code or a bad element fails the whole read, naming it', () {
    final dir = Directory.systemTemp.createTempSync('conditions');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/acute.json').writeAsStringSync(jsonEncode([influenza(), influenza()]));
    expect(
      () => readConditions(dir.path),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('duplicate code influenza'))),
    );
    File('${dir.path}/acute.json').writeAsStringSync(
      jsonEncode([
        {...influenza(), 'name': ''},
      ]),
    );
    expect(
      () => readConditions(dir.path),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('acute.json[0] (influenza)'))),
    );
  });

  test('the compiled seed is the data files, regenerated', () {
    final data = readConditions(inputDir);
    expect(conditionSeed.map((c) => c.values), data.map((c) => c.values));
    for (final kind in VisitKind.values) {
      expect(conditionSeed.map((c) => c.templates(kind)), data.map((c) => c.templates(kind)));
    }
  });

  test('the optional fields default, and are checked when set', () {
    final flu = MedicalCondition.fromJson(influenza(), type: 'acute');
    expect((flu.femaleShare, flu.urgent, flu.followUpStayHours, flu.courseGapDays), (0.5, false, null, null));
    expect(flu.stayHoursOf(VisitKind.repeat), flu.stayHours);
    expect(flu.values.sublist(flu.values.length - 4), [0.5, false, flu.stayHours, null]);
    final set = MedicalCondition.fromJson(
      {...influenza(), 'female_share': 0.8, 'urgent': true, 'follow_up_stay_hours': 1},
      type: 'acute',
    );
    expect((set.femaleShare, set.urgent, set.followUpStayHours), (0.8, true, 1));
    expect(set.stayHoursOf(VisitKind.first), 3);
    expect(set.stayHoursOf(VisitKind.last), 1);
    final problems = MedicalCondition.problems({
      ...influenza(),
      'female_share': 1.5,
      'urgent': 'yes',
      'follow_up_stay_hours': 0,
      'course_gap_days': 30,
    }, type: 'acute');
    expect(
      problems.join('\n'),
      allOf([
        contains('"female_share"'),
        contains('"urgent"'),
        contains('"follow_up_stay_hours"'),
        contains('"course_gap_days" is set, but only a chronic condition'),
      ]),
    );
    final diabetes = readConditions(fixtures).last;
    final chronic = {
      'code': diabetes.code,
      'name': diabetes.name,
      'type': 'chronic',
      'prevalence': 1,
      'min_age': 30,
      'max_age': 90,
      'summary': 's',
      'treatment': 't',
      'treatment_duration_days': null,
      'duration': 'd',
      'visits': {'count': 2, 'interval_days': 2, 'stay_hours': 4},
      'templates': {for (final kind in VisitKind.values) kind.json: diabetes.templates(kind)},
    };
    expect(MedicalCondition.problems({...chronic, 'course_gap_days': 0}, type: 'chronic'), isEmpty);
    expect(MedicalCondition.fromJson({...chronic, 'course_gap_days': 0}, type: 'chronic').courseGapDays, 0);
    expect(MedicalCondition.problems({...chronic, 'course_gap_days': -1}, type: 'chronic'), isNotEmpty);
    expect(MedicalCondition.problems({...chronic, 'female_share': 'half'}, type: 'chronic'), isNotEmpty);
  });

  test("a condition is weighed by its share of the person's sex", () {
    final chronic = [for (final c in conditionSeed) if (c.isChronic) c];
    final breast = conditionSeed.firstWhere((c) => c.code == 'breast_cancer');
    expect(breast.femaleShare, 0.99);
    expect(breast.sexWeight('woman'), closeTo(1.98, 1e-9));
    expect(breast.sexWeight('man'), closeTo(0.02, 1e-9));
    expect(breast.sexWeight(null), 1);
    final random = Random(6);
    int count(String sex, String code, int draws) {
      var n = 0;
      for (var i = 0; i < draws; i++) {
        if (pickCondition(chronic, 60, random, sex: sex)?.code == code) n++;
      }
      return n;
    }

    // Breast cancer: in about 1 man in 20,000 here, at most rare.
    expect(count('man', 'breast_cancer', 20000), lessThanOrEqualTo(5));
    expect(count('woman', 'breast_cancer', 20000), greaterThan(50));
    // Hypothyroidism, 80% women: four times as common among them.
    final women = count('woman', 'hypothyroidism', 20000);
    final men = count('man', 'hypothyroidism', 20000);
    expect(women / men, closeTo(4, 1.2));
    // A condition no one of that sex can have is never drawn for them.
    final onlyWomen = MedicalCondition.fromJson({...influenza(), 'female_share': 1}, type: 'acute');
    expect(pickCondition([onlyWomen], 40, random, sex: 'man'), isNull);
    expect(pickCondition([onlyWomen], 40, random, sex: 'woman'), onlyWomen);
  });

  test('the visit kind follows the visit number and the course', () {
    expect(VisitKind.of(1, 1), VisitKind.first);
    expect(VisitKind.of(1, 3), VisitKind.first);
    expect(VisitKind.of(2, 3), VisitKind.repeat);
    expect(VisitKind.of(3, 3), VisitKind.last);
    expect(VisitKind.of(2, 2), VisitKind.last);
  });

  test('a condition is drawn by prevalence among those fitting the age', () {
    final conditions = readConditions(fixtures);
    final random = Random(5);
    // Diabetes starts at 30 here: never for a 20-year-old.
    for (var i = 0; i < 100; i++) {
      expect(pickCondition(conditions, 20, random)?.code, 'influenza');
    }
    // At 60 both fit, in about their prevalence's ratio (8 to 9.5).
    var diabetes = 0;
    for (var i = 0; i < 4000; i++) {
      if (pickCondition(conditions, 60, random)!.code == 'type_2_diabetes') diabetes++;
    }
    expect(diabetes / 4000, closeTo(9.5 / 17.5, 0.03));
    expect(pickCondition(const [], 40, random), isNull);
  });

  test('every placeholder renders, and every seed template renders fully', () {
    const values = {
      'name': 'Núria Puig Soler',
      'first_name': 'Núria',
      'age': 54,
      'sex': 'woman',
      'occupation': 'teacher',
      'city': 'Reus',
      'hospital': 'Hospital Sant Joan',
      'visit_number': 2,
      'days_since_first_visit': 3,
    };
    expect(values.keys.toSet(), complaintPlaceholders);
    expect(
      renderComplaint(
        '{name}, {age}, a {sex} {occupation} from {city}, at {hospital}: visit {visit_number}, day {days_since_first_visit}',
        values,
      ),
      'Núria Puig Soler, 54, a woman teacher from Reus, at Hospital Sant Joan: visit 2, day 3',
    );
    for (final condition in [...readConditions(fixtures), ...conditionSeed]) {
      for (final kind in VisitKind.values) {
        for (final template in condition.templates(kind)) {
          final text = renderComplaint(template, values);
          expect(text, isNot(contains('{')), reason: '${condition.code}: $template');
          expect(text, isNot(contains('}')), reason: '${condition.code}: $template');
        }
      }
    }
  });
}
