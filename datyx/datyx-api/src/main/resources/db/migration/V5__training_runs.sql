-- Training runs: each time datyx trains a group of a source's table (a
-- time series dataset tagged in OpenMetadata) with its algorithm, XGBoost
-- so far (datyx.training). A run is queued, runs, and then succeeded or
-- failed; it keeps when, why (the first training, the schedule, or a
-- person asking), the settings it trained with, what it measured, and
-- the trained model. Removing the data source removes its runs.

create sequence training_run_seq start with 1 increment by 50;

create table training_run (
    id              bigint                      not null,
    data_source_id  bigint                      not null,
    table_fqn       varchar(1000)               not null,
    group_name      varchar(64)                 not null,
    algorithm       varchar(32)                 not null,
    trigger         varchar(16)                 not null,
    status          varchar(16)                 not null,
    queued_at       timestamp(6) with time zone not null,
    started_at      timestamp(6) with time zone,
    finished_at     timestamp(6) with time zone,
    error           varchar(2000),
    results         text,
    model           bytea,
    constraint training_run_pkey primary key (id),
    constraint training_run_data_source_fkey foreign key (data_source_id) references data_source (id) on delete cascade
);

create index training_run_group_idx on training_run (data_source_id, table_fqn, group_name, queued_at desc);
