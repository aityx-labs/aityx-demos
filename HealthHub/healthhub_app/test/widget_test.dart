import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthhub_app/api/health_hub_api.dart';
import 'package:healthhub_app/auth/auth_controller.dart';
import 'package:healthhub_app/location/location_controller.dart';
import 'package:healthhub_app/main.dart';
import 'package:healthhub_app/persist/session_store.dart';
import 'package:latlong2/latlong.dart';

/// An API with sign-in on or off, a hospital, a clinic and a health
/// station in Lisbon, and, with [simulation], two simulated people there.
class FakeApi implements HealthHubApi {
  FakeApi({this.auth = true, this.truncated = false, this.simulation = false});

  final bool auth;
  final bool truncated;
  final bool simulation;

  /// How many times the map asked for the people.
  int peopleAsked = 0;

  /// The types the events card asked for, in order.
  final eventTypes = <StreamEventType?>[];

  @override
  Future<StreamEvents> events({int limit = 20, StreamEventType? type}) async {
    eventTypes.add(type);
    if (!simulation) return const StreamEvents(enabled: false);
    final all = [
      // Older than the moves, so it sorts below them.
      const StreamEvent(
        id: 'lisboa-3',
        type: StreamEventType.admission,
        state: PersonState.atHospital,
        name: 'Inês Carvalho',
        age: 67,
        sex: 'woman',
        city: 'Lisboa',
        conditionCode: 'type_2_diabetes',
        conditionName: 'Type 2 diabetes',
        conditionType: ConditionType.chronic,
        visit: VisitKind.repeat,
        visitNumber: 2,
        complaint: "Hi, I'm Inês Carvalho, 67, back for my sugar check. The new tablets upset my stomach a little.",
        hospitalId: 7,
        hospitalName: 'Hospital de Santa Maria',
        simTime: '08:00',
        day: 2,
        partition: 0,
        offset: 9,
        eventId: 'lisboa-3-d2-t32',
      ),
      const StreamEvent(id: 'lisboa-1', state: PersonState.toHospital, hospitalName: 'Hospital de Santa Maria', simTime: '09:40', day: 2, partition: 0, offset: 42),
      const StreamEvent(id: 'lisboa-2', state: PersonState.home, simTime: '09:40', day: 2, partition: 0, offset: 41),
    ];
    return StreamEvents(
      enabled: true,
      topics: [type == StreamEventType.admission ? 'healthhub.admissions' : 'healthhub.people.moves'],
      events: [
        for (final event in all)
          if (type == null || event.type == type) event,
      ],
    );
  }

  @override
  Future<People> people({
    required double west,
    required double south,
    required double east,
    required double north,
  }) async {
    peopleAsked++;
    if (!simulation) return const People(enabled: false);
    return const People(
      enabled: true,
      simTime: '09:40',
      day: 2,
      people: [
        Person(
          id: 'lisboa-1',
          city: 'Lisboa',
          lat: 38.725,
          lon: -9.145,
          homeLat: 38.718,
          homeLon: -9.138,
          state: PersonState.toHospital,
          hospitalName: 'Hospital de Santa Maria',
        ),
        Person(
          id: 'lisboa-2',
          city: 'Lisboa',
          lat: 38.73,
          lon: -9.15,
          homeLat: 38.712,
          homeLon: -9.13,
          state: PersonState.atHospital,
          hospitalName: 'Hospital de Santa Maria',
          name: 'João Silva',
          age: 54,
          conditionName: 'Influenza',
          conditionType: ConditionType.acute,
        ),
      ],
    );
  }

  /// The areas the map asked for: [west, south, east, north].
  final asked = <List<double>>[];

  @override
  Future<CareCenters> careCenters({
    required double west,
    required double south,
    required double east,
    required double north,
  }) async {
    asked.add([west, south, east, north]);
    return CareCenters(const [
      CareCenter(id: 1, name: 'Hospital de Santa Maria', kind: CareCenterKind.hospital, lat: 38.73, lon: -9.15),
      CareCenter(id: 2, name: 'Clínica do Campo', kind: CareCenterKind.clinic, lat: 38.722, lon: -9.141, subtype: 'Policlínica'),
      CareCenter(id: 3, name: 'Centro de Saúde', kind: CareCenterKind.healthStation, lat: 38.715, lon: -9.135),
    ], truncated: truncated);
  }

  @override
  Future<AuthConfig> authConfig() async => AuthConfig(
    enabled: auth,
    issuer: 'https://accounts.google.com',
  );

  @override
  Future<Health> health() async => Health(ok: true, db: true, aityx: false);

  @override
  Future<Me> me() async => const Me(authenticated: false);

  @override
  Future<Me> datyxMe() async => const Me(authenticated: false);

  @override
  Future<int> datyxDataSources() async => 0;

  @override
  Future<Greeting> hello() async => Greeting(message: 'Hello, world', since: null, postgres: 'PostgreSQL 17.6');
}

/// A sign-in that is on and says who is signed in, without Google.
class FakeAuth extends AuthController {
  FakeAuth({this.signedInAs});

  SignedInUser? signedInAs;
  AuthConfig? _config;

  @override
  Future<void> start(AuthConfig config) async {
    _config = config;
    notifyListeners();
  }

  @override
  AuthConfig? get config => _config;

  @override
  bool get enabled => _config?.enabled ?? false;

  @override
  bool get signedIn => signedInAs != null;

  @override
  SignedInUser? get user => signedInAs;

  @override
  Future<void> signOut() async {
    signedInAs = null;
    notifyListeners();
  }
}

/// Locations a test hands out, or a problem.
class FakeLocations implements LocationSource {
  FakeLocations({this.problem});

  final LocationProblem? problem;
  final _controller = StreamController<UserLocation>.broadcast();

  void move(double lat, double lng) => _controller.add(UserLocation(LatLng(lat, lng), accuracy: 30));

  @override
  Stream<UserLocation> watch() =>
      problem != null ? Stream.error(problem!) : _controller.stream;
}

Widget app({FakeApi? api, FakeAuth? auth, FakeLocations? locations}) => HealthHubApp(
  api: api ?? FakeApi(),
  auth: auth ?? FakeAuth(),
  location: LocationController(source: locations ?? FakeLocations()),
  showTiles: false,
);

void main() {
  testWidgets('the index: a map and the welcome for someone not signed in', (tester) async {
    final locations = FakeLocations();
    await tester.pumpWidget(app(locations: locations));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to HealthHub'), findsOneWidget);
    expect(find.text('Finding where you are…'), findsOneWidget);
    expect(find.byKey(const Key('you-are-here')), findsNothing);

    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    expect(find.text('The orange dot is you.'), findsOneWidget);
    expect(find.byKey(const Key('you-are-here')), findsOneWidget);
    expect(find.byKey(const Key('location-tile')), findsNothing);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('you-are-here')), findsOneWidget);
  });

  testWidgets('says why when the location is refused, and asks again', (tester) async {
    await tester.pumpWidget(
      app(
        locations: FakeLocations(
          problem: const LocationProblem(LocationStatus.denied, 'Allow location access to see where you are.'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allow location access to see where you are.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(const Key('you-are-here')), findsNothing);
  });

  testWidgets('home after signing in: a dashboard with the map tile', (tester) async {
    final auth = FakeAuth(signedInAs: const SignedInUser(name: 'Ada', email: 'ada@example.com'));
    final locations = FakeLocations();
    await tester.pumpWidget(app(auth: auth, locations: locations));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to HealthHub'), findsNothing);
    expect(find.text('HealthHub'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byKey(const Key('location-tile')), findsOneWidget);
    expect(find.text('Where you are'), findsOneWidget);

    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('you-are-here')), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to HealthHub'), findsOneWidget);
  });

  testWidgets('the care centers in view are pinned, each kind with its icon', (tester) async {
    final api = FakeApi(truncated: true);
    final locations = FakeLocations();
    await tester.pumpWidget(app(api: api, locations: locations));
    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    // The map asks once it has stood still.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(api.asked, isNotEmpty);
    final [west, south, east, north] = api.asked.last;
    expect(west < -9.14 && -9.14 < east && south < 38.72 && 38.72 < north, isTrue);
    expect(find.byKey(const Key('care-center-1')), findsOneWidget);
    expect(find.byKey(const Key('care-center-2')), findsOneWidget);
    expect(find.byKey(const Key('care-center-3')), findsOneWidget);
    expect(find.byIcon(Icons.local_hospital), findsNWidgets(2)); // the pin and the legend
    expect(find.byIcon(Icons.medical_services), findsNWidgets(2));
    expect(find.byIcon(Icons.health_and_safety), findsNWidgets(2));
    expect(find.byKey(const Key('care-center-legend')), findsOneWidget);
    expect(find.text('Health station'), findsOneWidget);
    expect(find.text('Zoom in to see them all'), findsOneWidget);
    expect(find.byTooltip('Clínica do Campo\nPoliclínica'), findsOneWidget);
  });

  testWidgets('in dev mode the simulated people and their homes are drawn', (tester) async {
    final api = FakeApi(simulation: true);
    final locations = FakeLocations();
    await tester.pumpWidget(app(api: api, locations: locations));
    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    // The map asks for the people in view once it has stood still.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-lisboa-1')), findsOneWidget);
    expect(find.byKey(const Key('person-lisboa-2')), findsOneWidget);
    expect(find.byKey(const Key('home-lisboa-1')), findsOneWidget);
    expect(find.byKey(const Key('home-lisboa-2')), findsOneWidget);
    expect(find.byIcon(Icons.home), findsNWidgets(3)); // two homes and the legend
    expect(find.byTooltip('lisboa-1\nGoing to the hospital · Hospital de Santa Maria · 09:40'), findsOneWidget);
    // With a profile, the tooltip also says who they are and their condition.
    expect(
      find.byTooltip('João Silva, 54, lisboa-2\nInfluenza (acute)\nAt the hospital · Hospital de Santa Maria · 09:40'),
      findsOneWidget,
    );
    expect(find.text('Simulated time 09:40, day 2'), findsOneWidget);
    expect(find.text('Person, at the hospital'), findsOneWidget);

    // It keeps following them while the map is shown, every 5 seconds.
    final asked = api.peopleAsked;
    await tester.pump(const Duration(seconds: 2));
    expect(api.peopleAsked, asked);
    await tester.pump(const Duration(seconds: 3));
    expect(api.peopleAsked, greaterThan(asked));
  });

  testWidgets('nothing of the simulation shows when it is off', (tester) async {
    final api = FakeApi();
    final locations = FakeLocations();
    await tester.pumpWidget(app(api: api, locations: locations));
    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(api.peopleAsked, greaterThan(0));
    expect(find.byKey(const Key('person-lisboa-1')), findsNothing);
    expect(find.byIcon(Icons.home), findsNothing);
    expect(find.byKey(const Key('sim-time')), findsNothing);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('home lists the latest events on the stream under the map', (tester) async {
    // Tall enough for the card under the map.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(api: FakeApi(auth: false, simulation: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stream-events')), findsOneWidget);
    expect(find.text('On Kafka, healthhub.people.moves, healthhub.admissions; every 5 seconds'), findsOneWidget);
    expect(find.text('lisboa-1'), findsOneWidget);
    expect(find.text('Going to the hospital · Hospital de Santa Maria'), findsOneWidget);
    expect(find.text('p0 · #42'), findsOneWidget);
    expect(find.text('At home'), findsOneWidget);
  });

  testWidgets('an admission stands out in the events, with the complaint in full', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    // Moves and admissions are asked for apart, so moves can't push the
    // admissions out.
    expect(api.eventTypes, containsAll([StreamEventType.move, StreamEventType.admission]));
    expect(find.text('1 admission · 2 moves'), findsOneWidget);

    final row = find.byKey(const Key('admission-lisboa-3-d2-t32'));
    expect(row, findsOneWidget);
    Finder inRow(Finder finder) => find.descendant(of: row, matching: finder);
    expect(inRow(find.byIcon(Icons.local_hospital)), findsOneWidget);
    expect(inRow(find.text('Inês Carvalho, 67  Type 2 diabetes (chronic)', findRichText: true)), findsOneWidget);
    expect(inRow(find.text('Return visit, the 2nd · Hospital de Santa Maria')), findsOneWidget);
    expect(inRow(find.text('08:00, day 2')), findsOneWidget);
    expect(inRow(find.text('p0 · #9')), findsOneWidget);
    final complaint = tester.widget<Text>(inRow(find.textContaining('back for my sugar check')));
    expect(complaint.data, "“Hi, I'm Inês Carvalho, 67, back for my sugar check. The new tablets upset my stomach a little.”");
    expect(complaint.style?.fontStyle, FontStyle.italic);
    expect(complaint.overflow, isNull); // wrapped, never cut

    // The admission's orange bar sets it apart from the moves.
    final box = tester.widget<Container>(row).decoration! as BoxDecoration;
    expect((box.border! as Border).left.color, const Color(0xFFE36742));
    // It sorts by simulated time: 08:00 is older than the moves at 09:40.
    expect(tester.getTopLeft(row).dy, greaterThan(tester.getTopLeft(find.text('lisboa-1')).dy));
  });

  test('stream events read admissions and moves from the API', () {
    final events = StreamEvents.fromJson({
      'enabled': true,
      'topics': ['healthhub.people.moves', 'healthhub.admissions'],
      'events': [
        {
          'type': 'admission',
          'eventId': 'reus-3-d4-t90',
          'personId': 'reus-3',
          'name': 'Jordi Puig',
          'age': 41,
          'sex': 'man',
          'occupation': 'Electrician',
          'city': 'Reus',
          'conditionCode': 'influenza',
          'conditionName': 'Influenza',
          'conditionType': 'acute',
          'visit': 'last',
          'visitNumber': 3,
          'complaint': 'Feeling much better now.',
          'hospitalId': 12,
          'hospitalName': 'Hospital Sant Joan de Reus',
          'simTime': '10:00',
          'day': 4,
          'turn': 90,
          'partition': 0,
          'offset': 77,
        },
        {'type': 'move', 'id': 'reus-4', 'state': 'to_home', 'simTime': '10:00', 'day': 4, 'name': 'Anna Vidal', 'age': 33},
        // The records before admissions existed carried no type and a single topic.
        {'id': 'reus-5', 'state': 'home'},
        {'type': 'admission'}, // no person: left out
      ],
    });
    expect(events.topics, ['healthhub.people.moves', 'healthhub.admissions']);
    expect(events.events, hasLength(3));
    final admission = events.events[0];
    expect(admission.isAdmission, isTrue);
    expect(admission.id, 'reus-3');
    expect(admission.state, PersonState.atHospital);
    expect(admission.conditionType, ConditionType.acute);
    expect(admission.visit, VisitKind.last);
    expect(admission.visitNumber, 3);
    expect(admission.hospitalId, 12);
    expect(events.events[1].isAdmission, isFalse);
    expect(events.events[1].name, 'Anna Vidal');
    expect(events.events[2].type, StreamEventType.move);
    expect(StreamEvents.fromJson({'enabled': true, 'topic': 'healthhub.people.moves'}).topics, ['healthhub.people.moves']);
  });

  testWidgets('no events card when the simulation is off', (tester) async {
    await tester.pumpWidget(app(api: FakeApi(auth: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-tile')), findsOneWidget);
    expect(find.byKey(const Key('stream-events')), findsNothing);
  });

  testWidgets('home straight away when the API has sign-in off', (tester) async {
    await tester.pumpWidget(app(api: FakeApi(auth: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-tile')), findsOneWidget);
    expect(find.text('Welcome to HealthHub'), findsNothing);
  });

  group('sign-in outlives a reload', () {
    const config = AuthConfig(enabled: true, issuer: 'https://accounts.google.com', clientId: 'client-1');

    String token({required Duration expiresIn, String aud = 'client-1'}) {
      String part(Map<String, Object?> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
      return [
        part({'alg': 'RS256'}),
        part({'aud': aud, 'exp': exp, 'email': 'tests@example.com', 'name': 'Tests'}),
        'signature',
      ].join('.');
    }

    test('a fresh token signs in at once, before the API answers', () async {
      final kept = token(expiresIn: const Duration(minutes: 30));
      final auth = AuthController(store: SessionStore.memory()..write('idToken', kept));
      expect(auth.signedIn, isTrue);
      expect(auth.user?.email, 'tests@example.com');
      expect(auth.user?.name, 'Tests');
      await auth.start(config);
      expect(auth.signedIn, isTrue);
      expect(await auth.token(), kept);
    });

    test('an expired token, or another client\'s, is dropped', () async {
      for (final kept in [
        token(expiresIn: const Duration(seconds: 30)),
        token(expiresIn: const Duration(minutes: 30), aud: 'client-2'),
        'not a token',
      ]) {
        final store = SessionStore.memory()..write('idToken', kept);
        final auth = AuthController(store: store);
        await auth.start(config);
        expect(auth.signedIn, isFalse, reason: kept);
        expect(store.read('idToken'), isNull, reason: kept);
      }
    });

    test('signing out forgets the token', () async {
      final store = SessionStore.memory()..write('idToken', token(expiresIn: const Duration(minutes: 30)));
      final auth = AuthController(store: store);
      await auth.start(config);
      await auth.signOut();
      expect(auth.signedIn, isFalse);
      expect(store.read('idToken'), isNull);
    });

    test('with sign-in off the token is dropped', () async {
      final store = SessionStore.memory()..write('idToken', token(expiresIn: const Duration(minutes: 30)));
      final auth = AuthController(store: store);
      await auth.start(const AuthConfig(enabled: false, issuer: 'https://accounts.google.com'));
      expect(auth.signedIn, isFalse);
      expect(store.read('idToken'), isNull);
    });
  });

  test('a person the app cannot read is left out, not the whole answer', () {
    final people = People.fromJson({
      'enabled': true,
      'simTime': '09:00',
      'day': 1,
      'people': [
        {'id': 'reus-1', 'city': 'Reus', 'lat': 41.1, 'lon': 1.1, 'homeLat': 41.2, 'homeLon': 1.2, 'state': 'to_hospital', 'hospitalName': 'H'},
        {'id': 'reus-2', 'city': 'Reus', 'lat': 41.1, 'lon': 1.1, 'state': 'home'},
        'not a person',
      ],
    });
    expect(people.people.map((p) => p.id), ['reus-1']);
  });
}
