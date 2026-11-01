import 'dart:io';

import 'package:healthhub_api/triage.dart';
import 'package:test/test.dart';

/// The triage decision's rules, run on aityx.ai with Jev's readings given
/// as facts (a Decision-only call: no questions, so no Jev, and the same
/// facts always give the same answer), checked at each rule and at the
/// thresholds. Needs AITYX_API_KEY (scripts/model-test.sh reads it from
/// .env); skipped without it, so the suite passes offline.
void main() {
  final key = Platform.environment['AITYX_API_KEY'] ?? '';
  final url = Platform.environment['AITYX_URL'] ?? '';
  final aityx = Aityx(Uri.parse(url.isEmpty ? 'https://api.aityx.ai' : url), key);
  tearDownAll(aityx.close);

  /// A patient with no danger sign: a recent, mild problem.
  const calm = <String, Object>{
    'age': 40,
    'life_threat_probability': 0.02,
    'breathing_probability': 0.02,
    'cardiac_probability': 0.02,
    'stroke_probability': 0.02,
    'major_injury_probability': 0.02,
    'serious_infection_probability': 0.02,
    'dehydration_probability': 0.02,
    'self_harm_probability': 0.02,
    'pain': 'mild',
    'onset': 'this_week',
    'visit_purpose': 'new_problem',
    'body_system': 'general',
  };

  /// The decision's answers for [facts] over [calm].
  Future<Map<String, Object?>> decide(Map<String, Object> facts) async {
    final answer = await aityx.call({
      'decision': triageModel['decision'],
      'state': {...calm, ...facts},
    });
    expect(answer.status, 200, reason: '${answer.body}');
    expect(answer.mode, 'defined');
    final answers = answer.body['answers'] as Map;
    Object? value(String name) {
      final a = answers[name] as Map;
      return a['choice'] ?? a['number'] ?? a['noul'];
    }

    return {
      'level': value('level'),
      'wait': value('wait_minutes'),
      'area': value('area'),
      'nurse': value('nurse_check') == 1,
    };
  }

  void check(String name, Map<String, Object> facts, Map<String, Object> expected) {
    test(name, () async {
      if (key.isEmpty) {
        markTestSkipped('AITYX_API_KEY not set');
        return;
      }
      final got = await decide(facts);
      for (final entry in expected.entries) {
        expect(got[entry.key], entry.value, reason: entry.key);
      }
    }, tags: ['aityx']);
  }

  check('no danger sign, a recent problem: standard, minor care', {}, {
    'level': 'green', 'wait': 120, 'area': 'minor_care', 'nurse': false,
  });
  check('an immediate threat to life: resuscitation at once', {'life_threat_probability': 0.9}, {
    'level': 'red', 'wait': 0, 'area': 'resuscitation',
  });
  check('a threat to life wins over every other sign', {
    'life_threat_probability': 0.9, 'self_harm_probability': 0.9, 'pain': 'severe',
  }, {'level': 'red', 'area': 'resuscitation'});
  check('a stroke sign: very urgent', {'stroke_probability': 0.8}, {'level': 'orange', 'wait': 10, 'area': 'emergency'});
  check('struggling to breathe: very urgent', {'breathing_probability': 0.7}, {'level': 'orange'});
  check('just under the threshold, a sign is in doubt: a nurse checks', {'breathing_probability': 0.69}, {
    'level': 'green', 'nurse': true,
  });
  check('below the doubt threshold, nothing', {'breathing_probability': 0.34}, {'nurse': false});
  check('chest pain that may be the heart: very urgent', {'cardiac_probability': 0.75}, {'level': 'orange'});
  check('thoughts of self-harm: very urgent, with the mental health team', {'self_harm_probability': 0.8}, {
    'level': 'orange', 'area': 'mental_health',
  });
  check('severe pain: very urgent', {'pain': 'severe'}, {'level': 'orange', 'area': 'emergency'});
  check('an injury needing treatment: urgent', {'major_injury_probability': 0.9}, {'level': 'yellow', 'wait': 60});
  check('a serious infection: urgent; at 65 or older a nurse checks for sepsis', {
    'serious_infection_probability': 0.9, 'age': 70,
  }, {'level': 'yellow', 'nurse': true});
  check('a serious infection under 65: no nurse check', {'serious_infection_probability': 0.9}, {
    'level': 'yellow', 'nurse': false,
  });
  check('dehydrated: urgent', {'dehydration_probability': 0.8}, {'level': 'yellow'});
  check('moderate pain: urgent', {'pain': 'moderate'}, {'level': 'yellow'});
  check('a booked treatment session: non-urgent, in the day unit', {'visit_purpose': 'treatment_session'}, {
    'level': 'blue', 'wait': 240, 'area': 'day_unit',
  });
  check('a booked review: non-urgent, in outpatients', {'visit_purpose': 'follow_up', 'onset': 'longer'}, {
    'level': 'blue', 'area': 'outpatients',
  });
  check('a danger sign on a booked review still counts', {'visit_purpose': 'follow_up', 'cardiac_probability': 0.9}, {
    'level': 'orange', 'area': 'emergency',
  });
  check('a long-standing problem with nothing new: non-urgent, outpatients', {'onset': 'longer'}, {
    'level': 'blue', 'area': 'outpatients',
  });
  check('low mood with no risk: non-urgent, the mental health team', {
    'onset': 'longer', 'body_system': 'mental_health',
  }, {'level': 'blue', 'area': 'mental_health'});
}
