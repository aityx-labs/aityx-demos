-- HealthHub's schema as HealthHub's API makes it (HealthHub/healthhub_api/lib/db.dart),
-- in the schema the test's search_path names, with a few rows of correct data:
-- every check of datyx's curation document (devdata/healthhub-catalog.json) passes on it.

CREATE TABLE greetings (
  id SERIAL PRIMARY KEY,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO greetings (message) VALUES ('Hello, world');

CREATE TABLE care_centers (
  id SERIAL PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('hospital', 'clinic', 'health_station')),
  subtype TEXT,
  address TEXT,
  postal_code TEXT,
  city TEXT NOT NULL,
  region TEXT NOT NULL,
  country CHAR(2) NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  phone TEXT,
  website TEXT,
  ownership TEXT NOT NULL CHECK (ownership IN ('public', 'private', 'unknown')),
  source TEXT NOT NULL,
  source_id TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO care_centers (id, key, name, kind, subtype, address, postal_code, city, region, country, latitude,
    longitude, phone, website, ownership, source, source_id) VALUES
  (1, 'CNES:2077485', 'Hospital Sao Paulo', 'hospital', 'HOSPITAL GERAL', 'Rua Napoleao de Barros, 715',
    '04024-002', 'São Paulo', 'São Paulo', 'BR', -23.598, -46.645, '11 5576-4000', 'https://hospitalsaopaulo.org.br',
    'public', 'CNES', '2077485'),
  (2, 'es:reus:centre mq reus:carrer 1', 'Centre Mq Reus', 'health_station', 'CAP', 'Carrer de Sant Joan, 1',
    '43201', 'Reus', 'Catalonia', 'ES', 41.155, 1.107, NULL, NULL, 'public', 'Grup Pere Mata (peremata.cat)', NULL),
  (3, 'HIFLD Hospitals:0033136', 'JACKSON MEMORIAL HOSPITAL', 'hospital', 'GENERAL ACUTE CARE', '1611 NW 12th Ave',
    '33136', 'Miami', 'Florida', 'US', 25.791, -80.210, '(305) 585-1111', 'www.jacksonhealth.org', 'public',
    'HIFLD Hospitals', '0033136');

CREATE TABLE medical_conditions (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('acute', 'chronic')),
  prevalence DOUBLE PRECISION NOT NULL,
  min_age INT NOT NULL,
  max_age INT NOT NULL,
  summary TEXT NOT NULL,
  treatment TEXT NOT NULL,
  treatment_duration_days INT,
  duration TEXT NOT NULL,
  visit_count INT NOT NULL,
  visit_interval_days INT NOT NULL,
  stay_hours INT NOT NULL,
  female_share DOUBLE PRECISION NOT NULL DEFAULT 0.5,
  urgent BOOLEAN NOT NULL DEFAULT false,
  follow_up_stay_hours INT,
  course_gap_days INT,
  setting TEXT NOT NULL DEFAULT 'hospital',
  follow_up_setting TEXT NOT NULL DEFAULT 'hospital'
);
INSERT INTO medical_conditions VALUES
  ('acute_bronchitis', 'Acute bronchitis', 'acute', 6, 18, 90, 'An infection of the airways.', 'Rest and fluids.',
    10, '1 to 3 weeks', 2, 2, 2, 0.5, false, 1, NULL, 'primary', 'primary'),
  ('type_2_diabetes', 'Type 2 diabetes', 'chronic', 9, 30, 90, 'High blood sugar.', 'Metformin and diet.',
    NULL, 'lifelong, with periodic review', 4, 30, 1, 0.45, false, 1, NULL, 'primary', 'primary');

CREATE TABLE complaint_templates (
  id SERIAL PRIMARY KEY,
  condition_code TEXT NOT NULL REFERENCES medical_conditions (code) ON DELETE CASCADE,
  visit TEXT NOT NULL CHECK (visit IN ('first', 'repeat', 'last')),
  position INT NOT NULL,
  text TEXT NOT NULL,
  triage TEXT CHECK (triage IN ('red', 'orange', 'yellow', 'green', 'blue')),
  UNIQUE (condition_code, visit, position)
);
INSERT INTO complaint_templates (condition_code, visit, position, text, triage)
SELECT m.code, v.visit, p.position,
       'Hello, I''m {name}, {age}. This is my ' || v.visit || ' visit for ' || m.name || ', number '
         || p.position || ', in {city}.',
       CASE m.code WHEN 'acute_bronchitis' THEN 'green' ELSE 'blue' END
FROM medical_conditions m,
     (VALUES ('first'), ('repeat'), ('last')) AS v (visit),
     (VALUES (0), (1), (2)) AS p (position);

CREATE TABLE admissions (
  id SERIAL PRIMARY KEY,
  event_id TEXT NOT NULL UNIQUE,
  person_id TEXT NOT NULL,
  person_name TEXT NOT NULL,
  age INT NOT NULL,
  sex TEXT NOT NULL,
  occupation TEXT NOT NULL,
  city TEXT NOT NULL,
  condition_code TEXT NOT NULL,
  condition_name TEXT NOT NULL,
  condition_type TEXT NOT NULL,
  visit TEXT NOT NULL CHECK (visit IN ('first', 'repeat', 'last')),
  visit_number INT NOT NULL,
  complaint TEXT NOT NULL,
  template INT,
  hospital_id INT NOT NULL,
  hospital_name TEXT NOT NULL,
  sim_day INT NOT NULL,
  sim_time TEXT NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO admissions (event_id, person_id, person_name, age, sex, occupation, city, condition_code, condition_name,
    condition_type, visit, visit_number, complaint, template, hospital_id, hospital_name, sim_day, sim_time,
    recorded_at) VALUES
  ('a1b2c3d4-reus-1-d1-t5', 'reus-1', 'Rosa Moreno', 30, 'woman', 'cleaner', 'Reus', 'acute_bronchitis',
    'Acute bronchitis', 'acute', 'first', 1, 'Hello, I''m Rosa Moreno, 30. I have had a cough for a week.', 0, 2,
    'Centre Mq Reus', 1, '09:15', now() - INTERVAL '1 hour'),
  ('a1b2c3d4-miami-2-d1-t7', 'miami-2', 'Carlos Wilson', 60, 'man', 'driver', 'Miami', 'type_2_diabetes',
    'Type 2 diabetes', 'chronic', 'first', 1, 'Hello, I''m Carlos Wilson, 60. I am thirsty all the time.', 1, 3,
    'JACKSON MEMORIAL HOSPITAL', 1, '10:05', now() - INTERVAL '1 hour'),
  ('a1b2c3d4-reus-1-d3-t9', 'reus-1', 'Rosa Moreno', 30, 'woman', 'cleaner', 'Reus', 'acute_bronchitis',
    'Acute bronchitis', 'acute', 'last', 2, 'Hello, I''m Rosa Moreno, 30. The cough is better, I came to check.', 2,
    2, 'Centre Mq Reus', 3, '11:30', now() - INTERVAL '1 hour'),
  ('a1b2c3d4-miami-2-d5-t12', 'miami-2', 'Carlos Wilson', 60, 'man', 'driver', 'Miami', 'type_2_diabetes',
    'Type 2 diabetes', 'chronic', 'repeat', 2, 'Hello, I''m Carlos Wilson, 60. I am here for my review.', 0, 3,
    'JACKSON MEMORIAL HOSPITAL', 5, '08:00', now() - INTERVAL '1 hour');

CREATE TABLE admission_triage (
  event_id TEXT PRIMARY KEY REFERENCES admissions (event_id) ON DELETE CASCADE,
  level TEXT CHECK (level IN ('red', 'orange', 'yellow', 'green', 'blue')),
  wait_minutes INT,
  area TEXT,
  nurse_check BOOLEAN,
  level_rule INT,
  level_why TEXT,
  area_rule INT,
  area_why TEXT,
  signs JSONB,
  choices JSONB,
  receipt JSONB,
  reference TEXT CHECK (reference IN ('red', 'orange', 'yellow', 'green', 'blue')),
  error TEXT,
  input_tokens INT,
  millis INT,
  mode TEXT,
  triaged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((level IS NULL) <> (error IS NULL))
);
INSERT INTO admission_triage (event_id, level, wait_minutes, area, nurse_check, level_rule, level_why, area_rule,
    area_why, signs, choices, receipt, reference, error, input_tokens, millis, mode, triaged_at) VALUES
  ('a1b2c3d4-reus-1-d1-t5', 'green', 120, 'minor_care', false, 9, 'a minor problem', 5, 'minor care',
    '{"cardiac": 0.01}', '{}', '{}', 'green', NULL, 4200, 640, 'jev_aityx', now() - INTERVAL '30 minutes'),
  ('a1b2c3d4-miami-2-d1-t7', 'blue', 240, 'outpatients', false, 12, 'a review', 7, 'outpatients',
    '{"cardiac": 0.02}', '{}', '{}', 'blue', NULL, 4190, 702, 'jev_aityx', now() - INTERVAL '30 minutes'),
  ('a1b2c3d4-reus-1-d3-t9', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'green',
    'aityx_timeout', NULL, 60000, NULL, now() - INTERVAL '30 minutes');

CREATE TABLE admissions_hourly (
  run_id TEXT NOT NULL,
  hospital_id INT NOT NULL,
  hospital_name TEXT NOT NULL,
  hour_start TIMESTAMP NOT NULL,
  admissions INT NOT NULL,
  acute_admissions INT NOT NULL,
  chronic_admissions INT NOT NULL,
  PRIMARY KEY (run_id, hospital_id, hour_start)
);
INSERT INTO admissions_hourly VALUES
  ('a1b2c3d4', 2, 'Centre Mq Reus', '2026-01-01 09:00', 1, 1, 0),
  ('a1b2c3d4', 3, 'JACKSON MEMORIAL HOSPITAL', '2026-01-01 10:00', 1, 0, 1),
  ('a1b2c3d4', 2, 'Centre Mq Reus', '2026-01-03 11:00', 1, 1, 0),
  ('a1b2c3d4', 3, 'JACKSON MEMORIAL HOSPITAL', '2026-01-05 08:00', 1, 0, 1),
  -- A generated history, a run without admissions: not compared with them.
  ('e5f6a7b8', 3, 'JACKSON MEMORIAL HOSPITAL', '2026-01-02 08:00', 2, 1, 1);

CREATE VIEW patient_days AS
SELECT split_part(a.event_id, '-', 1) AS run_id,
       a.person_id,
       DATE '2026-01-01' + (a.sim_day - 1) AS day,
       max(a.age) AS age,
       max(a.sex) AS sex,
       max(a.city) AS city,
       max(a.hospital_id) AS hospital_id,
       coalesce(max(max(a.condition_code) FILTER (WHERE a.condition_type = 'chronic'))
         OVER (PARTITION BY split_part(a.event_id, '-', 1), a.person_id), 'none') AS chronic_condition,
       count(*)::int AS visits,
       (count(*) FILTER (WHERE a.condition_type = 'acute'))::int AS acute_visits,
       (count(*) FILTER (WHERE a.condition_type = 'chronic'))::int AS chronic_visits,
       sum(CASE WHEN a.visit = 'first' THEN m.stay_hours
                ELSE coalesce(m.follow_up_stay_hours, m.stay_hours) END)::int AS stay_hours
FROM admissions a
LEFT JOIN medical_conditions m ON m.code = a.condition_code
WHERE a.event_id ~ '^[0-9a-f]{8}-'
GROUP BY split_part(a.event_id, '-', 1), a.person_id, a.sim_day;

CREATE VIEW occupancy_hourly AS
WITH stays AS (
  SELECT split_part(a.event_id, '-', 1) AS run_id,
         a.hospital_id,
         a.hospital_name,
         a.person_id,
         TIMESTAMP '2026-01-01' + (a.sim_day - 1) * INTERVAL '1 day' + a.sim_time::time AS arrived,
         CASE WHEN a.visit = 'first' THEN m.stay_hours
              ELSE coalesce(m.follow_up_stay_hours, m.stay_hours) END AS stay_hours
  FROM admissions a
  JOIN medical_conditions m ON m.code = a.condition_code
  WHERE a.event_id ~ '^[0-9a-f]{8}-'
), bounded AS (
  SELECT *, date_trunc('hour', max(arrived) OVER (PARTITION BY run_id)) AS run_hour FROM stays
)
SELECT run_id,
       hospital_id,
       max(hospital_name) AS hospital_name,
       hour_start,
       count(DISTINCT person_id)::int AS occupancy
FROM bounded,
     generate_series(date_trunc('hour', arrived),
                     least(arrived + make_interval(hours => stay_hours) - INTERVAL '1 second', run_hour),
                     INTERVAL '1 hour') AS hour_start
GROUP BY run_id, hospital_id, hour_start;
