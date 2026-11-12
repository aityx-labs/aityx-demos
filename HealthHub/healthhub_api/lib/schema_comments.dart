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
      'urgent': 'Whether the first visit is an emergency, at any hour as soon as the condition starts, rather than at a daytime slot.',
      'follow_up_stay_hours': 'The hours a visit after the first stays, 1 to 72.',
      'course_gap_days': 'Chronic only: the days from the last visit of a course to the first of the next; null is a random 30 to 120, 0 continuous.',
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
    },
  ),
  'admissions': (
    table:
        'Every simulated arrival at a hospital, as the API\'s feed reads it from the Kafka topic '
        'healthhub.admissions; recorded once per event id, so a retry or a replay never doubles one. '
        'The people are simulated, not real.',
    columns: {
      'id': 'The row\'s id, in the order the admissions were recorded.',
      'event_id': 'The event\'s id: the run\'s id, the person, the day and the turn; unique.',
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
      'hospital_id': 'The hospital they arrive at (care_centers.id).',
      'hospital_name': 'The hospital\'s name.',
      'sim_day': 'The simulated day of the arrival, from 1 at each start of the API.',
      'sim_time': 'The simulated minute of the arrival, HH:MM.',
      'recorded_at': 'When the API recorded the admission, in real time.',
    },
  ),
  'admissions_hourly': (
    table:
        'The admissions per run, hospital and simulated hour, written by the Flink job '
        '(flink/admissions-hourly.sql) and upserted by the key. Sparse: an hour without admissions '
        'at a hospital has no row, so a missing row means zero.',
    columns: {
      'run_id': 'The run: each start of the API replays the simulated calendar from day 1, and the run tells the repeats apart.',
      'hospital_id': 'The hospital (care_centers.id).',
      'hospital_name': 'The hospital\'s name.',
      'hour_start': 'The simulated hour, without a time zone: day 1 is 2026-01-01.',
      'admissions': 'The admissions in the hour; acute_admissions and chronic_admissions add up to it.',
      'acute_admissions': 'The admissions in the hour for an acute condition.',
      'chronic_admissions': 'The admissions in the hour for a chronic condition.',
    },
  ),
};

/// [text] as an SQL string literal. COMMENT ON takes no parameters, so
/// its text goes in the statement; every text here is the API's own.
/// With standard_conforming_strings on (PostgreSQL's default since 9.1) a
/// doubled quote is the one character that needs escaping.
String sqlLiteral(String text) => "'${text.replaceAll("'", "''")}'";

/// The COMMENT ON statements for [comments]: a table's, then its columns'.
List<String> commentStatements(Map<String, TableComments> comments) => [
  for (final MapEntry(key: table, value: c) in comments.entries) ...[
    'COMMENT ON TABLE $table IS ${sqlLiteral(c.table)}',
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
