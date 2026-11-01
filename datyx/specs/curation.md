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
  a column for a column's, parameters, a description;
  [catalog.md](catalog.md#quality)).
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
the schema's checks the sync ran), gives a table the document's roles
for a group only when it has none of that group (people's changes in
OpenMetadata stay), and sets `timeSeriesRetrain` only when unset.

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
checks run and failed. The log says the same, with the contracts kept.

## In development: HealthHub

`DevCatalog`, dev mode only (`@IfBuildProfile("dev")`): every 30 s, the
first time 10 s after start, until a pass succeeds, then every
`datyx.dev-catalog.every` (10 minutes), so profiles, checks and
contracts follow the simulation:

1. It waits for HealthHub's data initialization: every table the
   document names is in HealthHub's database, described (HealthHub's
   API comments its schema at every start). Until then it logs why, once
   per reason.
2. For each profile's seeded HealthHub sources
   ([data-sources.md](data-sources.md)), it syncs the database (profiles
   and schema checks included) and the Kafka cluster (when it can't be
   read, the curation goes on without its topics), then applies the
   document.
3. It runs OpenMetadata's Data Insights (`DataInsightsApplication`), so
   the coverage reports (descriptions, owners, tiers) count the curation.

OpenMetadata unreachable, or refusing a call, is logged and tried again
in half a minute; another failure is logged and waits for the next
pass. `datyx.dev-catalog.enabled=false` turns it off.

With HealthHub's document, OpenMetadata shows: the Healthcare domain
and the HealthHub data product holding every asset; the HealthHub Data
team owning them; 18 glossary terms on the tables, columns and topics;
every asset described and tiered (Data Insights: 100% descriptions,
owners and tiers); 113 test cases passing (Data Quality: 8 healthy
assets of 8); 8 tables and 4 topics certified Gold; 8 contracts
approved and passing; the Flink job and HealthHub's API pipelines
(simulation, admissions feed, triage) with the lineage from the care
centers and conditions through the topics to the tables and the
`patient_days` and `occupancy_hourly` views; and the TimeSeries roles of
`admissions_hourly` (`default`, `acute`, `chronic`), `occupancy_hourly`
(`default`) and `patient_days` (`care`, XGBoost).

## Tests

`CurationTest`, no server: the tags written (a tier replaced, terms
added and quoted, other tags kept as they were, nothing patched when
they're there), what keeps an entity from its certification, nested
fields flattened, and HealthHub's document: it reads, its terms,
related terms, lineage ends, pipelines and time series tables all
exist, every topic is described, no em dashes. `DevCatalog` itself runs
against the live stack only.

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
