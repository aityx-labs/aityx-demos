-- Group switches: each time datyx learns that a group of a source's table
-- was switched on (its Disabled tag removed) or off (added), from
-- OpenMetadata's webhook, its own switch (PUT .../timeseries/enabled) or
-- its minute's check: when, by whom, which version of the table, and the
-- runs a switch on queued, one per algorithm of the group. Removing the
-- data source removes its switches.

create sequence group_event_seq start with 1 increment by 50;

create table group_event (
    id              bigint                      not null,
    data_source_id  bigint                      not null,
    table_fqn       varchar(1000)               not null,
    group_name      varchar(64)                 not null,
    enabled         boolean                     not null,
    via             varchar(32)                 not null,
    om_version      varchar(32),
    om_event_id     varchar(128),
    changed_by      varchar(320),
    changed_at      timestamp(6) with time zone,
    received_at     timestamp(6) with time zone not null,
    run_ids         varchar(1000),
    constraint group_event_pkey primary key (id),
    constraint group_event_data_source_fkey foreign key (data_source_id) references data_source (id) on delete cascade
);

create index group_event_group_idx on group_event (data_source_id, table_fqn, group_name, received_at desc);
create index group_event_om_event_idx on group_event (om_event_id);

-- The switch that queued a run, when one did.
alter table training_run add column group_event_id bigint;
alter table training_run add constraint training_run_group_event_fkey
    foreign key (group_event_id) references group_event (id) on delete set null;

-- One run of a group's algorithm queued or running at a time, now that a
-- group has more than one algorithm and three paths (the webhook, the
-- switch, the check) can queue it. A stopped API's runs are failed first,
-- as the API does at start, so none stands in the way.
update training_run set status = 'FAILED', finished_at = now(),
    error = 'interrupted: the API stopped before the run finished'
    where status in ('QUEUED', 'RUNNING');
create unique index training_run_one_active_idx on training_run (data_source_id, table_fqn, group_name, algorithm)
    where status in ('QUEUED', 'RUNNING');
