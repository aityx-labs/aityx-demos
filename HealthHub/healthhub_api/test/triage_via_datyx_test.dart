import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/triage.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// A stand-in for datyx's gateway or for aityx: answers each call with
/// [answer] (status, body, X-aityx-Mode) and keeps what it was sent.
class _Stub {
  _Stub._(this._server, this.answer);

  static Future<_Stub> start(({int status, String body, String? mode}) answer) async {
    final stub = _Stub._(await HttpServer.bind('127.0.0.1', 0), answer);
    stub._server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      stub.calls.add((path: request.uri.path, headers: request.headers, body: body));
      if (stub.hang) return;
      final answer = stub.answer;
      request.response
        ..statusCode = answer.status
        ..headers.contentType = ContentType.json;
      if (answer.mode != null) request.response.headers.set('X-aityx-Mode', answer.mode!);
      request.response.write(answer.body);
      await request.response.close();
    });
    return stub;
  }

  final HttpServer _server;
  ({int status, String body, String? mode}) answer;

  /// Never answers.
  var hang = false;
  final calls = <({String path, HttpHeaders headers, String body})>[];

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);
}

void main() {
  /// A real aityx answer to the triage of a 71-year-old's pneumonia.
  final answer = File('test/fixtures/triage/answer.json').readAsStringSync();
  const key = 'aityx-key-of-healthhub';
  const token = 'datyx-service-token';
  final admission = {
    'eventId': 'e1',
    'complaint': 'For three days I have had a fever and I am short of breath.',
    'age': 71,
    'conditionCode': 'pneumonia',
    'visit': 'first',
    'template': 0,
  };

  late _Stub aityxStub;
  setUp(() async {
    aityxStub = await _Stub.start((status: 200, body: answer, mode: 'jev_aityx'));
    addTearDown(aityxStub.close);
  });

  /// HealthHub's way to aityx: through [datyx] with the token, else
  /// directly with [withKey].
  Aityx route(Uri datyx, {String withKey = key, List<String>? log, DateTime Function()? clock}) {
    final aityx = Aityx(
      aityxStub.url,
      withKey,
      datyx: datyx,
      serviceToken: token,
      timeout: const Duration(seconds: 5),
      datyxTimeout: const Duration(milliseconds: 300),
      log: log?.add,
      clock: clock,
    );
    addTearDown(aityx.close);
    return aityx;
  }

  /// A port nothing listens on.
  Future<Uri> closedPort() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final url = Uri.parse('http://127.0.0.1:${server.port}');
    await server.close(force: true);
    return url;
  }

  test('only with datyx and a service token do calls go through datyx', () {
    final datyx = Uri.parse('http://127.0.0.1:9900/');
    expect(Aityx(aityxStub.url, key).routesViaDatyx, false);
    expect(Aityx(aityxStub.url, key, datyx: datyx).routesViaDatyx, false);
    expect(Aityx(aityxStub.url, key, serviceToken: token).routesViaDatyx, false);
    final through = Aityx(aityxStub.url, '', datyx: datyx, serviceToken: token);
    expect(through.routesViaDatyx, true);
    expect(through.configured, true);
    expect(through.gateway.toString(), 'http://127.0.0.1:9900/api/aityx/v1/systemone');
    expect(Aityx(aityxStub.url, '', datyx: datyx).configured, false);
  });

  test("through datyx: the token and HealthHub's name and purpose, never aityx's key", () async {
    final datyx = await _Stub.start((status: 200, body: answer, mode: 'jev_aityx'));
    addTearDown(datyx.close);
    final log = <String>[];
    final record = await triageAdmission(route(datyx.url, log: log), admission);

    expect(datyx.calls, hasLength(1));
    final call = datyx.calls.single;
    expect(call.path, '/api/aityx/v1/systemone');
    expect(call.headers.value('x-datyx-service-token'), token);
    expect(call.headers.value('x-datyx-caller'), 'HealthHub');
    expect(call.headers.value('x-datyx-purpose'), 'triage');
    expect(call.headers.value('authorization'), isNull);
    expect(call.headers.contentType?.mimeType, 'application/json');
    expect(jsonDecode(call.body), triageRequest(complaint: admission['complaint'] as String, age: 71));
    expect(call.body, isNot(contains(key)));
    // aityx itself is never called.
    expect(aityxStub.calls, isEmpty);

    expect(record['via'], 'datyx');
    expect(record['level'], 'yellow');
    expect(record['mode'], 'jev_aityx');
    expect(record['error'], isNull);
    expect(jsonEncode(record), isNot(contains(token)));
    expect(log, isEmpty);
  });

  test("when datyx can't be reached, aityx directly with HealthHub's key, noted", () async {
    final log = <String>[];
    final record = await triageAdmission(route(await closedPort(), log: log), admission);
    expect(aityxStub.calls, hasLength(1));
    final call = aityxStub.calls.single;
    expect(call.path, '/v1/systemone');
    expect(call.headers.value('authorization'), 'Bearer $key');
    expect(call.headers.value('x-datyx-service-token'), isNull);
    expect(record['via'], 'aityx');
    expect(record['level'], 'yellow');
    expect(log, ['triage: calling aityx directly, as datyx unreachable']);
    expect(log.join(), isNot(contains(token)));
    expect(log.join(), isNot(contains(key)));
  });

  test("when datyx doesn't answer in time, aityx directly", () async {
    final datyx = await _Stub.start((status: 200, body: answer, mode: null));
    addTearDown(datyx.close);
    datyx.hang = true;
    final log = <String>[];
    final record = await triageAdmission(route(datyx.url, log: log), admission);
    expect(datyx.calls, hasLength(1));
    expect(aityxStub.calls, hasLength(1));
    expect(record['via'], 'aityx');
    expect(log.single, contains('datyx did not answer in time'));
  });

  test('when datyx has no aityx key (503), aityx directly', () async {
    final datyx = await _Stub.start((status: 503, body: '{"error": "datyx has no aityx key"}', mode: null));
    addTearDown(datyx.close);
    final log = <String>[];
    final record = await triageAdmission(route(datyx.url, log: log), admission);
    expect(datyx.calls, hasLength(1));
    expect(aityxStub.calls.single.headers.value('authorization'), 'Bearer $key');
    expect(record['via'], 'aityx');
    expect(record['level'], 'yellow');
    expect(log.single, contains('datyx has no aityx key'));
  });

  test('a datyx without the gateway (404) or refusing the token (401), aityx directly', () async {
    for (final (status, body) in [(404, ''), (401, ''), (401, '{"error": "the service token isn\'t datyx\'s"}')]) {
      final datyx = await _Stub.start((status: status, body: body, mode: null));
      addTearDown(datyx.close);
      final record = await triageAdmission(route(datyx.url, log: []), admission);
      expect(record['via'], 'aityx', reason: '$status $body');
      expect(record['level'], 'yellow', reason: '$status $body');
    }
    expect(aityxStub.calls, hasLength(3));
  });

  test("aityx's own errors and datyx's failing to reach it come back through datyx, without a second call", () async {
    final datyx = await _Stub.start((status: 401, body: '{"error": {"code": "invalid_key"}}', mode: null));
    addTearDown(datyx.close);
    final aityx = route(datyx.url, log: []);
    var record = await triageAdmission(aityx, admission);
    expect(record['error'], 'aityx answered 401: invalid_key');
    expect(record['via'], 'datyx');

    datyx.answer = (status: 502, body: '{"error": "aityx can\'t be reached"}', mode: null);
    record = await triageAdmission(aityx, admission);
    expect(record['error'], "datyx answered 502: aityx can't be reached");
    expect(record['via'], 'datyx');

    // A 503 that isn't the missing key is datyx's answer too.
    datyx.answer = (status: 503, body: '{"error": "busy"}', mode: null);
    record = await triageAdmission(aityx, admission);
    expect(record['error'], 'datyx answered 503: busy');
    expect(aityxStub.calls, isEmpty);
  });

  test("without a key of HealthHub's, a triage datyx can't pass on fails, saying why", () async {
    final record = await triageAdmission(route(await closedPort(), withKey: '', log: []), admission);
    expect(record['error'], 'datyx unreachable, and HealthHub has no aityx key of its own');
    expect(record['via'], 'datyx');
    expect(record['level'], isNull);
    expect(aityxStub.calls, isEmpty);
  });

  test('the calls to aityx directly are noted once a minute, with how many', () async {
    var now = DateTime.utc(2026, 11, 1, 12);
    final log = <String>[];
    final aityx = route(await closedPort(), log: log, clock: () => now);
    for (var i = 0; i < 3; i++) {
      await aityx.call(triageRequest(complaint: 'x', age: 40));
      now = now.add(const Duration(seconds: 20));
    }
    expect(log, hasLength(1));
    // 60 s after the first note: the next, counting the two not noted.
    await aityx.call(triageRequest(complaint: 'x', age: 40));
    expect(log, hasLength(2));
    expect(log.last, 'triage: calling aityx directly, as datyx unreachable (3 calls since the last note)');
    expect(aityxStub.calls, hasLength(4));
  });

  test("the service token alone isn't a key: aityx is available once datyx says it has one", () async {
    var now = DateTime.utc(2026, 11, 1, 12);
    final datyx = await _Stub.start((status: 200, body: '{"configured": false}', mode: null));
    addTearDown(datyx.close);
    final aityx = route(datyx.url, withKey: '', log: [], clock: () => now);
    expect(aityx.configured, true);
    expect(aityx.available, false, reason: 'not before datyx says');
    expect(aityx.status.toString(), '${datyx.url}/api/aityx/v1/status');

    expect(await aityx.check(), false);
    expect(aityx.available, false);
    final asked = datyx.calls.single;
    expect(asked.path, '/api/aityx/v1/status');
    expect(asked.headers.value('x-datyx-service-token'), token);
    expect(asked.headers.value('authorization'), isNull);

    // Asked again only after a minute.
    datyx.answer = (status: 200, body: '{"configured": true}', mode: null);
    now = now.add(const Duration(seconds: 30));
    expect(await aityx.check(), false);
    expect(datyx.calls, hasLength(1));
    now = now.add(const Duration(seconds: 31));
    expect(await aityx.check(), true);
    expect(aityx.available, true);
    expect(datyx.calls, hasLength(2));

    // A call datyx refuses for want of a key says so at once.
    datyx.answer = (status: 503, body: '{"error": "datyx has no aityx key"}', mode: null);
    final record = await triageAdmission(aityx, admission);
    expect(record['error'], 'datyx has no aityx key, and HealthHub has no aityx key of its own');
    expect(aityx.available, false);
    expect(aityxStub.calls, isEmpty);
  });

  test("datyx unreachable, refusing the token or without the status is no key; HealthHub's own key always is", () async {
    expect(await route(await closedPort(), withKey: '', log: []).check(), false);
    for (final (status, body) in [(401, '{"error": "no"}'), (404, ''), (200, 'not json')]) {
      final datyx = await _Stub.start((status: status, body: body, mode: null));
      addTearDown(datyx.close);
      expect(await route(datyx.url, withKey: '', log: []).check(), false, reason: '$status $body');
    }
    final unasked = await _Stub.start((status: 200, body: '{"configured": false}', mode: null));
    addTearDown(unasked.close);
    final own = route(unasked.url, log: []);
    expect(own.available, true);
    expect(await own.check(), true);
    expect(unasked.calls, isEmpty);
    // Neither datyx nor a key: nothing to ask.
    expect(await Aityx(aityxStub.url, '').check(), false);
  });

  test('a call datyx passes on says it has a key', () async {
    final datyx = await _Stub.start((status: 200, body: answer, mode: 'jev_aityx'));
    addTearDown(datyx.close);
    final aityx = route(datyx.url, withKey: '', log: []);
    expect(aityx.available, false);
    final record = await triageAdmission(aityx, admission);
    expect(record['via'], 'datyx');
    expect(aityx.available, true);
  });

  test('admissions are skipped, not recorded as failures, while aityx has no key', () async {
    var ready = false;
    final worked = <Object?>[];
    final triager = Triager((admission) async => worked.add(admission['eventId']), ready: () async => ready);
    triager.triage({'eventId': 'e1'});
    triager.triage({'eventId': 'e2'});
    await triager.idle;
    expect(worked, isEmpty);
    expect(triager.skipped, 2);
    ready = true;
    triager.triage({'eventId': 'e3'});
    await triager.idle;
    expect(worked, ['e3']);
    expect(triager.skipped, 2);
  });

  test("datyx's refusals are its own errors, not aityx's passed back", () {
    expect(datyxRefusal(503, '{"error": "datyx has no aityx key"}'), 'datyx has no aityx key');
    expect(datyxRefusal(503, '{"error": "busy"}'), isNull);
    expect(datyxRefusal(503, '{"error": {"code": "overloaded"}}'), isNull);
    expect(datyxRefusal(404, '<html>Not found</html>'), 'datyx has no aityx gateway');
    expect(datyxRefusal(404, '{"error": {"code": "not_found"}}'), isNull);
    expect(datyxRefusal(401, ''), 'datyx refused the service token (401)');
    expect(datyxRefusal(403, '{"error": "no"}'), 'datyx refused the service token (403)');
    expect(datyxRefusal(401, '{"error": {"code": "invalid_key"}}'), isNull);
    expect(datyxRefusal(200, ''), isNull);
    expect(datyxRefusal(502, '{"error": "aityx can\'t be reached"}'), isNull);
  });

  /// Against the database (HEALTHHUB_DB_*, a scratch one when testing),
  /// when it answers; skipped otherwise. The admissions it writes are
  /// deleted after.
  test('which way each triage went is recorded and read back', () async {
    final settings = DbSettings.fromEnvironment();
    final db = Db(settings);
    addTearDown(db.close);
    if (!await db.ping()) {
      markTestSkipped('PostgreSQL not answering at $settings');
      return;
    }
    await db.migrate();
    const run = 'fffffff1';
    final ids = [for (var i = 1; i <= 4; i++) '$run-test-$i-d1-t090$i'];
    final c = await Connection.open(
      Endpoint(
        host: settings.host,
        port: settings.port,
        database: settings.database,
        username: settings.user,
        password: settings.password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    addTearDown(c.close);
    // Their triages go with them (ON DELETE CASCADE).
    Future<void> clean() => c.execute(
      Sql.named("DELETE FROM admissions WHERE event_id LIKE @run || '-%'"),
      parameters: {'run': run},
    );

    await clean();
    addTearDown(clean);
    for (final (i, id) in ids.indexed) {
      await db.recordAdmission({
        'eventId': id, 'personId': 'test-${i + 1}', 'name': 'Test', 'age': 40, 'sex': 'woman',
        'occupation': 'nurse', 'city': 'Reus', 'conditionCode': 'test', 'conditionName': 'Test',
        'conditionType': 'acute', 'visit': 'first', 'visitNumber': 1, 'complaint': 'test',
        'hospitalId': 900001, 'hospitalName': 'Test hospital', 'day': 1, 'simTime': '09:0$i',
      });
    }
    await db.recordTriage({'eventId': ids[0], 'level': 'green', 'waitMinutes': 120, 'via': 'datyx'});
    await db.recordTriage({'eventId': ids[1], 'error': 'aityx answered 401: invalid_key', 'via': 'aityx'});
    await db.recordTriage({'eventId': ids[2], 'error': 'the triage failed'});
    expect((await db.triageOf(ids[0]))?['via'], 'datyx');
    expect((await db.triageOf(ids[1]))?['via'], 'aityx');
    expect((await db.triageOf(ids[2]))?['via'], isNull);
    final latest = await db.latestTriage(limit: 200);
    expect(latest.firstWhere((row) => row['eventId'] == ids[0])['via'], 'datyx');
    await expectLater(
      db.recordTriage({'eventId': ids[3], 'error': 'x', 'via': 'elsewhere'}),
      throwsA(anything),
    );
  });
}
