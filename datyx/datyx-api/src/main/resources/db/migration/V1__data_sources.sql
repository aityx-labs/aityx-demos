-- The first schema: what Hibernate generated for the DataSource entity
-- (a sequence of 50, as Panache ids are allocated),
-- plus a unique index on the lower-cased name of a data source, so two
-- names that differ only in case can't both be stored: the loser of a
-- race gets a 409 from the API (DataSourceResource).

create sequence data_source_seq start with 1 increment by 50;

create table data_source (
    id                   bigint                      not null,
    name                 varchar(100)                not null,
    type                 varchar(20)                 not null,
    description          varchar(500),
    created_at           timestamp(6) with time zone not null,
    created_by           varchar(320),
    created_by_name      varchar(200),
    db_engine            varchar(40),
    db_host              varchar(255),
    db_port              integer,
    db_database          varchar(200),
    db_username          varchar(200),
    db_password          varchar(500),
    s3_bucket            varchar(255),
    s3_region            varchar(40),
    s3_endpoint          varchar(500),
    s3_prefix            varchar(1000),
    s3_access_key_id     varchar(200),
    s3_secret_access_key varchar(500),
    fs_path              varchar(1000),
    constraint data_source_pkey primary key (id),
    constraint data_source_type_check check (type in ('DATABASE', 'S3', 'FILESYSTEM'))
);

create unique index data_source_name_lower_key on data_source (lower(name));
