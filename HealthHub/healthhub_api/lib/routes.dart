/// What the API answers, by method and path, apart from the HTTP plumbing in
/// bin/server.dart, so it can be tested without a server or a database.
library;

import 'dart:math';

import 'auth.dart';
import 'care_centers.dart' show simulatedCapacity;
import 'conditions.dart' show CareSetting;
import 'simulation.dart' show LatLon, Place, admissionsTopic, movesTopic;

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
/// [nearest]: for GET /api/care-centers/nearest, the care center nearest
/// the query's lat and lon the server read (its center null when there is
/// none; null itself when the database didn't answer, 503).
/// [dev]: whether the API runs in dev mode (HEALTHHUB_MODE=dev), where
/// the simulation runs and GET /api/people serves it.
/// [kafka]: whether Kafka's REST proxy answers; [simulation]: whether the
/// simulation runs; both reported by /api/health.
/// [paused]: whether the simulation is paused, reported by /api/health
/// and GET /api/events.
/// [control]: for POST /api/simulation/pause and /resume, pauses (true)
/// or resumes (false) the simulation and says whether it is paused now;
/// called only for a signed-in user (once authentication is on) and while
/// the simulation runs in dev mode (else 401, 409).
/// [people]: the latest move of each simulated person, as read back from
/// Kafka by the server (lib/simulation.dart's PeopleFeed).
/// [events]: the latest moves and admissions the feed read, newest first.
/// [admissions]: what GET /api/admissions answers, the latest admissions
/// read from the database by the server, as many as [admissionsLimitOf]
/// the query says (null: the database didn't answer, 503).
/// [triageEnabled]: whether the API triages admissions with aityx
/// (lib/triage.dart), reported by /api/health and GET /api/triage.
/// [triage]: what GET /api/triage answers, the summary and the latest
/// triages read by the server, as many as [admissionsLimitOf] says
/// (null: the database didn't answer, 503).
/// [triageDetail]: for GET /api/triage/{eventId}, the triage the server
/// read (its row null when there is none, 404; null itself when the
/// database didn't answer, 503).
/// [person]: for GET /api/people/{id}, what the server read of that
/// person in the database (null: it didn't answer, 503), with [people]
/// for where they are now.
/// [prediction]: for GET /api/people/{id}/prediction, datyx's answer to
/// the inference the server asked for with the user's token (null: datyx
/// didn't answer, 502).
/// [careCenter]: for GET /api/care-centers/{id}, what the server read of
/// that care center in the database (null: it didn't answer, 503), with
/// [people] for who is there now.
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
  NearestCenter? nearest,
  bool dev = false,
  bool kafka = false,
  bool simulation = false,
  bool paused = false,
  bool Function(bool pause)? control,
  List<Map<String, Object?>> people = const [],
  List<Map<String, Object?>>? admissions,
  bool triageEnabled = false,
  Map<String, Object?>? triage,
  TriageLookup? triageDetail,
  PersonLookup? person,
  Forwarded? prediction,
  CareCenterLookup? careCenter,
}) {
  if (method == 'OPTIONS') return const Answer(204);
  if (method == 'POST') {
    switch (path) {
      // Anyone signed in may pause or resume it: there is one simulation,
      // and everyone watching sees it stand still.
      case simulationPausePath || simulationResumePath:
        if (auth.enabled && identity == null) return _signIn;
        if (!dev || !simulation || control == null) {
          return const Answer(409, body: {'error': 'the simulation does not run'});
        }
        return Answer(200, body: {'paused': control(path == simulationPausePath)});
    }
  }
  if (method == 'GET') {
    switch (personPath(path)) {
      case (final id, false):
        if (person == null) {
          return const Answer(503, body: {'error': 'the database is not answering'});
        }
        final answer = personAnswer(dev, id, people, person);
        return answer == null ? const Answer(404, body: {'error': 'nobody with that id'}) : Answer(200, body: answer);
      case (_, true):
        if (auth.enabled && identity == null) return _signIn;
        if (prediction == null) {
          return const Answer(502, body: {'error': 'the datyx API is not answering'});
        }
        return predictionAnswer(prediction);
      case null:
    }
    // Open to everyone, like the map it is opened from.
    if (careCenterIdOf(path) != null) {
      if (careCenter == null) {
        return const Answer(503, body: {'error': 'the database is not answering'});
      }
      final answer = careCenterAnswer(dev, careCenter, people);
      return answer == null
          ? const Answer(404, body: {'error': 'no care center with that id'})
          : Answer(200, body: answer);
    }
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
          'paused': paused,
          'triage': triageEnabled,
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
      // Open to everyone, like the care centers. The point is the user's
      // location: used for the query only, never logged or kept.
      case '/api/care-centers/nearest':
        if (nearestPoint(query) == null) {
          return const Answer(400, body: {'error': 'lat and lon are degrees, -90 to 90 and -180 to 180'});
        }
        if (nearest == null) {
          return const Answer(503, body: {'error': 'the database is not answering'});
        }
        return Answer(200, body: {'center': nearest.center});
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
        return Answer(200, body: eventsAnswer(dev, events, limit: limit, type: type, paused: paused));
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
      // Open to everyone, like the admissions they triage.
      case '/api/triage':
        if (admissionsLimitOf(query) == null) {
          return const Answer(400, body: {'error': 'limit is a positive number'});
        }
        if (triage == null) {
          return const Answer(503, body: {'error': 'the database is not answering'});
        }
        return Answer(200, body: {'enabled': triageEnabled, ...triage});
      case _ when triageEventId(path) != null:
        if (triageDetail == null) {
          return const Answer(503, body: {'error': 'the database is not answering'});
        }
        final row = triageDetail.row;
        if (row == null) return const Answer(404, body: {'error': 'no triage for that admission'});
        return Answer(200, body: row);
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
    'hospitalId', 'hospitalName', 'careCenterKind', 'conditionName', 'conditionType',
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

/// What the server read of a person for GET /api/people/{id}: [history],
/// the database's (Db.personHistory: the run, the admissions, the days),
/// and [currentRun], the simulation's run (null when it doesn't run), so
/// the answer says whether this is the person moving now.
class PersonLookup {
  const PersonLookup(this.history, {this.currentRun});

  final Map<String, Object?> history;
  final String? currentRun;
}

/// The person id in /api/people/{id}, and whether the path asks for their
/// prediction (/api/people/{id}/prediction); null for any other path.
(String, bool)? personPath(String path) {
  const prefix = '/api/people/';
  if (!path.startsWith(prefix)) return null;
  var rest = path.substring(prefix.length);
  final prediction = rest.endsWith('/prediction');
  if (prediction) rest = rest.substring(0, rest.length - '/prediction'.length);
  final String id;
  try {
    id = Uri.decodeComponent(rest);
  } on ArgumentError {
    return null;
  } on FormatException {
    // Not UTF-8 once decoded.
    return null;
  }
  return id.isEmpty || id.contains('/') || id.length > 200 ? null : (id, prediction);
}

/// What GET /api/people/{id} answers: one person of one run, their facts
/// (from their latest move and admission: a move has no sex or
/// occupation), where they are now when it is the current run (their
/// latest move, in dev mode), their admissions with each one's triage,
/// their days of care, and those counted; null when nothing is known of
/// them (404).
Map<String, Object?>? personAnswer(
  bool dev,
  String id,
  List<Map<String, Object?>> moves,
  PersonLookup person,
) {
  final history = person.history;
  final run = history['run'] as String?;
  final admissions = [for (final a in history['admissions'] as List? ?? const []) a as Map<String, Object?>];
  final days = [for (final d in history['days'] as List? ?? const []) d as Map<String, Object?>];
  // The latest move is this run's person only when the run is the current one.
  final current = person.currentRun != null && (run == null || run == person.currentRun);
  Map<String, Object?>? move;
  if (dev && current) {
    for (final m in moves) {
      if (m['id'] == id) move = m;
    }
  }
  if (move == null && admissions.isEmpty) return null;
  final latest = admissions.isEmpty ? null : admissions.first;
  const nowFields = [
    'state', 'mode', 'lat', 'lon', 'homeLat', 'homeLon', 'hospitalId', 'hospitalName', 'careCenterKind',
    'conditionName', 'conditionType', 'simTime', 'day',
  ];
  return {
    'id': id,
    'run': run ?? (move == null ? null : person.currentRun),
    'current': current,
    'name': move?['name'] ?? latest?['name'],
    'age': move?['age'] ?? latest?['age'],
    'sex': latest?['sex'],
    'occupation': latest?['occupation'],
    'city': move?['city'] ?? latest?['city'],
    'now': move == null ? null : {for (final field in nowFields) field: move[field]},
    'summary': {
      'admissions': admissions.length,
      'acute': admissions.where((a) => a['conditionType'] == 'acute').length,
      'chronic': admissions.where((a) => a['conditionType'] == 'chronic').length,
      'triaged': admissions.where((a) => a['triage'] != null).length,
      'days': days.length,
      'stayHours': days.fold<num>(0, (sum, d) => sum + ((d['stayHours'] as num?) ?? 0)),
    },
    'admissions': admissions,
    'days': days,
  };
}

/// What the server read of a care center for GET /api/care-centers/{id}:
/// [history], the database's (Db.careCenterHistory: the center, its
/// admissions counted and the latest), and [currentRun], the simulation's
/// run (null when it doesn't run).
class CareCenterLookup {
  const CareCenterLookup(this.history, {this.currentRun});

  final Map<String, Object?> history;
  final String? currentRun;
}

/// The id in /api/care-centers/{id}, a positive number; null for any other
/// path.
int? careCenterIdOf(String path) {
  const prefix = '/api/care-centers/';
  if (!path.startsWith(prefix)) return null;
  final rest = path.substring(prefix.length);
  if (!RegExp(r'^[0-9]{1,9}$').hasMatch(rest)) return null;
  final id = int.parse(rest);
  return id > 0 ? id : null;
}

/// What GET /api/care-centers/{id} answers: the care center, the settings
/// the simulation sends people to it for (lib/simulation.dart's
/// Place.serves), its capacity in the simulation
/// (lib/care_centers.dart's simulatedCapacity), who is
/// there now and who is on the way (their latest [moves], in dev mode),
/// how many have it as their hospital, and its admissions: counted in the
/// current run and in all, and the latest; null when there is no such
/// care center (404).
Map<String, Object?>? careCenterAnswer(bool dev, CareCenterLookup lookup, List<Map<String, Object?>> moves) {
  final center = lookup.history['center'] as Map<String, Object?>?;
  if (center == null) return null;
  final id = center['id'];
  final capacity = simulatedCapacity(center['key'] as String? ?? '$id', center['kind'] as String? ?? '');
  final place = Place(
    id: id is int ? id : 0,
    name: center['name'] as String? ?? '',
    kind: center['kind'] as String? ?? '',
    city: center['city'] as String? ?? '',
    at: const LatLon(0, 0),
    subtype: center['subtype'] as String?,
  );
  const personFields = [
    'id', 'name', 'age', 'city', 'state', 'mode', 'lat', 'lon', 'conditionName', 'conditionType', 'simTime', 'day',
  ];
  Map<String, Object?> who(Map<String, Object?> move) => {for (final field in personFields) field: move[field]};
  final mine = dev ? moves.where((m) => m['hospitalId'] == id).toList() : const <Map<String, Object?>>[];
  final here = [for (final m in mine) if (m['state'] == 'at_hospital') who(m)];
  final coming = [for (final m in mine) if (m['state'] == 'to_hospital') who(m)];
  Map<String, Object?>? newest;
  if (dev) {
    for (final move in moves) {
      final turn = move['turn'];
      if (turn is num && (newest == null || turn > (newest['turn'] as num))) newest = move;
    }
  }
  return {
    for (final MapEntry(:key, :value) in center.entries)
      if (key != 'key') key: value,
    'serves': [for (final setting in CareSetting.values) if (place.serves(setting)) setting.json],
    'capacity': {'places': capacity.places, 'unit': capacity.unit, 'simulated': true},
    'now': {
      'enabled': dev,
      'run': dev ? lookup.currentRun : null,
      'simTime': newest?['simTime'],
      'day': newest?['day'],
      'inUse': here.length,
      'usage': here.length / capacity.places,
      'assigned': mine.length,
      'here': here,
      'onTheWay': coming,
    },
    'admissions': lookup.history['admissions'] ??
        const {'run': null, 'thisRun': 0, 'total': 0, 'latestOf': 'all', 'latest': []},
  };
}

/// What GET /api/people/{id}/prediction answers from datyx's inference
/// ([prediction], POST /api/datasources/{id}/inference for the person's
/// series of patient_days): the person's prediction and what the model
/// is (`predicted`, the Target summed over the horizon ahead, null with a
/// `note` when it can't say; `last`, the same over the horizon just
/// gone; `target`, `horizon`, `group`, `table`, the training run and when
/// it was trained); datyx's own status and error otherwise, as it said.
Answer predictionAnswer(Forwarded prediction) {
  final body = prediction.body;
  if (prediction.status != 200 || body is! Map) return Answer(prediction.status, body: body);
  final predictions = body['predictions'];
  final first = predictions is List && predictions.isNotEmpty && predictions.first is Map
      ? predictions.first as Map
      : const {};
  return Answer(200, body: {
    'predicted': first['predicted'],
    'last': first['last'],
    'note': first['note'],
    'series': first['series'],
    'target': body['target'],
    'horizon': body['horizon'],
    'group': body['group'],
    'table': body['table'],
    'trainingRunId': body['runId'],
    'trainedAt': body['trainedAt'],
    'sourceId': body['sourceId'],
    'millis': body['millis'],
  });
}

/// The paths that pause and resume the simulation (POST).
const simulationPausePath = '/api/simulation/pause';
const simulationResumePath = '/api/simulation/resume';

/// How many events GET /api/events answers unless asked, and at most.
const eventsLimit = 20;
const eventsMax = 100;

/// What GET /api/events answers: in dev mode, the latest [events] read
/// from the streams (newest first, only those of [type] when given, at
/// most [limit], never more than [eventsMax]), each with its type and
/// where it sits in its topic, and whether the simulation is [paused]; in
/// prod, nothing. "topic" is the moves' topic, as before admissions;
/// "topics" names both.
Map<String, Object?> eventsAnswer(
  bool dev,
  List<Map<String, Object?>> events, {
  int limit = eventsLimit,
  String? type,
  bool paused = false,
}) {
  const topics = [movesTopic, admissionsTopic];
  if (!dev) return const {'enabled': false, 'paused': false, 'topic': movesTopic, 'topics': topics, 'events': []};
  return {
    'enabled': true,
    'paused': paused,
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
  'hospitalId', 'hospitalName', 'careCenterKind', 'simTime', 'day', 'turn', 'lat', 'lon', 'partition', 'offset',
];

const _admissionEventFields = [
  'type', 'eventId', 'personId', 'name', 'age', 'sex', 'occupation', 'city', 'conditionCode',
  'conditionName', 'conditionType', 'visit', 'visitNumber', 'complaint', 'hospitalId',
  'hospitalName', 'careCenterKind', 'simTime', 'day', 'turn', 'partition', 'offset',
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

/// What the server read for GET /api/triage/{eventId}: the triage, or
/// null when the admission has none.
class TriageLookup {
  const TriageLookup(this.row);

  final Map<String, Object?>? row;
}

/// The event id in /api/triage/{eventId}, or null for any other path.
String? triageEventId(String path) {
  const prefix = '/api/triage/';
  if (!path.startsWith(prefix)) return null;
  final String id;
  try {
    id = Uri.decodeComponent(path.substring(prefix.length));
  } on ArgumentError {
    return null;
  }
  return id.isEmpty || id.contains('/') || id.length > 200 ? null : id;
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

/// The point GET /api/care-centers/nearest asks about: its lat and lon in
/// degrees, or null when they aren't.
({double lat, double lon})? nearestPoint(Map<String, String> query) {
  final lat = double.tryParse(query['lat']?.trim() ?? '');
  final lon = double.tryParse(query['lon']?.trim() ?? '');
  if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) return null;
  return (lat: lat, lon: lon);
}

/// What the server read for GET /api/care-centers/nearest: the nearest
/// care center with its distance in metres, or null when none has a
/// location.
class NearestCenter {
  const NearestCenter(this.center);

  final Map<String, Object?>? center;
}

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
