/// The dev-mode simulation: people who live in the cities HealthHub
/// covers, each with a profile (lib/people_profiles.dart), maybe a
/// chronic condition and, now and then, an acute episode
/// (lib/conditions.dart), who stay home until a visit one of them calls
/// for is due, travel to the general hospital nearest home on foot, by
/// city transport or by car, stay, and travel back. Every turn
/// each person's move goes to Kafka (healthhub.people.moves), and every
/// arrival at the hospital is an admission (healthhub.admissions) with
/// what the person says there. The map doesn't read this memory: the
/// API's consumer ([PeopleFeed]) reads the streams back, /api/people
/// answers from the moves, and the admissions are recorded in the
/// database, so what the app shows went through Kafka.
///
/// Each person is its own async loop, Dart's equivalent of a virtual
/// thread: one task per person, woken by its own timer every turn, not one
/// loop that moves everyone. The turns stay in step because each loop
/// derives its turn from the time since the simulation started.
///
/// The geometry, the clock, the visits and the events are pure functions,
/// tested without Kafka.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'conditions.dart';
import 'kafka_rest.dart';
import 'people_profiles.dart';

/// The topic every move goes to.
const movesTopic = 'healthhub.people.moves';

/// The topic every admission goes to.
const admissionsTopic = 'healthhub.admissions';

/// The simulated clock's start: 06:00 on day 1, before anyone leaves home.
const simStartMinutes = 6 * 60;

const minutesPerDay = 24 * 60;

/// A due visit starts on the hour, from 08:00 to 17:00.
const visitFirstHour = 8;
const visitLastHour = 17;

/// When the first visit of a person's chronic condition falls: within
/// the first days of the simulation, so the map gets going.
const chronicOnsetDays = 10;

/// The share of people with no chronic condition.
const noChronicShare = 0.4;

/// The days between a chronic condition's courses of visits, unless the
/// condition says otherwise (MedicalCondition.courseGapDays).
const chronicGapDays = (30, 120);

/// The mean days from the end of one acute episode (or the start) to the
/// next: the gaps are exponential, so episodes come as a Poisson process,
/// about one every three months per person.
const acuteMeanGapDays = 90;

/// How far from a care center a home may be, so it falls in the city.
const homeRadiusMeters = 1500.0;

/// What a person is doing.
enum PersonState {
  home('home'),
  toHospital('to_hospital'),
  atHospital('at_hospital'),
  toHome('to_home');

  const PersonState(this.json);

  final String json;
}

/// How a person gets to the hospital, by the straight-line distance from
/// home, at a door-to-door speed that includes waiting and walking to the
/// stop or the car: walking up to 2 km, city transport up to 15 km, the
/// car beyond.
enum TravelMode {
  walk('walk', 5, 2000),
  transit('transit', 20, 15000),
  car('car', 50, double.infinity);

  const TravelMode(this.json, this.kmPerHour, this.upToMeters);

  final String json;
  final double kmPerHour;
  final double upToMeters;
}

/// The mode for a trip of [meters].
TravelMode travelMode(double meters) => TravelMode.values.firstWhere((mode) => meters <= mode.upToMeters);

/// How far someone travelling by [mode] gets in a turn of
/// [minutesPerTurn] simulated minutes, in meters.
double stepMeters(TravelMode mode, int minutesPerTurn) => mode.kmPerHour * 1000 * minutesPerTurn / 60;

/// A point on the map, in degrees.
class LatLon {
  const LatLon(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is LatLon && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => '($lat, $lon)';
}

/// A care center the simulation places homes near, or sends people to.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.kind,
    required this.city,
    required this.at,
    this.subtype,
  });

  final int id;
  final String name;
  final String kind;
  final String city;
  final LatLon at;

  /// The source's own classification (`Hospitales Generales`, `HOSPITAL
  /// ESPECIALIZADO - PSIQUIATRIA`); null when it has none.
  final String? subtype;

  bool get isHospital => kind == 'hospital';

  /// Whether it is a hospital people with any condition can be taken to:
  /// a general or acute one, not one specialised in a kind of patient or
  /// care ([isSpecialised]).
  bool get isGeneralHospital => isHospital && !isSpecialised(subtype, name);
}

/// What marks a hospital specialised in its subtype, as the sources word
/// it (data/care_centers.jsonl): Brazil's CNES says ESPECIALIZADO
/// (psychiatry, maternity, paediatrics, oncology, cardiology...) and
/// Spain's catalogue names the specialised, the mental health and
/// addiction, and the medium and long stay hospitals; the US data marks
/// psychiatric ones, and the VA's, which serves veterans only.
final _specialisedSubtype = RegExp(
  r'especializad|especialitzat|specialty|specialized|psychiatr|psiquiatr|salud mental|saude mental|'
  r'toxicoman|larga estancia|long[- ]term|rehabilit|maternidad|pediatr|\bVA hospital',
  caseSensitive: false,
);

/// What marks one in its name, where the subtype says only "Hospital" (the
/// US) or "general" for what is a children's or maternity hospital
/// (Brazil): children's, maternity, psychiatric, mental health,
/// rehabilitation, long stay (sociosanitari; Kindred and Select Specialty
/// run long-term acute care hospitals, Douglas Gardens long-term care, a
/// "hospital de transição" convalescence), geriatric, eye, cancer
/// (Sylvester is Miami's cancer center), infectious disease, dermatology
/// and rheumatology hospitals. Also those that only take one group of
/// people: military, navy, air force, police and fire brigade hospitals,
/// prison hospitals (SEAP) and the state servants' hospital. A "Hospital
/// e Maternidade" is a general hospital with a maternity ward.
final _specialisedName = RegExp(
  r"children'?s|infantil|crian[cç]a|pediatr|psiquiatr|psychiatr|behavioral|mental|rehabilit|reabilit|"
  r'sociosanitari|kindred|specialty|douglas gardens|transi[cç][aã]o|geriatr|convalesc|'
  r'eye inst|oftalm|olhos|cancer|oncol|sylvester|infectolog|dermatolog|reumatolog|'
  r'militar|naval|aeron[aá]utica|ex[eé]rcito|pol[ií]cia|bombeiros|cbmerj|\bseap\b|prisional|penitenci|'
  r'servidores do estado|(?<!hospital e )maternidade|maternity',
  caseSensitive: false,
);

/// Whether a hospital of [subtype] named [name] is specialised: in mental
/// health or addiction, long stay, rehabilitation, maternity, children,
/// or one organ or disease.
bool isSpecialised(String? subtype, String name) =>
    (subtype != null && _specialisedSubtype.hasMatch(subtype)) || _specialisedName.hasMatch(name);

const _earthRadiusMeters = 6371008.8;

double _radians(double degrees) => degrees * pi / 180;

/// The great-circle distance between [a] and [b], in meters.
double distanceMeters(LatLon a, LatLon b) {
  final dLat = _radians(b.lat - a.lat);
  final dLon = _radians(b.lon - a.lon);
  final h = pow(sin(dLat / 2), 2) + cos(_radians(a.lat)) * cos(_radians(b.lat)) * pow(sin(dLon / 2), 2);
  return 2 * _earthRadiusMeters * asin(min(1.0, sqrt(h)));
}

/// [meters] from [from] towards [to], along the straight line between
/// them, which is close enough to the great circle at a city's scale; [to]
/// itself when it is that close or closer, so a trip ends exactly there.
LatLon stepTowards(LatLon from, LatLon to, double meters) {
  final distance = distanceMeters(from, to);
  if (distance <= meters) return to;
  final fraction = meters / distance;
  return LatLon(
    from.lat + (to.lat - from.lat) * fraction,
    from.lon + (to.lon - from.lon) * fraction,
  );
}

/// The hospital nearest [home], among all of them: a town without one of
/// its own (Cornudella de Montsant) uses the nearest town's. A general
/// hospital ([Place.isGeneralHospital]) when there is one at all, since
/// a psychiatric or a maternity hospital doesn't take a pneumonia; any
/// hospital otherwise. Null when there are none.
Place? nearestHospital(LatLon home, Iterable<Place> places) {
  final general = places.any((p) => p.isGeneralHospital);
  Place? best;
  var bestDistance = double.infinity;
  for (final place in places) {
    if (general ? !place.isGeneralHospital : !place.isHospital) continue;
    final distance = distanceMeters(home, place.at);
    if (distance < bestDistance) {
      best = place;
      bestDistance = distance;
    }
  }
  return best;
}

/// A random point within [radiusMeters] of [center], uniform over the
/// disc.
LatLon randomPointNear(LatLon center, Random random, {double radiusMeters = homeRadiusMeters}) {
  final r = radiusMeters * sqrt(random.nextDouble());
  final angle = 2 * pi * random.nextDouble();
  final dLat = r * cos(angle) / _earthRadiusMeters * 180 / pi;
  final dLon = r * sin(angle) / (_earthRadiusMeters * cos(_radians(center.lat))) * 180 / pi;
  return LatLon(center.lat + dLat, center.lon + dLon);
}

/// The simulated clock at [turn]: minutes since midnight of day 1.
int simMinutes(int turn, int minutesPerTurn) => simStartMinutes + turn * minutesPerTurn;

/// The day at [minutes] on the clock, from 1.
int simDay(int minutes) => minutes ~/ minutesPerDay + 1;

/// The clock at midnight starting [day].
int dayStart(int day) => (day - 1) * minutesPerDay;

/// The time of day at [minutes] on the clock, as HH:MM.
String simTime(int minutes) {
  final ofDay = minutes % minutesPerDay;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(ofDay ~/ 60)}:${two(ofDay % 60)}';
}

/// A visit's start on [day], or the first day after it whose start is
/// later than [after]: a random hour from [visitFirstHour] to
/// [visitLastHour], so nobody turns up at the hospital at night for a
/// planned visit, and none is scheduled in the past.
int nextVisitStart(int day, int after, Random random) {
  for (var d = max(day, 1); ; d++) {
    final start = dayStart(d) + (visitFirstHour + random.nextInt(visitLastHour - visitFirstHour + 1)) * 60;
    if (start > after) return start;
  }
}

int _between((int, int) range, Random random) => range.$1 + random.nextInt(range.$2 - range.$1 + 1);

/// The minutes from the end of an acute episode (or the start) to the
/// next one: exponential, with a mean of [acuteMeanGapDays], and at least
/// a day.
int acuteGapMinutes(Random random) =>
    max(minutesPerDay, (-log(1 - random.nextDouble()) * acuteMeanGapDays * minutesPerDay).round());

/// The minutes a trip of [meters] by [mode] takes, rounded up.
int travelMinutes(double meters, TravelMode mode) => (meters / (mode.kmPerHour * 1000 / 60)).ceil();

/// [city] as an id prefix: lowercase ASCII, words joined by dashes.
String citySlug(String city) {
  const plain = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'ç': 'c', 'é': 'e', 'è': 'e',
    'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ó': 'o',
    'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  };
  final letters = city.toLowerCase().split('').map((c) => plain[c] ?? c).join();
  return letters.replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}

/// How the simulation runs, from the environment (scripts/env.sh and
/// compose.yaml set these):
///   HEALTHHUB_SIM_PEOPLE            people per city (default 10)
///   HEALTHHUB_SIM_TURN_MS           real milliseconds per turn (default 1000)
///   HEALTHHUB_SIM_MINUTES_PER_TURN  simulated minutes per turn (default
///                                   60: a real second is a simulated hour)
class SimulationSettings {
  const SimulationSettings({this.peoplePerCity = 10, this.turn = const Duration(seconds: 1), this.minutesPerTurn = 60});

  factory SimulationSettings.fromEnvironment([Map<String, String>? env]) {
    env ??= Platform.environment;
    int setting(String name, int fallback) {
      final value = int.tryParse(env![name] ?? '');
      return value == null || value < 1 ? fallback : value;
    }

    return SimulationSettings(
      peoplePerCity: setting('HEALTHHUB_SIM_PEOPLE', 10),
      turn: Duration(milliseconds: setting('HEALTHHUB_SIM_TURN_MS', 1000)),
      minutesPerTurn: setting('HEALTHHUB_SIM_MINUTES_PER_TURN', 60),
    );
  }

  final int peoplePerCity;
  final Duration turn;
  final int minutesPerTurn;

  @override
  String toString() => '$peoplePerCity people per city, a turn every ${turn.inMilliseconds} ms, '
      '$minutesPerTurn simulated minutes each';
}

/// One of a person's conditions and where its visits stand: a chronic
/// condition, kept for life and visited in courses, or an acute episode,
/// one course and gone.
class Course {
  Course(this.condition);

  final MedicalCondition condition;

  /// The visits made since the condition's first: a chronic condition's
  /// count across all its courses, which visit_number shows.
  int visits = 0;

  /// The visits made in the current course.
  int courseVisits = 0;

  /// The day of the condition's first visit ever, and of the latest.
  int? firstVisitDay;
  int? lastVisitDay;

  /// When the next visit is due, on the simulated clock (minutes); null
  /// while there is none to make.
  int? dueAt;

  /// The kind of the next visit: `first` only for the condition's very
  /// first visit, then `repeat`, and `last` for the last of each course,
  /// so a chronic condition's later courses never start over at `first`.
  VisitKind get nextKind => visits == 0
      ? VisitKind.first
      : courseVisits + 1 >= condition.visitCount
      ? VisitKind.last
      : VisitKind.repeat;

  /// Whether the next visit is an emergency, made at any hour.
  bool get nextIsUrgent => visits == 0 && condition.urgent;
}

/// One simulated person: who they are, where they live, the hospital they
/// go to and how, their conditions and their visits, and where they are.
/// A person has at most one chronic condition, for life, and, apart from
/// it, acute episodes that come and go: two processes whose visits
/// interleave, one at a time.
class Person {
  Person({
    required this.id,
    required this.city,
    required this.home,
    required this.hospital,
    required this.profile,
    required int minutesPerTurn,
  }) : mode = travelMode(distanceMeters(home, hospital.at)),
       at = home {
    step = stepMeters(mode, minutesPerTurn);
  }

  final String id;
  final String city;
  final LatLon home;
  final Place hospital;
  final Profile profile;

  /// How they travel between home and the hospital, and how far they get
  /// in a turn, in meters.
  final TravelMode mode;
  late final double step;

  LatLon at;
  PersonState state = PersonState.home;

  /// Their chronic condition, for life; null for those without one.
  Course? chronic;

  /// The acute episode they are in; null between episodes.
  Course? acute;

  /// When the next acute episode starts, on the simulated clock; null
  /// during one, or when there are no acute conditions.
  int? acuteOnsetAt;

  /// The course of the visit under way, from leaving home to coming back;
  /// null at home.
  Course? visiting;

  /// When and how far the trip under way started: its start, on the
  /// clock, and its length, so the arrival is timed to the minute.
  int tripStart = 0;
  double tripMeters = 0;

  /// When the current stay at the hospital ends.
  int? leaveAt;

  /// Admissions not yet published, kept for the next turn when Kafka
  /// fails.
  final unpublished = <Map<String, Object?>>[];

  /// The condition the moves show: the one of the visit under way, else
  /// the acute episode, else the chronic condition; null for someone
  /// healthy.
  MedicalCondition? get condition => visiting?.condition ?? acute?.condition ?? chronic?.condition;

  /// When the next visit of either kind is due; null when none is.
  int? get nextVisitAt {
    final dues = [?chronic?.dueAt, ?acute?.dueAt];
    return dues.isEmpty ? null : dues.reduce(min);
  }

  /// Gives them [condition] as their chronic condition, its first visit on
  /// [day]: at a daytime slot, or at a random time of that day when it is
  /// urgent.
  void giveChronic(MedicalCondition condition, int day, Random random) {
    final course = chronic = Course(condition);
    course.dueAt = condition.urgent
        ? max(simStartMinutes, dayStart(day) + random.nextInt(minutesPerDay))
        : nextVisitStart(day, simStartMinutes, random);
  }

  /// Starts an acute episode of [condition] at [onset]: its first visit
  /// then when it is urgent, else at the next daytime slot. A null
  /// [condition] (none fits) starts none, and waits for the next onset.
  void beginAcute(MedicalCondition? condition, int onset, Random random) {
    if (condition == null) {
      acuteOnsetAt = onset + acuteGapMinutes(random);
      return;
    }
    acuteOnsetAt = null;
    acute = Course(condition)
      ..dueAt = condition.urgent ? onset : nextVisitStart(simDay(onset), onset, random);
  }

  /// The record published for [turn]: key the id, value the person.
  Map<String, Object?> record(int turn, int minutesPerTurn) {
    final minutes = simMinutes(turn, minutesPerTurn);
    final shown = condition;
    return {
      'key': id,
      'value': {
        'id': id,
        'name': profile.name,
        'age': profile.age,
        'city': city,
        'lat': at.lat,
        'lon': at.lon,
        'homeLat': home.lat,
        'homeLon': home.lon,
        'hospitalId': hospital.id,
        'hospitalName': hospital.name,
        'state': state.json,
        'mode': mode.json,
        'conditionName': shown?.name,
        'conditionType': shown?.type,
        'simTime': simTime(minutes),
        'day': simDay(minutes),
        'turn': turn,
      },
    };
  }
}

/// One turn of [person] at [turn]: an acute episode starting when its
/// onset comes, the trip to the hospital when a visit of either condition
/// is due, the stay, and the trip home, at most [Person.step] meters a
/// turn. Returns the admission event when they arrive at the hospital
/// this turn ([admissionEvent]), else null. A new acute episode is drawn
/// from the acute ones among [conditions]; [run] is the simulation's run
/// id, part of every event id.
Map<String, Object?>? advance(
  Person person, {
  required int turn,
  required int minutesPerTurn,
  required Random random,
  required List<MedicalCondition> conditions,
  required String run,
}) {
  final now = simMinutes(turn, minutesPerTurn);
  // An episode starts wherever the person is: one that starts during a
  // visit waits for them to be home.
  final onset = person.acuteOnsetAt;
  if (onset != null && now >= onset) {
    final acute = [for (final c in conditions) if (!c.isChronic) c];
    person.beginAcute(
      pickCondition(acute, person.profile.age, random, sex: person.profile.sex),
      onset,
      random,
    );
  }
  if (person.state == PersonState.home) {
    final course = _due(person, now);
    if (course == null) return null;
    person
      ..visiting = course
      ..state = PersonState.toHospital
      ..tripStart = now
      ..tripMeters = distanceMeters(person.home, person.hospital.at);
  }
  if (person.state == PersonState.toHospital) {
    person.at = stepTowards(person.at, person.hospital.at, person.step);
    if (person.at != person.hospital.at) return null;
    person.state = PersonState.atHospital;
    // The minute they get there: the departure plus the trip, which falls
    // within this turn (or, after turns skipped by a slow publish, now).
    final arrival = max(now, person.tripStart + travelMinutes(person.tripMeters, person.mode));
    return _admit(person, turn, arrival, random, run);
  }
  if (person.state == PersonState.atHospital) {
    if (now < (person.leaveAt ?? now)) return null;
    person.state = PersonState.toHome;
  }
  // On the way home.
  person.at = stepTowards(person.at, person.home, person.step);
  if (person.at == person.home) {
    person.state = PersonState.home;
    _backHome(person, now, random);
  }
  return null;
}

/// The course whose visit is due at [now], the earliest when both are.
Course? _due(Person person, int now) {
  Course? due;
  for (final course in [?person.chronic, ?person.acute]) {
    final at = course.dueAt;
    if (at != null && at <= now && (due == null || at < due.dueAt!)) due = course;
  }
  return due;
}

/// The arrival of [person] at the hospital at [minutes] on the clock: counts
/// the visit, sets when the stay ends, and makes the admission.
Map<String, Object?> _admit(Person person, int turn, int minutes, Random random, String run) {
  final course = person.visiting!;
  final condition = course.condition;
  final kind = course.nextKind;
  final day = simDay(minutes);
  course
    ..visits += 1
    ..courseVisits += 1
    ..firstVisitDay ??= day
    ..lastVisitDay = day
    ..dueAt = null;
  person.leaveAt = minutes + condition.stayHoursOf(kind) * 60;
  final templates = condition.templates(kind);
  final complaint = renderComplaint(
    templates[random.nextInt(templates.length)],
    complaintValues(person, visitNumber: course.visits, daysSinceFirstVisit: day - course.firstVisitDay!),
  );
  return admissionEvent(
    person,
    condition: condition,
    run: run,
    turn: turn,
    minutes: minutes,
    kind: kind,
    visitNumber: course.visits,
    complaint: complaint,
  );
}

/// Home again at [now] after a visit: the next visit of its course, and
/// any visit that fell due while they were out moved to when they are
/// back, at once for an emergency, else the next daytime slot.
void _backHome(Person person, int now, Random random) {
  final course = person.visiting;
  person.visiting = null;
  if (course != null) _scheduleNext(person, course, now, random);
  for (final waiting in [?person.chronic, ?person.acute]) {
    final due = waiting.dueAt;
    if (due == null || due > now) continue;
    waiting.dueAt = waiting.nextIsUrgent ? now : nextVisitStart(simDay(now), now, random);
  }
}

/// After a visit of [course], home at [now]: the next visit of the course
/// [MedicalCondition.visitIntervalDays] after the last one; after a
/// course's last visit, a chronic condition's next course after its gap
/// ([MedicalCondition.courseGapDays], or [chronicGapDays]), or, for an
/// acute episode, its end, and the next episode's onset
/// [acuteGapMinutes] later.
void _scheduleNext(Person person, Course course, int now, Random random) {
  final condition = course.condition;
  final lastDay = course.lastVisitDay!;
  if (course.courseVisits < condition.visitCount) {
    course.dueAt = nextVisitStart(lastDay + condition.visitIntervalDays, now, random);
    return;
  }
  if (identical(course, person.chronic)) {
    final gap = condition.courseGapDays;
    final days = switch (gap) {
      null => _between(chronicGapDays, random),
      // Continuous: the next course goes on as if this one had not ended.
      0 => condition.visitIntervalDays,
      _ => gap,
    };
    course
      ..courseVisits = 0
      ..dueAt = nextVisitStart(lastDay + days, now, random);
  } else if (identical(course, person.acute)) {
    person
      ..acute = null
      ..acuteOnsetAt = now + acuteGapMinutes(random);
  }
}

/// What the placeholders of a complaint template stand for, for [person]
/// on visit [visitNumber] of their condition.
Map<String, Object> complaintValues(Person person, {required int visitNumber, required int daysSinceFirstVisit}) => {
  'name': person.profile.name,
  'first_name': person.profile.firstName,
  'age': person.profile.age,
  'sex': person.profile.sex,
  'occupation': person.profile.occupation,
  'city': person.city,
  'hospital': person.hospital.name,
  'visit_number': visitNumber,
  'days_since_first_visit': daysSinceFirstVisit,
};

/// The admission event of [person] arriving at the hospital at [minutes]
/// on the clock with [condition], in [turn] of the run [run]: the value
/// published to [admissionsTopic]. The run id makes the event id unique
/// across runs, whose people and turns repeat.
Map<String, Object?> admissionEvent(
  Person person, {
  required MedicalCondition condition,
  required String run,
  required int turn,
  required int minutes,
  required VisitKind kind,
  required int visitNumber,
  required String complaint,
}) {
  final day = simDay(minutes);
  return {
    'type': 'admission',
    'eventId': '$run-${person.id}-d$day-t$turn',
    'personId': person.id,
    'name': person.profile.name,
    'age': person.profile.age,
    'sex': person.profile.sex,
    'occupation': person.profile.occupation,
    'city': person.city,
    'conditionCode': condition.code,
    'conditionName': condition.name,
    'conditionType': condition.type,
    'visit': kind.json,
    'visitNumber': visitNumber,
    'complaint': complaint,
    'hospitalId': person.hospital.id,
    'hospitalName': person.hospital.name,
    'simTime': simTime(minutes),
    'day': day,
    'turn': turn,
  };
}

/// Starts [person]'s conditions: no chronic one for [noChronicShare] of
/// people, else one of the chronic [conditions] for their age and sex,
/// its first visit within the first [chronicOnsetDays] days; and the first
/// acute episode's onset [acuteGapMinutes] from the start.
void startConditions(Person person, List<MedicalCondition> conditions, Random random) {
  final chronic = [for (final c in conditions) if (c.isChronic) c];
  final acute = conditions.length > chronic.length;
  final none = random.nextDouble() < noChronicShare;
  final condition = none
      ? null
      : pickCondition(chronic, person.profile.age, random, sex: person.profile.sex);
  if (condition != null) person.giveChronic(condition, 1 + random.nextInt(chronicOnsetDays), random);
  person.acuteOnsetAt = acute ? simStartMinutes + acuteGapMinutes(random) : null;
}

/// The people of every city in [places] with a care center, [perCity]
/// each, living within [homeRadiusMeters] of a random care center of
/// their city and going to the hospital nearest home, each with a profile
/// of their city and their conditions from [conditions]
/// ([startConditions]).
List<Person> populate(
  List<Place> places,
  int perCity,
  int minutesPerTurn,
  Random random, {
  List<MedicalCondition> conditions = const [],
}) {
  final byCity = <String, List<Place>>{};
  for (final place in places) {
    byCity.putIfAbsent(place.city, () => []).add(place);
  }
  final people = <Person>[];
  for (final MapEntry(key: city, value: centers) in byCity.entries) {
    for (var n = 1; n <= perCity; n++) {
      final home = randomPointNear(centers[random.nextInt(centers.length)].at, random);
      final hospital = nearestHospital(home, places);
      if (hospital == null) return const [];
      final person = Person(
        id: '${citySlug(city)}-$n',
        city: city,
        home: home,
        hospital: hospital,
        profile: randomProfile(city, random),
        minutesPerTurn: minutesPerTurn,
      );
      startConditions(person, conditions, random);
      people.add(person);
    }
  }
  return people;
}

/// The running simulation: one loop per person, publishing every turn.
class Simulation {
  Simulation(this.people, this.settings, this.kafka, {this.conditions = const [], Random? random})
    : _random = random ?? Random();

  final List<Person> people;
  final SimulationSettings settings;
  final KafkaRest kafka;

  /// What a person's next condition is drawn from.
  final List<MedicalCondition> conditions;
  final Random _random;

  final _stopwatch = Stopwatch();
  bool _running = false;
  final _lastError = <String, DateTime>{};

  /// How many admissions a person keeps for a Kafka that stays down;
  /// beyond that the oldest are dropped, and logged.
  static const unpublishedLimit = 20;

  /// Which start the loops belong to: [stop] moves it on, so a loop still
  /// asleep when it wakes sees it is not the current one and ends, even
  /// after a new [start].
  int _generation = 0;

  /// The run id, random hex new at every [start], the start of every
  /// event id: the people's ids and the turns repeat from run to run (and
  /// API to API), and admissions.event_id is unique.
  String get run => _run;
  String _run = '';

  bool get running => _running;

  /// Starts every person's loop; they run until [stop].
  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    _run = _hex(Random.secure());
    _stopwatch
      ..reset()
      ..start();
    for (final person in people) {
      unawaited(_live(person, generation));
    }
    stdout.writeln('simulation: run $_run, ${people.length} people, ${conditions.length} conditions, $settings');
  }

  void stop() {
    _running = false;
    _generation++;
    _stopwatch.stop();
  }

  /// A person's loop: wait for the next turn, move, publish the move and
  /// any admission. Turn n starts n turns after the simulation did, so
  /// every loop agrees on the clock however long its own publishing took.
  Future<void> _live(Person person, int generation) async {
    final turnMs = settings.turn.inMilliseconds;
    final run = _run;
    var turn = 0;
    while (generation == _generation) {
      final admission = advance(
        person,
        turn: turn,
        minutesPerTurn: settings.minutesPerTurn,
        random: _random,
        conditions: conditions,
        run: run,
      );
      if (admission != null) {
        person.unpublished.add(admission);
        if (person.unpublished.length > unpublishedLimit) {
          final dropped = person.unpublished.removeAt(0);
          stderr.writeln('simulation: dropped admission ${dropped['eventId']}, Kafka has been down too long');
        }
      }
      try {
        await kafka.produce(movesTopic, [person.record(turn, settings.minutesPerTurn)]);
      } catch (error) {
        _logError(movesTopic, error);
      }
      if (person.unpublished.isNotEmpty && generation == _generation) {
        final batch = List.of(person.unpublished);
        try {
          await kafka.produce(admissionsTopic, [
            for (final event in batch) {'key': person.id, 'value': event},
          ]);
          person.unpublished.removeRange(0, batch.length);
        } catch (error) {
          _logError(admissionsTopic, error);
        }
      }
      // A slow publish skips the turns it overran, rather than falling
      // behind the others.
      turn = max(turn + 1, _stopwatch.elapsedMilliseconds ~/ turnMs);
      final wait = turn * turnMs - _stopwatch.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }
  }

  /// Logs a publishing failure at most once a minute per topic: when
  /// Kafka is down every person fails every turn.
  void _logError(String topic, Object error) {
    final now = DateTime.now();
    final last = _lastError[topic];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) return;
    _lastError[topic] = now;
    stderr.writeln('simulation: publishing to $topic: $error');
  }
}

/// The latest move of each person, read back from [movesTopic] (what GET
/// /api/people answers), and the admissions read from [admissionsTopic],
/// handed to [onAdmission] to be recorded. Two consumers, each with its
/// own poll loop: the moves in a consumer group new at every start, from
/// the newest records on, so the map never replays an old run; the
/// admissions in a stable group, [admissionsGroup], from the earliest
/// record its group has not committed, so none published while the API
/// was down or restarting is lost. Replayed admissions are harmless: the
/// database records each event id once.
class PeopleFeed {
  /// [people]: the ids of the simulation's people, the only ones kept.
  PeopleFeed(this.kafka, {required Iterable<String> people, this.onAdmission, Random? random})
    : _people = Set.of(people),
      group = 'healthhub-api-${_hex(random ?? Random.secure())}';

  final KafkaRest kafka;

  /// The moves' consumer group, new at every start.
  final String group;

  /// The admissions' consumer group, the same at every start, so its
  /// committed offsets carry over.
  static const admissionsGroup = 'healthhub-api-admissions';

  final Set<String> _people;

  /// Called with each valid admission of this simulation's people.
  final void Function(Map<String, Object?> admission)? onAdmission;

  final _latest = <String, Map<String, Object?>>{};

  /// The latest moves and admissions, apart, so the many moves never push
  /// the few admissions out; each with its arrival number, to merge them.
  final _moves = ListQueue<(int, Map<String, Object?>)>();
  final _admissions = ListQueue<(int, Map<String, Object?>)>();
  int _arrivals = 0;
  bool _running = false;
  Future<void>? _stopped;

  /// The event ids of the latest admissions, oldest first, so one read
  /// twice (a replay, a consumer made again after a failure) is kept and
  /// handed on once; bounded, as an admission is only ever replayed soon.
  final _seen = <String>{};
  final _seenOrder = ListQueue<String>();

  /// How many of the latest moves, and apart of the latest admissions,
  /// [recent] keeps.
  static const recentLimit = 100;

  /// How many admission event ids the feed remembers to drop duplicates.
  static const seenLimit = 1000;

  /// The latest record of each person, by id.
  List<Map<String, Object?>> get people => List.unmodifiable(_latest.values);

  /// The latest moves and admissions read from the streams, merged newest
  /// first by arrival, each with its "type" (move or admission), partition
  /// and offset: what GET /api/events answers.
  List<Map<String, Object?>> get recent {
    final merged = [..._moves, ..._admissions]..sort((a, b) => b.$1.compareTo(a.$1));
    return List.unmodifiable([for (final (_, event) in merged) event]);
  }

  static final _hhmm = RegExp(r'^\d\d:\d\d$');
  static final _states = {for (final state in PersonState.values) state.json};
  static final _visits = {for (final kind in VisitKind.values) kind.json};

  /// One record read from either topic, by its topic.
  void addRecord(KafkaRecord record) {
    if (record.topic == admissionsTopic) {
      addAdmission(record.value, partition: record.partition, offset: record.offset);
    } else {
      add(record.value, partition: record.partition, offset: record.offset);
    }
  }

  /// Keeps [value], a record's value, when it is a move of one of this
  /// simulation's people with every field the map uses, of the right type.
  /// Anything else on the topic (a test's record, another API's people,
  /// a malformed record) is skipped: one bad record must not break the
  /// whole answer the map reads, nor grow this memory without a bound.
  void add(Object? value, {int? partition, int? offset}) {
    if (value is! Map) return;
    final id = value['id'];
    final day = value['day'];
    final turn = value['turn'];
    final simTime = value['simTime'];
    final valid =
        id is String &&
        _people.contains(id) &&
        value['city'] is String &&
        value['hospitalName'] is String &&
        _states.contains(value['state']) &&
        simTime is String &&
        _hhmm.hasMatch(simTime) &&
        day is int &&
        day >= 1 &&
        turn is int &&
        turn >= 0 &&
        [value['lat'], value['lon'], value['homeLat'], value['homeLon']].every((v) => v is num);
    if (!valid) return;
    _latest[id] = Map<String, Object?>.from(value);
    _keep(_moves, {...value, 'type': 'move', 'partition': partition, 'offset': offset});
  }

  /// Keeps [value] when it is an admission of one of this simulation's
  /// people with every field of [admissionEvent], of the right type, and
  /// hands it to [onAdmission]; skips anything else, like [add], and an
  /// event id among the latest [seenLimit] already kept.
  void addAdmission(Object? value, {int? partition, int? offset}) {
    if (!isAdmission(value) || !_people.contains((value as Map)['personId'])) return;
    final eventId = value['eventId'] as String;
    if (!_seen.add(eventId)) return;
    _seenOrder.addLast(eventId);
    if (_seenOrder.length > seenLimit) _seen.remove(_seenOrder.removeFirst());
    final admission = Map<String, Object?>.from(value);
    _keep(_admissions, {...admission, 'partition': partition, 'offset': offset});
    onAdmission?.call(admission);
  }

  /// The largest a Postgres INT holds: every integer of an admission
  /// goes into one.
  static const int32Max = 2147483647;

  /// The days and visits an admission may carry: far beyond what a run
  /// reaches (a simulated day every 24 s is 1.3 million days a year), and
  /// within an INT.
  static const maxDay = 100000000;
  static const maxVisitNumber = 1000000;

  /// Whether [value] is an admission event with every field of
  /// [admissionEvent], of the right type and range: integers within what
  /// the database's INT columns hold, and no text with a NUL, which
  /// Postgres refuses, so a malformed record never reaches the recorder.
  static bool isAdmission(Object? value) {
    if (value is! Map) return false;
    bool text(String field) {
      final text = value[field];
      return text is String && text.isNotEmpty && !text.contains('\u0000');
    }

    bool within(String field, int least, int most) {
      final number = value[field];
      return number is int && number >= least && number <= most;
    }

    final simTime = value['simTime'];
    return value['type'] == 'admission' &&
        ['eventId', 'personId', 'name', 'occupation', 'city', 'conditionCode', 'conditionName', 'complaint', 'hospitalName']
            .every(text) &&
        within('age', minAdultAge, maxAdultAge) &&
        (value['sex'] == 'man' || value['sex'] == 'woman') &&
        conditionTypes.contains(value['conditionType']) &&
        _visits.contains(value['visit']) &&
        within('visitNumber', 1, maxVisitNumber) &&
        within('hospitalId', -int32Max - 1, int32Max) &&
        simTime is String &&
        _hhmm.hasMatch(simTime) &&
        within('day', 1, maxDay) &&
        within('turn', 0, int32Max);
  }

  void _keep(ListQueue<(int, Map<String, Object?>)> queue, Map<String, Object?> event) {
    queue.addLast((_arrivals++, event));
    if (queue.length > recentLimit) queue.removeFirst();
  }

  /// Reads both topics until [stop], each in its own loop
  /// ([_read]); completes once both have ended.
  Future<void> run() {
    if (_running) return _stopped!;
    _running = true;
    return _stopped = Future.wait([
      _read(group, movesTopic, 'latest'),
      _read(admissionsGroup, admissionsTopic, 'earliest'),
    ]).then((_) {});
  }

  /// Reads [topic] as [group] until [stop], from [offsetReset] when the
  /// group has no committed offset; on a failure, a new consumer after a
  /// pause, logged at the first failure and then every tenth. Its
  /// consumer is deleted on the proxy when it ends.
  Future<void> _read(String group, String topic, String offsetReset) async {
    var failures = 0;
    while (_running) {
      KafkaConsumer? consumer;
      try {
        consumer = await kafka.consumer(group, [topic], offsetReset: offsetReset);
        stdout.writeln('people feed: reading $topic as $group');
        failures = 0;
        while (_running) {
          for (final record in await consumer.poll()) {
            addRecord(record);
          }
        }
      } catch (error) {
        if (failures++ % 10 == 0) stderr.writeln('people feed: $topic: $error');
        await Future<void>.delayed(const Duration(seconds: 3));
      } finally {
        await consumer?.close();
      }
    }
  }

  /// Ends [run] after the current polls, and deletes both consumers on
  /// the proxy; completes once that is done.
  Future<void> stop() {
    _running = false;
    return _stopped ?? Future<void>.value();
  }
}

String _hex(Random random) =>
    List.generate(4, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
