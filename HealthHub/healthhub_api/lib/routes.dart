/// What the API answers, by method and path, apart from the HTTP plumbing in
/// bin/server.dart, so it can be tested without a server or a database.
library;

import 'dart:math';

import 'auth.dart';
import 'simulation.dart' show admissionsTopic, movesTopic;

/// An answer: a status, and a JSON body or a redirect.
class Answer {
  const Answer(this.status, {this.body, this.location});

  final int status;
  final Object? body;

  /// The Location of a redirect.
  final String? location;
}

/// An answer the datyx API gave to a call made on the user's behalf, with
/// the user's own token: passed on as it came.
class Forwarded {
  const Forwarded(this.status, this.body);

  final int status;
  final Object? body;
}

/// [db]: whether the database answers, reported by /api/health.
/// [aityx]: whether the API has an aityx key, reported by /api/health.
/// [greeting]: what GET /api/hello answers, read from the database by the
/// server (null when it can't be read: 503).
/// [auth]: how the API authenticates (GET /api/auth/config); with it on,
/// /api/me and /api/datyx/* want a signed-in user ([identity], from the
/// bearer token the server verified), a 401 without one.
/// [datyx]: the datyx API's answer for /api/datyx/*, which the server
/// fetched with the user's token (null: it didn't answer, 502).
/// [query]: the request's query parameters.
/// [careCenters]: what GET /api/care-centers answers, the care centers in
/// the query's bbox read by the server, up to [careCentersLimit] + 1 so
/// the answer can say whether there were more (null: the database didn't
/// answer, 503).
/// [dev]: whether the API runs in dev mode (HEALTHHUB_MODE=dev), where
/// the simulation runs and GET /api/people serves it.
/// [kafka]: whether Kafka's REST proxy answers; [simulation]: whether the
/// simulation runs; both reported by /api/health.
/// [people]: the latest move of each simulated person, as read back from
/// Kafka by the server (lib/simulation.dart's PeopleFeed).
/// [events]: the latest moves and admissions the feed read, newest first.
/// [admissions]: what GET /api/admissions answers, the latest admissions
/// read from the database by the server, as many as [admissionsLimitOf]
/// the query says (null: the database didn't answer, 503).
Answer route(
  String method,
  String path, {
  bool db = false,
  bool aityx = false,
  Map<String, Object?>? greeting,
  AuthSettings auth = const AuthSettings(issuer: 'https://accounts.google.com', clientId: ''),
  Identity? identity,
  Forwarded? datyx,
  Map<String, String> query = const {},
  List<Map<String, Object?>> events = const [],
  List<Map<String, Object?>>? careCenters,
  bool dev = false,
  bool kafka = false,
  bool simulation = false,
  List<Map<String, Object?>> people = const [],
  List<Map<String, Object?>>? admissions,
}) {
  if (method == 'OPTIONS') return const Answer(204);
  if (method == 'GET') {
    switch (path) {
      // The site root, which the web server proxies here
      // (scripts/flutter-web.sh), so a forwarded port's bare URL opens the
      // app. Relative, so it keeps the forwarded host and port.
      case '/':
        return const Answer(302, location: '/app/');
      case '/api/health':
        // Kafka and the simulation are reported, but don't make the API
        // unhealthy: only the map's people depend on them.
        return Answer(200, body: {
          'ok': true,
          'db': db,
          'aityx': aityx,
          'auth': auth.enabled,
          'kafka': kafka,
          'simulation': simulation,
        });
      case '/api/auth/config':
        return Answer(200, body: auth.toJson());
      case '/api/me':
        if (auth.enabled && identity == null) return _signIn;
        return Answer(200, body: {
          'authenticated': identity != null,
          if (identity != null) ...identity.toJson(),
        });
      case '/api/hello':
        if (greeting == null) {
          return const Answer(
            503,
            body: {'error': 'the database is not answering'},
          );
        }
        // Addressed to the signed-in user, when there is one.
        final name = identity?.name ?? identity?.email;
        return Answer(200, body: {
          ...greeting,
          if (name != null) 'message': 'Hello, $name',
          'user': identity?.toJson(),
        });
      // Open to everyone, like the map they're on: the index shows them too.
      case '/api/care-centers':
        if (query.containsKey('bbox') && Bbox.parse(query['bbox']) == null) {
          return const Answer(400, body: {'error': 'bbox is west,south,east,north in degrees'});
        }
        if (careCenters == null) {
          return const Answer(503, body: {'error': 'the database is not answering'});
        }
        return Answer(200, body: {
          'centers': careCenters.take(careCentersLimit).toList(),
          'truncated': careCenters.length > careCentersLimit,
        });
      // Open to everyone, like the care centers: the people are simulated.
      // The latest records on the stream, newest first, for home's events.
      case '/api/events':
        final limit = query.containsKey('limit') ? int.tryParse(query['limit']!) : eventsLimit;
        if (limit == null || limit < 1) {
          return const Answer(400, body: {'error': 'limit is a positive number'});
        }
        final type = query['type'];
        if (type != null && !eventTypes.contains(type)) {
          return const Answer(400, body: {'error': 'type is admission or move'});
        }
        return Answer(200, body: eventsAnswer(dev, events, limit: limit, type: type));
      // Open to everyone, like the events: the people are simulated. Read
      // from the database, so in prod too, whatever an earlier dev run
      // recorded.
      case '/api/admissions':
        if (admissionsLimitOf(query) == null) {
          return const Answer(400, body: {'error': 'limit is a positive number'});
        }
        if (admissions == null) {
          return const Answer(503, body: {'error': 'the database is not answering'});
        }
        return Answer(200, body: {'admissions': admissions});
      case '/api/people':
        final box = Bbox.parse(query['bbox']);
        if (query.containsKey('bbox') && box == null) {
          return const Answer(400, body: {'error': 'bbox is west,south,east,north in degrees'});
        }
        return Answer(200, body: peopleAnswer(dev, people, box: box));
      case '/api/datyx/me':
      case '/api/datyx/datasources':
        if (auth.enabled && identity == null) return _signIn;
        if (datyx == null) {
          return const Answer(502, body: {'error': 'the datyx API is not answering'});
        }
        return Answer(datyx.status, body: datyx.body);
    }
  }
  return const Answer(404, body: {'error': 'not found'});
}

const _signIn = Answer(401, body: {'error': 'sign in first'});

/// What GET /api/people answers: in dev mode, each person's latest
/// [moves] (the fields the map draws), only those in [box] when given
/// (where they are, or their home, so a home in view stays drawn while its
/// owner is out), and the simulated time and day of the newest move of
/// all; in prod, nothing.
Map<String, Object?> peopleAnswer(bool dev, List<Map<String, Object?>> moves, {Bbox? box}) {
  if (!dev) return const {'enabled': false, 'simTime': null, 'day': null, 'people': []};
  Map<String, Object?>? newest;
  for (final move in moves) {
    final turn = move['turn'];
    if (turn is num && (newest == null || turn > (newest['turn'] as num))) newest = move;
  }
  const fields = [
    'id', 'name', 'age', 'city', 'lat', 'lon', 'homeLat', 'homeLon', 'state', 'mode',
    'hospitalName', 'conditionName', 'conditionType',
  ];
  return {
    'enabled': true,
    'simTime': newest?['simTime'],
    'day': newest?['day'],
    'people': [
      for (final move in moves)
        if (box == null || box.holds(move['lat'], move['lon']) || box.holds(move['homeLat'], move['homeLon']))
          {for (final field in fields) field: move[field]},
    ],
  };
}

/// How many events GET /api/events answers unless asked, and at most.
const eventsLimit = 20;
const eventsMax = 100;

/// What GET /api/events answers: in dev mode, the latest [events] read
/// from the streams (newest first, only those of [type] when given, at
/// most [limit], never more than [eventsMax]), each with its type and
/// where it sits in its topic; in prod, nothing. "topic" is the moves'
/// topic, as before admissions; "topics" names both.
Map<String, Object?> eventsAnswer(
  bool dev,
  List<Map<String, Object?>> events, {
  int limit = eventsLimit,
  String? type,
}) {
  const topics = [movesTopic, admissionsTopic];
  if (!dev) return const {'enabled': false, 'topic': movesTopic, 'topics': topics, 'events': []};
  return {
    'enabled': true,
    'topic': movesTopic,
    'topics': topics,
    'events': [
      for (final event in events.where((e) => type == null || _typeOf(e) == type).take(limit.clamp(1, eventsMax)))
        if (_typeOf(event) == 'admission')
          // The person's id under "id" too, as a move has it.
          {for (final field in _admissionEventFields) field: event[field], 'id': event['personId']}
        else
          {for (final field in _moveEventFields) field: event[field], 'type': 'move'},
    ],
  };
}

/// The kinds of event, for GET /api/events?type=.
const eventTypes = {'admission', 'move'};

String _typeOf(Map<String, Object?> event) => event['type'] == 'admission' ? 'admission' : 'move';

const _moveEventFields = [
  'type', 'id', 'name', 'age', 'city', 'state', 'mode', 'conditionName', 'conditionType',
  'hospitalName', 'simTime', 'day', 'turn', 'lat', 'lon', 'partition', 'offset',
];

const _admissionEventFields = [
  'type', 'eventId', 'personId', 'name', 'age', 'sex', 'occupation', 'city', 'conditionCode',
  'conditionName', 'conditionType', 'visit', 'visitNumber', 'complaint', 'hospitalId',
  'hospitalName', 'simTime', 'day', 'turn', 'partition', 'offset',
];

/// How many admissions GET /api/admissions answers unless asked, and at
/// most.
const admissionsLimit = 20;
const admissionsMax = 200;

/// The number of admissions [query] asks for, at most [admissionsMax];
/// null when its limit isn't a positive number.
int? admissionsLimitOf(Map<String, String> query) {
  final limit = query.containsKey('limit') ? int.tryParse(query['limit']!) : admissionsLimit;
  return limit == null || limit < 1 ? null : min(limit, admissionsMax);
}

/// The datyx API's path behind one of ours (/api/datyx/me, /api/datyx/datasources), or null.
String? datyxPath(String path) => switch (path) {
  '/api/datyx/me' => '/api/me',
  '/api/datyx/datasources' => '/api/datasources',
  _ => null,
};

/// The most care centers one answer holds: hospitals first, then health
/// stations, then clinics, so a wide area shows the biggest first.
const careCentersLimit = 500;

/// An area of the map: GET /api/care-centers?bbox=west,south,east,north,
/// in degrees, west not east of east (no crossing the antimeridian).
class Bbox {
  const Bbox(this.west, this.south, this.east, this.north);

  /// The bbox in [raw], or null when it isn't one.
  static Bbox? parse(String? raw) {
    final parts = raw?.split(',').map((part) => double.tryParse(part.trim())).toList();
    if (parts == null || parts.length != 4 || parts.contains(null)) return null;
    final [west!, south!, east!, north!] = parts;
    final ok = -180 <= west && west <= east && east <= 180 && -90 <= south && south <= north && north <= 90;
    return ok ? Bbox(west, south, east, north) : null;
  }

  final double west;
  final double south;
  final double east;
  final double north;

  /// Whether the point [lat], [lon] is inside; false when either isn't a number.
  bool holds(Object? lat, Object? lon) =>
      lat is num && lon is num && south <= lat && lat <= north && west <= lon && lon <= east;
}
