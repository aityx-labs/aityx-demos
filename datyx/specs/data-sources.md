# Data sources

The first entity of datyx: where data lives and how to reach it, owned
by the profile of whoever adds it ([profiles.md](profiles.md)). Users add
and remove them; nothing reads them yet (connecting to them, and
registering them in OpenMetadata, comes next). Code in
`datyx-api/src/main/java/datyx/datasource/`.

## The entity

`DataSource` (table `data_source`): `id`, `profile` (`profile_id`, the
owner; cascade on delete), `name` (up to 100 characters, required,
unique within the profile whatever its case: a unique index on
`(profile_id, lower(name))`, made by the Flyway migration), `type`
(`database`, `s3` or `filesystem`; stored as `DATABASE`, `S3`,
`FILESYSTEM`), `description` (up to 500), `createdAt`, `createdBy` (the
email of the signed-in identity, else the token's subject; null while
authentication is off) and `createdByName`; then `access`: the access
details of its type as one JSON document (`DataSource.Access`, the group
of the type set), encrypted with the owning profile's key
([profiles.md](profiles.md)), column `bytea`. Nothing of where a source
is or how to reach it is in clear in the database; the API decrypts to
answer. The groups:

- A **database**: `engine` (postgresql, mysql, ...; lower-cased), `host`,
  `port` (1 to 65535), `database`, `username`, `password`.
- An **S3 bucket**: `bucket`, `region`, `endpoint` (S3-compatible stores
  only), `prefix`, `accessKeyId`, `secretAccessKey`.
- A **filesystem** folder: `path`.

Secrets (`password`, `secretAccessKey`) are never answered back: answers
carry `passwordSet` and `secretAccessKeySet` instead.

## Endpoints

All under `/api/datasources`, all wanting a signed-in user once
authentication is on ([auth.md](auth.md)), and all within the caller's
profile: another profile's source is a 404 by id and absent from the
list.

- `GET /api/datasources?limit=100` lists them, newest first (`limit`
  between 1 and 1000).
- `GET /api/datasources/{id}` answers one; 404 when there is none.
- `POST /api/datasources` adds one and answers 201 with it and a
  `Location`. The body names the source, its type and the details of that
  type under a key of the same name:
  `{"name":"warehouse","type":"database","description":"...","database":{"engine":"postgresql","host":"db","port":5432,"database":"dw","username":"u","password":"p"}}`,
  `{"name":"lake","type":"s3","s3":{"bucket":"b","region":"eu-west-1","prefix":"raw/","accessKeyId":"...","secretAccessKey":"..."}}`,
  `{"name":"exports","type":"filesystem","filesystem":{"path":"/data/exports"}}`.
  Field constraints (Hibernate Validator) and details missing for the
  type, or given for another type, are a 400 with `{"error":"..."}`; a
  name the profile already uses is a 409: the row is flushed in the
  call, and the index's refusal (SQLSTATE 23505) is answered, so a race
  has one winner.
- `DELETE /api/datasources/{id}` removes one (204; 404 when there is none).

An answer: the entity's fields, the type as its JSON name, and the
details of its type, without secrets:
`{"id":1,"name":"warehouse","type":"database","description":null,"createdAt":"...","createdBy":"alice@example.com","createdByName":"Alice","database":{"engine":"postgresql","host":"db","port":5432,"database":"dw","username":"u","passwordSet":true}}`.

`GET /api/profile` counts the profile's.

## Development data

In dev mode the Flyway location `db/devdata` ([api.md](api.md)) seeds
HealthHub's PostgreSQL as a data source named HealthHub in every
profile, so the dashboard has one to show and the catalogue something to
read; prod and tests get none.

## Migration

`V2__profiles_and_encrypted_access.sql` replaced the clear columns
(`db_*`, `s3_*`, `fs_path`) with `profile_id` and `access`, and the
index on `lower(name)` with the one per profile. The rows from before
had no owner and their details in clear, and SQL has no key to encrypt
them with, so the migration deletes them.
`V3__drop_hibernate_unique_name.sql` drops the global unique constraint
on the name that Hibernate generated on databases from before Flyway.

## Known limitations

- No update: remove and add again.
- Nothing connects to a source yet, and OpenMetadata knows nothing of them.
