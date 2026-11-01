-- aityx calls: each call datyx's gateway (datyx.aityx) passed on to
-- aityx's /v1/systemone, kept to account for it: whose (a profile's, or
-- none for a service's), who and why, when, how long, aityx's status and
-- mode, the model, decision and number of questions sent, the input
-- tokens and their cost, a short error, and the request sent and answer
-- received, each at most 64 KB (never a header). The latest 2,000 of each
-- profile, and of the services', are kept. Removing the profile removes
-- its calls.

create sequence aityx_call_seq start with 1 increment by 50;

create table aityx_call (
    id                  bigint                      not null,
    profile_id          bigint,
    caller              varchar(320),
    service             boolean                     not null,
    purpose             varchar(64),
    called_at           timestamp(6) with time zone not null,
    millis              integer                     not null,
    status              integer                     not null,
    mode                varchar(64),
    model               varchar(200),
    decision            varchar(500),
    questions           integer,
    input_tokens        bigint,
    cost_usd            double precision,
    error               varchar(500),
    personalized        boolean                     not null,
    request             text,
    request_truncated   boolean                     not null,
    response            text,
    response_truncated  boolean                     not null,
    constraint aityx_call_pkey primary key (id),
    constraint aityx_call_profile_fkey foreign key (profile_id) references profile (id) on delete cascade
);

create index aityx_call_profile_idx on aityx_call (profile_id, called_at desc);
