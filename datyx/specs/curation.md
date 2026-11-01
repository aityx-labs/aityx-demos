# Curation

What a data steward says in OpenMetadata about a customer's data, beyond
what the source says about itself, written by datyx from a document:
who owns it, the business domain and data product it belongs to, the
glossary of its terms, its tiers, the descriptions a database, a schema
and Kafka topics don't carry, checks of its values, where it comes from,
a data contract per table, and the certification each table and topic
earns. In development, datyx curates HealthHub this way, so
OpenMetadata's console shows HealthHub at its best: every asset
described, owned, tiered, in context and checked. Code in
`datyx-api/src/main/java/datyx/catalog/` (`Curation`, `DevCatalog`),
HealthHub's document in
`datyx-api/src/main/resources/devdata/healthhub-catalog.json`.

## The document

`Curation.Doc`, JSON:

- `sources`: the data sources it is about, by name: a `database` and a
  `kafka` cluster, both in the same profile.
- `team`: the owner, an OpenMetadata team (`Group`) of that name; it
  owns every service, database, schema, table, topic, pipeline, the
  glossary, the data product and each contract.
- `domain` (with its `domainType`) and `dataProduct`: every asset goes
  into both (the services into the domain only).
- `glossary` and its `terms`, each with synonyms and related terms.
- `certification`: the tag a table or topic earns
  (`Certification.Gold`), and `termsOfUse`, every contract's.
- `database`: its description and tier (its schemas take the tier),
  and each schema's description.
- `tables`, by `schema.table`: the tier, the table's glossary terms,
  each column's terms, and `checks` (`Quality.Check`: a test definition,
  a column for a column's, parameters by OpenMetadata's names, a
  description in words of what a failure means, and a `key` telling
  apart checks of one test on one table, a custom SQL check's rule;
  [catalog.md](catalog.md#quality)). A custom SQL check
  (`tableCustomSQLQuery`) answers the rows that break a rule, a `SELECT`
  of the source's tables by their names; it passes when it answers none,
  or as many as its `operator` and `threshold` allow. One with `strategy`
  `COUNT`, operator `>=` and threshold 0 never fails: it is there for
  its number (information). A check the document can't hold (an unknown
  test or parameter, SQL that doesn't only read) makes the document
  unreadable.
- `topics`, by name: the description, tier, terms, and each field's
  description (a nested field by its dotted path).
- `timeSeries`: groups of TimeSeries roles to start a table with, as
  `PUT .../timeseries` takes them, and how often to retrain.
- `pipelines`: each with its pipeline service (`Flink`,
  `CustomPipeline`...), tasks, description and tier.
- `lineage`: edges between `table:schema.name`, `topic:name`, through a
  pipeline (`service.name`) or none, each with a description.

## Applying it

`Curation.apply`, on a database source and a Kafka source already
synced, writes the team, domain, data product, glossary and terms (the
related terms once all exist), then patches, changing only what
differs: the services' owners; the database's and schemas' description,
owners and tier; each table's owners, tier and terms (another tier
replaced, other tags kept, PII's too) and its columns' terms; each
topic's description, fields' descriptions, owners, tier and terms; the
pipelines with their owners and tier; the lineage; then puts every asset
in the domain and the data product. A table or topic the document
doesn't name is logged and left uncertified.

It runs the document's checks on each table (`Catalog.check`, beside
the schema's checks the sync ran), writing each test case only when it
is new or its description, parameters or mark changed, and every
result (a check that can't run fails with its error, and the others
run); then removes the table's test cases datyx set (those with its
mark, the tag `Datyx.Managed`, [catalog.md](catalog.md#quality)) that
neither the document nor the schema has any longer; others' test cases
stay, whatever their names. It gives a table the
document's roles for a group only when it has none of that group
(people's changes in OpenMetadata stay), and sets `timeSeriesRetrain`
only when unset. It puts in the domain and the data product only the
assets not in them yet: adding the database service again makes
OpenMetadata go through every table and test case it holds, which takes
longer than a call may (20 s and more).

**Certification**, earned at every curation: a table with a
description, every column described, an owner, a tier and every check
passing, or a topic with a description, every field (nested ones too)
described, an owner and a tier, gets the document's certification for a
year, renewed when within 30 days of expiring. One that lacks something
has the certification taken off, and the log says what it lacks.

**Data contracts**: each curated table gets one, made the first time
with the table's columns as they are then (name, type, constraint,
description), its test cases as the quality expected, the owners, the
terms of use, approved. Later curations keep its schema as agreed and
the test cases up to date, then validate it and write the result
(`PUT /api/v1/dataContracts/{id}/results`): the schema passes when the
source still has each of the contract's columns with the same type, the
quality when every test's latest result is a success; the contract is
kept when both pass. OpenMetadata can't validate it itself here: its
validation runs the tests through an ingestion pipeline, and this stack
has none.

It answers `Applied`: the certified FQNs, the uncertified with why, the
checks run and failed, and the test cases made, changed and removed.
The log says the same, with the contracts kept.

## In development: HealthHub

`DevCatalog`, dev mode only (`@IfBuildProfile("dev")`): at every start
(10 s after it), then every 30 s until a pass succeeds, then every
`datyx.dev-catalog.every` (10 minutes), so every check is set in
OpenMetadata (made, updated, the stale ones removed) and run, and
profiles and contracts follow the simulation:

1. It waits for HealthHub's data initialization: every table the
   document names is in HealthHub's database, described (HealthHub's
   API comments its schema at every start). Until then it logs why, once
   per reason. The first pass also waits, at most
   `datyx.dev-catalog.rows-wait` (5 minutes), for each table the
   document gives a minimum row count to have rows (a new HealthHub's
   admissions, Flink's first counts), so a fresh start doesn't judge
   empty tables; past that it checks them all the same, and an empty
   table that should have rows fails.
2. For each profile's seeded HealthHub sources
   ([data-sources.md](data-sources.md)), it syncs the database (profiles
   and schema checks included) and the Kafka cluster (when it can't be
   read, the curation goes on without its topics), then applies the
   document.
3. It logs one line per pass: `dev catalogue: HealthHub's checks set in
   OpenMetadata and run: 217 (80 of the schema, 137 of the document;
   test cases 0 new, 1 changed, 1 removed), 215 passed (or aborted,
   nothing to judge), 2 failed`.
4. It runs OpenMetadata's Data Insights (`DataInsightsApplication`), so
   the coverage reports (descriptions, owners, tiers) count the curation.

OpenMetadata unreachable, or refusing a call, is logged and tried again
in half a minute; another failure is logged and waits for the next
pass. `datyx.dev-catalog.enabled=false` turns it off.

With HealthHub's document, OpenMetadata shows: the Healthcare domain
and the HealthHub data product holding every asset; the HealthHub Data
team owning them; 18 glossary terms on the tables, columns and topics;
every asset described and tiered (Data Insights: 100% descriptions,
owners and tiers); 206 test cases on the nine curated tables (137 of
the document, 69 of the schema), each with its result; the tables
certified Gold whose checks all pass, and 4 topics; a contract per
table, kept while its tests pass; the Flink job and HealthHub's API
pipelines (simulation, admissions feed, triage) with the lineage from
the care centers and conditions through the topics to the tables and
the `patient_days` and `occupancy_hourly` views; and the TimeSeries
roles of `admissions_hourly` (`default`, `acute`, `chronic`),
`occupancy_hourly` (`default`) and `patient_days` (`care`, XGBoost).

**HealthHub's checks**, per table (the document's; the schema adds its
not-nulls and keys):

| Table | Checks | Besides ranges, sets, formats and lengths |
|---|---|---|
| `admissions` | 29 | event ids unique and carrying their row's person and day; a first visit is number 1; a person keeps one age, sex and city in a run; the hospital is a care center, under its name; the condition is in the seed, same name and type, and fits the person's age; an acute course stays within its visits; the template is one of the condition's; nothing recorded in the future; placeholders all filled; the ages' mean |
| `admission_triage` | 17 | a call within its timeouts (180 s: 10 s connecting, 60 s sending, 60 s reading); every triage has its admission; a level or an error, never both nor neither; a level comes with its wait, area, nurse's check and rules; the wait is its level's; the reference is the template's level; triaged after admitted; information: the triages off their reference |
| `admissions_hourly` | 19 | seven columns, those of its DeepAR groups there; acute and chronic add up to admissions; on the hour; the hospital is a care center; **no count beyond the admissions table's**, for each settled hour of every run with admissions (before the hour of its latest admission recorded two minutes ago or more; a generated history, without admissions, isn't compared): Flink counting more than the table holds is admissions the feed lost; information: the settled hours Flink counted short, which HealthHub's spec allows (a restarted job recounting the topic, an hour at the edge of its one-day retention rewritten lower, counts held back while the database is down) |
| `patient_days` | 15 | the columns of the care group; one row per run, person and day; visits add up; the hours fit the visits (1 to 72 a visit); the chronic condition is a chronic one of the seed, named when there are chronic visits; the hospital is a care center |
| `occupancy_hourly` | 14 | five columns, those of its DeepAR group there; one row per run, care center and hour; on the hour; the care center is one, under its name; everyone arriving is in care in their hour; no hour after the run's latest arrival; information: the hours above the largest capacity of the care center's kind |
| `care_centers` | 13 | keys unique and made of the source and its id; both coordinates or none, within the country; postal codes and websites well formed |
| `medical_conditions` | 20 | codes well formed; settings known; prevalence above zero; ages in order; a treatment length for an acute condition only; nine complaint templates each |
| `complaint_templates` | 8 | one per condition, visit and position; the condition is in the seed; placeholders are the simulation's |
| `greetings` | 2 | one row, the greeting |

On 2026-11-01's data two fail, both the data's: `admissions_hourly`
has 104 hours (runs `adf5309c`, 93, and `e313f013`, 11) counting
admissions that the `admissions` table doesn't have, bursts of up to 23
care centers in one simulated hour, events Flink counted from Kafka
that the feed never stored; and two care centers' websites aren't web
addresses (`http://http:\\www.cntt.com.br`, `http://app/intranet/`, from
CNES). Those two tables aren't certified, and their contracts aren't
kept, until the data is mended.

## Tests

`CurationTest`, no server: the tags written (a tier replaced, terms
added and quoted, other tags kept as they were, nothing patched when
they're there), what keeps an entity from its certification, nested
fields flattened, and HealthHub's document: it reads, its terms,
related terms, lineage ends, pipelines and time series tables all
exist, every topic is described, no em dashes. `HealthHubChecksTest`,
on the Dev Services Postgres: HealthHub's schema
(`src/test/resources/catalog/healthhub-fixture.sql`, the tables and
views of HealthHub's `lib/db.dart`) with a few rows of correct data;
the document curates every table and view of it, every check is on a
column there, a definition datyx runs, under a name of its own (the
schema's too), and passes; then defects (an age out of range, an event
id that isn't its row's, a renamed condition, a wait not its level's,
hourly counts above the admissions, an hour Flink counted that admissions
hasn't, a triage call past its timeouts, swapped coordinates, a missing template, an unknown
placeholder, a view counting ahead of the run) fail exactly the checks
meant for them, while an hour Flink counted short and a slow call
within the timeouts fail none. `QualityChecksTest`: a check that can't
run fails with its error and the next ones run; a broken connection is
opened again; an empty table's min, max and mean are aborted.
`DevCatalog` itself runs against the live stack only.

## Known limitations

- Development data only: production has no schedule and no document;
  a person curates there, and the sync keeps it.
- Asset Health's **Pipeline** says no pipeline is linked: it counts
  OpenMetadata's own ingestion pipelines, which need an ingestion runner
  and the source's credentials, neither of which this stack gives
  OpenMetadata.
- The pipelines have no run status: datyx doesn't see Flink's or
  HealthHub's jobs run, so it says nothing of them.
- A contract's schema is the table's at the first curation; to agree on
  a new one, delete the contract in OpenMetadata and the next curation
  makes it again.
- A topic has no checks: OpenMetadata's test cases are for tables.
- One curation document; another customer would be another file and
  another schedule.
- The document's checks are HealthHub's as `main` has it: a table
  HealthHub adds (as `occupancy_alarm` on a branch) is synced, with its
  schema's checks, and left uncurated until the document names it; and
  the document naming a table HealthHub doesn't have keeps the
  curation waiting.
- Two datyx instances curating the same OpenMetadata with different
  documents undo each other's changes: a test case one removes the
  other makes again. Each removes only marked test cases, so a person's
  stay either way.
