-- Profiles: the person behind a sign-in. A profile is created the first
-- time an identity (an issuer and its subject: a Google account) calls
-- the API, and more identities can join it later. Each profile has its
-- own encryption key, made with it and stored wrapped by the server's
-- master key (DATYX_MASTER_KEY); the key encrypts the access details of
-- the profile's data sources (datyx.crypto, datyx.profile).

create sequence profile_seq start with 1 increment by 50;

create table profile (
    id          bigint                      not null,
    name        varchar(200),
    created_at  timestamp(6) with time zone not null,
    key_wrapped bytea                       not null,
    constraint profile_pkey primary key (id)
);

create sequence profile_identity_seq start with 1 increment by 50;

create table profile_identity (
    id           bigint                      not null,
    profile_id   bigint                      not null,
    issuer       varchar(500)                not null,
    subject      varchar(500)                not null,
    email        varchar(320),
    name         varchar(200),
    picture      varchar(1000),
    added_at     timestamp(6) with time zone not null,
    last_seen_at timestamp(6) with time zone not null,
    constraint profile_identity_pkey primary key (id),
    constraint profile_identity_profile_fkey foreign key (profile_id) references profile (id) on delete cascade,
    constraint profile_identity_issuer_subject_key unique (issuer, subject)
);

create index profile_identity_profile_idx on profile_identity (profile_id);

-- Data sources belong to a profile, and their access details (host,
-- database, user, password, bucket, keys, path) are one encrypted
-- document each, in the profile's key, in place of the clear columns.
-- The rows from before this version had no owner and their details in
-- clear; they can't be encrypted here (SQL has no key), so they go.
delete from data_source;

alter table data_source
    drop column db_engine,
    drop column db_host,
    drop column db_port,
    drop column db_database,
    drop column db_username,
    drop column db_password,
    drop column s3_bucket,
    drop column s3_region,
    drop column s3_endpoint,
    drop column s3_prefix,
    drop column s3_access_key_id,
    drop column s3_secret_access_key,
    drop column fs_path,
    add column profile_id bigint not null,
    add column access     bytea  not null,
    add constraint data_source_profile_fkey foreign key (profile_id) references profile (id) on delete cascade;

-- A name is unique within a profile, whatever its case.
drop index data_source_name_lower_key;
create unique index data_source_profile_name_key on data_source (profile_id, lower(name));
