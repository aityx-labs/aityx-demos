import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/routes.dart';
import 'package:healthhub_api/triage.dart';
import 'package:test/test.dart';

void main() {
  /// A real aityx answer to the triage of a 71-year-old's pneumonia.
  Map<String, Object?> answer() =>
      (jsonDecode(File('test/fixtures/triage/answer.json').readAsStringSync()) as Map).cast();

  test('the compiled model is the data file, regenerated', () {
    expect(triageModel, jsonDecode(File('data/triage/triage.json').readAsStringSync()));
    expect(triageModel['questions'], isA<Map>());
    expect((triageModel['decision'] as Map)['decisions'], containsPair('level', isA<Map>()));
  });

  test('the request holds the questions, the decision, and only what the desk knows', () {
    final sent = triageRequest(complaint: 'My ankle hurts.', age: 40);
    expect(sent.keys, containsAll(['model', 'questions', 'decision', 'state']));
    expect(sent['state'], {'complaint': 'My ankle hurts.', 'age': 40});
    // Every danger sign and choice is a question, and an input of the decision.
    final questions = (sent['questions'] as Map).keys;
    final inputs = ((sent['decision'] as Map)['inputs'] as Map).keys;
    for (final name in [for (final s in dangerSigns) '${s}_probability', ...triageChoices]) {
      expect(questions, contains(name));
      expect(inputs, contains(name));
    }
  });

  test("aityx's answer reads into the level, the wait, the area and the rules behind them", () {
    final sent = triageRequest(complaint: 'x', age: 71);
    final result = toTriage(sent, answer());
    expect(result.level, 'yellow');
    expect(result.waitMinutes, 60);
    expect(result.area, 'emergency');
    // 71 with a fever: a nurse checks for sepsis.
    expect(result.nurseCheck, true);
    expect(result.levelRule?.rule, 8);
    expect(result.levelRule?.why, 'A fever with signs of serious illness.');
    expect(result.areaRule?.why, contains('emergency department'));
    expect(result.signs.keys, dangerSigns);
    expect(result.signs['serious_infection'], greaterThanOrEqualTo(0.7));
    expect(result.choices['visit_purpose']?.choice, 'new_problem');
    expect(result.choices['body_system']?.choice, 'breathing');
    expect(result.receipt['decisions'], isA<Map>());
    expect(result.inputTokens, greaterThan(0));
  });

  test('an answer without a triage fails, saying why', () {
    final sent = triageRequest(complaint: 'x', age: 71);
    expect(
      () => toTriage(sent, {...answer(), 'decision_error': {'code': 'invalid_state'}}),
      throwsA(isA<TriageFailed>().having((e) => e.message, 'message', contains('invalid_state'))),
    );
    expect(() => toTriage(sent, {'answers': {}}), throwsA(isA<TriageFailed>()));
    final unknown = answer();
    (unknown['answers'] as Map)['level'] = {'type': 'choice', 'choice': 'purple'};
    expect(() => toTriage(sent, unknown), throwsA(isA<TriageFailed>()));
  });

  test("the level and area tables' rules, in order, with their why", () {
    final level = triageRules('level');
    expect(level, hasLength(14));
    expect(level.first, contains('threat to life'));
    expect(level[7], 'A fever with signs of serious illness.');
    expect(triageRules('area').first, contains('resuscitation'));
    expect(triageRules('nothing'), isEmpty);
  });

  test("a template's reference level comes from its condition's data", () {
    final sprain = conditionSeed.firstWhere((c) => c.code == 'ankle_sprain');
    expect(referenceLevel(conditionSeed, 'ankle_sprain', 'first', 0), sprain.triageOf(VisitKind.first)[0]);
    expect(referenceLevel(conditionSeed, 'anaphylaxis', 'first', 1), 'red');
    expect(referenceLevel(conditionSeed, 'ankle_sprain', 'first', null), isNull);
    expect(referenceLevel(conditionSeed, 'ankle_sprain', 'first', 3), isNull);
    expect(referenceLevel(conditionSeed, 'nothing', 'first', 0), isNull);
    expect(referenceLevel(conditionSeed, 'ankle_sprain', 'second', 0), isNull);
  });

  test("aityx's address ends in /v1/systemone, with or without a slash", () {
    expect(Aityx(Uri.parse('https://api.aityx.ai'), 'k').systemone.toString(), 'https://api.aityx.ai/v1/systemone');
    expect(Aityx(Uri.parse('https://x.test/base/'), 'k').systemone.toString(), 'https://x.test/base/v1/systemone');
    expect(Aityx(Uri.parse('https://x.test'), '').configured, false);
  });

  test('a triage that fails is recorded with its error, never the key', () async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    String? authorization;
    server.listen((request) async {
      authorization = request.headers.value('authorization');
      request.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write('{"error": {"code": "invalid_key"}}');
      await request.response.close();
    });
    final aityx = Aityx(Uri.parse('http://127.0.0.1:${server.port}'), 'secret-key');
    addTearDown(aityx.close);
    final record = await triageAdmission(aityx, {
      'eventId': 'e1',
      'complaint': 'My ankle hurts.',
      'age': 40,
      'conditionCode': 'ankle_sprain',
      'visit': 'first',
      'template': 1,
    });
    expect(authorization, 'Bearer secret-key');
    expect(record['eventId'], 'e1');
    expect(record['level'], isNull);
    expect(record['error'], 'aityx answered 401: invalid_key');
    expect(record['reference'], referenceLevel(conditionSeed, 'ankle_sprain', 'first', 1));
    expect(jsonEncode(record), isNot(contains('secret-key')));
  });

  test('the triager runs a few at a time, drops the oldest beyond its limit, and goes idle', () async {
    final started = <Object?>[];
    final gates = <Completer<void>>[];
    final triager = Triager((admission) {
      started.add(admission['eventId']);
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    }, concurrency: 2, limit: 2);
    for (var i = 1; i <= 5; i++) {
      triager.triage({'eventId': 'e$i'});
    }
    // Two run; of the three waiting, the oldest (e3) was dropped.
    expect(started, ['e1', 'e2']);
    expect(triager.pending, 2);
    var idle = false;
    unawaited(triager.idle.then((_) => idle = true));
    gates[0].complete();
    await pumpEventQueue();
    expect(started, ['e1', 'e2', 'e4']);
    for (final gate in gates.skip(1)) {
      if (!gate.isCompleted) gate.complete();
    }
    await pumpEventQueue();
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await pumpEventQueue();
    expect(started, ['e1', 'e2', 'e4', 'e5']);
    expect(idle, true);
    triager.stop();
    triager.triage({'eventId': 'e6'});
    expect(started, hasLength(4));
  });

  group('routes', () {
    final summary = {'total': 1, 'levels': {'yellow': 1}};
    test('GET /api/triage answers the summary and the latest, or why not', () {
      final ok = route('GET', '/api/triage', triageEnabled: true, triage: {'summary': summary, 'triaged': []});
      expect(ok.status, 200);
      expect(ok.body, {'enabled': true, 'summary': summary, 'triaged': []});
      expect(route('GET', '/api/triage').status, 503);
      expect(route('GET', '/api/triage', query: {'limit': '0'}, triage: const {}).status, 400);
    });

    test('GET /api/triage/{eventId} answers one, 404 without one, 503 without the database', () {
      final row = {'eventId': 'a b', 'level': 'red'};
      expect(route('GET', '/api/triage/a%20b', triageDetail: TriageLookup(row)).body, row);
      expect(route('GET', '/api/triage/x', triageDetail: const TriageLookup(null)).status, 404);
      expect(route('GET', '/api/triage/x').status, 503);
      expect(triageEventId('/api/triage/a%20b'), 'a b');
      expect(triageEventId('/api/triage/'), isNull);
      expect(triageEventId('/api/triage/a/b'), isNull);
      expect(triageEventId('/api/triage/%E0%A4%A'), isNull);
      expect(triageEventId('/api/admissions'), isNull);
    });
  });
}
