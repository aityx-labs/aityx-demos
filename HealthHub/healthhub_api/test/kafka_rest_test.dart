import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/kafka_rest.dart';
import 'package:healthhub_api/people_profiles.dart';
import 'package:healthhub_api/simulation.dart';

import 'package:test/test.dart';

import 'simulation_test.dart' show condition;

final cold = condition('cold', 'acute');

/// A stand-in for Karapace: keeps what is produced, hands it to the
/// consumer instances subscribed to its topic on their next poll, and
/// records every request. Instances are named i-1, i-2... in order.
class FakeProxy {
  late final HttpServer server;
  final requests = <(String, String, String?, String?, Object?)>[];
  final produced = <Map<String, Object?>>[];
  var pending = <(String, Map<String, Object?>)>[];
  var up = true;
  var failRecords = false;

  /// The instances' paths and the topics they subscribed to.
  final instances = <String, List<String>>{};

  Uri get url => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final json = body.isEmpty ? null : jsonDecode(body);
      final path = request.uri.path;
      requests.add((
        request.method,
        request.uri.toString(),
        request.headers.contentType?.toString(),
        request.headers.value(HttpHeaders.acceptHeader),
        json,
      ));
      final response = request.response..headers.contentType = ContentType('application', 'vnd.kafka.v2+json');
      Object? answer;
      if (!up) {
        response.statusCode = 500;
        answer = {'error_code': 500, 'message': 'down'};
      } else if (request.method == 'GET' && path == '/topics') {
        answer = ['healthhub.people.moves'];
      } else if (request.method == 'POST' && path.startsWith('/topics/')) {
        final records = ((json as Map)['records'] as List).cast<Map<String, Object?>>();
        produced.addAll(records);
        pending.addAll([for (final record in records) (Uri.decodeComponent(path.substring('/topics/'.length)), record)]);
        answer = {
          'offsets': [
            for (var i = 0; i < records.length; i++)
              failRecords
                  ? {'partition': null, 'offset': null, 'error_code': 1, 'error': 'nope'}
                  : {'partition': 0, 'offset': produced.length - records.length + i, 'error_code': null, 'error': null},
          ],
        };
      } else if (request.method == 'POST' && RegExp(r'^/consumers/[^/]+$').hasMatch(path)) {
        final id = 'i-${instances.length + 1}';
        instances['$path/instances/$id'] = [];
        answer = {'instance_id': id, 'base_uri': 'http://karapace-host:8082$path/instances/$id'};
      } else if (request.method == 'POST' && path.endsWith('/subscription') && instances.containsKey(_parent(path))) {
        instances[_parent(path)] = ((json as Map)['topics'] as List).cast<String>();
        response.statusCode = 204;
      } else if (request.method == 'GET' && path.endsWith('/records') && instances.containsKey(_parent(path))) {
        final topics = instances[_parent(path)]!;
        answer = [
          for (final (i, (topic, record)) in pending.indexed)
            if (topics.contains(topic))
              {'topic': topic, 'key': record['key'], 'value': record['value'], 'partition': 0, 'offset': i},
        ];
        pending = [for (final entry in pending) if (!topics.contains(entry.$1)) entry];
      } else if (request.method == 'DELETE' && instances.containsKey(path)) {
        response.statusCode = 204;
      } else {
        response.statusCode = 404;
        answer = {'error_code': 40401, 'message': 'not found'};
      }
      // UTF-8, as Karapace answers: names have accents.
      if (answer != null) response.add(utf8.encode(jsonEncode(answer)));
      await response.close();
    });
  }
}

String _parent(String path) => path.substring(0, path.lastIndexOf('/'));

void main() {
  late FakeProxy proxy;
  late KafkaRest kafka;

  setUp(() async {
    proxy = FakeProxy();
    await proxy.start();
    kafka = KafkaRest(proxy.url);
  });

  tearDown(() async {
    kafka.close();
    await proxy.server.close(force: true);
  });

  test('ping is whether GET /topics answers 200', () async {
    expect(await kafka.ping(), true);
    proxy.up = false;
    expect(await kafka.ping(), false);
    expect(await KafkaRest(Uri.parse('http://127.0.0.1:1')).ping(), false);
  });

  test('produce posts JSON records to the topic', () async {
    await kafka.produce('healthhub.people.moves', [
      {'key': 'reus-1', 'value': {'id': 'reus-1', 'lat': 41.1}},
    ]);
    final (method, uri, type, _, body) = proxy.requests.single;
    expect(method, 'POST');
    expect(uri, '/topics/healthhub.people.moves');
    expect(type, kafkaJson);
    expect(body, {
      'records': [
        {'key': 'reus-1', 'value': {'id': 'reus-1', 'lat': 41.1}},
      ],
    });
  });

  test('produce throws when the proxy refuses, or a record failed', () async {
    proxy.failRecords = true;
    await expectLater(kafka.produce('t', [{'value': 1}]), throwsA(isA<KafkaRestException>()));
    proxy
      ..failRecords = false
      ..up = false;
    await expectLater(
      kafka.produce('t', [{'value': 1}]),
      throwsA(isA<KafkaRestException>().having((e) => e.status, 'status', 500)),
    );
  });

  test('a consumer is created, subscribed, reads records and is deleted', () async {
    final consumer = await kafka.consumer('g', ['healthhub.people.moves']);
    await kafka.produce('healthhub.people.moves', [
      {'key': 'reus-1', 'value': {'id': 'reus-1'}},
      {'key': 'reus-2', 'value': {'id': 'reus-2'}},
    ]);
    final records = await consumer.poll(timeout: const Duration(milliseconds: 200));
    expect(records.map((r) => r.key), ['reus-1', 'reus-2']);
    expect(records.first.value, {'id': 'reus-1'});
    expect(records.last.offset, 1);
    expect(await consumer.poll(), isEmpty);
    await consumer.close();

    final calls = [for (final (method, uri, _, _, _) in proxy.requests) '$method $uri'];
    expect(calls, [
      'POST /consumers/g',
      'POST /consumers/g/instances/i-1/subscription',
      'POST /topics/healthhub.people.moves',
      'GET /consumers/g/instances/i-1/records?timeout=200',
      'GET /consumers/g/instances/i-1/records?timeout=1000',
      'DELETE /consumers/g/instances/i-1',
    ]);
    final (_, _, createType, _, create) = proxy.requests.first;
    expect(createType, kafkaV2);
    expect(create, {'format': 'json', 'auto.offset.reset': 'latest', 'auto.commit.enable': 'true'});
    expect(proxy.requests[1].$5, {'topics': ['healthhub.people.moves']});
    expect(proxy.requests[3].$4, kafkaJson);
  });

  test('every person publishes a move every turn, read back by the feed', () async {
    final places = [
      const Place(id: 1, name: 'Hospital Sant Joan', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076)),
      const Place(id: 2, name: 'CAP', kind: 'health_station', city: 'Cornudella de Montsant', at: LatLon(41.2648, 0.9063)),
    ];
    final people = populate(places, 2, 60, Random(5));
    // Reus's first person is due at the hospital on the first morning.
    people.first.beginAcute(cold, simStartMinutes, Random(5));
    final simulation = Simulation(
      people,
      const SimulationSettings(turn: Duration(milliseconds: 15)),
      kafka,
      conditions: [cold],
    )..start();
    expect(simulation.running, true);
    // Past 17:00 of day 1, the latest a visit starts: 12 turns.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    simulation.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final admissions = [
      for (final (_, uri, _, _, body) in proxy.requests)
        if (uri == '/topics/healthhub.admissions') ...((body as Map)['records'] as List).cast<Map>(),
    ];
    expect(admissions, hasLength(1));
    expect(admissions.single['key'], 'reus-1');
    expect((admissions.single['value'] as Map)['type'], 'admission');
    expect((admissions.single['value'] as Map)['eventId'], startsWith('${simulation.run}-reus-1-d1-'));

    final turns = <String, List<int>>{};
    for (final record in proxy.produced) {
      final value = record['value'] as Map;
      if (value['type'] == 'admission') continue;
      expect(record['key'], value['id']);
      turns.putIfAbsent(value['id'] as String, () => []).add(value['turn'] as int);
    }
    expect(turns.keys, unorderedEquals(['reus-1', 'reus-2', 'cornudella-de-montsant-1', 'cornudella-de-montsant-2']));
    for (final list in turns.values) {
      expect(list.first, 0);
      expect(list.length, greaterThanOrEqualTo(3));
      // In order, and never twice the same turn.
      expect(list.toSet().length, list.length);
      expect([...list]..sort(), list);
    }

    final recorded = <Map<String, Object?>>[];
    final feed = PeopleFeed(kafka, people: [for (final person in people) person.id], onAdmission: recorded.add);
    final consumer = await kafka.consumer('g', [movesTopic, admissionsTopic]);
    for (final record in await consumer.poll()) {
      feed.addRecord(record);
    }
    expect(feed.people, hasLength(4));
    expect(recorded.single['personId'], 'reus-1');
    expect(feed.recent.where((e) => e['type'] == 'admission'), hasLength(1));
  });

  test('a consumer reads from the earliest records when asked, and nothing else', () async {
    final consumer = await kafka.consumer('stable', [admissionsTopic], offsetReset: 'earliest');
    await consumer.close();
    expect(proxy.requests.first.$5, {'format': 'json', 'auto.offset.reset': 'earliest', 'auto.commit.enable': 'true'});
    expect(() => kafka.consumer('g', ['t'], offsetReset: 'none'), throwsArgumentError);
  });

  test('the feed reads moves as its own new group and admissions as the stable one, and deletes both', () async {
    final recorded = <Map<String, Object?>>[];
    final feed = PeopleFeed(kafka, people: ['reus-1'], onAdmission: recorded.add, random: Random(8));
    final running = feed.run();
    final admission = admissionEvent(
      Person(
        id: 'reus-1',
        city: 'Reus',
        home: const LatLon(41.16, 1.11),
        hospital: const Place(id: 1, name: 'H', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076)),
        profile: const Profile(firstName: 'Núria', lastName: 'Puig Soler', age: 54, sex: 'woman', occupation: 'teacher'),
        minutesPerTurn: 60,
      ),
      condition: cold,
      run: 'abcd1234',
      turn: 3,
      minutes: simMinutes(3, 60),
      kind: VisitKind.first,
      visitNumber: 1,
      complaint: 'I have a cold.',
    );
    // The same admission twice, as a replay would: recorded once.
    await kafka.produce(admissionsTopic, [
      for (var i = 0; i < 2; i++) {'key': 'reus-1', 'value': admission},
    ]);
    for (var i = 0; i < 100 && recorded.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await feed.stop();
    await running;
    expect(recorded, [admission]);

    final creates = {
      for (final (method, uri, _, _, body) in proxy.requests)
        if (method == 'POST' && RegExp(r'^/consumers/[^/]+$').hasMatch(uri)) Uri.decodeComponent(uri.split('/').last): body,
    };
    expect(creates.keys, unorderedEquals([feed.group, PeopleFeed.admissionsGroup]));
    expect(feed.group, isNot(PeopleFeed.admissionsGroup));
    expect(PeopleFeed.admissionsGroup, 'healthhub-api-admissions');
    expect((creates[feed.group] as Map)['auto.offset.reset'], 'latest');
    expect((creates[PeopleFeed.admissionsGroup] as Map)['auto.offset.reset'], 'earliest');
    final subscriptions = {
      for (final (method, uri, _, _, body) in proxy.requests)
        if (method == 'POST' && uri.endsWith('/subscription')) uri: (body as Map)['topics'],
    };
    expect(subscriptions.values, unorderedEquals([
      [movesTopic],
      [admissionsTopic],
    ]));
    // Both consumers deleted on stop.
    final deleted = [for (final (method, uri, _, _, _) in proxy.requests) if (method == 'DELETE') uri];
    expect(deleted, unorderedEquals(proxy.instances.keys));
    expect(deleted, hasLength(2));
  });
}
