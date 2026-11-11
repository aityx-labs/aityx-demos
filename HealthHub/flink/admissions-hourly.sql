-- The admissions per run, hospital and simulated hour, from the
-- healthhub.admissions topic into the healthhub.admissions.hourly topic
-- and the admissions_hourly table, kept up to date as admissions come in.
-- Submitted by submit.sh, which puts the database password in place of
-- @@HEALTHHUB_DB_PASSWORD@@, and Kafka's and the database's addresses in
-- place of @@HEALTHHUB_KAFKA_BOOTSTRAP@@, @@HEALTHHUB_DB_HOST@@ and
-- @@HEALTHHUB_DB_PORT@@ (compose's kafka:19092 and postgres:5432 unless
-- the environment names others). See ../specs/admissions-hourly.md.
--
-- No event-time windows: the simulated clock runs an hour every 10 real
-- seconds with the defaults and starts again from day 1 at every start
-- of the API, so watermarks would drop whole runs as late. A plain
-- GROUP BY keeps a count per key and sends each change downstream, where
-- both sinks upsert by the key.
-- The source reads the topic from its earliest record at every
-- submission, so the job is a function of what the topic keeps (24 h):
-- a resubmitted job recounts the same hours and writes the same rows.

SET 'pipeline.name' = 'healthhub-admissions-hourly';
SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '10 s';
-- Each key's count, and each event id the dedup has seen, is dropped a
-- day and an hour after its last change: past the topic's retention.
SET 'table.exec.state.ttl' = '25 h';

CREATE TEMPORARY TABLE admission_events (
  `type` STRING,
  eventId STRING,
  hospitalId INT,
  hospitalName STRING,
  conditionType STRING,
  `day` INT,
  simTime STRING,
  arrived AS PROCTIME()
) WITH (
  'connector' = 'kafka',
  'topic' = 'healthhub.admissions',
  'properties.bootstrap.servers' = '@@HEALTHHUB_KAFKA_BOOTSTRAP@@',
  'properties.group.id' = 'healthhub-flink-admissions-hourly',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'json',
  'json.ignore-parse-errors' = 'true'
);

-- One row per admission with what the counts need. The run is the event
-- id's first part (`3f9c0a7e-reus-3-d4-t75`); the hour is simulated time,
-- day 1 being 2026-01-01, so `"day": 4, "simTime": "09:09"` is
-- 2026-01-04 09:00. Records that aren't an admission, or lack a field
-- the counts need, are skipped, as are admissions with no run in their id
-- (`barcelona-10-d1-t2`, published by builds from before run ids).
CREATE TEMPORARY VIEW admission_rows AS
SELECT
  eventId AS event_id,
  SPLIT_INDEX(eventId, '-', 0) AS run_id,
  hospitalId AS hospital_id,
  hospitalName AS hospital_name,
  conditionType AS condition_type,
  `day` AS sim_day,
  TRY_CAST(SUBSTRING(simTime FROM 1 FOR 2) AS INT) AS sim_hour,
  arrived
FROM admission_events
WHERE `type` = 'admission'
  AND REGEXP(eventId, '^[0-9a-f]{8}-.+-d[0-9]+-t[0-9]+$')
  AND hospitalId IS NOT NULL AND hospitalName IS NOT NULL
  AND `day` BETWEEN 1 AND 1000000
  AND CHAR_LENGTH(simTime) = 5;

-- Each admission once: the API retries a failed publish, so an event id
-- can be on the topic twice; the first one counts.
CREATE TEMPORARY VIEW admissions_once AS
SELECT run_id, hospital_id, hospital_name, condition_type,
  TIMESTAMPADD(HOUR, sim_hour, TIMESTAMPADD(DAY, sim_day - 1, TIMESTAMP '2026-01-01 00:00:00')) AS hour_start
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY arrived ASC) AS row_num
  FROM admission_rows
  WHERE sim_hour BETWEEN 0 AND 23
)
WHERE row_num = 1;

CREATE TEMPORARY VIEW hourly AS
SELECT
  run_id,
  hospital_id,
  MAX(hospital_name) AS hospital_name,
  CAST(hour_start AS TIMESTAMP(3)) AS hour_start,
  CAST(COUNT(*) AS INT) AS admissions,
  CAST(COUNT(*) FILTER (WHERE condition_type = 'acute') AS INT) AS acute_admissions,
  CAST(COUNT(*) FILTER (WHERE condition_type = 'chronic') AS INT) AS chronic_admissions
FROM admissions_once
GROUP BY run_id, hospital_id, hour_start;

-- The stream: the latest count of each key, keyed by the key as JSON.
CREATE TEMPORARY TABLE admissions_hourly_topic (
  run_id STRING,
  hospital_id INT,
  hospital_name STRING,
  hour_start TIMESTAMP(3),
  admissions INT,
  acute_admissions INT,
  chronic_admissions INT,
  PRIMARY KEY (run_id, hospital_id, hour_start) NOT ENFORCED
) WITH (
  'connector' = 'upsert-kafka',
  'topic' = 'healthhub.admissions.hourly',
  'properties.bootstrap.servers' = '@@HEALTHHUB_KAFKA_BOOTSTRAP@@',
  'key.format' = 'json',
  'key.json.timestamp-format.standard' = 'ISO-8601',
  'value.format' = 'json',
  'value.json.timestamp-format.standard' = 'ISO-8601'
);

-- The table, which the API makes (lib/db.dart): INSERT ... ON CONFLICT
-- by its primary key.
CREATE TEMPORARY TABLE admissions_hourly_table (
  run_id STRING,
  hospital_id INT,
  hospital_name STRING,
  hour_start TIMESTAMP(3),
  admissions INT,
  acute_admissions INT,
  chronic_admissions INT,
  PRIMARY KEY (run_id, hospital_id, hour_start) NOT ENFORCED
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:postgresql://@@HEALTHHUB_DB_HOST@@:@@HEALTHHUB_DB_PORT@@/healthhub',
  'table-name' = 'admissions_hourly',
  'username' = 'healthhub',
  'password' = '@@HEALTHHUB_DB_PASSWORD@@',
  'sink.buffer-flush.interval' = '1 s',
  'sink.buffer-flush.max-rows' = '500'
);

EXECUTE STATEMENT SET
BEGIN
  INSERT INTO admissions_hourly_topic SELECT * FROM hourly;
  INSERT INTO admissions_hourly_table SELECT * FROM hourly;
END;
