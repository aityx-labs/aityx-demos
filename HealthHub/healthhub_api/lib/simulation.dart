/// The dev-mode simulation: people who live in the cities HealthHub
/// covers, each with a profile (lib/people_profiles.dart), maybe a
/// chronic condition and, now and then, an acute episode
/// (lib/conditions.dart), who stay home until a visit one of them calls
/// for is due, travel on foot, by city transport or by car to the care
/// center nearest home of the kind the visit needs (a health station, urgent
/// care, a mental health or dialysis clinic, a general hospital), stay, and
/// travel back. Every turn each person's move goes to Kafka
/// (healthhub.people.moves), and every arrival at a care center is an
/// admission (healthhub.admissions) with what the person says there. The map doesn't read this memory: the
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

/// The hour of day arrivals peak at, and how far they swing about their
/// mean: the hour of an arrival is drawn with weight 1 + amplitude ×
/// cos(2π (hour − peak) / 24) ([arrivalWeight]), a single daily harmonic,
/// highest at 13:00 and, with an amplitude of 1, nil at 01:00. The
/// amplitude is from 0 (flat) to 1, so no weight is negative.
const arrivalPeakHour = 13;
const arrivalAmplitude = 1.0;

/// When the first visit of a person's chronic condition falls: within
/// the first days of the simulation, so the map gets going.
const chronicOnsetDays = 10;

/// The share of people with no chronic condition.
const noChronicShare = 0.4;

/// The share of women of [pregnantAges] who are pregnant, for the whole
/// run, as ages don't advance: about the point prevalence.
const pregnantShare = 0.07;
const pregnantAges = (18, 44);

/// Who is monitored at home, the high-risk only, so most people aren't
/// (Person.monitoredFor): from this age, the pregnant, and those whose
/// chronic condition is one of [monitoredConditions].
const monitoredFromAge = 80;

/// The chronic conditions monitored at home: mental illness (depression,
/// dementia) and the failing heart and kidneys.
const monitoredConditions = {
  'major_depressive_disorder',
  'alzheimer_disease',
  'heart_failure',
  'end_stage_kidney_disease',
};

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

/// How a person gets to the care center of a visit, by the straight-line
/// distance from home, at a door-to-door speed that includes waiting and walking to the
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

  /// Whether it is primary care: a health station.
  bool get isPrimaryCare => kind == 'health_station';

  /// Whether it is a clinic of urgent care without beds ([_urgentCare]).
  bool get isUrgentCare => kind == 'clinic' && subtype != null && _urgentCare.hasMatch(subtype!);

  /// Whether it is an adult community mental health clinic ([_mentalHealth]).
  bool get isMentalHealth => kind == 'clinic' && subtype != null && _mentalHealth.hasMatch(subtype!);

  /// Whether it is a dialysis center.
  bool get isDialysis => kind == 'clinic' && subtype != null && _dialysis.hasMatch(subtype!);

  /// Whether a visit made in [setting] may be made here: a general
  /// hospital takes the urgent cases and dialysis where no clinic is
  /// nearer, a health station the mental health visits.
  bool serves(CareSetting setting) => switch (setting) {
    CareSetting.hospital => isGeneralHospital,
    CareSetting.primary => isPrimaryCare,
    CareSetting.urgentCare => isUrgentCare || isGeneralHospital,
    CareSetting.mentalHealth => isMentalHealth || isPrimaryCare,
    CareSetting.dialysis => isDialysis || isGeneralHospital,
  };
}

/// The clinics of urgent care without beds, as the sources' subtypes name
/// them (data/care_centers.jsonl): Catalonia's CUAP, Brazil's UPA, pronto
/// atendimento and general pronto socorro, Florida's urgent care and
/// walk-in clinics.
final _urgentCare = RegExp(
  r'\bCUAP\b|\bUPA\b|pronto atendimento|pronto socorro geral|urgent care|walk-in',
  caseSensitive: false,
);

/// The adult community mental health clinics: Catalonia's CSMA and
/// Barcelona's centres de salut mental, Brazil's CAPS I to III (not those
/// for children or for alcohol and drugs), Florida's community mental
/// health centers.
final _mentalHealth = RegExp(
  r'^CSMA$|centre de salut mental|community mental health|CAPS (I|II|III)$',
  caseSensitive: false,
);

/// The dialysis centers: Florida's end-stage renal disease centers.
/// Catalonia's and Brazil's registries list none apart, so their dialysis
/// is at the hospital.
final _dialysis = RegExp(r'end-stage renal disease', caseSensitive: false);

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

/// The care center nearest [home] that serves [setting] ([Place.serves]),
/// among all of them; the nearest hospital ([nearestHospital]) when none
/// does. Null when there are no hospitals either.
Place? nearestCareCenter(LatLon home, CareSetting setting, Iterable<Place> places) {
  if (setting == CareSetting.hospital) return nearestHospital(home, places);
  Place? best;
  var bestDistance = double.infinity;
  for (final place in places) {
    if (!place.serves(setting)) continue;
    final distance = distanceMeters(home, place.at);
    if (distance < bestDistance) {
      best = place;
      bestDistance = distance;
    }
  }
  return best ?? nearestHospital(home, places);
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

/// The simulated calendar's first moment: day 1 is 2026-01-01.
final simEpoch = DateTime.utc(2026, 1, 1);

/// The simulated moment [minutes] is, a date and time as ISO 8601 without
/// a zone, "2026-01-19T09:40": what the records carry as `at`, beside
/// their day and time.
String simAt(int minutes) => simEpoch.add(Duration(minutes: minutes)).toIso8601String().substring(0, 16);

/// The weight of [hour] (0 to 23) in the daily profile of arrivals:
/// 1 + [arrivalAmplitude] × cos(2π (hour − [arrivalPeakHour]) / 24). The
/// 24 weights add up to 24.
double arrivalWeight(int hour) => 1 + arrivalAmplitude * cos(2 * pi * (hour - arrivalPeakHour) / 24);

final _arrivalWeights = [for (var hour = 0; hour < 24; hour++) arrivalWeight(hour)];

/// An hour of the day (0 to 23) drawn from the daily profile of arrivals
/// ([arrivalWeight]): around midday mostly, at night seldom.
int arrivalHour(Random random) {
  var left = random.nextDouble() * 24;
  for (var hour = 0; hour < 23; hour++) {
    left -= _arrivalWeights[hour];
    if (left < 0) return hour;
  }
  return 23;
}

/// A visit's start: on the hour, the hour drawn once from the daily
/// profile ([arrivalHour]), on [day] or, when that hour of it is not later
/// than [after], the first day after on which it is, so planned visits
/// crowd around midday, seldom fall at night, and none is scheduled in
/// the past. One draw, kept to the next day: drawing again for it would
/// favour the hours later than [after], and put a same-day visit's peak
/// past 13:00. On the hour, like an appointment: the person leaves at the
/// turn it falls on and arrives within the hour, so the hours of the
/// arrivals follow the profile.
int nextVisitStart(int day, int after, Random random) {
  final hour = arrivalHour(random);
  for (var d = max(day, 1); ; d++) {
    final start = dayStart(d) + hour * 60;
    if (start > after) return start;
  }
}

int _between((int, int) range, Random random) => range.$1 + random.nextInt(range.$2 - range.$1 + 1);

/// The minutes from the end of an acute episode (or the start) to the
/// next one: exponential, with a mean of [acuteMeanGapDays], and at least
/// a day; divided by [rate], the person's onsets' pace under the care
/// centers' flow factors ([Person.acuteRate]), 1 normally.
int acuteGapMinutes(Random random, [double rate = 1]) {
  final gap = max(minutesPerDay, (-log(1 - random.nextDouble()) * acuteMeanGapDays * minutesPerDay).round());
  return rate == 1 ? gap : (gap / rate).round();
}

/// The bounds of a care center's flow factor ([Simulation.changeFlow]):
/// halved or doubled three times at most, 1 being the normal flow.
const flowMin = 0.125;
const flowMax = 8.0;

/// What a press of the care center view does to its flow factor: doubles
/// it, halves it, or sets it back to normal.
const flowActions = ['double', 'halve', 'reset'];

/// The flow factor after [action] on [factor], within [flowMin] and
/// [flowMax]; null for an action that isn't one of [flowActions].
double? flowAfter(double factor, String action) => switch (action) {
  'double' => min(factor * 2, flowMax),
  'halve' => max(factor / 2, flowMin),
  'reset' => 1.0,
  _ => null,
};

/// The flow factor at [place] in [flow] (care center id to factor): 1,
/// the normal flow, unless it was changed.
double flowAt(Map<int, double> flow, Place place) => flow[place.id] ?? 1;

/// [factor] as the log says it: ×2, ×1/4.
String flowLabel(double factor) => factor >= 1 ? '×${factor.round()}' : '×1/${(1 / factor).round()}';

/// A planned visit moved by the flow to about [minutes]: on the day of
/// [minutes], on the hour drawn from the daily profile ([arrivalHour]), or
/// the first day after on which that hour is later than [after] (now), as
/// [nextVisitStart] gives: the day moves with the flow, the hours keep to
/// the profile, and none is in the past.
int visitSlotFrom(int minutes, int after, Random random) => nextVisitStart(simDay(minutes), after, random);

/// When the next acute episode starts after [after]: on the day
/// [acuteGapMinutes] (at [rate], [Person.acuteRate]) from it gives, on the
/// hour, the hour from the daily profile ([arrivalHour]), so an emergency,
/// made at once, comes mostly around midday too; the next day at that
/// hour when it is not later than [after] (only at a rate above 1 can the
/// gap leave the day), so never before [after]. On the hour, as a planned
/// visit: with hour-long turns the person leaves at the turn of the onset
/// and arrives within its hour, not the next.
int acuteOnsetAfter(int after, Random random, [double rate = 1]) {
  final day = simDay(after + acuteGapMinutes(random, rate));
  final hour = arrivalHour(random);
  for (var d = day; ; d++) {
    final start = dayStart(d) + hour * 60;
    if (start > after) return start;
  }
}

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
///   HEALTHHUB_SIM_PEOPLE            people per city at start (default
///                                   80; the events can change it, up to
///                                   [maxPeoplePerCity])
///   HEALTHHUB_SIM_TURN_MS           real milliseconds per turn (default 2500)
///   HEALTHHUB_SIM_MINUTES_PER_TURN  simulated minutes per turn (default
///                                   15: a simulated hour every 10 real
///                                   seconds, so datyx's forecast, some 7 s
///                                   a call, comes within a simulated hour,
///                                   and its 24 hours ahead are 4 real
///                                   minutes of warning; specs/simulation.md)
class SimulationSettings {
  const SimulationSettings({
    this.peoplePerCity = 80,
    this.turn = const Duration(milliseconds: 2500),
    this.minutesPerTurn = 15,
  });

  factory SimulationSettings.fromEnvironment([Map<String, String>? env]) {
    env ??= Platform.environment;
    int setting(String name, int fallback) {
      final value = int.tryParse(env![name] ?? '');
      return value == null || value < 1 ? fallback : value;
    }

    return SimulationSettings(
      peoplePerCity: min(setting('HEALTHHUB_SIM_PEOPLE', 80), maxPeoplePerCity),
      turn: Duration(milliseconds: setting('HEALTHHUB_SIM_TURN_MS', 2500)),
      minutesPerTurn: setting('HEALTHHUB_SIM_MINUTES_PER_TURN', 15),
    );
  }

  final int peoplePerCity;
  final Duration turn;
  final int minutesPerTurn;

  @override
  String toString() => '$peoplePerCity people per city, a turn every ${turn.inMilliseconds} ms, '
      '$minutesPerTurn simulated minutes each';
}

/// The most people a city the simulation takes: each moves and publishes
/// every turn, through Kafka's REST proxy.
const maxPeoplePerCity = 200;

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

/// One simulated person: who they are, where they live, the care centers
/// they go to and how, their conditions and their visits, and where they
/// are.
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
    required this.minutesPerTurn,
    this.careCenters = const {},
    this.pregnant = false,
  }) : mode = travelMode(distanceMeters(home, hospital.at)),
       at = home {
    step = stepMeters(mode, minutesPerTurn);
  }

  final String id;
  final String city;
  final LatLon home;

  /// The general hospital nearest home: where a visit goes when no nearer
  /// care center serves it, and the one the moves name at home.
  final Place hospital;

  /// The care center nearest home for each setting ([nearestCareCenter]);
  /// a setting missing goes to [hospital].
  final Map<CareSetting, Place> careCenters;
  final Profile profile;
  final int minutesPerTurn;

  /// Whether she is pregnant, for the whole run ([pregnantShare]).
  final bool pregnant;

  /// How they travel to the care center of the trip under way (of the
  /// hospital, before the first), and how far they get in a turn, in
  /// meters: set again at every departure, by the trip's length.
  TravelMode mode;
  late double step;

  /// The care center of the visit under way, from leaving home to coming
  /// back; null at home.
  Place? destination;

  /// Where a visit made in [setting] goes.
  Place careCenterFor(CareSetting setting) => careCenters[setting] ?? hospital;

  /// Where the next visit of [course] goes, by its kind's setting.
  Place nextDestination(Course course) => careCenterFor(course.condition.settingOf(course.nextKind));

  /// Every care center their visits may go to: the hospital and those of
  /// each setting.
  Iterable<Place> get reachable => {hospital, ...careCenters.values};

  /// The pace of their acute onsets under [flow]: the highest flow factor
  /// among the care centers their visits may go to ([reachable]), 1 when
  /// none was changed. Onsets come at this rate, and an episode whose
  /// first visit goes to a care center of factor f is kept with
  /// probability f over it ([beginAcute]): Poisson thinning, so the
  /// episodes that start at each care center come at its factor times
  /// their normal rate.
  double acuteRate(Map<int, double> flow) =>
      flow.isEmpty ? 1 : reachable.map((place) => flowAt(flow, place)).reduce(max);

  /// The care center the moves name: the visit's, else the hospital.
  Place get shownCareCenter => destination ?? hospital;

  LatLon at;
  PersonState state = PersonState.home;

  /// Whether they left the simulation (fewer people a city): their loop
  /// ends at its next turn.
  bool gone = false;

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

  /// Why they are monitored at home, the high-risk only: "aged 84",
  /// "pregnant", or their chronic condition's name when it is one of
  /// [monitoredConditions]; null for everyone else, most people. Their
  /// moves say so, and the events mark them.
  String? get monitoredFor {
    if (profile.age >= monitoredFromAge) return 'aged ${profile.age}';
    if (pregnant) return 'pregnant';
    final condition = chronic?.condition;
    return condition != null && monitoredConditions.contains(condition.code) ? condition.name : null;
  }

  bool get monitored => monitoredFor != null;

  /// When the next visit of either kind is due; null when none is.
  int? get nextVisitAt {
    final dues = [?chronic?.dueAt, ?acute?.dueAt];
    return dues.isEmpty ? null : dues.reduce(min);
  }

  /// Gives them [condition] as their chronic condition, its first visit on
  /// [day]: at a visit's slot ([nextVisitStart]), or, when it is urgent, on
  /// the hour of that day drawn from the daily profile ([arrivalHour]);
  /// never before [after] (the run's start, or when they joined it).
  void giveChronic(MedicalCondition condition, int day, Random random, {int after = simStartMinutes}) {
    final course = chronic = Course(condition);
    course.dueAt = condition.urgent
        ? max(after, dayStart(day) + arrivalHour(random) * 60)
        : nextVisitStart(day, after, random);
  }

  /// Starts an acute episode of [condition] at [onset]: its first visit
  /// then when it is urgent, else at the next visit's slot. A null
  /// [condition] (none fits) starts none, and waits for the next onset.
  /// Under [flow], the episode is kept with probability the flow factor at
  /// its first visit's care center over [acuteRate] (always at the normal
  /// flow); one not kept starts none either.
  void beginAcute(MedicalCondition? condition, int onset, Random random, {Map<int, double> flow = const {}}) {
    final rate = acuteRate(flow);
    if (condition != null && flow.isNotEmpty) {
      final keep = flowAt(flow, careCenterFor(condition.settingOf(VisitKind.first))) / rate;
      if (keep < 1 && random.nextDouble() >= keep) condition = null;
    }
    if (condition == null) {
      acuteOnsetAt = acuteOnsetAfter(onset, random, rate);
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
        'hospitalId': shownCareCenter.id,
        'hospitalName': shownCareCenter.name,
        'careCenterKind': shownCareCenter.kind,
        'state': state.json,
        'mode': mode.json,
        'monitored': monitored,
        'monitoredFor': monitoredFor,
        'conditionName': shown?.name,
        'conditionType': shown?.type,
        'simTime': simTime(minutes),
        'day': simDay(minutes),
        'at': simAt(minutes),
        'turn': turn,
      },
    };
  }
}

/// One turn of [person] at [turn]: an acute episode starting when its
/// onset comes, the trip to the care center the visit needs
/// ([MedicalCondition.settingOf], [Person.careCenterFor]) when a visit of
/// either condition is due, the stay, and the trip home, at most
/// [Person.step] meters a turn. Returns the admission event when they
/// arrive this turn ([admissionEvent]), else null. A new acute episode is drawn
/// from the acute ones among [conditions]; [run] is the simulation's run
/// id, part of every event id. [flow] holds the care centers' flow factors
/// that are not 1 ([Simulation.changeFlow]): the visits headed to one come
/// that many times as often ([Person.beginAcute], [_scheduleNext]).
Map<String, Object?>? advance(
  Person person, {
  required int turn,
  required int minutesPerTurn,
  required Random random,
  required List<MedicalCondition> conditions,
  required String run,
  Map<int, double> flow = const {},
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
      flow: flow,
    );
  }
  if (person.state == PersonState.home) {
    final course = _due(person, now);
    if (course == null) return null;
    final destination = person.careCenterFor(course.condition.settingOf(course.nextKind));
    final meters = distanceMeters(person.home, destination.at);
    person
      ..visiting = course
      ..destination = destination
      ..mode = travelMode(meters)
      ..step = stepMeters(travelMode(meters), person.minutesPerTurn)
      ..state = PersonState.toHospital
      ..tripStart = now
      ..tripMeters = meters;
  }
  if (person.state == PersonState.toHospital) {
    final there = person.destination!.at;
    person.at = stepTowards(person.at, there, person.step);
    if (person.at != there) return null;
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
    _backHome(person, now, random, flow);
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
  final template = random.nextInt(templates.length);
  final complaint = renderComplaint(
    templates[template],
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
    template: template,
  );
}

/// Home again at [now] after a visit: the next visit of its course, and
/// any visit that fell due while they were out moved to when they are
/// back, at once for an emergency, else the next visit's slot.
void _backHome(Person person, int now, Random random, Map<int, double> flow) {
  final course = person.visiting;
  person
    ..visiting = null
    ..destination = null;
  if (course != null) _scheduleNext(person, course, now, random, flow);
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
/// ([acuteOnsetAfter]), at the person's rate under [flow]
/// ([Person.acuteRate]). A chronic visit's wait from [now] is divided by
/// the flow factor at its care center ([_flowed]).
void _scheduleNext(Person person, Course course, int now, Random random, Map<int, double> flow) {
  final condition = course.condition;
  final lastDay = course.lastVisitDay!;
  final chronic = identical(course, person.chronic);
  int flowed(int due) => chronic ? _flowed(person, course, now, due, flow, random) : due;
  if (course.courseVisits < condition.visitCount) {
    course.dueAt = flowed(nextVisitStart(lastDay + condition.visitIntervalDays, now, random));
    return;
  }
  if (chronic) {
    final gap = condition.courseGapDays;
    final days = switch (gap) {
      null => _between(chronicGapDays, random),
      // Continuous: the next course goes on as if this one had not ended.
      0 => condition.visitIntervalDays,
      _ => gap,
    };
    course.courseVisits = 0;
    course.dueAt = flowed(nextVisitStart(lastDay + days, now, random));
  } else if (identical(course, person.acute)) {
    person
      ..acute = null
      ..acuteOnsetAt = acuteOnsetAfter(now, random, person.acuteRate(flow));
  }
}

/// [due], the next visit of [person]'s [course] planned at [now], under
/// the flow factor f at its care center ([Person.nextDestination]): the
/// wait divided by f, at a visit's slot of the daily profile
/// ([visitSlotFrom]); [due] itself at the normal flow.
int _flowed(Person person, Course course, int now, int due, Map<int, double> flow, Random random) {
  final factor = flowAt(flow, person.nextDestination(course));
  return factor == 1 ? due : visitSlotFrom(now + ((due - now) / factor).round(), now, random);
}

/// Retimes [person] at [now] for the care centers' flow factors going from
/// [before] to [after], so a change shows at once rather than after the
/// visits already planned: their chronic condition's next visit, when its
/// care center's factor changed, is brought forward or put off, the time
/// left until it times the old factor over the new (at a visit's slot,
/// [visitSlotFrom], or for an urgent one at the hour from the daily
/// profile that day, as [Person.giveChronic] puts it; never in the past);
/// the next acute onset, when their [Person.acuteRate] changed, is drawn
/// again from now at the new rate ([acuteOnsetAfter]; the gaps are
/// exponential, so drawing again from now is the same process). The hours
/// keep to the daily profile ([arrivalHour]) either way. Says whether
/// anything moved.
bool retime(Person person, int now, Map<int, double> before, Map<int, double> after, Random random) {
  var moved = false;
  final chronic = person.chronic;
  final due = chronic?.dueAt;
  if (chronic != null && due != null && due > now) {
    final place = person.nextDestination(chronic);
    final was = flowAt(before, place);
    final factor = flowAt(after, place);
    if (was != factor) {
      final at = now + ((due - now) * was / factor).round();
      chronic.dueAt = chronic.nextIsUrgent
          ? max(now, dayStart(simDay(at)) + arrivalHour(random) * 60)
          : visitSlotFrom(at, now, random);
      moved = true;
    }
  }
  final onset = person.acuteOnsetAt;
  final rate = person.acuteRate(after);
  if (person.acute == null && onset != null && onset > now && person.acuteRate(before) != rate) {
    person.acuteOnsetAt = acuteOnsetAfter(now, random, rate);
    moved = true;
  }
  return moved;
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
  'hospital': person.shownCareCenter.name,
  'visit_number': visitNumber,
  'days_since_first_visit': daysSinceFirstVisit,
};

/// The admission event of [person] arriving at their care center at [minutes]
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
  int? template,
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
    // Which of the visit kind's templates it was said from (0 to 2), so
    // its reference triage level is known (lib/triage.dart).
    'template': ?template,
    // The care center, of any kind: the names stay those of when every
    // visit was to a hospital, as the table and the Flink job have them.
    'hospitalId': person.shownCareCenter.id,
    'hospitalName': person.shownCareCenter.name,
    'careCenterKind': person.shownCareCenter.kind,
    'simTime': simTime(minutes),
    'day': day,
    'at': simAt(minutes),
    'turn': turn,
  };
}

/// Starts [person]'s conditions: no chronic one for [noChronicShare] of
/// people, else one of the chronic [conditions] for their age and sex,
/// its first visit within the first [chronicOnsetDays] days; and the first
/// acute episode's onset ([acuteOnsetAfter] [from]).
void startConditions(
  Person person,
  List<MedicalCondition> conditions,
  Random random, {
  int from = simStartMinutes,
}) {
  final chronic = [for (final c in conditions) if (c.isChronic) c];
  final acute = conditions.length > chronic.length;
  final none = random.nextDouble() < noChronicShare;
  final condition = none
      ? null
      : pickCondition(chronic, person.profile.age, random, sex: person.profile.sex);
  if (condition != null) {
    person.giveChronic(condition, simDay(from) + random.nextInt(chronicOnsetDays), random, after: from);
  }
  person.acuteOnsetAt = acute ? acuteOnsetAfter(from, random) : null;
}

/// The seed the API draws its people with ([populate]): the same people,
/// homes, care centers and conditions at every start, so the admissions
/// history (lib/history.dart) covers exactly the care centers a live run
/// sends people to. What they do from there is drawn afresh every run.
const populationSeed = 20260101;

/// The people of every city in [places] with a care center, [perCity]
/// each, living within [homeRadiusMeters] of a random care center of
/// their city and going to the care centers nearest home, of the kind each
/// visit needs ([nearestCareCenter]), each with a profile
/// of their city and their conditions from [conditions]
/// ([startConditions]).
List<Person> populate(
  List<Place> places,
  int perCity,
  int minutesPerTurn,
  Random random, {
  List<MedicalCondition> conditions = const [],
}) {
  final people = <Person>[];
  for (final MapEntry(key: city, value: centers) in placesByCity(places).entries) {
    for (var n = 1; n <= perCity; n++) {
      final person = newPerson(city, n, centers, places, minutesPerTurn, random, conditions: conditions);
      if (person == null) return [];
      people.add(person);
    }
  }
  return people;
}

/// [places] by their city.
Map<String, List<Place>> placesByCity(List<Place> places) {
  final byCity = <String, List<Place>>{};
  for (final place in places) {
    byCity.putIfAbsent(place.city, () => []).add(place);
  }
  return byCity;
}

/// The [n]th person of [city] (id `<city>-<n>`), living within
/// [homeRadiusMeters] of a random one of its [centers] and going to the
/// care centers of [places] nearest home, with a profile of their city and
/// their conditions from [conditions], their visits from [from] on (the
/// run's start, or when they join it); null when no hospital has a place.
Person? newPerson(
  String city,
  int n,
  List<Place> centers,
  List<Place> places,
  int minutesPerTurn,
  Random random, {
  List<MedicalCondition> conditions = const [],
  int from = simStartMinutes,
}) {
  final home = randomPointNear(centers[random.nextInt(centers.length)].at, random);
  final hospital = nearestHospital(home, places);
  if (hospital == null) return null;
  final profile = randomProfile(city, random);
  final person = Person(
    id: '${citySlug(city)}-$n',
    city: city,
    home: home,
    hospital: hospital,
    careCenters: {
      for (final setting in CareSetting.values) setting: nearestCareCenter(home, setting, places) ?? hospital,
    },
    profile: profile,
    minutesPerTurn: minutesPerTurn,
    pregnant:
        profile.sex == 'woman' &&
        profile.age >= pregnantAges.$1 &&
        profile.age <= pregnantAges.$2 &&
        random.nextDouble() < pregnantShare,
  );
  startConditions(person, conditions, random, from: from);
  return person;
}

/// The running simulation: one loop per person, publishing every turn.
/// With the [places] it was populated from, the people a city can change
/// while it runs ([setPeoplePerCity]).
class Simulation {
  Simulation(
    List<Person> people,
    this.settings,
    this.kafka, {
    this.conditions = const [],
    this.places = const [],
    Random? random,
  }) : people = List.of(people),
       _random = random ?? Random() {
    for (final person in this.people) {
      final city = person.city;
      _count[city] = (_count[city] ?? 0) + 1;
      _next[city] = max(_next[city] ?? 1, _numberOf(person.id) + 1);
    }
    _perCity = _count.isEmpty ? settings.peoplePerCity : _count.values.reduce(max);
  }

  final List<Person> people;
  final SimulationSettings settings;
  final KafkaRest kafka;

  /// The care centers the people were made from, and new ones are.
  final List<Place> places;

  /// How many people each city has now, and the number the next one
  /// joining it takes: numbers are never given twice in a run, so a
  /// person's history is never another's.
  final _count = <String, int>{};
  final _next = <String, int>{};
  int _perCity = 0;

  /// The people a city now.
  int get peoplePerCity => _perCity;

  static int _numberOf(String id) => int.tryParse(id.substring(id.lastIndexOf('-') + 1)) ?? 0;

  /// Makes every city have [perCity] people (1 to [maxPeoplePerCity]):
  /// new people join at the turn now, their conditions starting from it,
  /// and their loops start when it runs; the last to join leave first,
  /// their loops ending at their next turn. Says who joined and who left,
  /// by id, for the feed.
  ({List<String> joined, List<String> left}) setPeoplePerCity(int perCity) {
    perCity = perCity.clamp(1, maxPeoplePerCity);
    final joined = <String>[];
    final left = <String>[];
    final turn = _turnNow();
    final from = simMinutes(turn, settings.minutesPerTurn);
    for (final MapEntry(key: city, value: centers) in placesByCity(places).entries) {
      while ((_count[city] ?? 0) < perCity) {
        final n = _next[city] ?? 1;
        final person = newPerson(city, n, centers, places, settings.minutesPerTurn, _random,
            conditions: conditions, from: from);
        if (person == null) break;
        // Their visits under the flow factors as they are now.
        if (_flow.isNotEmpty) retime(person, from, const {}, _flow, _random);
        _next[city] = n + 1;
        _count[city] = (_count[city] ?? 0) + 1;
        people.add(person);
        joined.add(person.id);
        if (_running) unawaited(_live(person, _generation, from: turn));
      }
    }
    for (final city in _count.keys) {
      final ofCity = [for (final p in people) if (p.city == city) p];
      for (final person in ofCity.reversed.take(max(0, ofCity.length - perCity))) {
        person.gone = true;
        people.remove(person);
        left.add(person.id);
      }
      _count[city] = min(_count[city]!, perCity);
    }
    _perCity = perCity;
    if (joined.isNotEmpty || left.isNotEmpty) {
      stdout.writeln('simulation: $perCity people per city now, ${joined.length} joined, ${left.length} left');
    }
    return (joined: joined, left: left);
  }

  /// What a person's next condition is drawn from.
  final List<MedicalCondition> conditions;
  final Random _random;

  /// The care centers' flow factors this run, by id, those that aren't 1
  /// ([changeFlow]).
  final _flow = <int, double>{};

  /// The flow factor at care center [id] this run: 1, the normal flow,
  /// unless [changeFlow] changed it.
  double flowOf(int id) => _flow[id] ?? 1;

  /// The care centers whose flow factor isn't 1, by id.
  Map<int, double> get flow => Map.unmodifiable(_flow);

  /// Doubles, halves or resets ([flowActions], [flowAfter]) the flow at
  /// care center [id], within [flowMin] and [flowMax], for the rest of the
  /// run: the visits headed there come that many times as often, the
  /// people whose visits go there retimed at once ([retime]); logged.
  /// Returns the factor now; null when the simulation sends nobody to a
  /// care center of that id (one without a location), or for an action
  /// that isn't one.
  double? changeFlow(int id, String action) {
    Place? place;
    for (final p in places) {
      if (p.id == id) {
        place = p;
        break;
      }
    }
    final was = flowOf(id);
    final factor = flowAfter(was, action);
    if (place == null || factor == null) return null;
    if (factor == was) return factor;
    final before = Map.of(_flow);
    if (factor == 1) {
      _flow.remove(id);
    } else {
      _flow[id] = factor;
    }
    final turn = _turnNow();
    final now = simMinutes(turn, settings.minutesPerTurn);
    var moved = 0;
    for (final person in people) {
      if (retime(person, now, before, _flow, _random)) moved++;
    }
    stdout.writeln(
      'simulation: flow at care center $id (${place.name}) ${flowLabel(factor)}, was ${flowLabel(was)}, '
      'run $_run at turn $turn, $moved people retimed',
    );
    return factor;
  }

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
  /// API to API), and admissions.event_id is unique. Never [historyRun].
  String get run => _run;
  String _run = '';

  /// Whether the simulation was started and not stopped since, paused or not.
  bool get running => _running;

  /// While paused, what every loop waits on before its next turn; null
  /// when not paused.
  Completer<void>? _resumed;

  /// Whether the simulation is paused ([pause]): no moves, no admissions,
  /// and the simulated clock stands still until [resume].
  bool get paused => _resumed != null;

  /// Starts every person's loop; they run until [stop].
  void start() {
    if (_running) return;
    _running = true;
    // A new run starts at the normal flow everywhere.
    _flow.clear();
    final generation = ++_generation;
    do {
      _run = _hex(Random.secure());
    } while (_run == historyRun);
    _stopwatch
      ..reset()
      ..start();
    for (final person in people) {
      unawaited(_live(person, generation));
    }
    stdout.writeln('simulation: run $_run, ${people.length} people, ${conditions.length} conditions, $settings');
  }

  /// Ends every loop, paused or asleep until its next turn: each wakes,
  /// sees the generation moved on, and ends.
  void stop() {
    _running = false;
    _generation++;
    _stopwatch.stop();
    final resumed = _resumed;
    _resumed = null;
    resumed?.complete();
  }

  /// Freezes the simulation: the clock stops, so the turns continue from
  /// where they were on [resume], with none skipped, and each loop waits
  /// before its next turn (a publish already under way finishes). Nothing
  /// when it doesn't run or is paused already.
  void pause() {
    if (!_running || paused) return;
    _resumed = Completer<void>();
    _stopwatch.stop();
    stdout.writeln('simulation: paused run $_run at turn ${_turnNow()}');
  }

  /// Lets a paused simulation go on from where it stood. Nothing when it
  /// isn't paused.
  void resume() {
    final resumed = _resumed;
    if (resumed == null) return;
    _resumed = null;
    _stopwatch.start();
    resumed.complete();
    stdout.writeln('simulation: resumed run $_run at turn ${_turnNow()}');
  }

  int _turnNow() => _stopwatch.elapsedMilliseconds ~/ settings.turn.inMilliseconds;

  /// A person's loop, from turn [from] (0, or the turn they joined at):
  /// wait for the next turn, move, publish the move and any admission.
  /// Turn n starts n turns after the simulation did, on its clock, which
  /// stands still while paused, so every loop agrees on the clock however
  /// long its own publishing took. It ends when the simulation stops or
  /// the person leaves it.
  Future<void> _live(Person person, int generation, {int from = 0}) async {
    final turnMs = settings.turn.inMilliseconds;
    final run = _run;
    var turn = from;
    while (true) {
      // Wait for the turn's start, and for a resume while paused: a pause
      // during the wait stops the clock, so the rest is waited after.
      while (generation == _generation) {
        if (_resumed case final resumed?) {
          await resumed.future;
          continue;
        }
        final wait = turn * turnMs - _stopwatch.elapsedMilliseconds;
        if (wait <= 0) break;
        await Future<void>.delayed(Duration(milliseconds: wait));
      }
      if (generation != _generation || person.gone) return;
      final admission = advance(
        person,
        turn: turn,
        minutesPerTurn: settings.minutesPerTurn,
        random: _random,
        conditions: conditions,
        run: run,
        flow: _flow,
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
      // behind the others; the paused time isn't on the clock, so a pause
      // skips none.
      turn = max(turn + 1, _stopwatch.elapsedMilliseconds ~/ turnMs);
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
/// How many events were read, all of them, and how many a second over
/// the last [window]: a moving average, from a count per second. Before a
/// [window] has gone by since the first, over the time since it.
class EventCounter {
  EventCounter({this.window = const Duration(minutes: 1), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _clock;

  /// Every event counted.
  int total = 0;

  DateTime? _first;

  /// The counts of the seconds within [window], oldest first: (the second
  /// since the epoch, how many).
  final _seconds = ListQueue<(int, int)>();

  void add() {
    final now = _clock();
    _first ??= now;
    total++;
    final second = now.millisecondsSinceEpoch ~/ 1000;
    if (_seconds.isNotEmpty && _seconds.last.$1 == second) {
      final (_, count) = _seconds.removeLast();
      _seconds.addLast((second, count + 1));
    } else {
      _seconds.addLast((second, 1));
    }
    _forget(second);
  }

  /// The events a second over the last [window]; 0 before the first.
  double get perSecond {
    final now = _clock();
    final first = _first;
    if (first == null) return 0;
    _forget(now.millisecondsSinceEpoch ~/ 1000);
    final seconds = (now.difference(first).inMilliseconds / 1000).clamp(1.0, window.inSeconds.toDouble());
    return _seconds.fold(0, (sum, s) => sum + s.$2) / seconds;
  }

  void _forget(int second) {
    while (_seconds.isNotEmpty && _seconds.first.$1 <= second - window.inSeconds) {
      _seconds.removeFirst();
    }
  }
}

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

  /// The latest moves and admissions, apart, so the moves never push the
  /// few admissions out; each with its arrival number, the order it was
  /// read in, which breaks the ties of the simulated time.
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

  /// Every move and admission read, those [recent] leaves out too, and how
  /// many a second over the last minute.
  final counter = EventCounter();

  /// The latest record of each person, by id.
  List<Map<String, Object?>> get people => List.unmodifiable(_latest.values);

  /// People who joined the simulation: their moves are kept from now on.
  void join(Iterable<String> ids) => _people.addAll(ids);

  /// People who left it: off the map at once, and a move of theirs still
  /// on its way is skipped.
  void leave(Iterable<String> ids) {
    for (final id in ids) {
      _people.remove(id);
      _latest.remove(id);
    }
  }

  /// The latest moves and admissions read from the streams as one stream,
  /// newest first by simulated time, the kinds among each other; at the
  /// same minute, the one read later first (the record's real order: its
  /// offset within a topic). Each with its "type" (move or admission),
  /// partition and offset: what GET /api/events answers.
  List<Map<String, Object?>> get recent {
    final merged = [
      for (final (read, event) in [..._moves, ..._admissions]) (simMinutesOf(event), read, event),
    ]..sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2));
    return List.unmodifiable([for (final (_, _, event) in merged) event]);
  }

  /// The simulated minutes of a kept record, from its day and time (both
  /// checked when it was kept).
  static int simMinutesOf(Map<String, Object?> event) {
    final time = event['simTime'] as String;
    return (event['day'] as int) * minutesPerDay + int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3));
  }

  /// The care center with the most people in care now (their latest move
  /// at it): `{"id", "name", "kind", "inCare"}`, the lower id on a tie;
  /// null while nobody is in care.
  Map<String, Object?>? get busiest {
    final inCare = <int, int>{};
    final named = <int, Map<String, Object?>>{};
    for (final person in _latest.values) {
      final id = person['hospitalId'];
      if (person['state'] != PersonState.atHospital.json || id is! int) continue;
      inCare[id] = (inCare[id] ?? 0) + 1;
      named[id] ??= person;
    }
    int? best;
    for (final MapEntry(key: id, value: n) in inCare.entries) {
      if (best == null || n > inCare[best]! || (n == inCare[best]! && id < best)) best = id;
    }
    if (best == null) return null;
    return {
      'id': best,
      'name': named[best]!['hospitalName'],
      'kind': named[best]!['careCenterKind'],
      'inCare': inCare[best],
    };
  }

  /// aityx's triage of a kept admission: its level ("red" to "blue"), or
  /// null when the triage failed; the admission carries it as "triage".
  void triaged(Object? eventId, Object? level) {
    for (final (_, admission) in _admissions) {
      if (admission['eventId'] == eventId) {
        admission['triage'] = level is String ? level : null;
        return;
      }
    }
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
    counter.add();
    final previous = _latest[id];
    _latest[id] = Map<String, Object?>.from(value);
    // Only a change of state is an event (left home, arrived, going home,
    // back home): a person moves every turn, and every move would bury
    // the admissions and the alarms. The first record read of someone
    // says no change; the map still has everyone.
    if (previous == null || previous['state'] == value['state']) return;
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
    counter.add();
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
        within('turn', 0, int32Max) &&
        (value['template'] == null || within('template', 0, templatesPerVisit - 1));
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

/// The history run: the run id of the admissions per hour the API
/// generates at start (lib/history.dart), never a simulation's
/// ([Simulation.run]), so its series stand apart from every live run's.
const historyRun = '00000000';

String _hex(Random random) =>
    List.generate(4, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
