import 'dart:convert';

import 'package:http/http.dart' as http;

/// What GET /api/hello answers: the greeting kept in the database, when it
/// was written, the PostgreSQL server's version, and who the API says is
/// signed in (the greeting is addressed to them).
class Greeting {
  const Greeting({
    required this.message,
    required this.since,
    required this.postgres,
    this.user,
  });

  factory Greeting.fromJson(Map<String, Object?> json) => Greeting(
    message: json['message'] as String,
    since: DateTime.tryParse((json['since'] as String?) ?? ''),
    postgres: (json['postgres'] as String?) ?? '',
    user: json['user'] is Map ? Me.fromJson((json['user'] as Map).cast()) : null,
  );

  final String message;
  final DateTime? since;

  /// PostgreSQL's `version()`, e.g. "PostgreSQL 17.6 on x86_64-pc-linux-gnu, ...".
  final String postgres;

  /// The signed-in user the API addressed, or null.
  final Me? user;

  /// The version's first words: "PostgreSQL 17.6".
  String get postgresShort {
    final words = postgres.split(' ');
    return words.length >= 2 ? '${words[0]} ${words[1]}' : postgres;
  }
}

/// What GET /api/health answers.
class Health {
  const Health({required this.ok, required this.db, required this.aityx, this.auth = false});

  factory Health.fromJson(Map<String, Object?> json) => Health(
    ok: json['ok'] == true,
    db: json['db'] == true,
    aityx: json['aityx'] == true,
    auth: json['auth'] == true,
  );

  final bool ok;

  /// Whether the API's database answers.
  final bool db;

  /// Whether the API has its aityx key.
  final bool aityx;

  /// Whether the API wants a signed-in user.
  final bool auth;
}

/// How the API authenticates: `GET /api/auth/config`. Off until the API
/// has a client id; on, the issuer (Google) and the OpenID Connect client id
/// the app signs in with.
class AuthConfig {
  const AuthConfig({required this.enabled, required this.issuer, this.clientId});

  factory AuthConfig.fromJson(Map<String, Object?> json) => AuthConfig(
    enabled: json['enabled'] == true,
    issuer: json['issuer'] as String? ?? '',
    clientId: json['clientId'] as String?,
  );

  final bool enabled;
  final String issuer;
  final String? clientId;
}

/// Who an API says is calling: `GET /api/me` here, `GET /api/datyx/me` as
/// the datyx API sees the same token.
class Me {
  const Me({required this.authenticated, this.subject, this.email, this.name, this.picture});

  factory Me.fromJson(Map<String, Object?> json) => Me(
    // datyx answers `authenticated`; our own hello embeds the identity alone.
    authenticated: json['authenticated'] == true || json['subject'] != null,
    subject: json['subject'] as String?,
    email: json['email'] as String?,
    name: json['name'] as String?,
    picture: json['picture'] as String?,
  );

  final bool authenticated;
  final String? subject;
  final String? email;
  final String? name;
  final String? picture;

  String get label => name ?? email ?? subject ?? 'anonymous';
}

/// A hospital, clinic or health station: one row of
/// `GET /api/care-centers`.
class CareCenter {
  const CareCenter({
    required this.id,
    required this.name,
    required this.kind,
    required this.lat,
    required this.lon,
    this.subtype,
    this.address,
    this.city,
    this.phone,
    this.website,
  });

  factory CareCenter.fromJson(Map<String, Object?> json) => CareCenter(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    kind: CareCenterKind.named(json['kind'] as String?),
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    subtype: json['subtype'] as String?,
    address: json['address'] as String?,
    city: json['city'] as String?,
    phone: json['phone'] as String?,
    website: json['website'] as String?,
  );

  final int id;
  final String name;
  final CareCenterKind kind;
  final double lat;
  final double lon;

  /// The source's own type: "CAP", "UBS", "Hospital Geral"...
  final String? subtype;
  final String? address;
  final String? city;
  final String? phone;
  final String? website;
}

/// What a care center is.
enum CareCenterKind {
  hospital('Hospital'),
  clinic('Clinic'),
  healthStation('Health station');

  const CareCenterKind(this.label);

  final String label;

  /// The API's name for it (`hospital`, `clinic`, `health_station`);
  /// anything else counts as a clinic.
  static CareCenterKind named(String? name) => switch (name) {
    'hospital' => hospital,
    'health_station' => healthStation,
    _ => clinic,
  };
}

/// The care centers of an area, and whether there were more than the API
/// gives at once (hospitals come first, then health stations, then clinics).
class CareCenters {
  const CareCenters(this.centers, {this.truncated = false});

  factory CareCenters.fromJson(Map<String, Object?> json) => CareCenters(
    [
      for (final center in (json['centers'] as List? ?? const []))
        CareCenter.fromJson((center as Map).cast()),
    ],
    truncated: json['truncated'] == true,
  );

  final List<CareCenter> centers;
  final bool truncated;
}

/// Where a simulated person is in their day.
enum PersonState {
  home('At home'),
  toHospital('Going to the hospital'),
  atHospital('At the hospital'),
  toHome('Going home');

  const PersonState(this.label);

  final String label;

  /// The API's name for it (`home`, `to_hospital`, `at_hospital`,
  /// `to_home`); anything else counts as home.
  static PersonState named(String? name) => switch (name) {
    'to_hospital' => toHospital,
    'at_hospital' => atHospital,
    'to_home' => toHome,
    _ => home,
  };
}

/// A simulated person, as the last record the API read from the Kafka
/// stream left them: one row of `GET /api/people`.
class Person {
  const Person({
    required this.id,
    required this.city,
    required this.lat,
    required this.lon,
    required this.homeLat,
    required this.homeLon,
    required this.state,
    this.hospitalName,
    this.name,
    this.age,
    this.conditionName,
    this.conditionType,
  });

  factory Person.fromJson(Map<String, Object?> json) => Person(
    id: json['id'] as String,
    city: (json['city'] as String?) ?? '',
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    homeLat: (json['homeLat'] as num).toDouble(),
    homeLon: (json['homeLon'] as num).toDouble(),
    state: PersonState.named(json['state'] as String?),
    hospitalName: json['hospitalName'] as String?,
    name: _string(json['name']),
    age: _int(json['age']),
    conditionName: _string(json['conditionName']),
    conditionType: ConditionType.named(json['conditionType']),
  );

  /// The city's slug and a number: "reus-3".
  final String id;
  final String city;
  final double lat;
  final double lon;
  final double homeLat;
  final double homeLon;
  final PersonState state;

  /// The hospital they go to when a visit is due, the one closest to
  /// their home.
  final String? hospitalName;

  /// Who they are and what brings them to the hospital, from their
  /// profile; null when the record doesn't carry them (an older API).
  final String? name;
  final int? age;
  final String? conditionName;
  final ConditionType? conditionType;
}

/// Whether a condition passes (acute) or stays (chronic).
enum ConditionType {
  acute('acute'),
  chronic('chronic');

  const ConditionType(this.label);

  final String label;

  /// The API's name for it; null for anything else.
  static ConditionType? named(Object? name) => switch (name) {
    'acute' => acute,
    'chronic' => chronic,
    _ => null,
  };
}

/// Which visit of a course an admission is: the first with the complaint,
/// a follow-up, or the last.
enum VisitKind {
  first('First visit'),
  repeat('Return visit'),
  last('Last visit');

  const VisitKind(this.label);

  final String label;

  static VisitKind? named(Object? name) => switch (name) {
    'first' => first,
    'repeat' => repeat,
    'last' => last,
    _ => null,
  };
}

/// Lenient readers for the optional fields of a record: a field of the
/// wrong type reads as absent rather than failing the whole record.
String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;
int? _int(Object? value) => value is num ? value.toInt() : null;

/// What `GET /api/people` answers: whether the simulation runs (dev mode
/// only), its clock, and where everyone is.
class People {
  const People({required this.enabled, this.simTime, this.day, this.people = const []});

  factory People.fromJson(Map<String, Object?> json) => People(
    enabled: json['enabled'] == true,
    simTime: json['simTime'] as String?,
    day: (json['day'] as num?)?.toInt(),
    people: [
      for (final person in (json['people'] as List? ?? const []))
        ?_person(person),
    ],
  );

  /// One person of the answer, or null when it can't be read: one bad
  /// entry is left off the map rather than failing the whole answer.
  static Person? _person(Object? json) {
    if (json is! Map) return null;
    try {
      return Person.fromJson(json.cast());
    } on TypeError {
      return null;
    }
  }

  /// Off in prod, where nothing of the simulation shows.
  final bool enabled;

  /// The simulated clock, "HH:MM", and which day it is; null before the
  /// first record arrives.
  final String? simTime;
  final int? day;
  final List<Person> people;
}

/// One record read from the Kafka stream, where it sits in its topic: a
/// person's move, or their admission at a hospital with what they said on
/// arrival. One row of `GET /api/events`.
class StreamEvent {
  const StreamEvent({
    required this.id,
    required this.state,
    this.type = StreamEventType.move,
    this.city,
    this.hospitalName,
    this.simTime,
    this.day,
    this.partition,
    this.offset,
    this.name,
    this.age,
    this.sex,
    this.occupation,
    this.conditionCode,
    this.conditionName,
    this.conditionType,
    this.visit,
    this.visitNumber,
    this.complaint,
    this.hospitalId,
    this.eventId,
  });

  /// A move carries the person in `id`; an admission in `personId`. An
  /// admission's person is at the hospital, so its state says so.
  factory StreamEvent.fromJson(Map<String, Object?> json) {
    final type = StreamEventType.named(json['type']);
    final admission = type == StreamEventType.admission;
    return StreamEvent(
      id: (admission ? json['personId'] ?? json['id'] : json['id'] ?? json['personId']) as String,
      type: type,
      state: admission ? PersonState.atHospital : PersonState.named(json['state'] as String?),
      city: _string(json['city']),
      hospitalName: _string(json['hospitalName']),
      simTime: _string(json['simTime']),
      day: _int(json['day']),
      partition: _int(json['partition']),
      offset: _int(json['offset']),
      name: _string(json['name']),
      age: _int(json['age']),
      sex: _string(json['sex']),
      occupation: _string(json['occupation']),
      conditionCode: _string(json['conditionCode']),
      conditionName: _string(json['conditionName']),
      conditionType: ConditionType.named(json['conditionType']),
      visit: VisitKind.named(json['visit']),
      visitNumber: _int(json['visitNumber']),
      complaint: _string(json['complaint']),
      hospitalId: _int(json['hospitalId']),
      eventId: _string(json['eventId']),
    );
  }

  /// The person's id: the city's slug and a number, "reus-3".
  final String id;
  final StreamEventType type;
  final PersonState state;
  final String? city;
  final String? hospitalName;
  final String? simTime;
  final int? day;
  final int? partition;
  final int? offset;

  /// Who the person is; moves carry the name and age too.
  final String? name;
  final int? age;
  final String? sex;
  final String? occupation;

  /// The condition behind the visit; moves carry its name and type too.
  final String? conditionCode;
  final String? conditionName;
  final ConditionType? conditionType;

  /// An admission's own fields: which visit of the course, what the
  /// person said on arrival, the hospital's id and the event's id.
  final VisitKind? visit;
  final int? visitNumber;
  final String? complaint;
  final int? hospitalId;
  final String? eventId;

  bool get isAdmission => type == StreamEventType.admission;
}

/// What a record on the stream is: a move (`healthhub.people.moves`) or an
/// admission (`healthhub.admissions`).
enum StreamEventType {
  move('move'),
  admission('admission');

  const StreamEventType(this.apiName);

  /// The API's name for it, as in `?type=`.
  final String apiName;

  /// Anything but "admission" counts as a move: the records before
  /// admissions existed carried no type.
  static StreamEventType named(Object? name) => name == 'admission' ? admission : move;
}

/// The latest records on the stream, newest first, and the topics they
/// came from; off in prod.
class StreamEvents {
  const StreamEvents({required this.enabled, this.topics = const [], this.events = const []});

  factory StreamEvents.fromJson(Map<String, Object?> json) => StreamEvents(
    enabled: json['enabled'] == true,
    topics: [
      for (final topic in (json['topics'] as List? ?? [?json['topic']]))
        if (topic is String && topic.isNotEmpty) topic,
    ],
    events: [
      for (final event in (json['events'] as List? ?? const []))
        if (event is Map && (event['id'] is String || event['personId'] is String))
          StreamEvent.fromJson(event.cast()),
    ],
  );

  final bool enabled;
  final List<String> topics;
  final List<StreamEvent> events;
}

/// The API, as the app sees it.
abstract class HealthHubApi {
  Future<Health> health();
  Future<Greeting> hello();
  Future<AuthConfig> authConfig();
  Future<Me> me();

  /// What the datyx API makes of the same user: `GET /api/datyx/me`.
  Future<Me> datyxMe();

  /// How many data sources datyx keeps, through `GET /api/datyx/datasources`.
  Future<int> datyxDataSources();

  /// The care centers between the given degrees:
  /// `GET /api/care-centers?bbox=west,south,east,north`.
  Future<CareCenters> careCenters({
    required double west,
    required double south,
    required double east,
    required double north,
  });

  /// The simulated people and their homes: `GET /api/people`.
  Future<People> people({
    required double west,
    required double south,
    required double east,
    required double north,
  });

  /// The latest records on the stream: `GET /api/events?limit=&type=`,
  /// only moves or only admissions with [type].
  Future<StreamEvents> events({int limit = 20, StreamEventType? type});
}

/// Thrown when the API answers an error, with its message.
class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'HTTP $status: $message';
}

/// Gives the bearer token for a call, or null for none.
typedef TokenProvider = Future<String?> Function();

/// The API over HTTP at [baseUrl]: `API_BASE_URL` (a dart-define) unless
/// given; empty means the app's own origin, where the web server proxies
/// /api/ to the API. [token] gives the signed-in user's ID token, sent as
/// `Authorization: Bearer`; after a 401, [refreshToken] is asked once for a
/// fresh one and the call is retried.
class HttpHealthHubApi implements HealthHubApi {
  HttpHealthHubApi({String? baseUrl, http.Client? client, this.token, this.refreshToken})
    : baseUrl = baseUrl ?? const String.fromEnvironment('API_BASE_URL'),
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final TokenProvider? token;
  final TokenProvider? refreshToken;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<Health> health() async => Health.fromJson(await _getMap('/api/health'));

  @override
  Future<Greeting> hello() async => Greeting.fromJson(await _getMap('/api/hello'));

  @override
  Future<AuthConfig> authConfig() async => AuthConfig.fromJson(await _getMap('/api/auth/config'));

  @override
  Future<Me> me() async => Me.fromJson(await _getMap('/api/me'));

  @override
  Future<Me> datyxMe() async => Me.fromJson(await _getMap('/api/datyx/me'));

  @override
  Future<int> datyxDataSources() async {
    final json = await _get('/api/datyx/datasources');
    return json is List ? json.length : 0;
  }

  @override
  Future<CareCenters> careCenters({
    required double west,
    required double south,
    required double east,
    required double north,
  }) async {
    return CareCenters.fromJson(await _getMap('/api/care-centers?bbox=${_bbox(west, south, east, north)}'));
  }

  @override
  Future<StreamEvents> events({int limit = 20, StreamEventType? type}) async => StreamEvents.fromJson(
    await _getMap('/api/events?limit=$limit${type == null ? '' : '&type=${type.apiName}'}'),
  );

  /// An area as the API's `bbox` takes it: west,south,east,north.
  static String _bbox(double west, double south, double east, double north) =>
      [west, south, east, north].map((d) => d.toStringAsFixed(5)).join(',');

  @override
  Future<People> people({
    required double west,
    required double south,
    required double east,
    required double north,
  }) async => People.fromJson(await _getMap('/api/people?bbox=${_bbox(west, south, east, north)}'));

  Future<Map<String, Object?>> _getMap(String path) async {
    final json = await _get(path);
    if (json is! Map<String, Object?>) throw const ApiException(200, 'unexpected answer');
    return json;
  }

  Future<Object?> _get(String path) async {
    var bearer = await token?.call();
    var retried = false;
    while (true) {
      final response = await _client
          .get(_uri(path), headers: {
            if (bearer != null && bearer.isNotEmpty) 'authorization': 'Bearer $bearer',
          })
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401 && bearer != null && !retried && refreshToken != null) {
        retried = true;
        final fresh = await refreshToken!.call();
        if (fresh != null && fresh != bearer) {
          bearer = fresh;
          continue;
        }
      }
      final Object? json;
      try {
        json = jsonDecode(response.body);
      } on FormatException {
        throw ApiException(response.statusCode, 'not JSON: ${response.body}');
      }
      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          json is Map ? (json['error'] as String?) ?? 'HTTP ${response.statusCode}' : 'HTTP ${response.statusCode}',
        );
      }
      return json;
    }
  }
}
