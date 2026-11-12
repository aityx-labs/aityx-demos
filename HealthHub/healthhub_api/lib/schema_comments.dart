/// What each table and column of the schema is, kept in the database as
/// PostgreSQL comments (COMMENT ON), which the migration sets at every
/// start. A catalogue reading the schema (OpenMetadata, through datyx)
/// takes them as the descriptions of the tables and columns, so the data
/// says what it is wherever it is read.
library;

import 'package:postgres/postgres.dart';

/// A table's description and its columns', every column of it.
typedef TableComments = ({String table, Map<String, String> columns});

const schemaComments = <String, TableComments>{
  'greetings': (
    table: 'The greeting the app shows, read by GET /api/hello: one row, written at start when the table is empty.',
    columns: {
      'id': 'The greeting\'s id; /api/hello reads the lowest.',
      'message': 'The greeting\'s text, "Hello, world".',
      'created_at': 'When the greeting was written.',
    },
  ),
  'care_centers': (
    table:
        'The hospitals, clinics and health stations of Catalonia, Brazil and Florida, from public '
        'catalogues; made to hold exactly the API\'s compiled-in seed at every start. GET '
        '/api/care-centers reads them, and the simulation sends people to the hospitals among them.',
    columns: {
      'id': 'The care center\'s id, as admissions and admissions_hourly name a hospital (hospital_id).',
      'key': 'The seed\'s key: the source and its id for the facility, else the country, city, name and address.',
      'name': 'The care center\'s name.',
      'kind': 'hospital, clinic or health_station (primary care).',
      'subtype': 'The source\'s own type, such as "CAP (Centro de Salud)" or "Urgent care".',
      'address': 'The street address, when the source has it.',
      'postal_code': 'The postal code, when the source has it.',
      'city': 'The city or municipality.',
      'region': 'The region or state.',
      'country': 'The country, as ISO 3166-1 alpha-2 (ES, BR, US).',
      'latitude': 'The latitude, WGS84; null when the source has no location.',
      'longitude': 'The longitude, WGS84; null when the source has no location.',
      'phone': 'The phone number, when the source has it.',
      'website': 'The website, when the source has one.',
      'ownership': 'public, private or unknown.',
      'source': 'The catalogue the row comes from.',
      'source_id': 'The facility\'s id in that catalogue, when it has one.',
      'updated_at': 'When the seed last wrote the row.',
    },
  ),
  'medical_conditions': (
    table:
        'The common conditions the simulation gives people: their treatment and how they bring people '
        'to the hospital. Made to hold exactly the API\'s compiled-in seed at every start.',
    columns: {
      'code': 'The condition\'s key: a lowercase slug.',
      'name': 'The condition\'s name.',
      'type': 'acute (it passes) or chronic (it stays).',
      'prevalence': 'How common it is among adults, relative to the other conditions of its type: only the ratios matter.',
      'min_age': 'The youngest adult age it plausibly occurs at, 18 to 90.',
      'max_age': 'The oldest adult age it plausibly occurs at, 18 to 90.',
      'summary': 'One sentence on what the condition is.',
      'treatment': 'The usual treatment: drug classes, procedures, follow-up.',
      'treatment_duration_days': 'Acute: the typical days of treatment and recovery; null for a chronic condition (ongoing).',
      'duration': 'The duration as people say it, such as "5 to 7 days".',
      'visit_count': 'The hospital visits in one course of the condition, at least 1.',
      'visit_interval_days': 'The days between the visits of a course, at least 1.',
      'stay_hours': 'The hours a first visit stays, 1 to 72.',
      'female_share': 'The share of its patients who are women, 0 to 1; a person\'s condition is weighed by it.',
      'urgent': 'Whether the first visit is an emergency, at any hour as soon as the condition starts, rather than at a planned slot.',
      'follow_up_stay_hours': 'The hours a visit after the first stays, 1 to 72.',
      'course_gap_days': 'Chronic only: the days from the last visit of a course to the first of the next; null is a random 30 to 120, 0 continuous.',
      'setting': 'Where the first visit goes: hospital, primary (a health station), urgent_care, mental_health or dialysis.',
      'follow_up_setting': 'Where the visits after the first go, one of the same; the setting when the seed names none.',
    },
  ),
  'complaint_templates': (
    table:
        'What a patient with a condition says on arrival, three per visit kind, with placeholders the '
        'simulation fills; seeded with the conditions.',
    columns: {
      'id': 'The template\'s id.',
      'condition_code': 'The condition it is for (medical_conditions.code).',
      'visit': 'The visit it is said at: first, repeat or last.',
      'position': 'Its place among the condition\'s templates for that visit, from 0.',
      'text': 'The complaint, with placeholders such as {occupation}.',
      'triage': 'The reference triage level a nurse applying the same policy gives it: red, orange, yellow, green or blue (immediate to non-urgent).',
    },
  ),
  'admissions': (
    table:
        'Every simulated arrival at a hospital, as the API\'s feed reads it from the Kafka topic '
        'healthhub.admissions; recorded once per event id, so a retry or a replay never doubles one. '
        'Run 00000001 is the simulated history, a year (by default) of the people\'s visits that the API '
        'simulates ahead at start and writes here itself (lib/simulated_history.dart), not through Kafka. '
        'The people are simulated, not real.',
    columns: {
      'id': 'The row\'s id, in the order the admissions were recorded.',
      'event_id': 'The event\'s id: the run\'s id, the person, the day and the turn; unique. '
          'The run is 8 hex digits, new at each start of the API; 00000001 is the simulated history.',
      'person_id': 'The simulated person\'s id within the run, such as reus-3.',
      'person_name': 'The simulated person\'s name.',
      'age': 'The person\'s age in years, 18 to 90.',
      'sex': 'The person\'s sex: woman or man.',
      'occupation': 'The person\'s job, one of 40, such as teacher.',
      'city': 'The city the person lives in.',
      'condition_code': 'The condition that brings them (medical_conditions.code).',
      'condition_name': 'The condition\'s name.',
      'condition_type': 'acute or chronic.',
      'visit': 'Which visit of the course: first, repeat or last.',
      'visit_number': 'The visit\'s number in the course, from 1.',
      'complaint': 'What the patient says on arrival.',
      'template': 'Which of the visit kind\'s complaint templates it was said from, 0 to 2 (complaint_templates.position); null for admissions recorded before it was.',
      'hospital_id': 'The hospital they arrive at (care_centers.id).',
      'hospital_name': 'The hospital\'s name.',
      'sim_day': 'The simulated day of the arrival, from 1 at each start of the API, and from 1 in the simulated history.',
      'sim_time': 'The simulated minute of the arrival, HH:MM.',
      'admitted_at': 'The admission\'s simulated date and time, from sim_day and sim_time: day 1 is 2026-01-01.',
      'recorded_at': 'When the API recorded the admission, in real time; for the simulated history, when it was written.',
    },
  ),
  'admission_triage': (
    table:
        'Each admission\'s triage at the desk by aityx, from what the patient said and their age only: '
        'the level, the wait, the area, whether a nurse checks, the rules behind them, what Jev read '
        'and aityx\'s receipt, beside the template\'s reference level; or why it failed. One row per '
        'admission, written once.',
    columns: {
      'event_id': 'The admission triaged (admissions.event_id).',
      'level': 'The triage level: red, orange, yellow, green or blue (immediate, very urgent, urgent, standard, non-urgent); null when the triage failed.',
      'wait_minutes': 'The longest wait before being seen, by level: 0, 10, 60, 120 or 240 minutes.',
      'area': 'Where in the hospital the patient goes: resuscitation, emergency, mental_health, minor_care, outpatients or day_unit.',
      'nurse_check': 'Whether a nurse checks first: a danger sign in doubt, or a possible serious infection at 65 or older.',
      'level_rule': 'The rule of the level decision table that applied, from 1.',
      'level_why': 'That rule\'s reason, in words.',
      'area_rule': 'The rule of the area decision table that applied, from 1.',
      'area_why': 'That rule\'s reason, in words.',
      'signs': 'The probability Jev read for each of the eight danger signs, such as {"cardiac": 0.12}.',
      'choices': 'The four choices Jev read (pain, onset, visit_purpose, body_system), each with its confidence.',
      'receipt': 'aityx\'s receipt of the call: the decisions taken and how.',
      'reference': 'The reference level of the complaint template the admission was said from, red to blue; null without one.',
      'error': 'Why the triage failed, by aityx\'s error code; null when it succeeded.',
      'input_tokens': 'The input tokens the call used.',
      'millis': 'How long the call took, in milliseconds.',
      'mode': 'How aityx ran the call, as its x-aityx-mode header says; null when it doesn\'t say.',
      'via': 'Which way the call went: datyx (through datyx\'s aityx gateway, which recorded it in its aityx account) or aityx (directly, with HealthHub\'s key); null for triages recorded before, or a call that never got that far.',
      'triaged_at': 'When the triage was recorded, in real time.',
    },
  ),
  'admissions_hourly': (
    table:
        'The admissions per run, hospital and simulated hour, written by the Flink job '
        '(flink/admissions-hourly.sql) and upserted by the key; run 00000000 is the history the API '
        'generates at start (lib/history.dart), every hour of 90 days by default, and run 00000001 the '
        'simulated history, a year (by default) of the people\'s visits that the API simulates ahead at '
        'start (lib/simulated_history.dart), counted from its admissions. Sparse: an hour '
        'without admissions at a hospital has no row, so a missing row means zero.',
    columns: {
      'run_id': 'The run: each start of the API replays the simulated calendar from day 1, and the run tells the repeats apart; '
          '00000000 is the generated history, 00000001 the simulated history.',
      'hospital_id': 'The hospital (care_centers.id).',
      'hospital_name': 'The hospital\'s name.',
      'hour_start': 'The simulated hour, without a time zone: day 1 is 2026-01-01.',
      'admissions': 'The admissions in the hour; acute_admissions and chronic_admissions add up to it.',
      'acute_admissions': 'The admissions in the hour for an acute condition.',
      'chronic_admissions': 'The admissions in the hour for a chronic condition.',
    },
  ),
  'patient_days': (
    table:
        'Each simulated person\'s visits and hours of hospital care per run and simulated day, with '
        'their facts: a view of admissions and medical_conditions, so always up to date. Run 00000001 is '
        'the simulated history, a year (by default) of the people\'s visits that the API simulates ahead '
        'at start. Sparse: a day without visits has no row, so a missing day is zero visits and zero hours.',
    columns: {
      'run_id': 'The run, the event id\'s first part; a person is the run and the id together. '
          '00000001 is the simulated history.',
      'person_id': 'The simulated person\'s id within the run, such as reus-3.',
      'day': 'The simulated day as a date: day 1 is 2026-01-01.',
      'age': 'The person\'s age in years, 18 to 90, the same on every row of a run.',
      'sex': 'The person\'s sex: woman or man.',
      'city': 'The city the person lives in.',
      'hospital_id': 'The hospital the person goes to (care_centers.id).',
      'chronic_condition': 'The code of the chronic condition the run\'s admissions show for the person (medical_conditions.code); none when they show none.',
      'visits': 'The admissions of the day: one, rarely two.',
      'acute_visits': 'The day\'s visits for an acute condition.',
      'chronic_visits': 'The day\'s visits for the chronic condition; with acute_visits, they add up to visits.',
      'stay_hours': 'The hours of care the day\'s visits take: a first visit\'s stay_hours, a later one\'s follow_up_stay_hours.',
    },
  ),
  'occupancy_hourly': (
    table:
        'How many people each care center has in care in each simulated hour of a run: each admission\'s '
        'stay, from its arrival, for its condition\'s hours. A view of admissions and medical_conditions, '
        'so always up to date, up to the run\'s latest arrival. Run 00000001 is the simulated history, a '
        'year (by default) of the people\'s visits that the API simulates ahead at start. Sparse: an hour '
        'nobody is in care has no row, so a missing hour is zero people.',
    columns: {
      'run_id': 'The run, the event id\'s first part: each start of the API is a new run from day 1; '
          '00000001 is the simulated history.',
      'hospital_id': 'The care center (care_centers.id): a hospital, a health station or a clinic.',
      'hospital_name': 'The care center\'s name.',
      'hour_start': 'The simulated hour: day 1 is 2026-01-01, a timestamp without a time zone.',
      'occupancy': 'The people in care at the care center at any minute of the hour, at least 1.',
    },
  ),
  'occupancy_alarm': (
    table:
        'Each occupancy alarm event: a care center\'s level rising, falling or clearing, from its occupancy per '
        'hour (occupancy_hourly), observed and as datyx\'s DeepAR forecasts it, against a threshold of its '
        'capacity in the simulation (90% unless HEALTHHUB_ALARM_THRESHOLD says). actual: the occupancy observed at '
        'the latest hour reaches it; expected: the forecast\'s mean reaches it at some hour ahead; possible: its '
        '90th percentile does. Written by the API once per event, also published to the healthhub.alarms topic.',
    columns: {
      'id': 'The event\'s id: the run, the care center and the API\'s counter.',
      'kind': 'alarm (the level rose), downgraded (to a lower level) or cleared (back to none).',
      'run_id': 'The run, as occupancy_hourly names it.',
      'hospital_id': 'The care center (care_centers.id).',
      'hospital_name': 'The care center\'s name.',
      'care_center_kind': 'hospital, clinic or health_station.',
      'level': 'The level after the event: possible, expected or actual (the worst); null when cleared.',
      'previous_level': 'The level before the event; null for a new alarm.',
      'threshold': 'The share of the capacity whose reaching is an alarm, 0.9 for 90%; null in events before it.',
      'occupancy': 'The people in care at the care center at observed_at, the run\'s latest hour.',
      'observed_at': 'The run\'s latest hour, whose occupancy the check read (simulated, day 1 is 2026-01-01).',
      'overflow_at': 'The earliest simulated hour at or above the threshold for the level (day 1 is 2026-01-01): '
          'observed_at for actual; null when cleared.',
      'lead_hours': 'The simulated hours from the series\' end to overflow_at, 0 for actual.',
      'mean': 'The forecast\'s mean at overflow_at, in people.',
      'p90': 'The forecast\'s 90th percentile at overflow_at, in people.',
      'peak_at': 'The hour of the horizon with the highest mean (the highest p90 for possible).',
      'peak_mean': 'The forecast\'s mean at peak_at.',
      'peak_p90': 'The forecast\'s 90th percentile at peak_at.',
      'capacity': 'The care center\'s capacity in the simulation, in beds or places.',
      'unit': 'beds (a hospital) or places (a clinic, a health station).',
      'series_end': 'The series\' end, the run\'s latest hour, where the forecast starts from.',
      'horizon_hours': 'How many hours the forecast covers.',
      'training_run': 'datyx\'s training run whose model answered.',
      'sim_day': 'The simulated day of the check, from 1.',
      'sim_time': 'The simulated time of the check, HH:MM.',
      'raised_at': 'When the check found it, real time.',
    },
  ),
  'occupancy_forecast': (
    table:
        'What datyx\'s DeepAR model predicted of each care center\'s occupancy (occupancy_hourly) in each simulated '
        'hour of a run before the hour was observed: the forecast made closest to the hour (from the latest series\' '
        'end before it) wins. Written by the API from the occupancy alarms\' checks and the care center view\'s '
        'forecasts, so the predicted line goes on over the past hours.',
    columns: {
      'run_id': 'The run, as occupancy_hourly names it.',
      'hospital_id': 'The care center (care_centers.id).',
      'hour_start': 'The simulated hour predicted (day 1 is 2026-01-01).',
      'series_end': 'The series\' end the forecast started from, the run\'s latest hour then, before hour_start.',
      'lead_hours': 'The simulated hours from series_end to hour_start, 1 for the next hour.',
      'mean': 'The forecast\'s mean of the people in care in the hour.',
      'p10': 'The forecast\'s 10th percentile.',
      'p90': 'The forecast\'s 90th percentile.',
      'training_run': 'datyx\'s training run whose model answered.',
      'forecast_at': 'When the API got the forecast, real time.',
    },
  ),
};

/// The relations of [schemaComments] that are views, commented as such.
const schemaViews = {'patient_days', 'occupancy_hourly'};

/// [text] as an SQL string literal. COMMENT ON takes no parameters, so
/// its text goes in the statement; every text here is the API's own.
/// With standard_conforming_strings on (PostgreSQL's default since 9.1) a
/// doubled quote is the one character that needs escaping.
String sqlLiteral(String text) => "'${text.replaceAll("'", "''")}'";

/// The COMMENT ON statements for [comments]: a table's, then its columns'.
List<String> commentStatements(Map<String, TableComments> comments) => [
  for (final MapEntry(key: table, value: c) in comments.entries) ...[
    'COMMENT ON ${schemaViews.contains(table) ? 'VIEW' : 'TABLE'} $table IS ${sqlLiteral(c.table)}',
    for (final MapEntry(key: column, value: text) in c.columns.entries)
      'COMMENT ON COLUMN $table.$column IS ${sqlLiteral(text)}',
  ],
];

/// Sets every comment of [schemaComments]; run after the tables are made.
/// A comment set again to the same text changes nothing.
Future<void> commentSchema(Session session) async {
  for (final statement in commentStatements(schemaComments)) {
    await session.execute(statement);
  }
}
