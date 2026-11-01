# Catalogue and time series

datyx learns a customer's data without the customer changing anything
for it: it reads what a database says about itself into OpenMetadata,
the catalogue, and people (later, a tool that suggests) say there what
the columns are to a forecast, with tags. datyx reads the tags back to
know which tables are time series, and how to train on them (DeepAR
first). Code in `datyx-api/src/main/java/datyx/catalog/`, the
OpenMetadata client in `datyx/openmetadata/`.

```
customer's database ──JDBC metadata──▶ datyx ──PUT──▶ OpenMetadata
                                                 ▲         │ tags, properties
                     people (OpenMetadata's UI) ─┘         ▼
                     PUT .../timeseries ───────────▶ GET .../timeseries ──▶ training
```

## Reading a source into the catalogue

`POST /api/datasources/{id}/catalog` connects to a database source with
its own access details (decrypted in the API, [data-sources.md](data-sources.md))
and reads, through JDBC's `DatabaseMetaData` and nothing specific to the
source, every table, view, materialized view and partitioned table
outside the system schemas: columns in order with their type,
nullability and comment, and the primary key (`SchemaReader`). No rows
are read. It then writes them to OpenMetadata, one create-or-update PUT
each:

- a database service named `datyx-ds-{id}` (unique across profiles;
  its display name is the source's name, its description the source's),
  of type `Postgres`, **with no connection details**: OpenMetadata runs
  no ingestion here and never gets the source's credentials;
- the database, by the source's database name, its schemas, and its
  tables (`Regular`, `View`, `MaterializedView`, `Partitioned`), each
  column with OpenMetadata's data type (`ColumnTypes`: from the JDBC type,
  or the database's type name where that says more: `text`,
  `timestamptz`, `jsonb`, `uuid`...), its type name as shown, a
  `PRIMARY_KEY` or `NOT_NULL` constraint, a composite primary key as a
  table constraint, and the comments as descriptions.

It answers `{"service":"datyx-ds-1","database":"datyx-ds-1.healthhub",
"schemas":["public"],"tables":6,"columns":69,"removed":[]}`. Running it
again updates the same entities: what people added in OpenMetadata
(tags, descriptions where the source has no comment, owners) stays, and
a table the source no longer has is soft-deleted (`removed`), and comes
back if it does again. Deleting the data source removes its service and
everything under it from OpenMetadata, best effort: a catalogue that
can't be reached is logged and the source is deleted anyway.

`GET /api/datasources/{id}/catalog` answers the tables as OpenMetadata
has them: `fqn`, `schema`, `name`, `type`, `description`, each column's
`name`, `dataType`, `constraint` and `tags` (tag FQNs), `constraints`
(the composite primary key) and `properties` (the custom properties).
Before a first sync, no tables.

Only database sources have a catalogue, and only PostgreSQL ones so far
(the one JDBC driver the API carries): an S3 bucket, a folder or another
engine is a 400. A source that can't be read (down, wrong password) is a
502 `the data source can't be read: ...`; OpenMetadata failing is a 502
`OpenMetadata ...` with its own message. All of them within the caller's
profile, a 404 for another's source, and no database transaction is held
while datyx talks to either.

## The TimeSeries vocabulary

datyx keeps in OpenMetadata, and makes on the first sync or tagging when
missing (`ensureVocabulary`), a classification, `TimeSeries`, whose tags
are the roles a column can have in a forecast. They name the model's
inputs in general terms; each tag's description says the DeepAR field
it becomes. A column can have more than one (a key that is also a
static category).

| Tag | What the column is | DeepAR (GluonTS) |
|---|---|---|
| `TimeSeries.Timestamp` | The time index; one per table, a date or timestamp | `start` and the position of each value |
| `TimeSeries.Target` | The value to forecast; one per table, a number | `target` |
| `TimeSeries.SeriesKey` | Which series a row belongs to; the key columns together name one series; none: one series | `item_id` |
| `TimeSeries.StaticCategorical` | A category that holds for a whole series (a hospital, a region) | `feat_static_cat` |
| `TimeSeries.StaticReal` | A number that holds for a whole series (a capacity) | `feat_static_real` |
| `TimeSeries.KnownCovariate` | A number over time known ahead, for the hours to forecast too (a schedule, a holiday) | `feat_dynamic_real` |
| `TimeSeries.PastCovariate` | A number over time known only once observed (a related count) | `past_feat_dynamic_real`, where supported |

### Groups: more than one series in a table

A table can hold several datasets to train on, each a **group** of roles
with a name. The tags above are the `default` group's. Another group's
roles are the same tags under the group's own tag:
`TimeSeries.acute.Target` is the `acute` group's Target, a child tag of
`TimeSeries.acute`, which datyx makes, with a child per role, the first
time a group is set (`ensureGroup`). The groups share the table's
columns, frequency and missing rows, and each is read and checked as a
series of its own, so one column can be every group's Timestamp, a
Target in one group and a PastCovariate in another. A group's name is
letters, digits, `_` and `-`, up to 64; `default` names the group of the
tags without one, and a role's name (in any case) can't be a group's.
A tag under a group that isn't a role, or the group's tag itself on a
column, isn't read.

And two custom properties of the table entity, strings:

- `timeSeriesFrequency`: how often rows come, as a pandas offset
  (`15min`, `1h`, `1D`, `1W`, `1MS`...). Required.
- `timeSeriesMissing`: what a missing row means: `zero` (nothing
  happened: counts, where a quiet hour has no row) or `unknown` (not
  observed; DeepAR takes it as a gap). `unknown` when not set.

People set them in OpenMetadata's UI (a column's tags, the table's
Custom Properties tab), or through datyx:

`PUT /api/datasources/{id}/timeseries` with a table (its name,
`schema.table`, or its FQN), a group (`default` when left out) and its
roles:
`{"table":"public.admissions_hourly","group":"acute","timestamp":"hour_start",
"target":"acute_admissions","seriesKey":["run_id","hospital_id"],
"staticCategorical":["hospital_id"],"staticReal":[],"knownCovariates":[],
"pastCovariates":[],"frequency":"1h","missing":"zero"}`. It replaces the
group's tags on the table's columns with these (other tags, other
groups' too, stay) and sets the table's two properties, removing one
left out: they are every group's. A group with no roles left is gone
from the table (its tags stay in the classification). A column the
table doesn't have, or a name that can't be a group's, is a 400, a table
the catalogue doesn't have a 404. Nothing is patched when nothing
changes. It answers the group read as a time series (below). This is
the call a tool that suggests the roles will make.

## Time series

`GET /api/datasources/{id}/timeseries` answers every group of every
table of the source, read as a time series (`TimeSeries.Spec`): a group
is there when a column is tagged with one of its roles, a table's
`default` group first, then the others as its columns name them:

```json
{"service":"datyx-ds-1","series":[{
  "table":"datyx-ds-1.healthhub.public.admissions_hourly","schema":"public","name":"admissions_hourly",
  "group":"default","timestamp":"hour_start","target":"admissions","seriesKey":["run_id","hospital_id"],
  "staticCategorical":["hospital_id"],"staticReal":[],"knownCovariates":[],"pastCovariates":[],
  "frequency":"1h","missing":"zero","ready":true,"problems":[]},
 {"table":"datyx-ds-1.healthhub.public.admissions_hourly","schema":"public","name":"admissions_hourly",
  "group":"acute","timestamp":"hour_start","target":"acute_admissions",...}]}
```

A series is the table and the group together. `ready` when there are
no `problems`, which say in words what to fix, of the group's own tags
(`no column is tagged TimeSeries.acute.Target`):
no Timestamp or Target, or more than one; a Timestamp that isn't a date
or timestamp; a Target, StaticReal or covariate that isn't a number; a
Timestamp or Target that also has another role; a column both
KnownCovariate and PastCovariate; no frequency, or one that isn't a
pandas offset; a `timeSeriesMissing` other than `zero` or `unknown`.

## HealthHub, as a customer

In development the HealthHub data source (seeded, [data-sources.md](data-sources.md))
is the example. HealthHub aggregates its admissions per hospital and
simulated hour into `admissions_hourly` (HealthHub's own Flink job, in
its folder), and datyx knows nothing of it beyond the catalogue: one
sync, then the roles above, by datyx's PUT or by hand in OpenMetadata.
The run is part of the series key because each HealthHub start replays
the simulated calendar from day 1. Three groups can train on it:
`default` forecasting `admissions`, `acute` forecasting
`acute_admissions` and `chronic` forecasting `chronic_admissions`, each
with the same `hour_start`, series key and static category.

## Signing in to OpenMetadata

`OpenMetadataSession`: a bot's token when `DATYX_OPENMETADATA_TOKEN` is
set; else basic authentication with `DATYX_OPENMETADATA_EMAIL` and
`DATYX_OPENMETADATA_PASSWORD` (`POST /api/v1/auth/login`, the password
in base64), the stack's built-in admin by default (`.env.example`),
kept until a minute before it expires and renewed, with the call tried
once more, when OpenMetadata answers 401. The client reads OpenMetadata's
answers leniently (`LenientJson`): an entity type's schema comes as a
string with raw line breaks.

## Tests

`TimeSeriesTest`, no server: a tagged table read as a ready series, the
problems of a badly tagged one, the frequency required and missing rows
unknown by default, a table's groups read as series of their own (with
their own problems), groups' names and tags, the roles' patch (the
group's tags replaced, other tags and other groups' kept, unchanged
columns left alone whatever the order of their tags, the properties set
and removed) and a column the table lacks refused, the type mapping,
quoted FQNs.
`CatalogResourceTest`, against the Dev Services Postgres standing in for
a source: `SchemaReader` reads a schema's table, view, column order,
types, comments and composite key, and no system schema; an S3 source is
a 400; a wrong password and an unreachable OpenMetadata are 502s; an
unknown source is a 404; deleting a source doesn't wait on the catalogue.
OpenMetadata itself isn't started for the tests.

## Known limitations

- PostgreSQL sources only; another engine needs its JDBC driver.
- Nothing reads rows yet: training on a series (DeepAR on GraalPy) is
  the next step, and will fill the missing hours by `timeSeriesMissing`.
- One Target per group; a table with two values to forecast is two
  groups.
- A group can't be renamed: set its roles under the new name, then
  empty the old one. Its tags stay in the classification once emptied.
- No suggestion of roles yet: they are set by hand or by the PUT.
- OpenMetadata keeps a composite key's columns in its own order, not
  the key's.
- A data source deleted while OpenMetadata was down leaves its service
  there (logged).
