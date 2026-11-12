# Data sources

The first entity of datyx: where data lives and how to reach it, owned
by the profile of whoever adds it ([profiles.md](profiles.md)). Users add
and remove them; a database or Kafka source is read into OpenMetadata, the
catalogue, on demand ([catalog.md](catalog.md)). Code in
`datyx-api/src/main/java/datyx/datasource/`.

## The entity

`DataSource` (table `data_source`): `id`, `profile` (`profile_id`, the
owner; cascade on delete), `name` (up to 100 characters, required,
unique within the profile whatever its case: a unique index on
`(profile_id, lower(name))`, made by the Flyway migration), `type`
(`database`, `s3`, `filesystem` or `kafka`; stored as `DATABASE`, `S3`,
`FILESYSTEM`, `KAFKA`), `description` (up to 500), `createdAt`, `createdBy` (the
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
- A **Kafka** cluster: `bootstrapServers` (`host:port`, comma-separated;
  blanks dropped), `securityProtocol` (`PLAINTEXT`, the default, `SSL`,
  `SASL_PLAINTEXT` or `SASL_SSL`; upper-cased), and with a SASL protocol
  `saslMechanism` (`PLAIN`, the default, `SCRAM-SHA-256` or
  `SCRAM-SHA-512`), `username` (required) and `password`. Another
  protocol or mechanism, a SASL protocol without a username, or a
  username, password or mechanism without one, is a 400.

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
  `{"name":"exports","type":"filesystem","filesystem":{"path":"/data/exports"}}`,
  `{"name":"stream","type":"kafka","kafka":{"bootstrapServers":"broker:9092","securityProtocol":"SASL_SSL","saslMechanism":"SCRAM-SHA-512","username":"u","password":"p"}}`.
  Field constraints (Hibernate Validator) and details missing for the
  type, or given for another type, are a 400 with `{"error":"..."}`; a
  name the profile already uses is a 409: the row is flushed in the
  call, and the index's refusal (SQLSTATE 23505) is answered, so a race
  has one winner.
- `DELETE /api/datasources/{id}` removes one (204; 404 when there is none),
  and its entry in the catalogue when it has one ([catalog.md](catalog.md)).

An answer: the entity's fields, the type as its JSON name, and the
details of its type, without secrets:
`{"id":1,"name":"warehouse","type":"database","description":null,"createdAt":"...","createdBy":"alice@example.com","createdByName":"Alice","database":{"engine":"postgresql","host":"db","port":5432,"database":"dw","username":"u","passwordSet":true}}`.

`GET /api/profile` counts the profile's.

## Development data

In dev mode (`datyx.devdata.enabled`, true in the dev profile alone)
every profile has HealthHub as two data sources (`DevData`): its
PostgreSQL, named HealthHub (database and user `healthhub`), and its
Kafka, plain text, named HealthHub Kafka, both added by `dev data`
(`createdByName`). So the dashboard has them to show and the catalogue
something to read, whoever calls; prod and tests get none. A profile has
them from the moment it exists:

- the profiles there at start, the Local one included, from the Flyway
  location `db/devdata` ([api.md](api.md));
- a profile made later, by someone's first sign-in, as it is made, in
  the same transaction (`ProfileMaker`, [profiles.md](profiles.md)).

Where HealthHub is comes from settings, so the same API reads it on a
laptop and where it is reached by name. An empty setting is its
default:

| Setting | Default | What |
|---|---|---|
| `DATYX_HEALTHHUB_DB_HOST` | `localhost` | the host of HealthHub's PostgreSQL |
| `DATYX_HEALTHHUB_DB_PORT` | `9803` | its port |
| `DATYX_HEALTHHUB_DB_PASSWORD` | HealthHub's development one | the `healthhub` user's password |
| `DATYX_HEALTHHUB_KAFKA` | `localhost:9804` | its Kafka's bootstrap servers |

The defaults are the ports HealthHub publishes on a laptop
(`HealthHub/.env.example`). The local Kubernetes cluster names
HealthHub's Services instead: `healthhub-postgres`, `5432` and
`healthhub-kafka:19092` (`k8s/api.yaml`,
[dev-environment.md](dev-environment.md)).

Once HealthHub's data initialization is done, datyx catalogues and
curates the sources by itself ([curation.md](curation.md)) and trains
their models ([training.md](training.md)): the profiles there at start
in the first pass, a profile made later from the next half-minute tick,
without waiting for the next pass.

## Migration

`V2__profiles_and_encrypted_access.sql` replaced the clear columns
(`db_*`, `s3_*`, `fs_path`) with `profile_id` and `access`, and the
index on `lower(name)` with the one per profile. The rows from before
had no owner and their details in clear, and SQL has no key to encrypt
them with, so the migration deletes them.
`V3__drop_hibernate_unique_name.sql` drops the global unique constraint
on the name that Hibernate generated on databases from before Flyway.
`V4__kafka_sources.sql` lets the type be `KAFKA`: V1's check on the
column named the three types before it.

## Known limitations

- No update: remove and add again.
- Only database sources, PostgreSQL ones, and Kafka clusters reach the
  catalogue; S3 buckets and folders are kept but nothing reads them.
- The development data's addresses are one HealthHub's, the same for
  every profile. In Docker Compose the API's container has no HealthHub
  at the defaults (its own localhost), and `compose.yaml` puts none on
  its network: the two sources are listed, and stay uncatalogued, until
  the `DATYX_HEALTHHUB_*` settings name a HealthHub the container
  reaches.
