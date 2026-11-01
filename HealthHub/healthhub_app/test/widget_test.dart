import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthhub_app/api/health_hub_api.dart';
import 'package:healthhub_app/auth/auth_controller.dart';
import 'package:healthhub_app/care_centers/care_center_screen.dart';
import 'package:healthhub_app/events/stream_events.dart';
import 'package:healthhub_app/location/location_controller.dart';
import 'package:healthhub_app/main.dart';
import 'package:healthhub_app/people/person_screen.dart';
import 'package:healthhub_app/persist/session_store.dart';
import 'package:healthhub_app/triage/triage_card.dart';
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

  /// The event ids whose triage detail was asked for.
  final triageDetailsAsked = <String>[];

  /// Whether the simulation is paused, and every pause (true) or resume asked.
  bool paused = false;
  final pausesAsked = <bool>[];

  @override
  Future<bool> pauseSimulation(bool pause) async {
    pausesAsked.add(pause);
    return paused = pause;
  }

  static const _signs = {
    'life_threat': 0.04,
    'breathing': 0.86,
    'cardiac': 0.12,
    'stroke': 0.02,
    'major_injury': 0.01,
    'serious_infection': 0.41,
    'dehydration': 0.05,
    'self_harm': 0.01,
  };

  /// As the API answers a triage: the COPD flare-up, a sprain and a failure.
  static final _triaged = <Map<String, Object?>>[
    {
      'eventId': 'r1-lisboa-1-d2-t40',
      'personId': 'lisboa-1',
      'name': 'Rui Matos',
      'age': 71,
      'complaint': "Hi, I'm Rui Matos, 71, I have COPD. For four days I've been much more breathless.",
      'conditionName': 'COPD',
      'visit': 'first',
      'visitNumber': 1,
      'hospitalName': 'Hospital de Santa Maria',
      'level': 'orange',
      'waitMinutes': 10,
      'area': 'emergency',
      'nurseCheck': true,
      'levelRule': 3,
      'levelWhy': 'Struggling to breathe at rest or while talking.',
      'areaRule': 3,
      'areaWhy': 'Very urgent and urgent patients are seen in the emergency department.',
      'signs': _signs,
      'choices': {
        'pain': {'choice': 'none', 'confidence': 0.9},
        'onset': {'choice': 'this_week', 'confidence': 0.8},
        'visit_purpose': {'choice': 'worse', 'confidence': 0.7},
        'body_system': {'choice': 'breathing', 'confidence': 0.95},
      },
      'reference': 'orange',
      'millis': 312,
      'inputTokens': 4100,
    },
    {
      'eventId': 'r1-lisboa-2-d2-t38',
      'name': 'Ana Sousa',
      'age': 34,
      'complaint': 'I twisted my ankle stepping off a kerb this morning.',
      'level': 'yellow',
      'waitMinutes': 60,
      'area': 'emergency',
      'levelWhy': 'Moderate pain: it hurts to move, swallow or bear weight.',
      'reference': 'green',
    },
    {'eventId': 'r1-lisboa-3-d2-t30', 'name': 'Inês Carvalho', 'age': 67, 'error': 'aityx answered 401: invalid_key'},
  ];

  @override
  Future<Triages> triage({int limit = 20}) async {
    if (!simulation) return const Triages();
    return Triages.fromJson({
      'enabled': true,
      'summary': {
        'total': 3,
        'failed': 1,
        'compared': 2,
        'matched': 1,
        'withinOne': 2,
        'under': 0,
        'over': 1,
        'nurseChecks': 1,
        'inputTokens': 8200,
        'medianMillis': 312,
        'levels': {'red': 0, 'orange': 1, 'yellow': 1, 'green': 0, 'blue': 0},
      },
      'triaged': _triaged,
    });
  }

  @override
  Future<Triaged> triageOf(String eventId) async {
    triageDetailsAsked.add(eventId);
    return Triaged.fromJson({
      ..._triaged.firstWhere((row) => row['eventId'] == eventId),
      'receipt': {
        'provenance': {'age': 'state', for (final sign in _signs.keys) '${sign}_probability': 'jev'},
        'decisions': {
          'level': {'value': 'orange', 'rule': 3},
        },
      },
      'rules': {
        'level': [
          'An immediate threat to life: seen at once, in resuscitation.',
          'Signs of a stroke or another sudden problem in the brain: every minute counts.',
          'Struggling to breathe at rest or while talking.',
          'Chest pain or palpitations that may come from the heart, until a tracing says otherwise.',
        ],
        'area': [
          'Immediate threats to life go to the resuscitation room.',
          'The mental health liaison team sees a patient at risk, in a safe room.',
          'Very urgent and urgent patients are seen in the emergency department.',
        ],
      },
    });
  }

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
        hospitalId: 1,
        hospitalName: 'Hospital de Santa Maria',
        simTime: '08:00',
        day: 2,
        partition: 0,
        offset: 9,
        eventId: 'a1b2c3d4-lisboa-3-d2-t32',
      ),
      const StreamEvent(
        id: 'lisboa-1',
        name: 'Rui Matos',
        state: PersonState.toHospital,
        conditionName: 'COPD',
        conditionType: ConditionType.chronic,
        hospitalId: 1,
        hospitalName: 'Hospital de Santa Maria',
        simTime: '09:40',
        day: 2,
        partition: 0,
        offset: 42,
      ),
      const StreamEvent(id: 'lisboa-2', name: 'Ana Sousa', state: PersonState.home, simTime: '09:40', day: 2, partition: 0, offset: 41),
    ];
    return StreamEvents(
      enabled: true,
      paused: paused,
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
  /// The people and predictions asked for: (id, run).
  final personAsked = <(String, String?)>[];
  final predictionAsked = <(String, String?)>[];

  /// Whether datyx has a model to predict with.
  bool model = true;

  @override
  Future<PersonDetail> person(String id, {String? run}) async {
    personAsked.add((id, run));
    if (id == 'nobody') throw const ApiException(404, 'nobody with that id');
    return PersonDetail.fromJson({
      'id': id,
      'run': run ?? 'cafe0001',
      'current': run == null,
      'name': 'Inês Carvalho',
      'age': 67,
      'sex': 'woman',
      'occupation': 'retired teacher',
      'city': 'Lisboa',
      'now': run == null
          ? {'state': 'at_hospital', 'hospitalId': 1, 'hospitalName': 'Hospital de Santa Maria',
              'conditionName': 'Type 2 diabetes',
              'conditionType': 'chronic', 'simTime': '09:40', 'day': 2}
          : null,
      'summary': {'admissions': 2, 'acute': 0, 'chronic': 2, 'triaged': 1, 'days': 2, 'stayHours': 6},
      'admissions': [
        {
          'eventId': 'a1b2c3d4-lisboa-3-d2-t32',
          'conditionName': 'Type 2 diabetes',
          'conditionType': 'chronic',
          'visit': 'repeat',
          'visitNumber': 2,
          'complaint': 'Back for my sugar check.',
          'hospitalId': 1,
          'hospitalName': 'Hospital de Santa Maria',
          'day': 2,
          'simTime': '08:00',
          'triage': {'level': 'green', 'waitMinutes': 120, 'area': 'outpatients', 'nurseCheck': false, 'reference': 'green'},
        },
        {
          'eventId': 'a1b2c3d4-lisboa-3-d1-t10',
          'conditionName': 'Type 2 diabetes',
          'conditionType': 'chronic',
          'visit': 'first',
          'visitNumber': 1,
          'hospitalName': 'Hospital de Santa Maria',
          'day': 1,
          'simTime': '10:30',
          'triage': null,
        },
      ],
      'days': [
        {'day': '2026-01-02', 'visits': 1, 'acuteVisits': 0, 'chronicVisits': 1, 'stayHours': 2},
        {'day': '2026-01-01', 'visits': 1, 'acuteVisits': 0, 'chronicVisits': 1, 'stayHours': 4},
      ],
    });
  }

  /// The care centers asked for, by id.
  final careCenterAsked = <int>[];

  /// Care center 1 is the hospital, with a person there and one on the way;
  /// 2 the clinic, where nobody goes; anything else isn't there.
  @override
  Future<CareCenterDetail> careCenter(int id) async {
    careCenterAsked.add(id);
    if (id == 2) {
      return CareCenterDetail.fromJson({
        'id': 2, 'name': 'Clínica do Campo', 'kind': 'clinic', 'subtype': 'Policlínica', 'city': 'Lisboa',
        'country': 'PT', 'lat': 38.722, 'lon': -9.141, 'capacity': {'places': 3, 'unit': 'places'},
        'now': {'enabled': true, 'inUse': 0, 'usage': 0, 'assigned': 0, 'here': [], 'onTheWay': []},
        'admissions': {'thisRun': 0, 'total': 0, 'latest': []},
      });
    }
    if (id != 1) throw const ApiException(404, 'no care center with that id');
    return CareCenterDetail.fromJson({
      'id': 1,
      'name': 'Hospital de Santa Maria',
      'kind': 'hospital',
      'subtype': 'Hospital Central',
      'address': 'Avenida Professor Egas Moniz',
      'postalCode': '1649-035',
      'city': 'Lisboa',
      'country': 'PT',
      'lat': 38.73,
      'lon': -9.15,
      'phone': '217 805 000',
      'ownership': 'public',
      'source': 'sns',
      'capacity': {'places': 8, 'unit': 'beds', 'simulated': true},
      'now': {
        'enabled': true,
        'run': 'cafe0001',
        'simTime': '09:40',
        'day': 2,
        'inUse': 1,
        'usage': 0.125,
        'assigned': 3,
        'here': [
          {'id': 'lisboa-2', 'name': 'João Silva', 'age': 54, 'city': 'Lisboa', 'state': 'at_hospital',
            'lat': 38.73, 'lon': -9.15, 'conditionName': 'Influenza', 'conditionType': 'acute'},
        ],
        'onTheWay': [
          {'id': 'lisboa-1', 'name': 'Rui Matos', 'age': 71, 'city': 'Lisboa', 'state': 'to_hospital',
            'lat': 38.725, 'lon': -9.145, 'conditionName': 'COPD', 'conditionType': 'chronic'},
        ],
      },
      'admissions': {
        'run': 'cafe0001',
        'thisRun': 4,
        'thisRunAcute': 1,
        'thisRunChronic': 3,
        'total': 11,
        'latestOf': 'run',
        'latest': [
          {
            'eventId': 'cafe0001-lisboa-3-d2-t32',
            'personId': 'lisboa-3',
            'name': 'Inês Carvalho',
            'age': 67,
            'conditionName': 'Type 2 diabetes',
            'conditionType': 'chronic',
            'visit': 'repeat',
            'visitNumber': 2,
            'complaint': 'Back for my sugar check.',
            'day': 2,
            'simTime': '08:00',
            'triage': {'level': 'green', 'waitMinutes': 120, 'area': 'outpatients'},
          },
        ],
      },
    });
  }

  @override
  Future<Prediction> prediction(String id, {String? run}) async {
    predictionAsked.add((id, run));
    if (!model) throw const ApiException(404, 'no model of the group care of public.patient_days has been trained yet');
    return Prediction.fromJson({
      'predicted': 9.022,
      'last': 4.0,
      'target': 'stay_hours',
      'horizon': '30D',
      'group': 'care',
      'trainingRunId': 1,
      'trainedAt': '2026-11-01T09:42:05Z',
      'millis': 63,
    });
  }
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
    // On the index there is no person view to open: a tap shows who.
    expect(find.byTooltip('lisboa-1\nGoing to the hospital · Hospital de Santa Maria · 09:40'), findsOneWidget);
    // With a profile, the tooltip also says who they are and their condition.
    expect(
      find.byTooltip('João Silva, 54, lisboa-2\nInfluenza (acute)\nAt the hospital · Hospital de Santa Maria · 09:40'),
      findsOneWidget,
    );
    expect(find.text('Simulated time 09:40, day 2'), findsOneWidget);
    expect(find.text('Person, in care'), findsOneWidget);

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
    // Tall enough for the cards under the map.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(api: FakeApi(auth: false, simulation: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stream-events')), findsOneWidget);
    expect(find.text('On Kafka, healthhub.people.moves, healthhub.admissions; every 5 seconds'), findsOneWidget);
    // Each move names its person, a link to their view.
    final card = find.byKey(const Key('stream-events'));
    expect(find.descendant(of: card, matching: find.text('Rui Matos')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Ana Sousa')), findsOneWidget);
    // What they do, and the hospital, a link to its view.
    expect(find.text('Going to the hospital · '), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const Key('care-center-link-1'))), findsNWidgets(2));
    expect(find.text('p0 · #42'), findsOneWidget);
    expect(find.text('At home'), findsOneWidget);
  });

  testWidgets('the explainers sit beside the map and the triage, and under them when narrow', (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(api: FakeApi(auth: false, simulation: true)));
    await tester.pumpAndSettle();

    final simulation = find.byKey(const Key('simulation-explainer'));
    final aityx = find.byKey(const Key('aityx-explainer'));
    expect(find.descendant(of: simulation, matching: find.text('The data, and the simulation')), findsOneWidget);
    expect(find.descendant(of: simulation, matching: find.text('A real stream')), findsOneWidget);
    expect(find.descendant(of: aityx, matching: find.text('What aityx does at the desk')), findsOneWidget);
    for (final point in ['Jev reads', 'Rules decide', 'In one call', 'Explained']) {
      expect(find.descendant(of: aityx, matching: find.text(point)), findsOneWidget);
    }
    // In the map's row, to its right; in the triage's row, to its right.
    final map = tester.getRect(find.byKey(const Key('location-tile')));
    expect(tester.getRect(simulation).left, greaterThan(map.right));
    expect(tester.getRect(simulation).top, map.top);
    final triage = tester.getRect(find.byKey(const Key('triage-card')));
    expect(tester.getRect(aityx).left, greaterThan(triage.right));
    expect(tester.getRect(aityx).top, triage.top);

    // Narrow: under them.
    tester.view.physicalSize = const Size(800, 4000);
    await tester.pumpAndSettle();
    expect(tester.getRect(simulation).top, greaterThan(tester.getRect(find.byKey(const Key('location-tile'))).bottom));
  });

  testWidgets('the events invite opening anyone, and pause the simulation', (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-invite')), findsOneWidget);
    expect(find.textContaining('Open anyone by their name'), findsOneWidget);

    final button = find.byKey(const Key('simulation-pause'));
    expect(find.descendant(of: button, matching: find.text('Pause the simulation')), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(api.pausesAsked, [true]);
    expect(find.descendant(of: button, matching: find.text('Resume the simulation')), findsOneWidget);
    expect(find.text('Paused: nobody moves, the clock stands'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(api.pausesAsked, [true, false]);
    expect(find.descendant(of: button, matching: find.text('Pause the simulation')), findsOneWidget);
  });

  testWidgets('an admission is marked in the events, with what was said on one line', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    // Moves and admissions are asked for apart, so moves can't push the
    // admissions out.
    expect(api.eventTypes, containsAll([StreamEventType.move, StreamEventType.admission]));
    expect(find.text('1 admission · 2 moves'), findsOneWidget);

    final row = find.byKey(const Key('admission-a1b2c3d4-lisboa-3-d2-t32'));
    expect(row, findsOneWidget);
    Finder inRow(Finder finder) => find.descendant(of: row, matching: finder);
    expect(inRow(find.byIcon(Icons.local_hospital)), findsOneWidget);
    // The name is a link to her view, of the admission's run.
    expect(inRow(find.byKey(const Key('person-link-lisboa-3'))), findsOneWidget);
    expect(inRow(find.text('Inês Carvalho, 67')), findsOneWidget);
    expect(inRow(find.textContaining('Type 2 diabetes (chronic)', findRichText: true)), findsOneWidget);
    expect(inRow(find.text('Return visit, the 2nd · ')), findsOneWidget);
    expect(inRow(find.byKey(const Key('care-center-link-1'))), findsOneWidget);
    expect(inRow(find.text('08:00, day 2')), findsOneWidget);
    expect(inRow(find.text('p0 · #9')), findsOneWidget);
    final complaint = tester.widget<Text>(inRow(find.textContaining('back for my sugar check')));
    expect(complaint.data, "“Hi, I'm Inês Carvalho, 67, back for my sugar check. The new tablets upset my stomach a little.”");
    expect(complaint.style?.fontStyle, FontStyle.italic);
    // One line, cut short when it doesn't fit, all of it on hover.
    expect(inRow(find.byTooltip(
      "Hi, I'm Inês Carvalho, 67, back for my sugar check. The new tablets upset my stomach a little.",
    )), findsOneWidget);

    // The admission's orange bar marks it; a move's bar is its state's colour.
    final box = tester.widget<Container>(row).decoration! as BoxDecoration;
    expect((box.border! as Border).left.color, const Color(0xFFE36742));
    // Every row is the same shape: as tall as a move's.
    final move = find.byKey(const Key('move-lisboa-1-42'));
    expect(tester.getSize(row).height, tester.getSize(move).height);
    expect(tester.getSize(row).height, tester.getSize(find.byKey(const Key('move-lisboa-2-41'))).height);
    // The time and the offset end at the right edge of every row, whatever
    // the name and condition before them.
    final whens = find.byKey(const Key('event-when'));
    final wheres = find.byKey(const Key('event-where'));
    expect(whens, findsNWidgets(3));
    final rightEdge = tester.getTopRight(whens.first).dx;
    for (var i = 0; i < 3; i++) {
      expect(tester.getTopRight(whens.at(i)).dx, moreOrLessEquals(rightEdge));
      expect(tester.getTopRight(wheres.at(i)).dx, moreOrLessEquals(rightEdge));
    }
    // It sorts by simulated time: 08:00 is older than the moves at 09:40.
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(tester.getTopLeft(find.descendant(of: find.byKey(const Key('stream-events')), matching: find.text('Rui Matos'))).dy),
    );
  });

  testWidgets('the conditions under the pause keep only their events, through the reads', (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(api: FakeApi(auth: false, simulation: true)));
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('stream-events'));
    final filter = find.byKey(const Key('condition-filter'));
    // A row of its own, under the pause, above the events.
    expect(tester.getTopLeft(filter).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('simulation-pause'))).dy));
    expect(tester.getTopLeft(filter).dy, lessThan(tester.getTopLeft(find.byKey(const Key('move-lisboa-1-42'))).dy));
    // All, then the conditions of the events by name, with how many each.
    final chips = tester.widgetList<FilterChip>(find.descendant(of: filter, matching: find.byType(FilterChip))).toList();
    expect(chips.map((chip) => (chip.label as Text).data), ['All conditions', 'COPD 1', 'Type 2 diabetes 1']);
    expect(chips.first.selected, isTrue);

    await tester.tap(find.byKey(const Key('condition-filter-Type 2 diabetes')));
    await tester.pump();
    expect(find.byKey(const Key('admission-a1b2c3d4-lisboa-3-d2-t32')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Rui Matos')), findsNothing);
    expect(find.descendant(of: card, matching: find.text('Ana Sousa')), findsNothing); // no condition
    expect(find.text('1 admission · 0 moves'), findsOneWidget);
    expect(tester.widget<FilterChip>(find.byKey(const Key('condition-filter-all'))).selected, isFalse);

    // Several at once; the choice outlives the next read.
    await tester.tap(find.byKey(const Key('condition-filter-COPD')));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('1 admission · 1 move'), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Rui Matos')), findsOneWidget);

    // All shows everything again.
    await tester.tap(find.byKey(const Key('condition-filter-all')));
    await tester.pump();
    expect(find.text('1 admission · 2 moves'), findsOneWidget);
  });

  testWidgets('a chosen condition without events stays, to be unchosen', (tester) async {
    var reads = 0;
    final events = [
      const StreamEvent(id: 'reus-1', name: 'Jordi Puig', state: PersonState.home, conditionName: 'Influenza', simTime: '09:00', day: 1, offset: 1),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StreamEventsCard(
              events: ({int limit = 20, StreamEventType? type}) async {
                reads++;
                return StreamEvents(enabled: true, events: reads <= 2 && type == StreamEventType.move ? events : const []);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('condition-filter-Influenza')));
    await tester.pump(const Duration(seconds: 6));
    // Gone from the events, kept as a chosen chip with none.
    expect(find.text('Influenza 0'), findsOneWidget);
    expect(find.byKey(const Key('stream-events-none')), findsNothing); // nothing at all: waiting
    await tester.tap(find.byKey(const Key('condition-filter-Influenza')));
    await tester.pump();
    expect(find.byKey(const Key('condition-filter-Influenza')), findsNothing);
  });

  testWidgets("a person's id opens their view, datyx's 30-day prediction highlighted", (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    // A move's id: the person of the run going on now.
    await tester.tap(
      find.descendant(of: find.byKey(const Key('stream-events')), matching: find.byKey(const Key('person-link-lisboa-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PersonScreen), findsOneWidget);
    expect(api.personAsked, [('lisboa-1', null)]);
    expect(api.predictionAsked, [('lisboa-1', null)]);
    expect(find.text('Inês Carvalho'), findsNWidgets(2)); // the title and the header
    expect(find.text('67 · woman · retired teacher · Lisboa'), findsOneWidget);
    expect(find.text('At the hospital · Hospital de Santa Maria'), findsOneWidget);

    // The prediction, set apart: the hours ahead large, the 30 days gone, the model.
    final card = find.byKey(const Key('prediction-card'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Return in the next 30 days')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('prediction-value'))).data, '9.0 h');
    expect(find.text('4 h in the last 30 days'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    expect(find.textContaining('group care · stay_hours over 30D · training run 1'), findsOneWidget);
    final border = (tester.widget<Container>(card).decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, const Color(0xFFE36742));
    // Right under who they are, above their admissions and days.
    expect(tester.getTopLeft(card).dy, lessThan(tester.getTopLeft(find.text('Admissions')).dy));

    // Under it, how it is made, and why Jev can't make it.
    final explainer = find.byKey(const Key('prediction-explainer'));
    expect(find.descendant(of: explainer, matching: find.text('How this prediction is made')), findsOneWidget);
    expect(find.descendant(of: explainer, matching: find.text('XGBoost, on their history')), findsOneWidget);
    expect(find.descendant(of: explainer, matching: find.text('Why not Jev')), findsOneWidget);
    expect(tester.getTopLeft(explainer).dy, greaterThan(tester.getBottomLeft(card).dy));

    // Their admissions with aityx's triage, newest first, and their days.
    final first = find.byKey(const Key('person-admission-a1b2c3d4-lisboa-3-d2-t32'));
    expect(find.descendant(of: first, matching: find.textContaining('Standard · 2 h')), findsOneWidget);
    expect(find.descendant(of: first, matching: find.text('Return visit, the 2nd')), findsOneWidget);
    expect(
      find.descendant(of: first, matching: find.byKey(const Key('care-center-link-1'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('person-admission-a1b2c3d4-lisboa-3-d1-t10')), matching: find.text('Not triaged yet')),
      findsOneWidget,
    );
    expect(find.text('2026-01-02'), findsOneWidget);
    expect(find.text('6'), findsOneWidget); // hours of care, counted

    // Back home.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PersonScreen), findsNothing);
  });

  testWidgets("an admission's name opens the person of that admission's run", (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('person-link-lisboa-3')));
    await tester.pumpAndSettle();
    expect(api.personAsked, [('lisboa-3', 'a1b2c3d4')]);
    expect(api.predictionAsked, [('lisboa-3', 'a1b2c3d4')]);
    expect(find.text('lisboa-3 · run a1b2c3d4 · a past run'), findsOneWidget);
  });

  testWidgets("a triage's name, and a person on the map, open their view", (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    final locations = FakeLocations();
    await tester.pumpWidget(app(api: api, locations: locations));
    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // The triage of Rui Matos, a link to him; the rest of the row opens the triage.
    final triage = find.byKey(const Key('triage-r1-lisboa-1-d2-t40'));
    await tester.tap(find.descendant(of: triage, matching: find.byKey(const Key('person-link-lisboa-1'))));
    await tester.pumpAndSettle();
    expect(api.personAsked, [('lisboa-1', null)]);
    expect(api.triageDetailsAsked, isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('person-lisboa-2')));
    await tester.pumpAndSettle();
    expect(api.personAsked.last, ('lisboa-2', null));
    expect(find.byType(PersonScreen), findsOneWidget);
  });

  testWidgets("a care center's pin opens its view: the map, the capacity in use, who is there", (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    final locations = FakeLocations();
    await tester.pumpWidget(app(api: api, locations: locations));
    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // On home a tap opens it; the tooltip says so.
    expect(find.byTooltip('Hospital de Santa Maria\nHospital\nClick to open'), findsOneWidget);
    // At its corner: João, at the hospital, is drawn on top of its middle.
    await tester.tapAt(tester.getTopLeft(find.byKey(const Key('care-center-1'))) + const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(CareCenterScreen), findsOneWidget);
    expect(api.careCenterAsked, [1]);
    expect(find.text('Hospital de Santa Maria'), findsNWidgets(2)); // the title and the header
    expect(find.text('Hospital · Hospital Central'), findsOneWidget);
    expect(find.text('Avenida Professor Egas Moniz, 1649-035 Lisboa, PT'), findsOneWidget);

    // Where it is, with who is on the way, and a badge of who is there.
    expect(find.byKey(const Key('care-center-map')), findsOneWidget);
    expect(find.byKey(const Key('on-the-way-lisboa-1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('here-badge')), matching: find.text('1')), findsOneWidget);

    // The capacity in use, highlighted.
    final usage = find.byKey(const Key('usage-card'));
    expect(find.descendant(of: usage, matching: find.text('Capacity in use now')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('usage-in-use'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('usage-capacity'))).data, 'of 8 beds');
    expect(tester.widget<Text>(find.byKey(const Key('usage-percent'))).data, '13% in use');
    expect(find.text('1 on the way · 3 people have it as their hospital'), findsOneWidget);
    expect(find.text('Simulated time 09:40, day 2'), findsOneWidget);

    // Who is there and on the way, and its admissions, counted and the latest with who.
    expect(find.byKey(const Key('care-center-person-lisboa-2')), findsOneWidget);
    expect(find.byKey(const Key('care-center-person-lisboa-1')), findsOneWidget);
    expect(find.text('Influenza (acute) · At the hospital'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('admissions-this-run')), matching: find.text('4')),
      findsOneWidget,
    );
    expect(find.descendant(of: find.byKey(const Key('admissions-total')), matching: find.text('11')), findsOneWidget);
    final admission = find.byKey(const Key('person-admission-cafe0001-lisboa-3-d2-t32'));
    expect(find.descendant(of: admission, matching: find.text('Inês Carvalho, 67')), findsOneWidget);
    expect(find.descendant(of: admission, matching: find.textContaining('Standard · 2 h')), findsOneWidget);

    // It follows them: read again every 5 seconds.
    await tester.pump(const Duration(seconds: 5));
    expect(api.careCenterAsked.length, greaterThan(1));

    // Its people are links, from its own page.
    await tester.tap(find.byKey(const Key('person-link-lisboa-2')));
    await tester.pumpAndSettle();
    expect(find.byType(PersonScreen), findsOneWidget);
    expect(api.personAsked.last, ('lisboa-2', null));
    // And the person's hospital leads back to it.
    await tester.tap(find.byKey(const Key('care-center-link-1')).first);
    await tester.pumpAndSettle();
    expect(find.byType(CareCenterScreen), findsNWidgets(1));
    expect(api.careCenterAsked.last, 1);
  });

  testWidgets('a hospital named in the events and in the triage opens its view', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    final events = find.byKey(const Key('stream-events'));
    await tester.tap(find.descendant(of: events, matching: find.byKey(const Key('care-center-link-1'))).first);
    await tester.pumpAndSettle();
    expect(find.byType(CareCenterScreen), findsOneWidget);
    expect(api.careCenterAsked, [1]);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // In the triage's detail, which opens above home, the person is a link still.
    await tester.tap(find.byKey(const Key('triage-r1-lisboa-1-d2-t40')));
    await tester.pumpAndSettle();
    expect(find.byType(TriageDetailDialog), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(TriageDetailDialog), matching: find.byKey(const Key('person-link-lisboa-1'))));
    await tester.pumpAndSettle();
    expect(find.byType(PersonScreen), findsOneWidget);
  });

  testWidgets("a clinic's view says the simulation sends nobody there; none is a 404", (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(home: CareCenterScreen(id: 2, load: api.careCenter, showTiles: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clinic · Policlínica'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('usage-capacity'))).data, 'of 3 places');
    // A kind of clinic the simulation routes nobody to.
    expect(find.textContaining('The simulation sends nobody to a Policlínica'), findsOneWidget);
    expect(find.text('No admissions recorded here.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: CareCenterScreen(key: const Key('99'), id: 99, load: api.careCenter, showTiles: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No care center with the id 99.'), findsOneWidget);
  });

  test('what a person does names the kind of care center they go to', () {
    expect(PersonState.toHospital.labelAt(CareCenterKind.healthStation), 'Going to the health station');
    expect(PersonState.atHospital.labelAt(CareCenterKind.clinic), 'At the clinic');
    expect(PersonState.atHospital.labelAt(null), 'At the hospital');
    expect(PersonState.home.labelAt(CareCenterKind.clinic), 'At home');
    final move = StreamEvent.fromJson({'id': 'reus-1', 'state': 'to_hospital', 'careCenterKind': 'health_station'});
    expect(move.state.labelAt(move.careCenterKind), 'Going to the health station');
    expect(StreamEvent.fromJson({'id': 'reus-1', 'state': 'home'}).careCenterKind, isNull);
    final center = CareCenterDetail.fromJson({'id': 1, 'name': 'CAP', 'kind': 'health_station', 'serves': ['primary']});
    expect(center.serves, ['primary']);
  });

  testWidgets('without a model, the prediction card says why', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true)..model = false;
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byKey(const Key('stream-events')), matching: find.byKey(const Key('person-link-lisboa-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prediction-card')), findsOneWidget);
    expect(find.text('no model of the group care of public.patient_days has been trained yet'), findsOneWidget);
    expect(find.byKey(const Key('prediction-value')), findsNothing);
    // The rest of the person is there all the same.
    expect(find.text('Admissions'), findsOneWidget);
  });

  test('a run is the event id up to the person, eight hex digits', () {
    expect(runOf('df0837e4-reus-5-d141-t3369'), 'df0837e4');
    expect(runOf('lisboa-3-d2-t32'), isNull);
    expect(runOf(null), isNull);
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

  testWidgets("home shows aityx's triage of the admissions, against the reference", (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(api: FakeApi(auth: false, simulation: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('triage-card')), findsOneWidget);
    expect(find.text('Triage at the desk, by aityx'), findsOneWidget);
    expect(find.text('3 triaged · 50% at the reference level'), findsOneWidget);
    expect(find.text('Very urgent 1'), findsOneWidget);
    expect(find.text('failed 1'), findsOneWidget);
    // The COPD flare-up: very urgent, why, a nurse's check, the reference.
    expect(find.text('Very urgent · within 10 min'), findsOneWidget);
    expect(find.text('Struggling to breathe at rest or while talking.'), findsOneWidget);
    expect(find.text('a nurse checks'), findsOneWidget);
    expect(find.text('✓ the reference level'), findsOneWidget);
    // The sprain, one level more urgent than the reference; the failure.
    expect(find.text('one level more urgent than the reference'), findsOneWidget);
    expect(find.text('Not triaged'), findsOneWidget);
    expect(find.text('aityx answered 401: invalid_key'), findsOneWidget);
  });

  testWidgets('a tap on a triage shows why: what Jev read, the rules tried, the reference', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('triage-r1-lisboa-1-d2-t40')));
    await tester.pumpAndSettle();
    expect(api.triageDetailsAsked, ['r1-lisboa-1-d2-t40']);
    expect(find.byKey(const Key('triage-detail')), findsOneWidget);
    expect(find.text('Very urgent, within 10 min'), findsOneWidget);
    expect(find.text('What Jev read'), findsOneWidget);
    expect(find.text('Struggling to breathe'), findsOneWidget);
    expect(find.text('0.86 present'), findsOneWidget);
    expect(find.text('0.41 in doubt'), findsOneWidget);
    expect(find.text('The level: rule 3 of 4'), findsOneWidget);
    expect(find.text('✗ 1. An immediate threat to life: seen at once, in resuscitation.'), findsOneWidget);
    expect(find.text('✓ 3. Struggling to breathe at rest or while talking.'), findsOneWidget);
    expect(find.textContaining('A nurse confirms the level'), findsOneWidget);
    expect(find.textContaining('The simulated patient has COPD, first visit.'), findsOneWidget);
    expect(find.textContaining('aityx gave the reference level'), findsOneWidget);
    expect(find.textContaining('8 inputs from Jev, age from the desk'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('triage-detail')), findsNothing);
  });

  testWidgets('no triage card when the API triages nothing', (tester) async {
    await tester.pumpWidget(app(api: FakeApi(auth: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('triage-card')), findsNothing);
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
