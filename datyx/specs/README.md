# datyx: software specification

The current specification of the system, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

datyx is a system built around data: a Quarkus REST API on GraalVM, its
PostgreSQL database and an OpenMetadata server as the catalogue. Data and
logic live in the API; its views are the datyx dashboard, a Flutter app in
a folder of its own ([../../datyx-dashboard/](../../datyx-dashboard/),
specified there), which only asks and shows. The API, the dashboard and
HealthHub are the datyx group, started and stopped together. The stack
starts with one command; the API answers its health (how it runs and
its dependencies), keeps the
data sources users add, each in the profile of whoever added it and
with its access details encrypted with that profile's key, and
authenticates users with Google through OpenID Connect, an identity
HealthHub passes on unchanged.

## Features

- [The API](api.md): the Quarkus app, its endpoints, its entities and the
  components it is built from.
- [Data sources](data-sources.md): the first entity, databases, S3
  buckets, folders and Kafka clusters with their access details, added
  and removed.
- [Authentication](auth.md): OpenID Connect with Google, who is calling,
  what is secured, and HealthHub's tokens accepted too.
- [Catalogue and time series](catalog.md): a database source or a Kafka
  cluster read into OpenMetadata without the source changing, the
  TimeSeries tags and table properties that say what its columns are to
  a forecast, the algorithms that train each group (DeepAR, XGBoost) and
  how far ahead, the time series datyx finds in them, and the groups
  switched on and off, which OpenMetadata's webhook tells datyx of; every
  column's and field's PII classification, in the GDPR's terms; and each
  table's profile and data quality checks with their results.
- [Curation](curation.md): owners, domain, data product, glossary,
  tiers, descriptions, checks, lineage, data contracts and the
  certifications earned, written to OpenMetadata from a document; in
  development, HealthHub's, as soon as its data initialization is done.
- [Training](training.md): the trainer started with the API, which
  trains each algorithm of a group, XGBoost or DeepAR (DJL on PyTorch),
  when it never was, when the group is switched on and again as often as
  its table says, and keeps each run, its test metrics, the features that
  weighed most (XGBoost's) and the highest scores.
- [Inference](inference.md): the trained models scoring series on
  demand, as their training did (a DeepAR model's forecast step by step,
  with its percentiles), and the account of every call: who,
  which model, how many series, how long, failures, per hour.
- [aityx](aityx.md): the gateway to aityx's `/v1/systemone`, with
  datyx's key, for signed-in users and for services (HealthHub's
  triage) with a token of their own, the account of every call (who,
  why, model, decision, latency, input tokens and their cost, the
  request and the answer), and the hook where calls will be
  personalized per profile.
- [Profiles](profiles.md): the person behind a sign-in, made on the first
  call, with identities and an encryption key of its own that protects
  the profile's data source access details at rest.
- [Development environment](dev-environment.md): devbox, process-compose,
  Docker Compose, the ports, the settings, the version and the build.
