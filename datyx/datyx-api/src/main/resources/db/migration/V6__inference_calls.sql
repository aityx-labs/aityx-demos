-- Inference calls: each time a model datyx trained (a training run's) is
-- asked to score series (datyx.training.Inference), kept to account for
-- them: who asked, which model, how many series it was asked for and
-- scored, how long it took, and whether it failed. Removing the data
-- source, or the run, removes its calls.

create sequence inference_call_seq start with 1 increment by 50;

create table inference_call (
    id               bigint                      not null,
    data_source_id   bigint                      not null,
    training_run_id  bigint                      not null,
    table_fqn        varchar(1000)               not null,
    group_name       varchar(64)                 not null,
    called_at        timestamp(6) with time zone not null,
    millis           integer                     not null,
    requested        integer                     not null,
    scored           integer                     not null,
    status           varchar(16)                 not null,
    error            varchar(2000),
    caller           varchar(320),
    constraint inference_call_pkey primary key (id),
    constraint inference_call_data_source_fkey foreign key (data_source_id) references data_source (id) on delete cascade,
    constraint inference_call_training_run_fkey foreign key (training_run_id) references training_run (id) on delete cascade
);

create index inference_call_called_idx on inference_call (data_source_id, called_at desc);
