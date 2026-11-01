import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthhub_app/api/health_hub_api.dart';
import 'package:healthhub_app/auth/auth_controller.dart';
import 'package:healthhub_app/care_centers/care_center_screen.dart';
import 'package:healthhub_app/events/simulated_clock.dart';
import 'package:healthhub_app/events/stream_events.dart';
import 'package:healthhub_app/care_centers/occupancy_timeline.dart';
import 'package:healthhub_app/sim_clock.dart';
import 'package:healthhub_app/location/location_controller.dart';
import 'package:healthhub_app/main.dart';
import 'package:healthhub_app/people/person_screen.dart';
import 'package:healthhub_app/persist/session_store.dart';
import 'package:healthhub_app/triage/triage_card.dart';
import 'package:healthhub_app/theme.dart';
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

  /// The types the events card asked for, in order, and how many.
  final eventTypes = <StreamEventType?>[];
  final eventLimits = <int>[];

  /// The events the stream answers in place of the usual three, in the
  /// API's order, and the busiest care center it names.
  List<StreamEvent>? stream;
  Map<String, Object?>? busiest;

  /// The event ids whose triage detail was asked for.
  final triageDetailsAsked = <String>[];

  /// The occupancy alarms the events carry, as the API writes them
  /// (`alarms` of `GET /api/events`); none without.
  Map<String, Object?>? alarms;

  /// Whether the simulation is paused, and every pause (true) or resume asked.
  bool paused = false;
  final pausesAsked = <bool>[];

  @override
  Future<bool> pauseSimulation(bool pause) async {
    pausesAsked.add(pause);
    return paused = pause;
  }

  /// The people a city, and every change asked.
  int perCity = 80;
  final perCityAsked = <int>[];

  @override
  Future<int> setPeoplePerCity(int perCity) async {
    perCityAsked.add(perCity);
    return this.perCity = perCity;
  }

  /// The hospital's flow factor, every change asked, and, while set, what
  /// holds the answer back; with [flowRefused], the API's refusal.
  double flow = 1;
  final flowAsked = <(int, FlowAction)>[];
  Completer<void>? flowGate;
  ApiException? flowRefused;

  @override
  Future<double> changeFlow(int id, FlowAction action) async {
    flowAsked.add((id, action));
    await flowGate?.future;
    if (flowRefused case final refused?) throw refused;
    return flow = switch (action) {
      FlowAction.doubled => flow * 2,
      FlowAction.halved => flow / 2,
      FlowAction.reset => 1.0,
    }.clamp(flowMin, flowMax).toDouble();
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
      'via': 'datyx',
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
    eventLimits.add(limit);
    if (!simulation) return const StreamEvents(enabled: false);
    final all = stream ?? [
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
      // At home, so monitored: the API leaves out everyone else at home.
      const StreamEvent(id: 'lisboa-2', name: 'Ana Sousa', state: PersonState.home, monitored: true, monitoredFor: 'aged 84', simTime: '09:40', day: 2, partition: 0, offset: 41),
    ];
    return StreamEvents(
      enabled: true,
      paused: paused,
      peoplePerCity: perCity,
      // The feed's counts; the answer read later counts more.
      total: type == StreamEventType.move ? 48190 : 48213,
      perSecond: type == StreamEventType.move ? 70.1 : 70.4,
      alarms: OccupancyAlarms.fromJson(alarms),
      busiest: BusiestCareCenter.fromJson(busiest),
      topics: [
        if (type != StreamEventType.admission) 'healthhub.people.moves',
        if (type != StreamEventType.move) 'healthhub.admissions',
      ],
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

  /// The points the map asked the nearest care center of.
  final nearestAsked = <List<double>>[];

  /// Nearest to Lisbon's center: a hospital the care centers in view leave out.
  @override
  Future<CareCenter?> nearestCareCenter({required double lat, required double lon}) async {
    nearestAsked.add([lat, lon]);
    return const CareCenter(id: 9, name: 'Hospital da Luz', kind: CareCenterKind.hospital, lat: 38.75, lon: -9.17);
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
        'country': 'PT', 'lat': 38.722, 'lon': -9.141, 'capacity': {'places': 3, 'unit': 'places'}, 'flow': 1,
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
      'serves': ['hospital', 'urgent_care', 'dialysis'],
      'flow': flow,
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

  /// The care centers whose people in care per hour, and whose forecast, were asked for.
  final hourlyAsked = <(int, String?, int?)>[];

  /// Whether the occupancy's run is going on; when not, it ended at day 19, 12:00.
  bool occupancyCurrent = true;
  final forecastAsked = <(int, String?)>[];

  /// Care centers 1 and 2 had 0, 1, 3, 2, 2 and 1 people in care from 07:00 to 12:00 of day 19, run 1349d576
  /// (current), the clock at 12:40, and datyx had predicted 2.8, 2.2, 1.6 and 1.2 of 09:00 to 12:00 before
  /// them (nothing of 07:00 and 08:00); 7, nobody.
  @override
  Future<HourlyOccupancy> careCenterOccupancy(int id, {String? run, int? hours}) async {
    hourlyAsked.add((id, run, hours));
    if (id != 1 && id != 2) return HourlyOccupancy(hospitalId: id);
    const inCare = [0, 1, 3, 2, 2, 1];
    const predicted = [null, null, 2.8, 2.2, 1.6, 1.2];
    return HourlyOccupancy.fromJson({
      'hospitalId': id,
      'run': '1349d576',
      'current': occupancyCurrent,
      'end': '2026-01-19T12:00',
      'threshold': 0.9,
      'now': {'day': 19, 'simTime': '12:40', 'date': '2026-01-19'},
      'hours': [
        for (var h = 7; h <= 12; h++)
          {
            'hour': '2026-01-19T${'$h'.padLeft(2, '0')}:00',
            'occupancy': inCare[h - 7],
            'predicted': predicted[h - 7] == null
                ? null
                : {'mean': predicted[h - 7], 'p10': 1.0, 'p90': 3.5, 'leadHours': 1},
          },
      ],
    });
  }

  /// DeepAR's forecast of the next four hours of care center 2; none without a [model].
  @override
  Future<HourlyForecast> occupancyForecast(int id, {String? run}) async {
    forecastAsked.add((id, run));
    if (!model) throw const ApiException(404, 'no model of the group default of public.occupancy_hourly has been trained yet');
    const means = [1.0, 1.5, 2.0, 1.5];
    return HourlyForecast.fromJson({
      'predicted': 6.0,
      'last': 9.0,
      'target': 'occupancy',
      'horizon': '4h',
      'group': 'default',
      'trainingRunId': 5,
      'forecast': [
        for (var h = 13; h <= 16; h++)
          {'at': '2026-01-19T$h:00', 'mean': means[h - 13], 'p10': 0, 'p50': 1, 'p90': 3},
      ],
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

  testWidgets('home centres the map on the care center nearest the user', (tester) async {
    final api = FakeApi();
    final auth = FakeAuth(signedInAs: const SignedInUser(name: 'Ada', email: 'ada@example.com'));
    final locations = FakeLocations();
    await tester.pumpWidget(app(api: api, auth: auth, locations: locations));
    await tester.pumpAndSettle();

    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    expect(api.nearestAsked, [
      [38.72, -9.14],
    ]);
    final camera = MapCamera.of(tester.element(find.byKey(const Key('you-are-here'))));
    expect(camera.center.latitude, closeTo(38.75, 1e-6));
    expect(camera.center.longitude, closeTo(-9.17, 1e-6));
    // Close, but not so close that the user is out of view; and the
    // nearest is pinned though the area's answer leaves it out.
    expect(camera.visibleBounds.contains(const LatLng(38.72, -9.14)), isTrue);
    expect(camera.zoom, lessThanOrEqualTo(14));
    expect(find.byKey(const Key('care-center-9')), findsOneWidget);

    // The button still brings it back to the user.
    await tester.tap(find.byTooltip('Back to where you are'));
    await tester.pumpAndSettle();
    final back = MapCamera.of(tester.element(find.byKey(const Key('you-are-here'))));
    expect(back.center.latitude, closeTo(38.72, 1e-6));
    expect(back.center.longitude, closeTo(-9.14, 1e-6));
  });

  testWidgets('the index centres on the user, asking for no nearest care center', (tester) async {
    final api = FakeApi();
    final locations = FakeLocations();
    await tester.pumpWidget(app(api: api, locations: locations));
    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();

    expect(api.nearestAsked, isEmpty);
    final camera = MapCamera.of(tester.element(find.byKey(const Key('you-are-here'))));
    expect(camera.center.latitude, closeTo(38.72, 1e-6));
    expect(camera.zoom, 14);
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
    expect(find.byTooltip('lisboa-1\nGoing to the hospital · Hospital de Santa Maria · Jan 2, 2026 09:40'), findsOneWidget);
    // With a profile, the tooltip also says who they are and their condition.
    expect(
      find.byTooltip('João Silva, 54, lisboa-2\nInfluenza (acute)\nAt the hospital · Hospital de Santa Maria · Jan 2, 2026 09:40'),
      findsOneWidget,
    );
    expect(find.text('Simulated time: Jan 2, 2026 09:40'), findsOneWidget);
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

    // One stream, every kind in one answer (no type), more than the rows
    // shown, so a pill has rows to keep.
    expect(api.eventTypes.toSet(), {null});
    expect(api.eventLimits.toSet(), {60});
    // No counts of what is shown.
    expect(find.byKey(const Key('stream-events-counts')), findsNothing);
    expect(find.textContaining('2 moves'), findsNothing);
    // Beside the title, every event the API read, hidden ones too, and a second over the last minute.
    expect(tester.widget<Text>(find.byKey(const Key('stream-events-total'))).data, '48,213 events · 70.4/s');
    // Ana is at home and monitored, so her move shows, marked, why on hover.
    final events = find.byKey(const Key('stream-events'));
    final monitor = find.descendant(of: events, matching: find.byKey(const Key('monitored')));
    expect(monitor, findsOneWidget);
    expect(tester.widget<Tooltip>(find.ancestor(of: monitor, matching: find.byType(Tooltip)).first).message, 'Monitored at home: aged 84');

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
    expect(inRow(find.text('Jan 2, 2026 08:00')), findsOneWidget);
    expect(inRow(find.text('p0 · #9')), findsOneWidget);
    // datyx's 30-day prediction for her, asked once for the admission's run.
    expect(api.predictionAsked, [('lisboa-3', 'a1b2c3d4')]);
    expect(
      tester.widget<Text>(inRow(find.byKey(const Key('admission-care-a1b2c3d4-lisboa-3-d2-t32')))).data,
      '9.0 h expected in 30 days',
    );
    expect(inRow(find.byIcon(Icons.bed_outlined)), findsOneWidget);
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

  testWidgets('without a model, an admission shows no 30-day hours', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true)..model = false;
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    expect(api.predictionAsked, [('lisboa-3', 'a1b2c3d4')]);
    expect(find.byKey(const Key('admission-a1b2c3d4-lisboa-3-d2-t32')), findsOneWidget);
    expect(find.byKey(const Key('admission-care-a1b2c3d4-lisboa-3-d2-t32')), findsNothing);
    expect(find.byIcon(Icons.bed_outlined), findsNothing);
    // Asked once, however many times the events are read again.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(api.predictionAsked, [('lisboa-3', 'a1b2c3d4')]);
  });

  testWidgets('no condition filter nor counts; beside the pause, the people a city, which anyone can change', (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(app(api: api));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('condition-filter')), findsNothing);
    expect(find.text('1 admission · 2 moves'), findsNothing);
    final picker = find.byKey(const Key('simulation-people'));
    expect(find.descendant(of: picker, matching: find.text('80 people a city')), findsOneWidget);
    expect(tester.getCenter(picker).dy, closeTo(tester.getCenter(find.byKey(const Key('simulation-pause'))).dy, 4));

    await tester.tap(picker);
    await tester.pumpAndSettle();
    for (final n in peopleChoices) {
      expect(find.byKey(Key('simulation-people-$n')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('simulation-people-160')));
    await tester.pumpAndSettle();
    expect(api.perCityAsked, [160]);
    expect(find.descendant(of: picker, matching: find.text('160 people a city')), findsOneWidget);
    // The next read says so too.
    await tester.pump(const Duration(seconds: 6));
    expect(find.descendant(of: picker, matching: find.text('160 people a city')), findsOneWidget);
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
    // After the events card's own, for its admission.
    expect(api.predictionAsked, [('lisboa-3', 'a1b2c3d4'), ('lisboa-1', null)]);
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
    expect(find.text('Jan 2, 2026'), findsOneWidget);
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

    // The events card asked once for the admission's 30 days.
    expect(api.predictionAsked, [('lisboa-3', 'a1b2c3d4')]);
    await tester.tap(find.byKey(const Key('person-link-lisboa-3')));
    await tester.pumpAndSettle();
    expect(api.personAsked, [('lisboa-3', 'a1b2c3d4')]);
    expect(api.predictionAsked, [('lisboa-3', 'a1b2c3d4'), ('lisboa-3', 'a1b2c3d4')]);
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
    expect(find.text('Simulated time: Jan 2, 2026 09:40'), findsOneWidget);

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

    // Its people in care per hour up to now, and datyx's forecast of the next ones, under the map.
    final timeline = find.byType(OccupancyTimelineCard);
    expect(timeline, findsOneWidget);
    expect(api.hourlyAsked.first, (1, null, 72));
    expect(api.forecastAsked.first, (1, null));
    expect(find.descendant(of: timeline, matching: find.byType(OccupancyTimelineChart)), findsOneWidget);
    expect(find.textContaining("datyx's DeepAR expects 1.5 on average over the next 4 hours"), findsOneWidget);
    expect(tester.getTopLeft(timeline).dy, greaterThan(tester.getBottomLeft(usage).dy));
    expect(tester.getTopLeft(timeline).dy, lessThan(tester.getTopLeft(find.byKey(const Key('care-center-person-lisboa-2'))).dy));

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

  testWidgets("a care center's view doubles and halves the flow of people there, beside what it is", (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(MaterialApp(
      home: CareCenterScreen(id: 1, load: api.careCenter, flow: api.changeFlow, showTiles: false),
    ));
    await tester.pumpAndSettle();
    String factor() => tester.widget<Text>(find.byKey(const Key('flow-factor'))).data!;
    bool enabled(String key) => tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

    // Beside the header, on its right, at the normal flow.
    final card = find.byKey(const Key('flow-card'));
    expect(card, findsOneWidget);
    final header = find.ancestor(of: find.text('Hospital · Hospital Central'), matching: find.byType(Card));
    expect(tester.getTopLeft(card).dy, tester.getTopLeft(header).dy);
    expect(tester.getTopLeft(card).dx, greaterThan(tester.getTopRight(header).dx));
    expect(factor(), 'Flow ×1');
    final height = tester.getSize(card).height;
    expect(find.text('Double the flow'), findsOneWidget);
    expect(find.text('Halve the flow'), findsOneWidget);
    expect(find.byKey(const Key('flow-reset')), findsNothing);
    expect(find.byTooltip('Twice as many arrivals here: the visits headed here come twice as often (up to ×8)'),
        findsOneWidget);

    // A press asks the API, both buttons disabled until it answers, then says the factor.
    api.flowGate = Completer<void>();
    await tester.tap(find.byKey(const Key('flow-double')));
    await tester.pump();
    expect(api.flowAsked, [(1, FlowAction.doubled)]);
    expect(enabled('flow-double'), isFalse);
    expect(enabled('flow-halve'), isFalse);
    api.flowGate!.complete();
    api.flowGate = null;
    await tester.pumpAndSettle();
    expect(factor(), 'Flow ×2');
    expect(find.text('The visits headed here come twice as often.'), findsOneWidget);
    expect(enabled('flow-double'), isTrue);
    // The reset shows, and the card keeps its height.
    expect(find.byKey(const Key('flow-reset')), findsOneWidget);
    expect(tester.getSize(card).height, height);

    // Up to ×8, where doubling stops; halved, and back to normal.
    await tester.tap(find.byKey(const Key('flow-double')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flow-double')));
    await tester.pumpAndSettle();
    expect(factor(), 'Flow ×8');
    expect(enabled('flow-double'), isFalse);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('flow-halve')));
      await tester.pumpAndSettle();
    }
    expect(factor(), 'Flow ×1/4');
    expect(find.text('The visits headed here come a quarter as often.'), findsOneWidget);
    // A read of the care center says the same.
    await tester.pump(CareCenterScreen.refresh);
    await tester.pumpAndSettle();
    expect(factor(), 'Flow ×1/4');
    await tester.tap(find.byKey(const Key('flow-reset')));
    await tester.pumpAndSettle();
    expect(factor(), 'Flow ×1');
    expect(api.flowAsked.last, (1, FlowAction.reset));

    // Refused: the reason in a snack bar, the factor as it was.
    api.flowRefused = const ApiException(401, 'sign in first');
    await tester.tap(find.byKey(const Key('flow-halve')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to change the flow.'), findsOneWidget);
    expect(factor(), 'Flow ×1');

    // Without the control, or a flow (prod, no simulation), no buttons.
    await tester.pumpWidget(MaterialApp(home: CareCenterScreen(key: const Key('no-flow'), id: 1, load: api.careCenter, showTiles: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flow-card')), findsNothing);
  });

  testWidgets("on a narrow window the flow's buttons are under what it is", (tester) async {
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi(auth: false, simulation: true);
    await tester.pumpWidget(MaterialApp(
      home: CareCenterScreen(id: 1, load: api.careCenter, flow: api.changeFlow, showTiles: false),
    ));
    await tester.pumpAndSettle();
    final header = find.ancestor(of: find.text('Hospital · Hospital Central'), matching: find.byType(Card));
    expect(tester.getTopLeft(find.byKey(const Key('flow-card'))).dy, greaterThan(tester.getBottomLeft(header).dy));
    expect(find.text('Double the flow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a care center says its flow factor in the simulation, none in prod', () {
    expect(CareCenterDetail.fromJson({'id': 1, 'flow': 2}).flow, 2);
    expect(CareCenterDetail.fromJson({'id': 1, 'flow': 0.125}).flow, 0.125);
    expect(CareCenterDetail.fromJson({'id': 1, 'flow': null}).flow, isNull);
    expect(flowLabel(1), '×1');
    expect(flowLabel(0.5), '×1/2');
    expect(flowLabel(8), '×8');
  });

  testWidgets("a clinic's view says the simulation sends nobody there; none is a 404", (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(home: CareCenterScreen(id: 2, load: api.careCenter, flow: api.changeFlow, showTiles: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clinic · Policlínica'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('usage-capacity'))).data, 'of 3 places');
    // A kind of clinic the simulation routes nobody to.
    expect(find.textContaining('The simulation sends nobody to a Policlínica'), findsOneWidget);
    // Nor buttons for its flow.
    expect(find.byKey(const Key('flow-card')), findsNothing);
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
        {'type': 'move', 'id': 'reus-4', 'state': 'to_home', 'simTime': '10:00', 'day': 4, 'name': 'Anna Vidal', 'age': 33, 'monitored': true, 'monitoredFor': 'pregnant'},
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
    expect((events.events[1].monitored, events.events[1].monitoredFor), (true, 'pregnant'));
    expect(events.events[2].type, StreamEventType.move);
    expect(events.events[2].monitored, isFalse);
    // An API from before the counts: none.
    expect((events.total, events.perSecond), (null, null));
    final counted = StreamEvents.fromJson({'enabled': true, 'total': 48213, 'perSecond': 70, 'events': []});
    expect((counted.total, counted.perSecond), (48213, 70.0));
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
    expect(find.textContaining('312 ms, 4100 input tokens, via datyx.'), findsOneWidget);

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

  group("a care center's occupancy per hour", () {
    Widget card(FakeApi api, int id, {int capacity = 8}) => MaterialApp(
      theme: aityxDarkTheme(),
      home: Scaffold(
        body: SizedBox(width: 720, child: OccupancyTimelineCard(
          occupancy: api.careCenterOccupancy,
          forecast: api.occupancyForecast,
          hospitalId: id,
          capacity: capacity,
          unit: 'beds',
          refresh: const Duration(days: 1))),
      ),
    );

    testWidgets('both series, observed and predicted, the now line, the threshold and its crossings', (tester) async {
      final semantics = tester.ensureSemantics();
      final api = FakeApi();
      await tester.pumpWidget(card(api, 2));
      await tester.pumpAndSettle();
      expect(api.hourlyAsked, [(2, null, 72)]);
      expect(api.forecastAsked, [(2, null)]);
      expect(find.text('Occupancy per hour'), findsOneWidget);
      // Now, the simulated clock as a date and time, never the run's id.
      expect(tester.widget<Text>(find.byKey(const Key('occupancy-now'))).data, 'Now · Jan 19, 2026 12:40');
      expect(find.textContaining('1349d576'), findsNothing);
      final status = tester.widget<Text>(find.byKey(const Key('occupancy-status'))).data!;
      expect(status, contains('1 in care at Jan 19, 2026 12:00; at most 3 of 8 beds in the last 6 hours.'));
      // How far off datyx was of the hours it predicted: |3-2.8|, |2-2.2|, |2-1.6|, |1-1.2|; how many in the band.
      expect(status, contains('datyx predicted 4 of them before they came, off by 0.25 on average; '));
      expect(status, matches(RegExp(r'; \d fell in its 80% band\.')));
      expect(status, contains("datyx's DeepAR expects 1.5 on average over the next 4 hours, 2.0 at most (model of training run 5)"));
      // Of 8 beds, 90% is 7.2: nothing reaches it.
      expect(status, isNot(contains('90% of the capacity')));
      expect(find.text('In care (observed)'), findsOneWidget);
      expect(find.text('Predicted by DeepAR before each hour and ahead (mean; the band, 10th to 90th percentile)'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Capacity, 8 beds'), findsOneWidget);
      expect(find.text('Alarm threshold, 90% (7.2)'), findsOneWidget);
      expect(find.text('In care at or above it'), findsOneWidget);
      expect(find.text('Predicted at or above it'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Occupancy per hour: 1 in care now (Jan 19, 2026 12:40), at most 3 in the last 6 hours, of a capacity of 8; '
          '4 of them predicted before; 1.5 on average forecast over the next 4; '
          'alarm threshold 90%, 7.2: 0 hours in care and 0 predicted at or above it',
        ),
        findsOneWidget,
      );

      // Touching an hour shows its numbers: three in care and what was predicted of them, then a forecast hour.
      final chart = tester.getRect(find.byType(OccupancyTimelineChart));
      double xOf(int index) => chart.left + 28 + index / 9 * (chart.width - 36);
      await tester.tapAt(Offset(xOf(2), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 09:00\n3 in care of 8 beds (38%)\npredicted 2.8, 1 h before\n1 to 3.5 (80%)'), findsOneWidget);
      await tester.tapAt(Offset(xOf(1), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 08:00\n1 in care of 8 beds (13%)'), findsOneWidget);
      await tester.tapAt(Offset(xOf(8), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 15:00, forecast\n2.0 expected of 8 beds (25%)\n0 to 3 (80%)'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('every hour at or above the threshold is marked, and the first ahead labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      // Of 3 beds, 90% is 2.7: 3 in care at 09:00 and its 2.8 predicted reach it; ahead, the 90th percentile (3) from 13:00.
      await tester.pumpWidget(card(FakeApi(), 2, capacity: 3));
      await tester.pumpAndSettle();
      expect(find.text('Alarm threshold, 90% (2.7)'), findsOneWidget);
      final status = tester.widget<Text>(find.byKey(const Key('occupancy-status'))).data!;
      expect(status, endsWith('90% of the capacity possible at Jan 19, 2026 13:00.'));
      expect(
        find.bySemanticsLabel(RegExp(
          r'alarm threshold 90%, 2\.7: 1 hours in care and 1 predicted at or above it; 90% possible at Jan 19, 2026 13:00$',
        )),
        findsOneWidget,
      );
      final chart = tester.getRect(find.byType(OccupancyTimelineChart));
      double xOf(int index) => chart.left + 28 + index / 9 * (chart.width - 36);
      await tester.tapAt(Offset(xOf(2), chart.center.dy));
      await tester.pump();
      expect(find.textContaining('3 in care of 3 beds (100%)\npredicted 2.8, 1 h before\n1 to 3.5 (80%)\nat or above the 90% threshold'),
          findsOneWidget);
      await tester.tapAt(Offset(xOf(6), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 13:00, forecast\n1.0 expected of 3 beds (33%)\n0 to 3 (80%)\n90% threshold possible'), findsOneWidget);
      semantics.dispose();
    });

    test('the first crossing ahead: by the mean, else by the 90th percentile', () {
      ForecastStep step(int h, double mean, double p90) =>
          ForecastStep(at: DateTime.utc(2026, 1, 19, h), mean: mean, p10: 0, p50: mean, p90: p90);
      expect(firstCrossing([step(13, 5, 8), step(14, 7.2, 9), step(15, 8, 9)], 7.2), (at: DateTime.utc(2026, 1, 19, 14), expected: true, index: 1));
      expect(firstCrossing([step(13, 5, 7.1), step(14, 6, 7.2)], 7.2), (at: DateTime.utc(2026, 1, 19, 14), expected: false, index: 1));
      expect(firstCrossing([step(13, 5, 7.1)], 7.2), isNull);
      // 90% of 10 is 9, reached by 9.
      expect(reachesThreshold(9, 0.9 * 10), isTrue);
      expect(percentText(0.9), '90%');
      expect(simDayTime(DateTime.utc(2026, 1, 19, 16)), 'Jan 19 16:00');
    });

    testWidgets('the now line is at the clock, the series\' end without one, and the predicted line over the past', (tester) async {
      final semantics = tester.ensureSemantics();
      final hours = [
        for (var h = 7; h <= 12; h++)
          HourOccupancy(hour: DateTime.utc(2026, 1, 19, h), occupancy: 9, predicted: h >= 10 ? PredictedHour(mean: 9.5, p10: 8, p90: 11) : null),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: aityxDarkTheme(),
        home: Scaffold(body: SizedBox(width: 600, child: OccupancyTimelineChart(hours: hours, capacity: 10, unit: 'beds'))),
      ));
      // Without a clock (a run that has ended), no now: the last hour; without a forecast the predicted past still shows, and its marks.
      expect(
        find.bySemanticsLabel(RegExp(r'^Occupancy per hour: 9 in care at the end \(Jan 19, 2026 12:00\).*; 3 of them predicted before; '
            r'alarm threshold 90%, 9: 6 hours in care and 3 predicted at or above it$')),
        findsOneWidget,
      );
      await tester.pumpWidget(MaterialApp(
        theme: aityxDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: OccupancyTimelineChart(hours: hours, capacity: 10, unit: 'beds', threshold: 0.95, now: DateTime.utc(2026, 1, 19, 12, 30)),
          ),
        ),
      ));
      expect(find.bySemanticsLabel(RegExp(r'9 in care now \(Jan 19, 2026 12:30\).*alarm threshold 95%, 9\.5: 0 hours in care and 3 predicted')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a run that has ended: its end in the header, no now line and no "Now" in the key', (tester) async {
      final semantics = tester.ensureSemantics();
      final api = FakeApi()..occupancyCurrent = false;
      await tester.pumpWidget(card(api, 2));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('occupancy-now'))).data, 'Ended Jan 19, 2026 12:00');
      expect(find.text('Now'), findsNothing);
      expect(find.text('In care (observed)'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Occupancy per hour: 1 in care at the end \(Jan 19, 2026 12:00\)')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a forecast starting hours after the last hour observed is drawn from its first step, without failing', (tester) async {
      final semantics = tester.ensureSemantics();
      // Observed 07:00 to 12:00; datyx read a longer series, so its first step is 14:00, the third reaching 90% of 8.
      final hours = [for (var h = 7; h <= 12; h++) HourOccupancy(hour: DateTime.utc(2026, 1, 19, h), occupancy: 3)];
      final steps = [
        for (final (h, mean) in [(14, 4.0), (15, 6.0), (16, 7.5)])
          ForecastStep(at: DateTime.utc(2026, 1, 19, h), mean: mean, p10: mean - 1, p50: mean, p90: mean + 1),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: aityxDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: OccupancyTimelineChart(hours: hours, forecast: steps, capacity: 8, unit: 'beds', now: DateTime.utc(2026, 1, 19, 12, 40)),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel(RegExp(r'5\.8 on average forecast over the next 3; .*; 90% expected at Jan 19, 2026 16:00$')),
        findsOneWidget,
      );
      // The hour between, 13:00, has a slot and no forecast.
      final chart = tester.getRect(find.byType(OccupancyTimelineChart));
      double xOf(int index) => chart.left + 28 + index / 9 * (chart.width - 36);
      await tester.tapAt(Offset(xOf(6), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 13:00, forecast'), findsOneWidget);
      semantics.dispose();
    });

    test('the label of the first crossing goes above its ring when there is room, else below it: never over the point', () {
      // A point low enough: the pill ends 3 px above its ring.
      expect(crossingLabelTop(pointY: 120, ring: 11, pill: 17), 120 - 11 - 3 - 17);
      // Just under the threshold line near the top (capacity 10, 9.2 at y ≈ 38): below the ring.
      expect(crossingLabelTop(pointY: 38, ring: 11, pill: 17), 38 + 11 + 3);
      for (final y in [24.0, 41.0, 60.0, 198.0]) {
        final top = crossingLabelTop(pointY: y, ring: 11, pill: 17);
        // The pill [top, top + 17] never covers the ring [y - 11, y + 11], nor reaches the now label.
        expect(top + 17 <= y - 11 || top >= y + 11, isTrue, reason: '$y');
        expect(top, greaterThanOrEqualTo(22));
      }
    });

    testWidgets('the forecast of the hours gone stays over them, to compare, until the run changes', (tester) async {
      final semantics = tester.ensureSemantics();
      // Day 19, 07:00 to 12:00, forecast 13:00 to 16:00; then 09:00 to 14:00, forecast 15:00 to 18:00;
      // then a new run.
      var read = 0;
      HourlyOccupancy series(String run, int from, List<int> inCare) => HourlyOccupancy.fromJson({
        'hospitalId': 2,
        'run': run,
        'current': true,
        'end': '2026-01-19T${'${from + inCare.length - 1}'.padLeft(2, '0')}:00',
        'hours': [
          for (var k = 0; k < inCare.length; k++)
            {'hour': '2026-01-19T${'${from + k}'.padLeft(2, '0')}:00', 'occupancy': inCare[k]},
        ],
      });
      HourlyForecast ahead(int from, List<double> means) => HourlyForecast.fromJson({
        'trainingRunId': 5,
        'forecast': [
          for (var k = 0; k < means.length; k++)
            {'at': '2026-01-19T${from + k}:00', 'mean': means[k], 'p10': 0, 'p50': 1, 'p90': 3},
        ],
      });
      await tester.pumpWidget(MaterialApp(
        theme: aityxDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: OccupancyTimelineCard(
              occupancy: (id, {run, hours}) async => switch (read++) {
                0 => series('1349d576', 7, [0, 1, 3, 2, 2, 1]),
                1 => series('1349d576', 9, [3, 2, 2, 1, 2, 5]),
                _ => series('5eed0002', 9, [0, 0, 0, 0, 0, 1]),
              },
              forecast: (id, {run}) async => read <= 1 ? ahead(13, [1.0, 1.5, 2.0, 1.5]) : ahead(15, [2.0, 2.5, 2.0, 1.5]),
              hospitalId: 2,
              capacity: 8,
              unit: 'beds',
              refresh: const Duration(seconds: 10),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('before they came'), findsNothing);

      // 13:00 and 14:00 were counted: 2 in care, in the band, and 5, above it; the first forecast stays over them
      // (the API keeps no prediction of them here, so the view's own are shown).
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'datyx predicted 2 of them before they came, off by ${expectedText(2.25)} on average; 1 fell in its 80% band.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Occupancy per hour: 5 in care now (Jan 19, 2026 14:00), at most 5 in the last 6 hours, of a capacity of 8; '
          '2 of them predicted before; 2.0 on average forecast over the next 4; '
          'alarm threshold 90%, 7.2: 0 hours in care and 0 predicted at or above it',
        ),
        findsOneWidget,
      );
      // 09:00 to 14:00 then 15:00 to 18:00: 13:00 is the fifth of ten.
      final chart = tester.getRect(find.byType(OccupancyTimelineChart));
      double xOf(int index) => chart.left + 28 + index / 9 * (chart.width - 36);
      await tester.tapAt(Offset(xOf(4), chart.center.dy));
      await tester.pump();
      // Forecast from 12:00's series' end: 13:00 an hour ahead.
      expect(find.text('Jan 19, 2026 13:00\n2 in care of 8 beds (25%)\npredicted 1.0, 1 h before\n0 to 3 (80%)'), findsOneWidget);
      // An hour from before any forecast has none.
      await tester.tapAt(Offset(xOf(1), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 10:00\n2 in care of 8 beds (25%)'), findsOneWidget);

      // A new run starts again: nothing of the old forecast is kept.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.textContaining('5eed0002'), findsNothing); // the run's id isn't shown: the simulated time is
      expect(tester.widget<Text>(find.byKey(const Key('occupancy-now'))).data, startsWith('Now · '));
      expect(find.textContaining('before they came'), findsNothing);
      semantics.dispose();
    });

    testWidgets("the API's prediction of an hour comes first, the view's own only where the API has none", (tester) async {
      // Day 19, 07:00 to 12:00, forecast 13:00 to 16:00; then 09:00 to 14:00, the API keeping a prediction of 13:00 only.
      var read = 0;
      HourlyOccupancy series(int from, List<int> inCare, {Map<int, Map<String, Object?>> predicted = const {}}) =>
          HourlyOccupancy.fromJson({
            'hospitalId': 2,
            'run': '1349d576',
            'current': true,
            'end': '2026-01-19T${'${from + inCare.length - 1}'.padLeft(2, '0')}:00',
            'hours': [
              for (var k = 0; k < inCare.length; k++)
                {
                  'hour': '2026-01-19T${'${from + k}'.padLeft(2, '0')}:00',
                  'occupancy': inCare[k],
                  if (predicted[from + k] != null) 'predicted': predicted[from + k],
                },
            ],
          });
      final forecast = HourlyForecast.fromJson({
        'trainingRunId': 5,
        'forecast': [
          for (var k = 0; k < 4; k++) {'at': '2026-01-19T${13 + k}:00', 'mean': 1.0 + k / 2, 'p10': 0, 'p50': 1, 'p90': 3},
        ],
      });
      await tester.pumpWidget(MaterialApp(
        theme: aityxDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: OccupancyTimelineCard(
              occupancy: (id, {run, hours}) async => read++ == 0
                  ? series(7, [0, 1, 3, 2, 2, 1])
                  : series(9, [3, 2, 2, 1, 2, 5], predicted: {13: {'mean': 2.5, 'p10': 2, 'p90': 3, 'leadHours': 3}}),
              forecast: (id, {run}) async => forecast,
              hospitalId: 2,
              capacity: 8,
              unit: 'beds',
              refresh: const Duration(seconds: 10),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      // 13:00: the API's 2.5, 3 h before (in its band); 14:00: the view's own 1.5, 2 h before (5 is above its band).
      expect(
        find.textContaining('datyx predicted 2 of them before they came, off by ${expectedText((0.5 + 3.5) / 2)} on average; '
            '1 fell in its 80% band.'),
        findsOneWidget,
      );
      final chart = tester.getRect(find.byType(OccupancyTimelineChart));
      double xOf(int index) => chart.left + 28 + index / 7 * (chart.width - 36);
      await tester.tapAt(Offset(xOf(4), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 13:00\n2 in care of 8 beds (25%)\npredicted 2.5, 3 h before\n2 to 3 (80%)'), findsOneWidget);
      await tester.tapAt(Offset(xOf(5), chart.center.dy));
      await tester.pump();
      expect(find.text('Jan 19, 2026 14:00\n5 in care of 8 beds (63%)\npredicted 1.5, 2 h before\n0 to 3 (80%)'), findsOneWidget);
    });

    testWidgets('without a model the hours still show, and the card says why', (tester) async {
      final api = FakeApi()..model = false;
      await tester.pumpWidget(card(api, 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('No forecast: no model of the group default of public.occupancy_hourly has been trained yet'),
          findsOneWidget);
      expect(find.byType(OccupancyTimelineChart), findsOneWidget);
      expect(find.text('In care (observed)'), findsOneWidget);
      // What datyx predicted before is still shown, and keyed.
      expect(find.textContaining('Predicted by DeepAR'), findsOneWidget);
    });

    testWidgets('without a capacity there is no capacity line, nor its key', (tester) async {
      await tester.pumpWidget(card(FakeApi(), 2, capacity: 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('at most 3 in the last 6 hours.'), findsOneWidget);
      expect(find.textContaining('Capacity'), findsNothing);
    });

    testWidgets('a care center nobody was admitted to says so', (tester) async {
      await tester.pumpWidget(card(FakeApi(), 7));
      await tester.pumpAndSettle();
      expect(find.text('Nobody has been admitted here yet.'), findsOneWidget);
      expect(find.byType(OccupancyTimelineChart), findsNothing);
    });

    test('a simulated time is a date on the calendar from 2026-01-01', () {
      expect(simDateTime(DateTime.utc(2026, 1, 1, 6)), 'Jan 1, 2026 06:00');
      expect(simWhen(32, '17:05'), 'Feb 1, 2026 17:05');
      expect(simWhen(554, '18:17'), 'Jul 8, 2027 18:17');
      expect(simWhen(null, '09:40'), '09:40');
      expect(simDayLabel(DateTime.utc(2026, 3, 9)), 'Mar 9');
      expect(simDateOf('2026-01-19'), 'Jan 19, 2026');
      expect(simDateOf('not a date'), 'not a date');
    });
  });

  group('occupancy alarms and the simulated clock', () {
    // As the API writes them (specs/occupancy-alarms.md).
    Map<String, Object?> event(String kind, String? level, {String? id, int hospital = 1, String name = 'Hospital de Santa Maria'}) => {
      'kind': kind,
      'id': id ?? 'cafe0001-$hospital-$kind',
      'run': 'cafe0001',
      'hospitalId': hospital,
      'hospitalName': name,
      'careCenterKind': 'hospital',
      'level': level,
      'previous': kind == 'cleared' ? 'possible' : null,
      'threshold': 0.9,
      'thresholdPlaces': 7.2,
      'occupancy': level == 'actual' ? 8 : 6,
      'occupancyShare': level == 'actual' ? 1.0 : 0.75,
      'observedAt': '2026-01-02T09:00',
      'overflowAt': kind == 'cleared' ? null : (level == 'actual' ? '2026-01-02T09:00' : '2026-01-02T16:00'),
      'overflowDay': kind == 'cleared' ? null : 2,
      'leadHours': kind == 'cleared' ? null : 7,
      'mean': kind == 'cleared' ? null : (level == 'expected' ? 10.0 : 6.6),
      'p90': kind == 'cleared' ? null : 12.4,
      'peak': {'at': '2026-01-02T18:00', 'day': 2, 'mean': 11.3, 'p90': 13.0},
      'capacity': 8,
      'unit': 'beds',
      'end': '2026-01-02T09:00',
      'horizonHours': 24,
      'trainingRun': 4,
      'now': {'day': 2, 'simTime': '09:00', 'date': '2026-01-02'},
      'raisedAt': '2026-11-01T14:03:05.120Z',
    };
    Map<String, Object?> active(
      String level, {
      int hospital = 1,
      String name = 'Hospital de Santa Maria',
      int lead = 7,
      String overflowAt = '2026-01-02T16:00',
    }) => {
      ...event('alarm', level, hospital: hospital, name: name)..remove('kind')..remove('id'),
      'leadHours': lead,
      'overflowAt': overflowAt,
      'since': '2026-11-01T14:03:05.120Z',
      'checkedAt': '2026-11-01T14:03:10.120Z',
    };
    final twoAlarms = {
      'enabled': true,
      'checkedAt': '2026-11-01T14:03:10.120Z',
      'status': 200,
      'note': null,
      'active': [
        active('expected'),
        active('possible', hospital: 2, name: 'Clínica do Campo', lead: 4, overflowAt: '2026-01-02T13:00'),
      ],
      'recent': [
        event('alarm', 'expected', id: 'e3'),
        event('alarm', 'possible', id: 'e2', hospital: 2, name: 'Clínica do Campo'),
        event('cleared', null, id: 'e1', hospital: 3, name: 'Centro de Saúde'),
      ],
    };

    Future<FakeApi> home(
      WidgetTester tester, {
      Map<String, Object?>? alarms,
      List<StreamEvent>? stream,
      Map<String, Object?>? busiest,
      double height = 2600,
    }) async {
      tester.view.physicalSize = Size(1400, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final api = FakeApi(auth: false, simulation: true)
        ..alarms = alarms
        ..stream = stream
        ..busiest = busiest;
      final locations = FakeLocations();
      await tester.pumpWidget(app(api: api, locations: locations));
      locations.move(38.72, -9.14);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      return api;
    }

    Color borderOf(WidgetTester tester, Key key) {
      final decoration = tester.widget<Container>(find.byKey(key)).decoration! as BoxDecoration;
      return switch (decoration.border) {
        final Border border when border.left.width == 4 && border.top == BorderSide.none => border.left.color,
        final Border border => border.top.color,
        _ => Colors.transparent,
      };
    }

    test('the API answer is read: the clock, the alarms now and the events', () {
      final events = StreamEvents.fromJson({
        'enabled': true,
        'now': {'day': 154, 'simTime': '16:00', 'date': '2026-06-03'},
        'alarms': {
          ...twoAlarms,
          'active': [...twoAlarms['active']! as List, 'not an alarm', {'level': 'expected'}],
        },
        'events': [],
      });
      expect(events.clock!.day, 154);
      expect(simClockLabel(events.clock!), 'Jun 3, 2026 16:00');
      // Without the date, it is counted from day 1, Jan 1, 2026.
      expect(simClockLabel(const SimNow(day: 2, simTime: '09:40')), 'Jan 2, 2026 09:40');
      expect(simClockLabel(SimNow.fromJson({'date': '2026-01-03', 'simTime': '00:00'})!), 'Jan 3, 2026 00:00');

      final alarms = events.alarms;
      expect(alarms.reported, isTrue);
      expect(alarms.active.map((a) => a.careCenterId), [1, 2]); // the entries it can't read are left out
      final expected = alarms.active.first;
      expect(expected.level, AlarmLevel.expected);
      expect(expected.kind, AlarmKind.alarm);
      expect(expected.careCenterName, 'Hospital de Santa Maria');
      expect(expected.careCenterKind, CareCenterKind.hospital);
      expect(expected.overflowAt, DateTime.utc(2026, 1, 2, 16));
      expect((expected.leadHours, expected.mean, expected.p90, expected.capacity, expected.unit), (7.0, 10.0, 12.4, 8, 'beds'));
      expect((expected.peakAt, expected.peakMean, expected.peakP90), (DateTime.utc(2026, 1, 2, 18), 11.3, 13.0));
      expect((expected.trainingRun, expected.now!.simTime), (4, '09:00'));
      expect((expected.threshold, expected.thresholdPlaces, expected.occupancy, expected.occupancyShare), (0.9, 7.2, 6, 0.75));
      expect(expected.observedAt, DateTime.utc(2026, 1, 2, 9));
      expect(AlarmLevel.named('actual'), AlarmLevel.actual);
      expect(OccupancyAlarms.fromJson({...twoAlarms, 'threshold': 0.9}).threshold, 0.9);
      expect(alarms.recent.map((a) => (a.id, a.kind, a.level)), [
        ('e3', AlarmKind.alarm, AlarmLevel.expected),
        ('e2', AlarmKind.alarm, AlarmLevel.possible),
        ('e1', AlarmKind.cleared, null),
      ]);

      // Without `now`, the clock is the newest record's; without `alarms`, none.
      final older = StreamEvents.fromJson({
        'enabled': true,
        'events': [
          {'id': 'a', 'simTime': '08:00', 'day': 3},
          {'id': 'b', 'simTime': '09:40', 'day': 3},
        ],
      });
      expect((older.clock!.day, older.clock!.simTime), (3, '09:40'));
      expect(older.alarms.reported, isFalse);
      expect(older.alarms.active, isEmpty);
    });

    testWidgets('the alarms are pinned at the top of the events: expected in red, possible in amber', (tester) async {
      await home(tester, alarms: twoAlarms);
      final card = find.byKey(const Key('stream-events'));

      // The header counts them, in red.
      final badge = find.descendant(of: card, matching: find.byKey(const Key('alarms-badge')));
      expect(find.descendant(of: badge, matching: find.text('2 alarms')), findsOneWidget);
      expect((tester.widget<Container>(badge).decoration! as BoxDecoration).color, Aityx.red);

      final expected = find.byKey(const Key('alarm-banner-1'));
      final possible = find.byKey(const Key('alarm-banner-2'));
      expect(find.descendant(of: expected, matching: find.text('90% occupancy expected at ')), findsOneWidget);
      expect(find.descendant(of: expected, matching: find.text('Hospital de Santa Maria')), findsOneWidget);
      // How far ahead from the clock above, Jan 2, 2026 09:40, not from the check (7 h then).
      expect(find.descendant(of: expected, matching: find.text(' in 6 h 20 min')), findsOneWidget);
      expect(
        find.descendant(
          of: expected,
          matching: find.text('Jan 2, 2026 16:00: 10 in care of 8 beds (90% range up to 12.4) · peak 11.3 at Jan 2, 2026 18:00 (90% range up to 13)'),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: expected, matching: find.byIcon(Icons.crisis_alert)), findsOneWidget);
      expect(borderOf(tester, const Key('alarm-banner-1')), Aityx.red);

      expect(find.descendant(of: possible, matching: find.text('90% occupancy possible: ')), findsOneWidget);
      expect(find.descendant(of: possible, matching: find.text(' may reach 90% of its 8 beds in 3 h 20 min')), findsOneWidget);
      expect(
        find.descendant(of: possible, matching: find.textContaining('Jan 2, 2026 13:00: 6.6 expected in care of 8 beds, 90% range up to 12.4')),
        findsOneWidget,
      );
      expect(find.descendant(of: possible, matching: find.byIcon(Icons.warning_amber)), findsOneWidget);
      expect(borderOf(tester, const Key('alarm-banner-2')), Aityx.amber);
      // Up to date: nothing says otherwise.
      expect(find.byKey(const Key('alarm-stale')), findsNothing);
      expect(find.byKey(const Key('alarms-stale')), findsNothing);

      // Pinned at the top: under the simulation's controls, above every row, expected first.
      final invite = tester.getRect(find.byKey(const Key('person-invite')));
      expect(tester.getRect(find.byKey(const Key('simulation-pause'))).bottom, lessThanOrEqualTo(tester.getRect(expected).top));
      expect(tester.getRect(expected).bottom, lessThanOrEqualTo(tester.getRect(possible).top));
      expect(tester.getRect(possible).bottom, lessThan(invite.top));
    });

    testWidgets('the occupancy now at the threshold: a red banner first, "now at 100%", current though datyx is not', (tester) async {
      await home(tester, alarms: {
        ...twoAlarms,
        'stale': true,
        'note': 'the datyx API is not answering',
        'active': [
          active('actual', overflowAt: '2026-01-02T09:00', lead: 0),
          active('possible', hospital: 2, name: 'Clínica do Campo', lead: 4, overflowAt: '2026-01-02T13:00'),
        ],
        'recent': [event('alarm', 'actual', id: 'e4')],
      });
      final actual = find.byKey(const Key('alarm-banner-1'));
      expect(find.descendant(of: actual, matching: find.text('Occupancy now at 100% at ')), findsOneWidget);
      expect(find.descendant(of: actual, matching: find.text('Hospital de Santa Maria')), findsOneWidget);
      expect(
        find.descendant(of: actual, matching: find.textContaining('Jan 2, 2026 09:00: 8 in care of 8 beds (100%)')),
        findsOneWidget,
      );
      expect(find.descendant(of: actual, matching: find.byIcon(Icons.emergency)), findsOneWidget);
      expect(borderOf(tester, const Key('alarm-banner-1')), Aityx.red);
      // The occupancy observed isn't datyx's: not out of date with it; the forecast's alarm is.
      expect(find.descendant(of: actual, matching: find.byKey(const Key('alarm-stale'))), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('alarm-banner-2')), matching: find.byKey(const Key('alarm-stale'))), findsOneWidget);
      expect(tester.getRect(actual).bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const Key('alarm-banner-2'))).top));
      final row = find.byKey(const Key('alarm-row-e4'));
      expect(find.descendant(of: row, matching: find.text('Alarm: 90% reached now · ')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('8 in care of 8 beds (100%)')), findsOneWidget);
      expect(borderOf(tester, const Key('alarm-row-e4')), Aityx.red);
    });

    testWidgets("an alarm's care center opens its view", (tester) async {
      final api = await home(tester, alarms: twoAlarms);
      await tester.tap(find.descendant(of: find.byKey(const Key('alarm-banner-1')), matching: find.byKey(const Key('care-center-link-1'))));
      await tester.pumpAndSettle();
      expect(find.byType(CareCenterScreen), findsOneWidget);
      expect(api.careCenterAsked, [1]);
    });

    testWidgets('the alarms raised and cleared are rows of the stream: red, amber, green', (tester) async {
      await home(tester, alarms: {
        ...twoAlarms,
        'recent': [...twoAlarms['recent']! as List, event('downgraded', 'possible', id: 'e0', hospital: 4, name: 'Hospital Dona Estefânia')],
      });
      final card = find.byKey(const Key('stream-events'));
      final raised = find.byKey(const Key('alarm-row-e3'));
      expect(find.descendant(of: card, matching: raised), findsOneWidget);
      expect(find.descendant(of: raised, matching: find.text('Alarm: 90% expected · ')), findsOneWidget);
      expect(find.descendant(of: raised, matching: find.text('in 7 h, Jan 2, 2026 16:00 · 10 in care of 8 beds (90% range up to 12.4)')), findsOneWidget);
      expect(find.descendant(of: raised, matching: find.text('Jan 2, 2026 09:00')), findsOneWidget);
      expect(borderOf(tester, const Key('alarm-row-e3')), Aityx.red);
      expect(find.descendant(of: find.byKey(const Key('alarm-row-e2')), matching: find.text('Alarm: 90% possible · ')), findsOneWidget);

      final cleared = find.byKey(const Key('alarm-row-e1'));
      expect(find.descendant(of: cleared, matching: find.text('Cleared: below 90% · ')), findsOneWidget);
      expect(find.descendant(of: cleared, matching: find.text('Centro de Saúde')), findsOneWidget);
      expect(find.descendant(of: cleared, matching: find.text('In care and forecast below 90% of 8 beds')), findsOneWidget);
      expect(borderOf(tester, const Key('alarm-row-e1')), Aityx.green);
      expect(borderOf(tester, const Key('alarm-row-e0')), Aityx.amber);

      // Of the same shape as the others, and in time order: after the 09:40 moves, before the 08:00 admission.
      final rowHeight = tester.getSize(find.byKey(const Key('move-lisboa-1-42'))).height;
      expect(tester.getSize(raised).height, rowHeight);
      expect(tester.getRect(raised).top, greaterThan(tester.getRect(find.byKey(const Key('move-lisboa-1-42'))).top));
      expect(tester.getRect(cleared).top, lessThan(tester.getRect(find.byKey(const Key('admission-a1b2c3d4-lisboa-3-d2-t32'))).top));
    });

    testWidgets('an overflow the clock has passed reads now, since its hour', (tester) async {
      await home(tester, alarms: {
        ...twoAlarms,
        'active': [active('expected', lead: 1, overflowAt: '2026-01-02T08:00')],
      });
      final banner = find.byKey(const Key('alarm-banner-1'));
      expect(find.descendant(of: banner, matching: find.text(' now, since Jan 2, 2026 08:00')), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.textContaining('in 1 h')), findsNothing);
    });

    testWidgets('alarms datyx no longer refreshes say so, and since when', (tester) async {
      await home(tester, alarms: {
        ...twoAlarms,
        'status': 502,
        'note': 'the datyx API is not answering',
        'stale': true,
        'active': [{...active('expected'), 'stale': true}],
      });
      final banner = find.byKey(const Key('alarm-banner-1'));
      // Still pinned, still red, but marked.
      expect(borderOf(tester, const Key('alarm-banner-1')), Aityx.red);
      expect(
        find.descendant(of: banner, matching: find.text('Not current: last checked Jan 2, 2026 09:00')),
        findsOneWidget,
      );
      // And the panel says why, though alarms are up.
      expect(
        find.text('Occupancy alarms may be out of date · last checked Jan 2, 2026 09:00 · the datyx API is not answering'),
        findsOneWidget,
      );
      expect(find.textContaining("datyx can't forecast yet"), findsNothing);
    });

    testWidgets('one alarm left out of the latest answer is marked alone', (tester) async {
      await home(tester, alarms: {
        ...twoAlarms,
        'active': [{...active('expected'), 'stale': true}, active('possible', hospital: 2, name: 'Clínica do Campo')],
      });
      expect(find.descendant(of: find.byKey(const Key('alarm-banner-1')), matching: find.byKey(const Key('alarm-stale'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('alarm-banner-2')), matching: find.byKey(const Key('alarm-stale'))), findsNothing);
    });

    testWidgets('no alarm, no banner nor badge; why when datyx cannot forecast', (tester) async {
      await home(tester, alarms: {'enabled': true, 'checkedAt': null, 'status': 404, 'note': 'no model of the group default has been trained yet', 'active': [], 'recent': []});
      expect(find.byKey(const Key('alarms-badge')), findsNothing);
      expect(find.byType(AlarmBanner), findsNothing);
      expect(find.byType(AlarmRow), findsNothing);
      expect(find.textContaining("Occupancy alarms: datyx can't forecast yet, only the occupancy now is checked (no model"), findsOneWidget);
    });

    // As the API gives them, its order: newest first, but the client
    // sorts by simulated time all the same.
    StreamEvent admitted(String id, String eventId, String time, {int hospital = 1, ConditionType type = ConditionType.acute, TriageLevel? triage, int offset = 1}) => StreamEvent(
      id: id,
      type: StreamEventType.admission,
      state: PersonState.atHospital,
      name: 'Patient $id',
      age: 50,
      conditionName: type == ConditionType.acute ? 'Influenza' : 'COPD',
      conditionType: type,
      visit: VisitKind.first,
      visitNumber: 1,
      complaint: 'I feel unwell.',
      hospitalId: hospital,
      hospitalName: hospital == 2 ? 'Hospital Dona Estefânia' : 'Hospital de Santa Maria',
      simTime: time,
      day: 2,
      partition: 0,
      offset: offset,
      eventId: eventId,
      triage: triage,
    );
    StreamEvent moved(String id, PersonState state, String time, int offset, {int hospital = 1, ConditionType? type}) => StreamEvent(
      id: id,
      name: 'Person $id',
      state: state,
      conditionName: type == null ? null : (type == ConditionType.acute ? 'Influenza' : 'COPD'),
      conditionType: type,
      hospitalId: hospital,
      hospitalName: hospital == 2 ? 'Hospital Dona Estefânia' : 'Hospital de Santa Maria',
      simTime: time,
      day: 2,
      partition: 0,
      offset: offset,
    );
    final mixed = [
      moved('lisboa-1', PersonState.toHospital, '09:40', 42, type: ConditionType.chronic),
      admitted('lisboa-4', 'r1-lisboa-4-d2-t41', '10:15', hospital: 2, triage: TriageLevel.red, offset: 8),
      moved('lisboa-5', PersonState.atHospital, '09:40', 41, hospital: 2, type: ConditionType.acute),
      // At home: the record names their usual hospital, the busiest, but they aren't there.
      moved('lisboa-6', PersonState.home, '09:20', 40, hospital: 2),
      admitted('lisboa-3', 'r1-lisboa-3-d2-t32', '08:00', type: ConditionType.chronic, triage: TriageLevel.green, offset: 7),
      admitted('lisboa-7', 'r1-lisboa-7-d2-t30', '07:00', triage: TriageLevel.orange, offset: 6),
    ];
    const busiest = {'id': 2, 'name': 'Hospital Dona Estefânia', 'kind': 'hospital', 'inCare': 3};
    const rowKeys = {
      'a4': Key('admission-r1-lisboa-4-d2-t41'),
      'm1': Key('move-lisboa-1-42'),
      'm5': Key('move-lisboa-5-41'),
      'm6': Key('move-lisboa-6-40'),
      'e3': Key('alarm-row-e3'),
      'e2': Key('alarm-row-e2'),
      'e1': Key('alarm-row-e1'),
      'a3': Key('admission-r1-lisboa-3-d2-t32'),
      'a7': Key('admission-r1-lisboa-7-d2-t30'),
    };
    // The rows shown in the card, top to bottom.
    List<String> shownRows(WidgetTester tester) {
      final card = find.byKey(const Key('stream-events'));
      final shown = [
        for (final MapEntry(:key, :value) in rowKeys.entries)
          if (find.descendant(of: card, matching: find.byKey(value)).evaluate().isNotEmpty) (key, tester.getRect(find.byKey(value)).top),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final (key, _) in shown) key];
    }

    testWidgets('one stream newest first by simulated time, the kinds among each other', (tester) async {
      final api = await home(tester, alarms: twoAlarms, stream: mixed, busiest: busiest, height: 3600);
      expect(api.eventTypes.toSet(), {null});
      // The 10:15 admission on top; the moves of 09:40 in the API's order (the
      // order read); the alarms of the 09:00 check among them; the older
      // admissions after.
      expect(shownRows(tester), ['a4', 'm1', 'm5', 'm6', 'e3', 'e2', 'e1', 'a3', 'a7']);
      // aityx's triage on an admission's row.
      final mark = find.byKey(const Key('admission-triage-r1-lisboa-4-d2-t41'));
      expect(find.descendant(of: mark, matching: find.text('Immediate')), findsOneWidget);
      expect(find.descendant(of: find.byKey(rowKeys['a3']!), matching: find.text('Standard')), findsOneWidget);
      // No counts in the header: the simulated date and time, here the
      // newest record's (this answer has no clock of its own).
      expect(find.textContaining(RegExp(r'\d+ (admission|move)s?\b')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('events-clock')), matching: find.text('Jan 2, 2026 10:15')), findsOneWidget);
    });

    testWidgets('pills filter the stream, one at a time, All first; the busiest named', (tester) async {
      await home(tester, alarms: twoAlarms, stream: mixed, busiest: busiest, height: 3600);
      final pills = find.byKey(const Key('events-filter'));
      String labelOf(String name) => tester.widget<Text>(find.descendant(
        of: find.byKey(Key('events-filter-$name')),
        matching: find.byType(Text),
      )).data!;
      // Each with how many of the rows read it keeps; All without.
      expect([for (final f in EventsFilter.values) labelOf(f.name)], [
        'All',
        'Busiest: Hospital Dona Estefânia · 3',
        'Alarms 3',
        'Urgent 2',
        'Admissions 3',
        'On the move 1',
        'Acute 3',
        'Chronic 2',
      ]);
      // How many are in care there, on hover.
      expect(
        tester.widget<Tooltip>(find.ancestor(of: find.byKey(const Key('events-filter-busiest')), matching: find.byType(Tooltip)).first).message,
        startsWith('Hospital Dona Estefânia: the most people in care now, 3.'),
      );
      bool selected(String name) => tester.widget<ChoiceChip>(find.byKey(Key('events-filter-$name'))).selected;
      expect(selected('all'), isTrue);
      // Under the controls and the invitation, above the rows.
      expect(tester.getRect(pills).top, greaterThan(tester.getRect(find.byKey(const Key('person-invite'))).bottom));
      expect(tester.getRect(pills).bottom, lessThan(tester.getRect(find.byKey(rowKeys['a4']!)).top));

      final expected = {
        'busiest': ['a4', 'm5', 'e2'],
        'alarms': ['e3', 'e2', 'e1'],
        'urgent': ['a4', 'a7'],
        'admissions': ['a4', 'a3', 'a7'],
        'onTheMove': ['m1'],
        'acute': ['a4', 'm5', 'a7'],
        'chronic': ['m1', 'a3'],
        'all': ['a4', 'm1', 'm5', 'm6', 'e3', 'e2', 'e1', 'a3', 'a7'],
      };
      for (final MapEntry(key: name, value: rows) in expected.entries) {
        await tester.tap(find.byKey(Key('events-filter-$name')));
        await tester.pump();
        expect(shownRows(tester), rows, reason: name);
        // One at a time.
        for (final f in EventsFilter.values) {
          expect(selected(f.name), f.name == name, reason: '$name: ${f.name}');
        }
      }
      // The choice holds over the next reads.
      await tester.tap(find.byKey(const Key('events-filter-urgent')));
      await tester.pump(const Duration(seconds: 6));
      expect(shownRows(tester), ['a4', 'a7']);
    });

    testWidgets('a pill that keeps nothing says so; no busiest pill until the API names one', (tester) async {
      await home(tester);
      expect(find.byKey(const Key('events-filter-busiest')), findsNothing);
      expect(find.byKey(const Key('events-filter-all')), findsOneWidget);
      await tester.tap(find.byKey(const Key('events-filter-urgent')));
      await tester.pump();
      expect(find.text('No urgent event among the latest.'), findsOneWidget);
      expect(find.byType(EventRow), findsNothing);
      await tester.tap(find.byKey(const Key('events-filter-all')));
      await tester.pump();
      expect(find.byKey(const Key('events-filter-empty')), findsNothing);
      expect(find.byType(EventRow), findsNWidgets(3));
    });

    test('the busiest keeps its care center: admissions, people going to, at or leaving it, its alarms', () {
      const at = BusiestCareCenter(id: 2, name: 'Hospital Dona Estefânia', inCare: 3);
      StreamRow row(StreamEvent event) => (event: event, alarm: null, minutes: 0);
      bool kept(StreamEvent event) => keeps(EventsFilter.busiest, row(event), at);
      expect(kept(admitted('a', 'x', '09:00', hospital: 2)), isTrue);
      expect(kept(admitted('a', 'x', '09:00')), isFalse);
      for (final state in [PersonState.toHospital, PersonState.atHospital, PersonState.toHome]) {
        expect(kept(moved('b', state, '09:00', 1, hospital: 2)), isTrue, reason: '$state');
      }
      expect(kept(moved('b', PersonState.home, '09:00', 1, hospital: 2)), isFalse);
      final alarm = OccupancyAlarm.fromJson(event('alarm', 'expected', hospital: 2))!;
      expect(keeps(EventsFilter.busiest, (event: null, alarm: alarm, minutes: 0), at), isTrue);
      // Without a busiest, nothing.
      expect(keeps(EventsFilter.busiest, row(admitted('a', 'x', '09:00', hospital: 2)), null), isFalse);
      // The answer names it; none without an id.
      final named = StreamEvents.fromJson({'enabled': true, 'busiest': busiest, 'events': []}).busiest!;
      expect((named.id, named.name, named.kind, named.inCare), (2, 'Hospital Dona Estefânia', CareCenterKind.hospital, 3));
      expect(StreamEvents.fromJson({'enabled': true, 'busiest': {'name': 'x'}}).busiest, isNull);
      // An admission's triage, as the API writes it.
      final triaged = StreamEvent.fromJson({'type': 'admission', 'personId': 'p', 'triage': 'orange'});
      expect((triaged.triage, triaged.isUrgent), (TriageLevel.orange, true));
      expect(StreamEvent.fromJson({'type': 'admission', 'personId': 'p', 'triage': 'yellow'}).isUrgent, isFalse);
    });

    testWidgets('the simulated date and time on top of the map and of the events, and Paused', (tester) async {
      final api = await home(tester);
      final mapClock = find.byKey(const Key('map-clock'));
      final eventsClock = find.byKey(const Key('events-clock'));
      // On the map tile's header, beside its title; beside the events' title too.
      expect(find.descendant(of: find.byKey(const Key('location-tile')), matching: mapClock), findsOneWidget);
      expect(find.descendant(of: mapClock, matching: find.text('Jan 2, 2026 09:40')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('stream-events')), matching: eventsClock), findsOneWidget);
      expect(find.descendant(of: eventsClock, matching: find.text('Jan 2, 2026 09:40')), findsOneWidget);
      final title = tester.getRect(find.text('Latest events'));
      expect(tester.getRect(eventsClock).left, greaterThan(title.right));
      expect(tester.getCenter(eventsClock).dy, closeTo(title.center.dy, 4));
      expect(find.text('Paused'), findsNothing);

      await tester.tap(find.byKey(const Key('simulation-pause')));
      await tester.pump();
      expect(api.pausesAsked, [true]);
      expect(find.descendant(of: mapClock, matching: find.text('Paused')), findsOneWidget);
      expect(find.descendant(of: eventsClock, matching: find.text('Paused')), findsOneWidget);

      // The next read says it too; resumed, it goes.
      await tester.pump(const Duration(seconds: 5));
      expect(find.descendant(of: eventsClock, matching: find.text('Paused')), findsOneWidget);
      await tester.tap(find.byKey(const Key('simulation-pause')));
      await tester.pump();
      expect(find.text('Paused'), findsNothing);
    });

    testWidgets('the index shows the simulated date and time under the welcome', (tester) async {
      final locations = FakeLocations();
      await tester.pumpWidget(app(api: FakeApi(simulation: true), locations: locations));
      locations.move(38.72, -9.14);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final clock = find.byKey(const Key('index-clock'));
      expect(find.descendant(of: clock, matching: find.text('Jan 2, 2026 09:40')), findsOneWidget);
      expect(tester.getRect(clock).top, greaterThan(tester.getRect(find.byKey(const Key('welcome'))).bottom - 1));
    });

    testWidgets('nothing of the clock before the simulation says its time', (tester) async {
      await tester.pumpWidget(app(api: FakeApi()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('index-clock')), findsNothing);
      expect(find.byType(SimClockText), findsNothing);
    });

    test('the clock keeps the newest reading, but follows a new run back', () {
      final clock = SimClock();
      var told = 0;
      clock.addListener(() => told++);
      clock.report(const SimNow(day: 2, simTime: '09:40'));
      clock.report(const SimNow(day: 2, simTime: '09:12')); // a slower poll's
      expect(clock.now!.simTime, '09:40');
      clock.report(null, paused: true);
      expect((clock.paused, told), (true, 2));
      clock.report(const SimNow(day: 1, simTime: '00:00')); // a new run
      expect((clock.now!.day, told), (1, 3));
      clock.dispose();
    });
  });
}
