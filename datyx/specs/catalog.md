# Catalogue and time series

datyx learns a customer's data without the customer changing anything
for it: it reads what a database or a Kafka cluster says about itself
into OpenMetadata, the catalogue, and people (later, a tool that suggests) say there what
the columns are to a forecast, with tags. datyx reads the tags back to
know which tables are time series, which algorithms train on each
(DeepAR, XGBoost, or both) and how, and OpenMetadata tells datyx, through
a webhook, when a group is switched on. Every column and every field of
a record also gets a PII classification, in the GDPR's terms, from its
name ([Personal data](#personal-data-gdpr)). Code in
`datyx-api/src/main/java/datyx/catalog/`, the OpenMetadata client in
`datyx/openmetadata/`.

```
customer's database ──JDBC metadata──▶ datyx ──PUT──▶ OpenMetadata
customer's Kafka ─topics, latest records─┘
                                                 ▲         │ tags, properties
                     people (OpenMetadata's UI) ─┘         ▼
                     PUT .../timeseries ───────────▶ GET .../timeseries ──▶ training

  OpenMetadata ──webhook: a table's tags changed──▶ POST /api/catalog/openmetadata-events
                                                    ──▶ group_event ──▶ a run per algorithm
```

## Reading a database into the catalogue

`POST /api/datasources/{id}/catalog` connects to a database source with
its own access details (decrypted in the API, [data-sources.md](data-sources.md))
and reads, through JDBC's `DatabaseMetaData` and nothing specific to the
source, every table, view, materialized view and partitioned table
outside the system schemas: columns in order with their type,
nullability and comment, and the primary key (`SchemaReader`). It then
writes them to OpenMetadata, one create-or-update PUT each:

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
  table constraint, and the comments as descriptions;
- each table's quality ([Quality](#quality)): its profile, and the
  checks its schema implies as test cases with their results.

It answers `{"service":"datyx-ds-1","database":"datyx-ds-1.healthhub",
"schemas":["public"],"tables":8,"columns":101,"personal":50,"special":32,
"tests":67,"failed":0,"failing":[],"removed":[]}`: `personal` counts the
columns holding personal data, `special` those of a special category
([Personal data](#personal-data-gdpr)), `tests` the checks run and
`failed` those that failed, `failing` the tables with a failed check.
Running it again updates the same entities: what people added in
OpenMetadata (tags, descriptions where the source has no comment,
owners, domains) stays, and so do the data products and the
certification, which a PUT would clear: read before it, they go back in
it or in a patch after it. A table the source no longer has is
soft-deleted (`removed`), and comes back if it does again. The database
and its schemas keep their descriptions and data products the same way.
Deleting the data source removes its service and
everything under it from OpenMetadata, best effort: a catalogue that
can't be reached is logged and the source is deleted anyway.

`GET /api/datasources/{id}/catalog` answers the tables as OpenMetadata
has them: `fqn`, `schema`, `name`, `type`, `description`, each column's
`name`, `dataType`, `constraint` and `tags` (tag FQNs), `constraints`
(the composite primary key) and `properties` (the custom properties).
Before a first sync, no tables.

## Reading a Kafka cluster into the catalogue

The same `POST /api/datasources/{id}/catalog` on a Kafka source
connects with its servers, protocol and SASL sign-in (`StreamReader`,
Kafka's own client, `quarkus-kafka-client`) and reads every topic that
isn't internal (none starting with `__`): its partitions, replication
factor and settings (`cleanup.policy`, `retention.ms`,
`retention.bytes`, `max.message.bytes`, `min.insync.replicas`). Kafka
keeps no schema, and datyx has no schema registry to ask, so it reads
the latest 10 records of each partition, for 5 s at most, committed
ones only, joining no consumer group and committing nothing: the
fields of those that are JSON objects, merged newest first (a field
null in one record takes its type from another; nested objects and
arrays of objects keep their fields), each with OpenMetadata's type
(`STRING`, `INT`, `LONG`, `DOUBLE`, `BOOLEAN`, `RECORD`, `ARRAY`,
`NULL`). Only names and types go to OpenMetadata, never a value. It
writes:

- a messaging service named `datyx-ds-{id}`, of type `Kafka`, **with no
  connection details**, like a database's;
- each topic, with its partitions, replication factor, cleanup policies,
  retention (time and size, when limited), largest message, minimum
  in-sync replicas, the settings read as its `topicConfig`, and its
  message schema: `JSON`, the fields as `schemaFields` and a JSON Schema
  of them as `schemaText`.

It answers `{"service":"datyx-ds-2","topics":5,"fields":46,"sampled":4,
"personal":37,"special":13,"removed":[]}`: `fields` counts the topics'
top-level fields, `sampled` the topics with a record, `personal` and
`special` the top-level fields holding personal data and special
category data. Running it again keeps what people added (the
topic's description, a field's description and tags, its data products
and domains, sent back with the PUT; its certification, patched back);
a topic with no record keeps the schema OpenMetadata has; a
topic the cluster no longer has is soft-deleted (`removed`). Deleting
the source removes its messaging service and topics.

`GET /api/datasources/{id}/catalog` on a Kafka source answers
`{"service":...,"topics":[...]}`: each topic's `fqn`, `name`,
`description`, `partitions`, `replicationFactor`, `cleanupPolicies`,
`retentionTime` (ms) and `retentionSize` (bytes; null when unlimited),
`schemaType`, its `tags`, and `fields`: `name`, `dataType`, `tags` and a
record's `children`. Before a first sync, no topics. Topics have no time
series yet: `GET .../timeseries` answers none, and the PUT finds no
table.

## Personal data (GDPR)

Every sync tags every column of every table, and every field of every
topic's records, nested ones and the records holding them too, with
one tag of OpenMetadata's own `PII` classification, and those holding
personal data with one of its `PersonalData` classification too (both
ship with OpenMetadata and each allows one tag per column: `Pii`). It reads only
names, the table's or topic's, the column's and those of the records a
field is in, never a value, so nothing new leaves the source.

A column holds personal data (GDPR Art. 4(1): information relating to
an identified or identifiable natural person) only when its record is
about a person: the record's name says so (`patients`, `people.moves`,
a health encounter such as `admissions` or `admission_triage`, but not
a count of them, `admissions_hourly`), or one of its columns names one
(`person_id`, `customer_email`, `first_name`, `date_of_birth`). A care
center's `phone` and `address` are an organisation's, which the GDPR
doesn't cover (Recital 14). In a record about a person, the first that
applies:

| Category | What the name says | `PII` | `PersonalData` |
|---|---|---|---|
| Special category | Health, genetic, biometric, racial or ethnic origin, political opinions, religious or philosophical beliefs, trade union membership, sex life or orientation (Art. 9), criminal convictions and offences (Art. 10): `condition_code`, `complaint`, `diagnosis`, `religion`, `criminal_record`. In a health care record (a patient's, or a health encounter's) every other fact is health data too, and so is a patient's number (Recital 35) | `Sensitive` | `SpecialCategory` |
| Direct identifier | A person's name, contact details, an identification number, financial data, an online identifier, precise location, an image, a secret: `person_name`, `name`, `email`, `home_address`, `ssn`, `iban`, `ip_address`, `lat`, `homeLon`, `password` | `Sensitive` | `Personal` |
| Quasi-identifier | Identifies the person with other data: `age`, `sex`, `date_of_birth`, `city`, `postal_code`, `occupation`, `nationality` | `NonSensitive` | `Personal` |
| Key | A key of the person's record (`id`, `person_id`, `event_id`, `hospital_id`): pseudonymous data is still personal (Art. 4(5), Recital 26) | `NonSensitive` | `Personal` |
| Personal | Anything else about the person (Art. 4(1)) | `NonSensitive` | `Personal` |

Anything else is `PII.None`, with no `PersonalData` tag. A name, an
address, a city or coordinates are a person's only when nothing but
person words and modifiers come with them (`shipping_address`,
`homeLat`), not another thing's (`store_address`, `hospital_name`). A
record or array field is the most protected of itself and its fields,
`holds ...` in its reason. Words match in snake, kebab or camel case,
singular or plural.

Each tag is written `Automated` and `Confirmed`, with its `reason`, the
GDPR article it rests on (`a person's name, which identifies them
directly (GDPR Art. 4(1))`), shown by OpenMetadata. They are
suggestions from names: a person's own tag (`Manual`, set in
OpenMetadata's UI) in `PII` or in `PersonalData` wins, and datyx leaves
that classification of the column alone on every sync after; datyx's
own are replaced when the names say something else. Since a PUT merges
tags and both classifications are mutually exclusive, the tags are
written after the PUT by one JSON Patch of the table or topic, only when
something changed. `GET .../catalog` answers them among the `tags`.

In HealthHub's catalogue: `admissions`, `admission_triage`,
`patient_days` and the topics `healthhub.admissions` and
`healthhub.people.moves` hold personal data, the conditions, complaints
and the encounters' facts special category data; `care_centers`,
`medical_conditions`, `complaint_templates`, `greetings` and the hourly
counts none.

## Quality

`Quality`: how good a table's data is, in OpenMetadata's own terms, read
by datyx with SQL aggregates (counts, bounds, lengths: never a row's
values) on a read-only connection, 60 s a query, and written to
OpenMetadata, which has no connection to run them itself:

- the table's **profile** (`PUT /api/v1/tables/{id}/tableProfile`), one
  query a table: its rows and columns, and per column its values, nulls
  and their share, distinct values (not for `json`, `bytea`, `xml`,
  arrays), a number's min, max, mean, sum and standard deviation, and a
  text's shortest and longest length;
- **checks**, each one of OpenMetadata's test definitions, as a test
  case of the table or column (by name, `{column}_{test}`, with a
  description in words; `PUT /api/v1/dataQuality/testCases`, which puts
  it in the table's own test suite) and its result at every sync
  (`Success` or `Failed`, in words, the values found and the rows passed
  and failed). The schema gives each table `columnValuesToBeNotNull` for
  every `NOT NULL` or key column, and `columnValuesToBeUnique` for a
  one-column primary key, or a `tableCustomSQLQuery` counting duplicates
  of a composite one. Others come from people, through a curation
  ([curation.md](curation.md)): `columnValuesToBeBetween` (`minValue`,
  `maxValue`, either), `columnValuesToBeInSet` (`allowedValues`, compared
  as text), `columnValuesToMatchRegex` (`regex`, PostgreSQL's) and
  `tableRowCountToBeBetween`. Another test definition is refused; a
  custom SQL check is datyx's own only.

OpenMetadata then shows each table's Data Quality (its tests passing),
its profile in Data Observability, and the tests' history.

## Which sources, and errors

Database sources, PostgreSQL ones so far (the one JDBC driver the API
carries), and Kafka clusters have a catalogue: an S3 bucket, a folder or
another engine is a 400. A source that can't be read (down, wrong
password, a broker that doesn't answer in 10 s) is a
502 `the data source can't be read: ...`; OpenMetadata failing is a 502
`OpenMetadata ...` with its own message. All of them within the caller's
profile, a 404 for another's source, and no database transaction is held
while datyx talks to either.

## The TimeSeries vocabulary

datyx keeps in OpenMetadata, and makes on the first sync or tagging when
missing (`ensureVocabulary`), a classification, `TimeSeries`, whose tags
are the roles a column can have in a forecast. They name the model's
inputs in general terms; each tag's description says what it becomes
to DeepAR and to XGBoost. A column can have more than one (a key that
is also a static category).

| Tag | What the column is | DeepAR (GluonTS) | XGBoost |
|---|---|---|---|
| `TimeSeries.Timestamp` | The time index; one per table, a date or timestamp | `start` and the position of each value | the cutoffs, and the windows before and after them |
| `TimeSeries.Target` | The value to forecast; one per table, a number | `target` | the label, its sum over the horizon after a cutoff; its sums before are features |
| `TimeSeries.SeriesKey` | Which series a row belongs to; the key columns together name one series; none: one series | `item_id` | whom a score is for: a row per series and cutoff |
| `TimeSeries.StaticCategorical` | A category that holds for a whole series (a hospital, a region) | `feat_static_cat` | a categorical feature |
| `TimeSeries.StaticReal` | A number that holds for a whole series (a capacity) | `feat_static_real` | a numeric feature |
| `TimeSeries.KnownCovariate` | A number over time known ahead, for the hours to forecast too (a schedule, a holiday) | `feat_dynamic_real` | features of the horizon ahead |
| `TimeSeries.PastCovariate` | A number over time known only once observed (a related count) | `past_feat_dynamic_real`, where supported | its sums over windows before the cutoff |

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
tags without one, and a role's or an algorithm's name (in any case)
can't be a group's. A tag under a group that isn't a role or an
algorithm, or the group's tag itself on a column, isn't read.

### Algorithms: what trains a group

Each group says which algorithms train on it with tags **on the
table**, not on a column: `TimeSeries.XGBoost` for the `default`
group, `TimeSeries.care.XGBoost` for the `care` group (a child tag of
`TimeSeries.care`, made with the group's roles). A group can have more
than one: `TimeSeries.care.XGBoost` and `TimeSeries.care.DeepAR` both
train on the care group's columns, each with runs of its own. A group
without any is DeepAR's, as every group was before there was a choice;
`TimeSeries.DeepAR` says it explicitly. What trains a group finds its
work by its algorithm's tag, through `GET .../timeseries?algorithm=XGBoost`
or OpenMetadata's search.

| Tag | What trains the group |
|---|---|
| `TimeSeries.DeepAR`, `TimeSeries.{group}.DeepAR`, or none | DeepAR (GluonTS): a probabilistic forecast of each series, step by step over the horizon (its `prediction_length`) |
| `TimeSeries.XGBoost`, `TimeSeries.{group}.XGBoost` | XGBoost: a score per series and cutoff, the Target summed over the horizon that follows, predicted from the series' static features, the Target and PastCovariates summed over windows before the cutoff, and the KnownCovariates ahead. The horizon is required |

And four custom properties of the table entity, strings:

- `timeSeriesFrequency`: how often rows come, as a pandas offset
  (`15min`, `1h`, `1D`, `1W`, `1MS`...). Required.
- `timeSeriesMissing`: what a missing row means: `zero` (nothing
  happened: counts, where a quiet hour has no row) or `unknown` (not
  observed; DeepAR takes it as a gap). `unknown` when not set.
- `timeSeriesHorizon`: how far ahead to predict, as a pandas offset
  (`24h`, `30D`, `4W`). DeepAR forecasts each step of it, and does
  without (its trainer picks); XGBoost scores the Target summed over it,
  and needs it.
- `timeSeriesRetrain`: how often datyx trains the table's groups again,
  a span (`1h`, `6h`, `1D`, `1W`) or `never`; `1D` when not set. See
  [training.md](training.md), which also sets it
  (`PUT /api/datasources/{id}/training`).

People set them in OpenMetadata's UI (a column's tags, the table's
Custom Properties tab), or through datyx:

`PUT /api/datasources/{id}/timeseries` with a table (its name,
`schema.table`, or its FQN), a group (`default` when left out), its
algorithms (`"algorithms":["XGBoost","DeepAR"]`, each `DeepAR` or
`XGBoost` in any case; or one as `"algorithm":"XGBoost"`, as before a
group could have more, `algorithms` winning when both are given; none
when left out) and its roles:
`{"table":"public.patient_days","group":"care","algorithms":["XGBoost"],
"timestamp":"day","target":"stay_hours","seriesKey":["run_id","person_id"],
"staticCategorical":["sex","city","hospital_id","chronic_condition"],
"staticReal":["age"],"knownCovariates":[],
"pastCovariates":["visits","acute_visits","chronic_visits"],
"frequency":"1D","missing":"zero","horizon":"30D"}`. It replaces the
group's tags on the table's columns with these (other tags, other
groups' too, stay), the group's algorithm tags on the table with one per
algorithm named (none when none is: DeepAR; the table's other tags
stay), and
sets the table's three properties, removing one left out: they are
every group's. A group with no roles left is gone from the table, its
algorithm tags too (its tags stay in the classification). An algorithm
other than DeepAR or XGBoost, or a name that can't be a group's, is a
400 before the catalogue is read; a column the table doesn't have a 400
too, a table the catalogue doesn't have a 404. Nothing is patched when nothing
changes. It answers the group read as a time series (below). This is
the call a tool that suggests the roles will make.

### Switching a group off

A group can be switched off with a tag on its table, as its algorithm is
named: `TimeSeries.Disabled` for the `default` group,
`TimeSeries.chronic.Disabled` for `chronic` (a child tag of the group's,
made with its roles and algorithms; `Disabled` can't name a group). datyx
doesn't train a group switched off ([training.md](training.md)), whose
spec says `"enabled": false`; removing the tag switches it on, and that
removal is what trains it, a run per algorithm of the group: in
OpenMetadata's UI (the table's tags, where the change is in the table's
version history: who, when, which version), whose webhook tells datyx
(below), or through datyx:

`PUT /api/datasources/{id}/timeseries/enabled` with
`{"table":"public.admissions_hourly","group":"chronic","enabled":false}`
(the table as `PUT .../timeseries` takes it; the `default` group when
none) adds the group's Disabled tag to the table, or removes it, the
table's other tags kept, nothing patched when it already is, and answers
the group read as a time series with `event`, the switch it kept
(`{"id":7,"runIds":[41,42]}`; null when the group already was on or
off). Switched on, it queues the group's runs itself, one per
algorithm, an `enabled` run each, so they never wait on the webhook;
OpenMetadata's post of the same change, seconds later, queues nothing
more. Switched off, the trainer notes it, so a switch off and on again
within minutes counts even when OpenMetadata merges one user's quick
changes into one version. A table or group the catalogue doesn't have
is a 404, a name that can't be a group's or no `enabled` a 400. The
dashboard's switch on each group is this call. A group with no roles
left loses its Disabled tag with its algorithms'.

### OpenMetadata's webhook: switches as they happen

datyx keeps an **event subscription** in OpenMetadata (`CatalogEvents`),
named `datyx-catalog-events` (`DATYX_OPENMETADATA_SUBSCRIPTION`), made a
few seconds after start with a create-or-update
`PUT /api/v1/events/subscriptions`, and made again at the minute's look
while OpenMetadata can't be reached, or when the subscription is gone or
posts elsewhere:

```json
{"name":"datyx-catalog-events","displayName":"datyx: tables switched on and off","description":"...",
 "alertType":"Notification","enabled":true,"batchSize":10,"retries":3,"pollInterval":5,
 "resources":["table"],
 "input":{"filters":[{"name":"filterByEventType","effect":"include","prefixCondition":"AND",
   "arguments":[{"name":"eventTypeList","input":["entityUpdated"]}]}],"actions":[]},
 "destinations":[{"category":"External","type":"Webhook","timeout":10,"readTimeout":12,
   "config":{"endpoint":"http://host.docker.internal:9900/api/catalog/openmetadata-events","httpMethod":"POST",
     "authType":{"type":"bearer","secretKey":"..."}}}]}
```

Every update of a table is posted (OpenMetadata 2.0.7 filters a table's
events by type, not by field: it refuses `filterByFieldChange` for
tables, so datyx reads the tags itself), to
`datyx.openmetadata.callback-url` (`DATYX_OPENMETADATA_CALLBACK_URL`):
in dev, and from `scripts/api.sh` in every mode,
`http://host.docker.internal:{port}/api/catalog/openmetadata-events`
(OpenMetadata runs in Docker, the API on the host); in Docker Compose
the `api` service, `http://api:9900/...`; unset in prod, no subscription,
the trainer's minute check alone. An API listening on localhost refuses
a request whose Host header isn't a localhost name (Quarkus's host
validation, against DNS rebinding), so `CallbackHostConfigSourceFactory`
allows the callback's host beside them
(`quarkus.http.host-validation.allowed-hosts` =
`localhost,127.0.0.1,[::1],host.docker.internal`), and no other.

`POST /api/catalog/openmetadata-events` is open to OpenMetadata without
a sign-in ([auth.md](auth.md)) and **authenticated by its signature**:
OpenMetadata signs each post with the subscription's `secretKey`, the
header `X-OM-Signature: sha256=` and the **base64** (not hex) of the
HMAC-SHA256 of the raw body, as OpenMetadata 2.0.7 was seen to send it,
which datyx compares in constant time. The secret is
`datyx.openmetadata.webhook-secret` (`DATYX_OPENMETADATA_WEBHOOK_SECRET`),
or one datyx draws at start (32 random bytes) and gives OpenMetadata with
the subscription; OpenMetadata keeps it encrypted and never answers it.
Without the header or with a wrong one, a 401 and nothing more is read;
a post over 1 MB, a 413; not JSON, a 400. Neither the secret nor a post
is logged. A post is one change event (or an array of them), as
OpenMetadata 2.0.7 sends it, with the headers `X-OM-Signature`,
`X-Auth-Params-Email` (the OpenMetadata user it acts for) and
`Content-Type: application/json`:

```json
{"id":"4c9cd012-...","eventType":"entityUpdated","entityType":"table","entityId":"595eaee3-...",
 "entityFullyQualifiedName":"datyx-ds-1.healthhub.public.admissions_hourly",
 "previousVersion":0.1,"currentVersion":0.6,"userName":"admin","timestamp":1793532978432,
 "changeDescription":{"fieldsAdded":[],"fieldsUpdated":[],
   "fieldsDeleted":[{"name":"tags","oldValue":"[{\"tagFQN\":\"TimeSeries.chronic.Disabled\",...}]"}],
   "previousVersion":0.5},
 "entity":"{\"id\":\"595eaee3-...\",\"name\":\"admissions_hourly\",\"version\":0.6,\"tags\":[],\"columns\":[...],\"service\":{\"type\":\"databaseService\",\"name\":\"datyx-ds-1\"},...}"}
```

A table of one of datyx's database sources (its service `datyx-ds-{id}`,
exactly as datyx names it, `datyx-ds-07` not source 7's, and the table's
FQN under it) whose own tags (the field `tags`, not `columns.{name}.tags`; the values
JSON or its text) lost a group's Disabled tag switched the group **on**;
gained it, **off**; `fieldsUpdated` compares the old tags with the new.
Another entity, another service, a source datyx doesn't have, a column's
tag or any other tag switches nothing; nor does a group the table, read
again, no longer has (removing a group's roles removes its Disabled tag
with them: no switch on, no run). Each switch is kept; a switch on
reads the group again from OpenMetadata (from the post's `entity` when
OpenMetadata can't be read) and queues one run per algorithm, its note
naming the change: `TimeSeries.chronic.Disabled removed in OpenMetadata
(table version 0.6, by admin, 2026-11-01 11:38 UTC; webhook)`. It
answers `{"recorded":[{"eventId":3,"runIds":[3]}]}`, empty when the post
told datyx nothing new.

### Switches kept

`GroupEvent`, table `group_event` (migration `V8__group_events.sql`):
the source (removing it removes them), the table's FQN, the group,
`enabled`, `via` (`openmetadata-webhook`; `datyx-api`, datyx's switch;
`poll`, the trainer's minute check, kept only when it queued a run),
`om_version` (the table's version after the change), `om_event_id`
(OpenMetadata's event id and the group), `changed_by`, `changed_at` (the
event's time: OpenMetadata merging one user's quick changes may give a
switch the time of the version it returns to), `received_at`, and
`run_ids`, the runs it queued, comma-separated. A run queued by a
switch names it (`training_run.group_event_id`, `eventId` in its view).
One switch queues its runs once, whichever path learns of it first
([training.md](training.md)): an OpenMetadata event kept already, or the
same switch (on or off, at the same version of the table) kept since the
switch began (its change's time; for datyx's switch, when the call
began; for a switch on, when datyx last knew the group off, if later),
is known and kept no more. One kept before isn't the same: OpenMetadata,
merging one user's quick changes, can give a table a version it had
before. A switch off told after a switch on datyx kept since, while the
table reads the group on (the webhook's post of an off that datyx's
switch, or a later change, has undone already), is passed over: kept,
it would make that switch on's runs look older than the off and queue
them again.

`GET /api/catalog/events?limit=50` (1 to 200), secured like the
sources, answers the latest switches of the caller's sources, the
newest first:

```json
{"events":[{"id":3,"sourceId":1,"source":"HealthHub","table":"datyx-ds-1.healthhub.public.admissions_hourly",
  "name":"admissions_hourly","group":"chronic","enabled":true,"via":"openmetadata-webhook","version":"0.6",
  "by":"admin","at":"2026-11-01T11:38:56.235Z","receivedAt":"2026-11-01T11:38:59.102Z","runIds":[3]}]}
```

`by` is OpenMetadata's user for the webhook and the check; for datyx's
switch, the caller (their email) when signed in, else the OpenMetadata
user datyx acts as.

## Time series

`GET /api/datasources/{id}/timeseries` answers every group of every
table of the source, read as a time series (`TimeSeries.Spec`): a group
is there when a column is tagged with one of its roles, or the table
with its algorithm, a table's `default` group first, then the others as
its tags name them. `?algorithm=XGBoost` (or `DeepAR`, in any case)
answers only the groups that algorithm trains (among others), what a
trainer asks; an algorithm there isn't is a 400. `algorithms` lists a
group's algorithms, XGBoost first (`["DeepAR"]` when the table names
none), and `algorithm` is the first of them, as before a group could
have more than one.

```json
{"service":"datyx-ds-1","series":[{
  "table":"datyx-ds-1.healthhub.public.admissions_hourly","schema":"public","name":"admissions_hourly",
  "group":"default","algorithm":"DeepAR","algorithms":["DeepAR"],"enabled":true,"timestamp":"hour_start","target":"admissions","seriesKey":["run_id","hospital_id"],
  "staticCategorical":["hospital_id"],"staticReal":[],"knownCovariates":[],"pastCovariates":[],
  "frequency":"1h","horizon":null,"missing":"zero","ready":true,"problems":[]},
 {"table":"datyx-ds-1.healthhub.public.patient_days","schema":"public","name":"patient_days",
  "group":"care","algorithm":"XGBoost","algorithms":["XGBoost"],"enabled":true,"timestamp":"day","target":"stay_hours","seriesKey":["run_id","person_id"],
  "staticCategorical":["sex","city","hospital_id","chronic_condition"],"staticReal":["age"],"knownCovariates":[],
  "pastCovariates":["visits","acute_visits","chronic_visits"],"frequency":"1D","horizon":"30D","missing":"zero",
  "ready":true,"problems":[]}]}
```

A series is the table and the group together. `ready` when there are
no `problems`, which say in words what to fix, of the group's own tags
(`no column is tagged TimeSeries.acute.Target`):
no Timestamp or Target, or more than one; a Timestamp that isn't a date
or timestamp; a Target, StaticReal or covariate that isn't a number; a
Timestamp or Target that also has another role; a column both
KnownCovariate and PastCovariate; no frequency, or one that isn't a
pandas offset; a `timeSeriesMissing` other than `zero` or `unknown`;
with XGBoost among its algorithms, no horizon; a
horizon that isn't a pandas offset; a `timeSeriesRetrain` neither a span
nor `never`. The spec answers `retrain` as the table sets it (null when
not).

## HealthHub, as a customer

In development the HealthHub data source (seeded, [data-sources.md](data-sources.md))
is the example. HealthHub aggregates its admissions per hospital and
simulated hour into `admissions_hourly` (HealthHub's own Flink job, in
its folder), and datyx knows nothing of it beyond the catalogue: one
sync, then the roles above, by datyx's PUT or by hand in OpenMetadata;
in development, datyx's curation of HealthHub gives a table without
them the roles below on its first pass ([curation.md](curation.md)).
The run is part of the series key because each HealthHub start replays
the simulated calendar from day 1. Three groups can train on it:
`default` forecasting `admissions`, `acute` forecasting
`acute_admissions` and `chronic` forecasting `chronic_admissions`, each
with the same `hour_start`, series key and static category, all three
DeepAR's. `chronic` is switched off by default
(`TimeSeries.chronic.Disabled` on the table, set through datyx's switch
in development's OpenMetadata): switching it on queues its run, which
trains it with DeepAR ([training.md](training.md)).

HealthHub's view `patient_days` (in its folder) is a series per patient:
a row per run, person and simulated day with a visit, the day's visits
and hours of hospital care, and the person's facts. Its `care` group
scores each patient's care to come with XGBoost: the hours of care
(`stay_hours`) summed over the next 30 days (`timeSeriesHorizon` `30D`,
a parameter of the table), from the patient's age, sex, city, hospital
and chronic condition and their visits and hours before the cutoff. A
patient is the run and the person (`run_id`, `person_id`); a day without
a visit is zero (`timeSeriesMissing` `zero`), at a frequency of `1D`.

HealthHub's view `occupancy_hourly` (in its folder) is a series per care
center: a row per run, care center and simulated hour with someone in
care, how many. Its `default` group is DeepAR's, tagged as
`admissions_hourly`'s is: Target `occupancy`, a series per `run_id` and
`hospital_id` (the care center a category), hourly, missing hours zero,
no horizon (24 hours). HealthHub's care center view plots its forecast.

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
their own problems), groups' names and tags, a group's algorithm and
the horizon read from the table (DeepAR without a tag, XGBoost wanting
a horizon, both algorithms a group's, XGBoost first, a group with only
its algorithm listed), algorithms' names (one, several, each once), the
roles' patch (the group's tags
replaced, other tags and other groups' kept, unchanged columns left
alone whatever the order of their tags, the group's algorithm tags set
(one per algorithm, `algorithms` winning over `algorithm`),
replaced and removed beside the table's other tags, the properties set
and removed, nothing patched when nothing changes, a group's Disabled
tag kept by new roles and gone with its last role) and a column the
table lacks or an algorithm there isn't refused, the type mapping,
quoted FQNs; a group switched off by its Disabled tag (no group of its
own, `Disabled` no group's name), the switch's patch (added, removed,
another group's kept, a group the table hasn't refused), and the table's
history in OpenMetadata read for the version that removed it.
`CatalogEventsTest`, no server: OpenMetadata's change events read for
the groups they switched (on, off, both at once, an unrelated tag, a
column's tag, another service, a service name that isn't datyx's own
for its id (`datyx-ds-07`), a table outside its service, a topic, still
off, unreadable values),
the signature (good, missing, without its prefix, another secret,
another body, a known base64 value), the host the API lets OpenMetadata
post to, and the subscription asked for.
`CatalogResourceTest`, against the Dev Services Postgres standing in for
a source: `SchemaReader` reads a schema's table, view, column order,
types, comments and composite key, and no system schema; an S3 source is
a 400; a wrong password, a Kafka broker that isn't there and an
unreachable OpenMetadata are 502s, an algorithm there isn't a 400
(among several too, before the catalogue is read); an
unknown source is a 404; deleting a source doesn't wait on the
catalogue. `StreamReaderTest`, no cluster:
the fields and types learnt from JSON records, nested ones included,
records merged newest first (a null's type from another record, fields
only older ones have added, what isn't a JSON object skipped), the SASL
sign-in only for a SASL protocol, its user and password quoted; a topic
as the catalogue writes it, keeping a description and field tags people
added, and the schema it had when no record was read. OpenMetadata and
Kafka themselves aren't started for the tests. `PiiTest`, no server:
names split into words, HealthHub's admissions classified column by
column, a patient's number as health data, records of things and of
counts holding none, a column that names a person making its record
personal, nested fields and the record holding them, a person's tags
kept and datyx's replaced (other classifications' kept), and the patch
`Catalog.classify` sends, with nested paths, empty once written.
`QualityTest`, no server: the checks a schema implies (a composite key
by SQL), the profile's query by type, quoting, test cases, results and
profiles as OpenMetadata takes them, checks read from JSON and an
unknown test refused. `CatalogResourceTest` also profiles a table on the
Dev Services Postgres and runs each kind of check on it, passing and
failing.

## Known limitations

- PostgreSQL sources only; another engine needs its JDBC driver.
- A topic's fields are learnt from its latest records, JSON ones only:
  Avro or Protobuf records, a schema registry, and the records' keys
  aren't read; a field the sampled records don't have is missing, and a
  number's type is what the sampled values fit (`INT` until one doesn't).
- Kafka over SSL trusts the JVM's certificate authorities only: no
  truststore or client certificate of the source's own yet.
- DeepAR trains on the Target, the series and its StaticCategoricals
  ([training.md](training.md)); its covariates and StaticReals are tagged
  but not used yet.
- The webhook's subscription posts every update of every table, and
  datyx reads each for its tags: OpenMetadata 2.0.7 offers no filter by
  field for tables. Several API instances against one OpenMetadata each
  need a subscription name of their own.
- A secret drawn at start changes at each start, and the subscription is
  updated with it: posts OpenMetadata retries across a restart are
  refused (the minute's check catches up). Set
  `DATYX_OPENMETADATA_WEBHOOK_SECRET` to keep one.
- The horizon is the table's, shared by its groups like the frequency:
  groups of one table that need different horizons are two tables (or
  views).
- One Target per group; a table with two values to forecast is two
  groups.
- A group can't be renamed: set its roles under the new name, then
  empty the old one. Its tags stay in the classification once emptied.
- No suggestion of roles yet: they are set by hand or by the PUT.
- OpenMetadata keeps a composite key's columns in its own order, not
  the key's.
- Personal data is told from names only, in English: a column named
  for something else (`notes` holding a diagnosis), or in another
  language, is missed, and a word can mislead (`client_id` of an OAuth
  client is taken for a person's). People correct a column in
  OpenMetadata, and their tag stays. No value is sampled to check, as
  OpenMetadata's own auto-classification would.
- The properties inside a `json` or `jsonb` column aren't read (no
  values are): the column is classified as a whole.
- A check's results are only as fresh as the latest sync: datyx runs no
  schedule of its own outside development ([curation.md](curation.md)).
  A test case of a column the source no longer has stays in
  OpenMetadata with its last result.
- The profile has no histograms, quartiles or medians, and a date's
  range isn't profiled.
- Criminal data (Art. 10) is tagged `PersonalData.SpecialCategory`,
  OpenMetadata having no tag of its own for it; the reason says Art. 10.
- Tables and topics themselves get no PII tag, only their columns and
  fields.
- A data source deleted while OpenMetadata was down leaves its service
  there (logged).
