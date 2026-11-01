-- A data source can be a Kafka cluster: its type is stored as KAFKA, which
-- the check V1 made (DATABASE, S3, FILESYSTEM; Postgres names it the same
-- on a database Hibernate made before Flyway) refused. Its access details
-- are in the encrypted document like the other types', so no column.
alter table data_source drop constraint if exists data_source_type_check;
alter table data_source add constraint data_source_type_check
    check (type in ('DATABASE', 'S3', 'FILESYSTEM', 'KAFKA'));
