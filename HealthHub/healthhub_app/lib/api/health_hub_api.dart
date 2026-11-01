import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sim_clock.dart' show simEpoch;

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

  /// As in "going to the health station".
  String get noun => label.toLowerCase();

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

  /// What they are doing when the care center they go to or are at is a
  /// [kind]: "Going to the health station", "At the clinic"; the hospital
  /// when the record doesn't say, as before visits went elsewhere.
  String labelAt(CareCenterKind? kind) => switch (this) {
    toHospital => 'Going to the ${(kind ?? CareCenterKind.hospital).noun}',
    atHospital => 'At the ${(kind ?? CareCenterKind.hospital).noun}',
    _ => label,
  };

  /// The legend's words for it, of any kind of care center.
  String get legend => switch (this) {
    home => 'at home',
    toHospital => 'going for care',
    atHospital => 'in care',
    toHome => 'going home',
  };
}

/// The kind of care center a record names (`careCenterKind`); null when
/// it doesn't say.
CareCenterKind? _kindOf(Object? name) => name is String ? CareCenterKind.named(name) : null;

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
    this.careCenterKind,
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
    careCenterKind: _kindOf(json['careCenterKind']),
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

  /// The care center of the visit under way, else the general hospital
  /// closest to their home, and its kind.
  final String? hospitalName;
  final CareCenterKind? careCenterKind;

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
  const People({required this.enabled, this.simTime, this.day, this.paused, this.people = const []});

  factory People.fromJson(Map<String, Object?> json) => People(
    enabled: json['enabled'] == true,
    paused: json['paused'] is bool ? json['paused'] as bool : null,
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

  /// Whether the simulation is paused; null when the API doesn't say.
  final bool? paused;
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
    this.monitored = false,
    this.monitoredFor,
    this.city,
    this.hospitalName,
    this.careCenterKind,
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
      monitored: json['monitored'] == true,
      monitoredFor: _string(json['monitoredFor']),
      city: _string(json['city']),
      hospitalName: _string(json['hospitalName']),
      careCenterKind: _kindOf(json['careCenterKind']),
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

  /// Whether the person is monitored at home, the high-risk only, and why
  /// ("aged 84", "pregnant", a chronic condition): only their moves at
  /// home are events (the API leaves everyone else's out); moves carry it.
  final bool monitored;
  final String? monitoredFor;
  final String? city;
  final String? hospitalName;

  /// What kind of care center [hospitalName] is.
  final CareCenterKind? careCenterKind;
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

/// The latest records on the stream, newest first, the topics they came
/// from, and how many the API read in all and a second; off in prod.
class StreamEvents {
  const StreamEvents({
    required this.enabled,
    this.paused = false,
    this.topics = const [],
    this.events = const [],
    this.total,
    this.perSecond,
    this.peoplePerCity,
    this.now,
    this.alarms = const OccupancyAlarms(),
  });

  factory StreamEvents.fromJson(Map<String, Object?> json) => StreamEvents(
    enabled: json['enabled'] == true,
    paused: json['paused'] == true,
    peoplePerCity: _int(json['peoplePerCity']),
    now: SimNow.fromJson(json['now']),
    alarms: OccupancyAlarms.fromJson(json['alarms']),
    total: _int(json['total']),
    perSecond: json['perSecond'] is num ? (json['perSecond'] as num).toDouble() : null,
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

  /// Whether the simulation is paused: nobody moves, the clock stands.
  final bool paused;
  final List<String> topics;
  final List<StreamEvent> events;

  /// Every move and admission the API read since it started, those it
  /// leaves out of [events] too, and how many a second over the last
  /// minute, a moving average; null from an API that doesn't count.
  final int? total;
  final double? perSecond;

  /// The people each city of the simulation has now; null from an API
  /// that doesn't say.
  final int? peoplePerCity;

  /// The simulated day and time of the newest move, the simulation's
  /// clock; from the newest record when the API doesn't say.
  final SimNow? now;

  /// The care centers whose occupancy datyx expects over their capacity,
  /// and the latest alarms raised and cleared: [OccupancyAlarms].
  final OccupancyAlarms alarms;

  /// [now], or the time of the newest record read.
  SimNow? get clock {
    if (now != null) return now;
    SimNow? newest;
    for (final event in events) {
      final at = SimNow.at(event.day, event.simTime);
      if (at != null && (newest == null || at.minutes! > newest.minutes!)) newest = at;
    }
    return newest;
  }
}

/// A moment of the simulation: its day (from 1), the time "HH:MM", and
/// the date of that day, which the API may give (`YYYY-MM-DD`) and is
/// otherwise counted from day 1.
class SimNow {
  const SimNow({this.day, this.simTime, this.date});

  /// `{"day", "simTime", "date"}`, leniently; null when it holds no day.
  static SimNow? fromJson(Object? json) {
    if (json is! Map) return null;
    final date = _date(json['date']);
    final day = _int(json['day']) ?? (date == null ? null : date.difference(simEpoch).inDays + 1);
    if (day == null) return null;
    return SimNow(day: day, simTime: _string(json['simTime']) ?? _string(json['time']), date: date);
  }

  /// A record's [day] and [simTime], or null without a day.
  static SimNow? at(int? day, String? simTime) => day == null ? null : SimNow(day: day, simTime: simTime);

  /// A simulated hour as the API writes it, `YYYY-MM-DDTHH:MM`.
  static SimNow? ofHour(DateTime? hour) {
    if (hour == null) return null;
    final date = DateTime.utc(hour.year, hour.month, hour.day);
    String two(int n) => n.toString().padLeft(2, '0');
    return SimNow(
      day: date.difference(simEpoch).inDays + 1,
      simTime: '${two(hour.hour)}:${two(hour.minute)}',
      date: date,
    );
  }

  final int? day;
  final String? simTime;
  final DateTime? date;

  /// The date of [day]: as given, or counted from day 1.
  DateTime? get calendarDate => date ?? (day == null ? null : simEpoch.add(Duration(days: day! - 1)));

  /// The simulated minutes since day 0 at 00:00; null without a day.
  int? get minutes {
    if (day == null) return null;
    final parts = simTime?.split(':');
    final hours = parts?.length == 2 ? int.tryParse(parts![0]) ?? 0 : 0;
    final mins = parts?.length == 2 ? int.tryParse(parts![1]) ?? 0 : 0;
    return day! * 24 * 60 + hours * 60 + mins;
  }
}

DateTime? _date(Object? value) {
  if (value is! String || value.length < 10) return null;
  final parsed = DateTime.tryParse('${value.substring(0, 10)}T00:00:00Z');
  return parsed;
}

/// A simulated hour, `YYYY-MM-DDTHH:MM` (UTC, with or without the zone),
/// or `{"day", "simTime"}`; null when it is neither.
DateTime? _simHour(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value.endsWith('Z') || value.contains('+') ? value : '${value}Z');
  }
  final now = SimNow.fromJson(value);
  final minutes = now?.minutes;
  return minutes == null ? null : simEpoch.add(Duration(minutes: minutes - 24 * 60));
}

double? _double(Object? value) => value is num ? value.toDouble() : null;

/// How bad an occupancy alarm is: datyx's forecast mean over the capacity
/// ([expected]), or only its 90th percentile ([possible]).
enum AlarmLevel {
  expected,
  possible;

  static AlarmLevel? named(Object? name) => switch (name) {
    'expected' => expected,
    'possible' => possible,
    _ => null,
  };
}

/// What an alarm event says happened: an [alarm] raised (or escalated), a
/// level [downgraded], or the alarm [cleared].
enum AlarmKind {
  alarm,
  downgraded,
  cleared;

  static AlarmKind named(Object? name) => switch (name) {
    'downgraded' => downgraded,
    'cleared' => cleared,
    _ => alarm,
  };
}

/// One care center's occupancy alarm, now ([OccupancyAlarms.active]) or
/// as an event on `healthhub.alarms` ([OccupancyAlarms.recent]): datyx's
/// DeepAR forecast of its people in care against its capacity. The
/// earliest forecast hour over it ([overflowAt]), how many simulated hours
/// ahead ([leadHours]), the forecast mean and 90th percentile there, the
/// peak over the horizon, and when it was checked ([now]).
class OccupancyAlarm {
  const OccupancyAlarm({
    required this.careCenterId,
    required this.careCenterName,
    this.careCenterKind,
    this.id,
    this.kind = AlarmKind.alarm,
    this.level,
    this.run,
    this.overflowAt,
    this.leadHours,
    this.mean,
    this.p90,
    this.peakAt,
    this.peakMean,
    this.peakP90,
    this.capacity,
    this.unit,
    this.trainingRun,
    this.now,
    this.raisedAt,
    this.partition,
    this.offset,
    this.stale = false,
  });

  /// Leniently: the care center as `hospitalId`/`hospitalName` (as the
  /// API writes it), `careCenterId`/`careCenterName`, or nested in
  /// `careCenter`; null without a care center. An active alarm has no
  /// `kind` and reads as an [AlarmKind.alarm].
  static OccupancyAlarm? fromJson(Object? json) {
    if (json is! Map) return null;
    final center = json['careCenter'] is Map ? json['careCenter'] as Map : const {};
    final id = _int(json['careCenterId']) ?? _int(json['hospitalId']) ?? _int(center['id']);
    final name =
        _string(json['careCenterName']) ?? _string(json['hospitalName']) ?? _string(center['name']) ?? _string(json['name']);
    if (id == null && name == null) return null;
    final peak = json['peak'] is Map ? json['peak'] as Map : const {};
    // `kind` is the event's (alarm, downgraded, cleared), or else the care center's.
    final kind = json['kind'];
    final eventKind = AlarmKind.values.any((k) => k.name == kind);
    return OccupancyAlarm(
      careCenterId: id,
      careCenterName: name ?? 'Care center $id',
      careCenterKind: _kindOf(json['careCenterKind'] ?? center['kind'] ?? (eventKind ? null : kind)),
      id: _string(json['id']) ?? _string(json['alarmId']) ?? _string(json['eventId']),
      kind: AlarmKind.named(eventKind ? kind : json['event'] ?? json['type']),
      level: AlarmLevel.named(json['level']),
      run: _string(json['run']),
      overflowAt: _simHour(json['overflowAt']),
      leadHours: _double(json['leadHours']),
      mean: _double(json['mean']),
      p90: _double(json['p90']),
      peakAt: _simHour(peak['at']),
      peakMean: _double(peak['mean']),
      peakP90: _double(peak['p90']),
      capacity: _int(json['capacity']),
      unit: _string(json['unit']),
      trainingRun: _int(json['trainingRun']) ?? _int(json['trainingRunId']),
      now: SimNow.fromJson(json['now']) ?? SimNow.at(_int(json['day']), _string(json['simTime'])),
      raisedAt: json['raisedAt'] is String ? DateTime.tryParse(json['raisedAt'] as String) : null,
      partition: _int(json['partition']),
      offset: _int(json['offset']),
      stale: json['stale'] == true,
    );
  }

  final int? careCenterId;
  final String careCenterName;
  final CareCenterKind? careCenterKind;

  /// The event's id; an active alarm may have none.
  final String? id;
  final AlarmKind kind;

  /// The level now (null once cleared).
  final AlarmLevel? level;
  final String? run;

  /// The earliest simulated hour the forecast goes over the capacity at
  /// [level], and how many simulated hours after the series' end (the
  /// run's latest hour, where the forecast starts) it is.
  final DateTime? overflowAt;
  final double? leadHours;

  /// The forecast mean and 90th percentile at [overflowAt].
  final double? mean;
  final double? p90;

  /// The peak over the horizon: the hour with the highest mean for an
  /// expected alarm, the highest 90th percentile for a possible one, and
  /// the forecast there.
  final DateTime? peakAt;
  final double? peakMean;
  final double? peakP90;
  final int? capacity;

  /// "beds" (a hospital) or "places".
  final String? unit;

  /// datyx's training run that forecast it.
  final int? trainingRun;

  /// The simulated time of the check, and the real time it was raised.
  final SimNow? now;
  final DateTime? raisedAt;

  /// Where the event sits on `healthhub.alarms`, when the API says.
  final int? partition;
  final int? offset;

  /// Whether an active alarm may be out of date: the latest check had no
  /// forecast of it, or none had one for a while; [now] is when it was
  /// last read.
  final bool stale;

  bool get expected => level == AlarmLevel.expected;
}

/// The occupancy alarms as `GET /api/events` carries them (`alarms`), as
/// `GET /api/alarms` has them: the care centers with a level now, most
/// severe first then soonest over, and the latest events, newest first.
class OccupancyAlarms {
  const OccupancyAlarms({
    this.active = const [],
    this.recent = const [],
    this.reported = false,
    this.enabled = true,
    this.note,
    this.status,
    this.checkedAt,
    this.stale = false,
    this.signIn = false,
  });

  /// `{"enabled", "checkedAt", "status", "note", "stale", "active",
  /// "recent"}`; not [reported] when [json] isn't one.
  static OccupancyAlarms fromJson(Object? json) {
    if (json is! Map) return const OccupancyAlarms();
    List<OccupancyAlarm> all(Object? list) => [
      for (final alarm in (list is List ? list : const [])) ?OccupancyAlarm.fromJson(alarm),
    ];
    return OccupancyAlarms(
      active: [
        for (final alarm in all(json['active']))
          if (alarm.level != null) alarm,
      ],
      recent: all(json['recent']),
      reported: true,
      enabled: json['enabled'] != false,
      note: _string(json['note']),
      status: _int(json['status']),
      checkedAt: json['checkedAt'] is String ? DateTime.tryParse(json['checkedAt'] as String) : null,
      stale: json['stale'] == true,
      signIn: json['signIn'] == true,
    );
  }

  final List<OccupancyAlarm> active;
  final List<OccupancyAlarm> recent;

  /// Whether the answer said anything of alarms: an API without them
  /// doesn't.
  final bool reported;

  /// Off when the API checks no alarms (`HEALTHHUB_ALARM_EVERY_MS` 0).
  final bool enabled;

  /// Why the latest check got no forecast from datyx, in its words (no
  /// model trained yet...); null when it got one.
  final String? note;

  /// datyx's status at the latest check (502: it didn't answer), and the
  /// real time of the latest check that got a forecast.
  final int? status;
  final DateTime? checkedAt;

  /// Whether the [active] may be out of date: the latest check got no
  /// forecast, or none got one for a while.
  final bool stale;

  /// Whether the API keeps the alarms for a signed-in user (sign-in on,
  /// nobody signed in): [active] and [recent] are then empty.
  final bool signIn;

  bool get isEmpty => active.isEmpty && recent.isEmpty;
}


/// A triage level, most urgent first (the API's lib/triage.dart).
enum TriageLevel {
  red('Immediate', 0),
  orange('Very urgent', 10),
  yellow('Urgent', 60),
  green('Standard', 120),
  blue('Non-urgent', 240);

  const TriageLevel(this.label, this.minutes);

  final String label;

  /// The longest the patient should wait, as the decision sets it.
  final int minutes;

  static TriageLevel? parse(Object? name) {
    for (final level in values) {
      if (level.name == name) return level;
    }
    return null;
  }

  /// How many levels less urgent than [other] this is (negative: more).
  int below(TriageLevel other) => index - other.index;
}

/// The danger signs Jev gives a probability of, with how the app names them.
const triageSigns = {
  'life_threat': 'Threat to life',
  'breathing': 'Struggling to breathe',
  'cardiac': 'Heart pain or palpitations',
  'stroke': 'Signs of a stroke',
  'major_injury': 'Injury needing treatment',
  'serious_infection': 'Serious infection',
  'dehydration': 'Dehydration',
  'self_harm': 'Thoughts of self-harm',
};

/// The areas of the hospital, as the app names them.
const triageAreas = {
  'resuscitation': 'Resuscitation room',
  'emergency': 'Emergency department',
  'mental_health': 'Mental health team',
  'minor_care': 'Minor illness and injury',
  'outpatients': 'Outpatients clinic',
  'day_unit': 'Day unit',
};

/// The questions Jev answers with one of their options, as the app names them.
const triageChoiceNames = {
  'pain': 'Pain',
  'onset': 'Started',
  'visit_purpose': 'Visit',
  'body_system': 'About',
};

/// What the decision counts a danger sign present at, and in doubt at.
const triageEvidence = 0.7;
const triageDoubt = 0.35;

/// One admission's triage by aityx: who, what they said, and what aityx
/// read and decided. One row of `GET /api/triage`, or with [receipt] and
/// [rules], `GET /api/triage/{eventId}`.
class Triaged {
  const Triaged({
    required this.eventId,
    this.personId,
    this.name,
    this.age,
    this.complaint,
    this.conditionName,
    this.visit,
    this.visitNumber,
    this.hospitalId,
    this.hospitalName,
    this.day,
    this.simTime,
    this.level,
    this.waitMinutes,
    this.area,
    this.nurseCheck = false,
    this.levelRule,
    this.levelWhy,
    this.areaRule,
    this.areaWhy,
    this.signs = const {},
    this.choices = const {},
    this.reference,
    this.error,
    this.inputTokens,
    this.millis,
    this.receipt,
    this.rules = const {},
  });

  factory Triaged.fromJson(Map<String, Object?> json) {
    final signs = json['signs'];
    final choices = json['choices'];
    final rules = json['rules'];
    return Triaged(
      eventId: json['eventId'] as String,
      personId: _string(json['personId']),
      name: _string(json['name']),
      age: _int(json['age']),
      complaint: _string(json['complaint']),
      conditionName: _string(json['conditionName']),
      visit: VisitKind.named(json['visit']),
      visitNumber: _int(json['visitNumber']),
      hospitalId: _int(json['hospitalId']),
      hospitalName: _string(json['hospitalName']),
      day: _int(json['day']),
      simTime: _string(json['simTime']),
      level: TriageLevel.parse(json['level']),
      waitMinutes: _int(json['waitMinutes']),
      area: _string(json['area']),
      nurseCheck: json['nurseCheck'] == true,
      levelRule: _int(json['levelRule']),
      levelWhy: _string(json['levelWhy']),
      areaRule: _int(json['areaRule']),
      areaWhy: _string(json['areaWhy']),
      signs: {
        if (signs is Map)
          for (final MapEntry(:key, :value) in signs.entries)
            if (value is num) key as String: value.toDouble(),
      },
      choices: {
        if (choices is Map)
          for (final MapEntry(:key, :value) in choices.entries)
            if (value is Map && value['choice'] is String)
              key as String: (choice: value['choice'] as String, confidence: (value['confidence'] as num?)?.toDouble()),
      },
      reference: TriageLevel.parse(json['reference']),
      error: _string(json['error']),
      inputTokens: _int(json['inputTokens']),
      millis: _int(json['millis']),
      receipt: (json['receipt'] as Map?)?.cast<String, Object?>(),
      rules: {
        if (rules is Map)
          for (final MapEntry(:key, :value) in rules.entries)
            if (value is List) key as String: [for (final why in value) why as String?],
      },
    );
  }

  final String eventId;

  /// Who arrived: the simulated person's id.
  final String? personId;
  final String? name;
  final int? age;
  final String? complaint;
  final String? conditionName;
  final VisitKind? visit;
  final int? visitNumber;
  final int? hospitalId;
  final String? hospitalName;
  final int? day;
  final String? simTime;

  /// Null when the triage failed ([error]).
  final TriageLevel? level;
  final int? waitMinutes;
  final String? area;
  final bool nurseCheck;
  final int? levelRule;
  final String? levelWhy;
  final int? areaRule;
  final String? areaWhy;

  /// Jev's probability of each of [triageSigns].
  final Map<String, double> signs;

  /// Jev's option for each of [triageChoiceNames], and its confidence.
  final Map<String, ({String choice, double? confidence})> choices;

  /// The level a nurse applying the same policy gives what the patient
  /// said: the simulation knows it from the complaint's template.
  final TriageLevel? reference;
  final String? error;
  final int? inputTokens;
  final int? millis;

  /// aityx's receipt, in the detail only.
  final Map<String, Object?>? receipt;

  /// The `# why` of each rule of the level and area tables, in order, in
  /// the detail only.
  final Map<String, List<String?>> rules;
}

/// Every triage so far, counted: `GET /api/triage`'s summary.
class TriageSummary {
  const TriageSummary({
    this.total = 0,
    this.failed = 0,
    this.compared = 0,
    this.matched = 0,
    this.withinOne = 0,
    this.under = 0,
    this.over = 0,
    this.nurseChecks = 0,
    this.inputTokens = 0,
    this.medianMillis,
    this.levels = const {},
  });

  factory TriageSummary.fromJson(Map<String, Object?> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    final levels = json['levels'];
    return TriageSummary(
      total: n('total'),
      failed: n('failed'),
      compared: n('compared'),
      matched: n('matched'),
      withinOne: n('withinOne'),
      under: n('under'),
      over: n('over'),
      nurseChecks: n('nurseChecks'),
      inputTokens: n('inputTokens'),
      medianMillis: (json['medianMillis'] as num?)?.toInt(),
      levels: {
        if (levels is Map)
          for (final level in TriageLevel.values) level: (levels[level.name] as num?)?.toInt() ?? 0,
      },
    );
  }

  final int total;
  final int failed;

  /// How many could be set against a reference level, and of those, how
  /// many matched it, were within one level, or less or more urgent.
  final int compared;
  final int matched;
  final int withinOne;
  final int under;
  final int over;
  final int nurseChecks;
  final int inputTokens;
  final int? medianMillis;
  final Map<TriageLevel, int> levels;
}

/// `GET /api/triage`: whether the API triages admissions, the summary,
/// and the latest triages, newest first.
class Triages {
  const Triages({this.enabled = false, this.summary = const TriageSummary(), this.triaged = const []});

  factory Triages.fromJson(Map<String, Object?> json) => Triages(
    enabled: json['enabled'] == true,
    summary: TriageSummary.fromJson((json['summary'] as Map?)?.cast() ?? const {}),
    triaged: [
      for (final row in (json['triaged'] as List? ?? const []))
        if (row is Map && row['eventId'] is String) Triaged.fromJson(row.cast()),
    ],
  );

  final bool enabled;
  final TriageSummary summary;
  final List<Triaged> triaged;
}

/// The run an event id belongs to: its first part, eight hex digits
/// before the person's id (`df0837e4-reus-5-d141-t3369`); null when it has
/// none (the ids recorded before runs).
String? runOf(String? eventId) => _runPrefix.firstMatch(eventId ?? '')?.group(1);

final _runPrefix = RegExp(r'^([0-9a-f]{8})-');

/// One person of one run: `GET /api/people/{id}`. A person's id comes
/// back in every run, a new person each time.
class PersonDetail {
  const PersonDetail({
    required this.id,
    this.run,
    this.current = false,
    this.name,
    this.age,
    this.sex,
    this.occupation,
    this.city,
    this.now,
    this.summary = const PersonSummary(),
    this.admissions = const [],
    this.days = const [],
  });

  factory PersonDetail.fromJson(Map<String, Object?> json) => PersonDetail(
    id: json['id'] as String? ?? '',
    run: _string(json['run']),
    current: json['current'] == true,
    name: _string(json['name']),
    age: _int(json['age']),
    sex: _string(json['sex']),
    occupation: _string(json['occupation']),
    city: _string(json['city']),
    now: json['now'] is Map ? PersonNow.fromJson((json['now'] as Map).cast()) : null,
    summary: PersonSummary.fromJson((json['summary'] as Map?)?.cast() ?? const {}),
    admissions: [
      for (final a in json['admissions'] as List? ?? const [])
        if (a is Map && a['eventId'] is String) PersonAdmission.fromJson(a.cast()),
    ],
    days: [
      for (final d in json['days'] as List? ?? const [])
        if (d is Map) PersonDay.fromJson(d.cast()),
    ],
  );

  final String id;
  final String? run;

  /// Whether this is the run going on now, the person moving on the map.
  final bool current;
  final String? name;
  final int? age;
  final String? sex;
  final String? occupation;
  final String? city;

  /// Where they are and what they do now: the current run, in dev mode.
  final PersonNow? now;
  final PersonSummary summary;

  /// Newest first.
  final List<PersonAdmission> admissions;

  /// Their days of care, the latest first.
  final List<PersonDay> days;
}

/// What a person does now: their latest move.
class PersonNow {
  const PersonNow({
    this.state = PersonState.home,
    this.mode,
    this.hospitalId,
    this.hospitalName,
    this.careCenterKind,
    this.conditionName,
    this.conditionType,
    this.simTime,
    this.day,
  });

  factory PersonNow.fromJson(Map<String, Object?> json) => PersonNow(
    state: PersonState.named(json['state'] as String?),
    mode: _string(json['mode']),
    hospitalId: _int(json['hospitalId']),
    hospitalName: _string(json['hospitalName']),
    careCenterKind: _kindOf(json['careCenterKind']),
    conditionName: _string(json['conditionName']),
    conditionType: ConditionType.named(json['conditionType']),
    simTime: _string(json['simTime']),
    day: _int(json['day']),
  );

  final PersonState state;
  final String? mode;
  final int? hospitalId;
  final String? hospitalName;
  final CareCenterKind? careCenterKind;
  final String? conditionName;
  final ConditionType? conditionType;
  final String? simTime;
  final int? day;
}

/// A person's admissions and days, counted by the API.
class PersonSummary {
  const PersonSummary({
    this.admissions = 0,
    this.acute = 0,
    this.chronic = 0,
    this.triaged = 0,
    this.days = 0,
    this.stayHours = 0,
  });

  factory PersonSummary.fromJson(Map<String, Object?> json) => PersonSummary(
    admissions: _int(json['admissions']) ?? 0,
    acute: _int(json['acute']) ?? 0,
    chronic: _int(json['chronic']) ?? 0,
    triaged: _int(json['triaged']) ?? 0,
    days: _int(json['days']) ?? 0,
    stayHours: (json['stayHours'] as num?) ?? 0,
  );

  final int admissions;
  final int acute;
  final int chronic;
  final int triaged;
  final int days;

  /// The hours of care of all their days.
  final num stayHours;
}

/// One admission, with its triage when it has one: of a person, in their
/// view, or at a care center, in its view, where it says who.
class PersonAdmission {
  const PersonAdmission({
    required this.eventId,
    this.personId,
    this.name,
    this.age,
    this.conditionName,
    this.conditionType,
    this.visit,
    this.visitNumber,
    this.complaint,
    this.hospitalId,
    this.hospitalName,
    this.day,
    this.simTime,
    this.triaged = false,
    this.level,
    this.waitMinutes,
    this.area,
    this.nurseCheck = false,
    this.reference,
    this.error,
  });

  factory PersonAdmission.fromJson(Map<String, Object?> json) {
    final triage = json['triage'];
    final t = triage is Map ? triage.cast<String, Object?>() : const <String, Object?>{};
    return PersonAdmission(
      eventId: json['eventId'] as String,
      personId: _string(json['personId']),
      name: _string(json['name']),
      age: _int(json['age']),
      conditionName: _string(json['conditionName']),
      conditionType: ConditionType.named(json['conditionType']),
      visit: VisitKind.named(json['visit']),
      visitNumber: _int(json['visitNumber']),
      complaint: _string(json['complaint']),
      hospitalId: _int(json['hospitalId']),
      hospitalName: _string(json['hospitalName']),
      day: _int(json['day']),
      simTime: _string(json['simTime']),
      triaged: triage is Map,
      level: TriageLevel.parse(t['level']),
      waitMinutes: _int(t['waitMinutes']),
      area: _string(t['area']),
      nurseCheck: t['nurseCheck'] == true,
      reference: TriageLevel.parse(t['reference']),
      error: _string(t['error']),
    );
  }

  final String eventId;

  /// Who was admitted: their id, name and age.
  final String? personId;
  final String? name;
  final int? age;
  final String? conditionName;
  final ConditionType? conditionType;
  final VisitKind? visit;
  final int? visitNumber;
  final String? complaint;
  final int? hospitalId;
  final String? hospitalName;
  final int? day;
  final String? simTime;

  /// Whether aityx triaged it: [level] then, or the [error].
  final bool triaged;
  final TriageLevel? level;
  final int? waitMinutes;
  final String? area;
  final bool nurseCheck;
  final TriageLevel? reference;
  final String? error;
}

/// One day of a person's care: patient_days.
class PersonDay {
  const PersonDay({required this.day, this.visits = 0, this.acuteVisits = 0, this.chronicVisits = 0, this.stayHours = 0});

  factory PersonDay.fromJson(Map<String, Object?> json) => PersonDay(
    day: json['day'] as String? ?? '',
    visits: _int(json['visits']) ?? 0,
    acuteVisits: _int(json['acuteVisits']) ?? 0,
    chronicVisits: _int(json['chronicVisits']) ?? 0,
    stayHours: _int(json['stayHours']) ?? 0,
  );

  /// The date, 2026-05-21.
  final String day;
  final int visits;
  final int acuteVisits;
  final int chronicVisits;
  final int stayHours;
}

/// One care center: `GET /api/care-centers/{id}`. Where it is, what it
/// is, its capacity in the simulation, who is there and on the way now,
/// and its admissions.
class CareCenterDetail {
  const CareCenterDetail({
    required this.id,
    required this.name,
    required this.kind,
    this.subtype,
    this.address,
    this.postalCode,
    this.city,
    this.region,
    this.country,
    this.lat,
    this.lon,
    this.phone,
    this.website,
    this.ownership,
    this.source,
    this.serves = const [],
    this.capacity = 0,
    this.unit = 'places',
    this.now = const CareCenterNow(),
    this.admissions = const CareCenterAdmissions(),
  });

  factory CareCenterDetail.fromJson(Map<String, Object?> json) {
    final capacity = (json['capacity'] as Map?)?.cast<String, Object?>() ?? const {};
    return CareCenterDetail(
      id: _int(json['id']) ?? 0,
      name: _string(json['name']) ?? '',
      kind: CareCenterKind.named(json['kind'] as String?),
      subtype: _string(json['subtype']),
      address: _string(json['address']),
      postalCode: _string(json['postalCode']),
      city: _string(json['city']),
      region: _string(json['region']),
      country: _string(json['country']),
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      phone: _string(json['phone']),
      website: _string(json['website']),
      ownership: _string(json['ownership']),
      source: _string(json['source']),
      serves: [for (final s in json['serves'] as List? ?? const []) if (s is String) s],
      capacity: _int(capacity['places']) ?? 0,
      unit: _string(capacity['unit']) ?? 'places',
      now: CareCenterNow.fromJson((json['now'] as Map?)?.cast() ?? const {}),
      admissions: CareCenterAdmissions.fromJson((json['admissions'] as Map?)?.cast() ?? const {}),
    );
  }

  final int id;
  final String name;
  final CareCenterKind kind;

  /// The source's own type: "CAP", "UBS", "Hospital Geral"...
  final String? subtype;
  final String? address;
  final String? postalCode;
  final String? city;
  final String? region;
  final String? country;

  /// Null when the registry has no location for it.
  final double? lat;
  final double? lon;
  final String? phone;
  final String? website;

  /// public, private or unknown.
  final String? ownership;

  /// The registry it comes from.
  final String? source;

  /// What the simulation sends people to it for: `hospital`, `primary`,
  /// `urgent_care`, `mental_health`, `dialysis`; none for a kind of clinic
  /// it doesn't route to (dental, rehabilitation...).
  final List<String> serves;

  /// How many people it takes at once in the simulation, in [unit]s (beds
  /// for a hospital, places for the rest): sized to the simulation, not
  /// the building.
  final int capacity;
  final String unit;
  final CareCenterNow now;
  final CareCenterAdmissions admissions;
}

/// Who is at a care center now and who is on the way, in dev mode.
class CareCenterNow {
  const CareCenterNow({
    this.enabled = false,
    this.run,
    this.simTime,
    this.day,
    this.inUse = 0,
    this.usage = 0,
    this.assigned = 0,
    this.here = const [],
    this.onTheWay = const [],
  });

  factory CareCenterNow.fromJson(Map<String, Object?> json) {
    List<Person> people(Object? list) => [
      for (final p in list as List? ?? const [])
        if (p is Map && p['id'] is String) _personOf(p.cast()),
    ];
    return CareCenterNow(
      enabled: json['enabled'] == true,
      run: _string(json['run']),
      simTime: _string(json['simTime']),
      day: _int(json['day']),
      inUse: _int(json['inUse']) ?? 0,
      usage: (json['usage'] as num?)?.toDouble() ?? 0,
      assigned: _int(json['assigned']) ?? 0,
      here: people(json['here']),
      onTheWay: people(json['onTheWay']),
    );
  }

  /// A person of the answer, where they are; no home in it.
  static Person _personOf(Map<String, Object?> json) {
    final lat = (json['lat'] as num?)?.toDouble() ?? 0;
    final lon = (json['lon'] as num?)?.toDouble() ?? 0;
    return Person(
      id: json['id'] as String,
      city: _string(json['city']) ?? '',
      lat: lat,
      lon: lon,
      homeLat: lat,
      homeLon: lon,
      state: PersonState.named(json['state'] as String?),
      name: _string(json['name']),
      age: _int(json['age']),
      conditionName: _string(json['conditionName']),
      conditionType: ConditionType.named(json['conditionType']),
    );
  }

  /// Off in prod, where nobody moves.
  final bool enabled;
  final String? run;
  final String? simTime;
  final int? day;

  /// How many are there now, and that over the capacity.
  final int inUse;
  final double usage;

  /// How many people have it as their hospital, wherever they are now.
  final int assigned;
  final List<Person> here;
  final List<Person> onTheWay;
}

/// A care center's admissions: counted in the current run and in all, and
/// the latest, of the current run when it has any there ([latestOf] `run`).
class CareCenterAdmissions {
  const CareCenterAdmissions({
    this.run,
    this.thisRun = 0,
    this.thisRunAcute = 0,
    this.thisRunChronic = 0,
    this.total = 0,
    this.acute = 0,
    this.chronic = 0,
    this.latestOfRun = false,
    this.latest = const [],
  });

  factory CareCenterAdmissions.fromJson(Map<String, Object?> json) => CareCenterAdmissions(
    run: _string(json['run']),
    thisRun: _int(json['thisRun']) ?? 0,
    thisRunAcute: _int(json['thisRunAcute']) ?? 0,
    thisRunChronic: _int(json['thisRunChronic']) ?? 0,
    total: _int(json['total']) ?? 0,
    acute: _int(json['acute']) ?? 0,
    chronic: _int(json['chronic']) ?? 0,
    latestOfRun: json['latestOf'] == 'run',
    latest: [
      for (final a in json['latest'] as List? ?? const [])
        if (a is Map && a['eventId'] is String) PersonAdmission.fromJson(a.cast()),
    ],
  );

  final String? run;
  final int thisRun;
  final int thisRunAcute;
  final int thisRunChronic;
  final int total;
  final int acute;
  final int chronic;

  /// Whether [latest] are the current run's (else of any run).
  final bool latestOfRun;

  /// Newest first.
  final List<PersonAdmission> latest;
}

/// datyx's prediction for a person: `GET /api/people/{id}/prediction`,
/// the hours of care ([target]) summed over the [horizon] ahead
/// ([predicted]), and over the one just gone ([last]); [note] says why
/// there is no prediction when [predicted] is null.
class Prediction {
  const Prediction({
    this.predicted,
    this.last,
    this.note,
    this.target,
    this.horizon,
    this.group,
    this.table,
    this.trainingRunId,
    this.trainedAt,
    this.millis,
  });

  factory Prediction.fromJson(Map<String, Object?> json) => Prediction(
    predicted: json['predicted'] as num?,
    last: json['last'] as num?,
    note: _string(json['note']),
    target: _string(json['target']),
    horizon: _string(json['horizon']),
    group: _string(json['group']),
    table: _string(json['table']),
    trainingRunId: _int(json['trainingRunId']),
    trainedAt: DateTime.tryParse(json['trainedAt'] as String? ?? ''),
    millis: _int(json['millis']),
  );

  final num? predicted;
  final num? last;
  final String? note;
  final String? target;
  final String? horizon;
  final String? group;
  final String? table;
  final int? trainingRunId;
  final DateTime? trainedAt;
  final int? millis;
}

/// One hour of a care center's occupancy: when it starts (simulated time,
/// day 1 being 2026-01-01) and how many people were in care there at any
/// minute of it.
class HourOccupancy {
  const HourOccupancy({required this.hour, this.occupancy = 0});

  factory HourOccupancy.fromJson(Map<String, Object?> json) =>
      HourOccupancy(hour: _hour(json['hour']), occupancy: _int(json['occupancy']) ?? 0);

  final DateTime hour;
  final int occupancy;
}

/// A simulated hour as the API writes it, `YYYY-MM-DDTHH:MM`, read as UTC.
DateTime _hour(Object? value) => DateTime.parse('${value as String}Z');

/// What `GET /api/care-centers/{id}/occupancy` answers: the people in
/// care at a care center in each hour up to its run's end, oldest first;
/// no run and no hours when nobody has been admitted there.
class HourlyOccupancy {
  const HourlyOccupancy({required this.hospitalId, this.run, this.current = false, this.end, this.hours = const []});

  factory HourlyOccupancy.fromJson(Map<String, Object?> json) => HourlyOccupancy(
    hospitalId: _int(json['hospitalId']) ?? 0,
    run: _string(json['run']),
    current: json['current'] == true,
    end: json['end'] is String ? _hour(json['end']) : null,
    hours: [
      for (final hour in (json['hours'] as List? ?? const []))
        HourOccupancy.fromJson((hour as Map).cast()),
    ],
  );

  final int hospitalId;
  final String? run;

  /// Whether [run] is the simulation's run going on now.
  final bool current;

  /// The run's latest hour, where its series end.
  final DateTime? end;
  final List<HourOccupancy> hours;
}

/// One step of a forecast: the hour, the mean, and the 10th, 50th and
/// 90th percentiles of its sample paths.
class ForecastStep {
  const ForecastStep({required this.at, required this.mean, required this.p10, required this.p50, required this.p90});

  factory ForecastStep.fromJson(Map<String, Object?> json) => ForecastStep(
    at: _hour(json['at']),
    mean: (json['mean'] as num?)?.toDouble() ?? 0,
    p10: (json['p10'] as num?)?.toDouble() ?? 0,
    p50: (json['p50'] as num?)?.toDouble() ?? 0,
    p90: (json['p90'] as num?)?.toDouble() ?? 0,
  );

  final DateTime at;
  final double mean;
  final double p10;
  final double p50;
  final double p90;
}

/// What `GET /api/care-centers/{id}/occupancy/forecast` answers: datyx's
/// DeepAR forecast of a care center's people in care per hour from its
/// series' end, step by step ([steps] empty with a [note] when it can't
/// say), and which model said it.
class HourlyForecast {
  const HourlyForecast({this.steps = const [], this.prediction = const Prediction()});

  factory HourlyForecast.fromJson(Map<String, Object?> json) => HourlyForecast(
    steps: [
      for (final step in (json['forecast'] as List? ?? const []))
        ForecastStep.fromJson((step as Map).cast()),
    ],
    prediction: Prediction.fromJson(json),
  );

  final List<ForecastStep> steps;

  /// The forecast summed over the horizon (`predicted`), the hours just gone
  /// (`last`), why there is none (`note`), and the model.
  final Prediction prediction;
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

  /// The care center nearest the point, or null when none has a location:
  /// `GET /api/care-centers/nearest?lat=..&lon=..`.
  Future<CareCenter?> nearestCareCenter({required double lat, required double lon});

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

  /// How aityx triages the admissions: `GET /api/triage?limit=`.
  Future<Triages> triage({int limit = 20});

  /// One admission's triage with aityx's receipt: `GET /api/triage/{eventId}`.
  Future<Triaged> triageOf(String eventId);

  /// One person of [run] (the current one unless given): `GET /api/people/{id}?run=`.
  Future<PersonDetail> person(String id, {String? run});

  /// datyx's prediction of a person's hours of care over the next 30
  /// days: `GET /api/people/{id}/prediction?run=`.
  Future<Prediction> prediction(String id, {String? run});

  /// One care center, with who is there now: `GET /api/care-centers/{id}`.
  Future<CareCenterDetail> careCenter(int id);

  /// A care center's people in care per hour, the [hours] up to its run's
  /// end: `GET /api/care-centers/{id}/occupancy?run=&hours=`.
  Future<HourlyOccupancy> careCenterOccupancy(int id, {String? run, int? hours});

  /// datyx's forecast of them:
  /// `GET /api/care-centers/{id}/occupancy/forecast?run=`.
  Future<HourlyForecast> occupancyForecast(int id, {String? run});

  /// Pauses the simulation, or resumes it: `POST /api/simulation/pause`
  /// or `/resume`. Whether it is paused now.
  Future<bool> pauseSimulation(bool pause);

  /// Sets the people each city of the simulation has, and says how many it
  /// is now: `POST /api/simulation/people`.
  Future<int> setPeoplePerCity(int perCity);
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

  @override
  Future<Triages> triage({int limit = 20}) async => Triages.fromJson(await _getMap('/api/triage?limit=$limit'));

  @override
  Future<Triaged> triageOf(String eventId) async =>
      Triaged.fromJson(await _getMap('/api/triage/${Uri.encodeComponent(eventId)}'));

  @override
  Future<PersonDetail> person(String id, {String? run}) async =>
      PersonDetail.fromJson(await _getMap(_personPath(id, '', run)));

  @override
  Future<Prediction> prediction(String id, {String? run}) async =>
      Prediction.fromJson(await _getMap(_personPath(id, '/prediction', run)));

  @override
  Future<CareCenterDetail> careCenter(int id) async =>
      CareCenterDetail.fromJson(await _getMap('/api/care-centers/$id'));

  @override
  Future<HourlyOccupancy> careCenterOccupancy(int id, {String? run, int? hours}) async {
    final query = [
      if (run != null) 'run=${Uri.encodeQueryComponent(run)}',
      if (hours != null) 'hours=$hours',
    ].join('&');
    return HourlyOccupancy.fromJson(await _getMap('/api/care-centers/$id/occupancy${query.isEmpty ? '' : '?$query'}'));
  }

  @override
  Future<HourlyForecast> occupancyForecast(int id, {String? run}) async => HourlyForecast.fromJson(
    await _getMap('/api/care-centers/$id/occupancy/forecast${run == null ? '' : '?run=${Uri.encodeQueryComponent(run)}'}'),
  );

  static String _personPath(String id, String suffix, String? run) =>
      '/api/people/${Uri.encodeComponent(id)}$suffix${run == null ? '' : '?run=${Uri.encodeQueryComponent(run)}'}';

  @override
  Future<bool> pauseSimulation(bool pause) async =>
      (await _send('POST', '/api/simulation/${pause ? 'pause' : 'resume'}') as Map?)?['paused'] == true;

  @override
  Future<int> setPeoplePerCity(int perCity) async =>
      _int((await _send('POST', '/api/simulation/people', body: {'perCity': perCity}) as Map?)?['perCity']) ?? perCity;

  @override
  Future<CareCenter?> nearestCareCenter({required double lat, required double lon}) async {
    final json = await _getMap('/api/care-centers/nearest?lat=${lat.toStringAsFixed(6)}&lon=${lon.toStringAsFixed(6)}');
    return json['center'] is Map ? CareCenter.fromJson((json['center'] as Map).cast()) : null;
  }

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

  Future<Object?> _get(String path) => _send('GET', path);

  /// [method] [path] with the user's token, refreshed once on a 401: the
  /// JSON answer, or an [ApiException] with the API's error.
  Future<Object?> _send(String method, String path, {Object? body}) async {
    var bearer = await token?.call();
    var retried = false;
    while (true) {
      final headers = {
        if (bearer != null && bearer.isNotEmpty) 'authorization': 'Bearer $bearer',
        if (body != null) 'content-type': 'application/json',
      };
      final response = await (method == 'POST'
              ? _client.post(_uri(path), headers: headers, body: body == null ? null : jsonEncode(body))
              : _client.get(_uri(path), headers: headers))
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
