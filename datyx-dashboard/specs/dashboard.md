# The dashboard

The datyx dashboard is a Flutter web app in `datyx_dashboard/` (package
`datyx_dashboard`), in the aityx dark palette like every demo's app. It
invokes the datyx API ([../../datyx/specs/api.md](../../datyx/specs/api.md))
and shows what it answers, with the details of each call. It computes,
stores and decides nothing on its own: when a view needs data the API
doesn't have, the API gets it first.

## What it shows

One screen, `DashboardScreen`, with an app bar and eight tabs under it
(a `TabBar`, as the demos' apps have), in the order of `DashboardTab`:
Data sources, Catalog, Training, Inference, aityx, Audit, Health, Profile. Data sources opens at
start, unless the page's address names another (see Kept across a
reload).

- The app bar: the title, the account corner (`UserMenu`: nothing while
  the API has authentication off; Google's own sign-in button while
  nobody is signed in; the user's picture, name, email and a sign-out
  button once someone is) and the refresh button, which asks the API
  again for the status, the data sources and the profile, as a timer
  does every 15 s.

- **Data sources** (`DataSourcesCard`): the list from
  `GET /api/datasources`, newest first, one row each with the kind's
  icon, the name and kind, where it points on one line
  (`engine://host:port/database as user`, `s3://bucket/prefix (region)
  at endpoint`, the path, or `kafka://servers (protocol, mechanism) as
  user`, the protocol left out when plain text), the description, when and by whom it was
  added, and a remove button, which confirms and then `DELETE`s. An Add
  button opens `AddDataSourceDialog`: the kind (Database, S3 bucket,
  Filesystem, Kafka), name and description, then the fields of that kind
  (engine and port, host, database, username and password; bucket,
  region and prefix, endpoint, access key id and secret access key; the
  path; or the bootstrap servers, the security protocol and SASL
  mechanism picked from the API's lists, and with a SASL protocol the
  username and password), the required ones checked before the `POST`; secrets go as
  typed, the rest trimmed. Errors the API answers show in a snack bar.
  With authentication on and nobody signed in, the card says to sign in
  and the list isn't asked. A line in red above the card when the API
  itself didn't answer.

- **Catalog** (`CatalogTab`): what datyx makes of the data in each
  source, as the catalogue (OpenMetadata) has it
  ([../../datyx/specs/catalog.md](../../datyx/specs/catalog.md)). Under
  an intro card, the sources come in sections, each with a title (an
  icon, its name and what its cards show) and room above it, and 16 px
  between cards: **Databases**, **Streams** (Kafka sources) and **Not
  read yet** (S3 and folder sources), a section only when it has a
  source. Each database source is a card (`SourceCatalog`) that loads
  `GET /api/datasources/{id}/catalog` and `.../timeseries`: "Not
  catalogued yet" before a first read; **Read schema** (then **Read
  again**) calls `POST .../catalog` and says how many tables and columns
  it read. Each table is a tile that opens on its columns: name (a key
  icon for the primary key), OpenMetadata's type, and its tags, a
  TimeSeries tag shown as its role and what it is to the algorithms that
  train its group, DeepAR's field (`Target · target`), its part in
  XGBoost's dataset (`Target · label: sum over the horizon`), or both
  (`Target · label: sum over the horizon / target`), with its
  group first when it isn't the default one (`acute: Target · target`).
  The table's own tags come first, *on the table*: each of a group's
  algorithm tags shown as `care: trained by XGBoost`, its Disabled tag as `chronic:
  disabled, not trained`. A table can hold several time
  series, one per group of tags, each read by the API on its own and
  trained by its own algorithms (DeepAR, XGBoost, or both, each its own
  model; the API's `algorithms`, XGBoost first; an API that only says
  `algorithm`, that one). Each group has a
  color, on its tags and its box (a dot and the border): the
  default group first, then the others by name, take orange, blue and
  aqua (`groupPalette`, checked with the dataviz skill's validator to
  stay apart side by side on the dark surface, for color blindness too;
  no fourth hue does with these three), and any past the third a neutral
  gray. The status colors (green, amber, red) are never a group's. The
  name is always on the chip and the box, so the color is never alone. A tagged table has
  a badge, *time series: ready* or *needs work* for one group, *3 time
  series: all ready* (or how many are) for several; under its name, even
  closed, what trains each group, in the group's color (`care: XGBoost,
  30D ahead`, `acute: DeepAR`, `chronic: DeepAR, disabled`, `care:
  XGBoost + DeepAR, 30D ahead`); and a box per group named by its
  algorithms in full (`DeepAR Forecasting · acute`, `XGBoost Classification · care`, `XGBoost Classification + DeepAR Forecasting ·
  care`, the default's first; only these boxes name them in full, the
  rest of the dashboard says `DeepAR` and `XGBoost`), its switch and
  **Edit** always at its top right, whatever its left side holds (its tag
  chip when disabled)
  with what its tags give the algorithm (`item_id = run_id +
  hospital_id`; for XGBoost first what it scores, `scores stay_hours
  summed over the next 30D, per run_id + person_id`), `freq`, `horizon`
  (the trainer's choice for DeepAR when the table has none), a missing
  row as 0 or unknown, whether it is ready, the API's problems, an
  **Enabled**/**Disabled** switch and **Edit**.
  A group is enabled or disabled, as the API answers (`enabled` in
  `GET .../timeseries`; an API that doesn't say, enabled): disabled, the
  table carries the group's tag `TimeSeries.<group>.Disabled`
  (`TimeSeries.Disabled` for the default group) in OpenMetadata and
  datyx doesn't train the group. The switch is that tag: flipping it
  calls `PUT .../timeseries/enabled` with the table, the group and
  `enabled`, which adds the tag to disable and removes it to enable;
  while the call is on, a spinner stands in for the switch; the group
  becomes the API's answer and the table's tags are read again. Enabling
  has datyx queue a run for each of the group's algorithms, and so does
  removing the tag in OpenMetadata itself, which datyx hears of from
  OpenMetadata's webhook. Its tooltip says so, with the algorithms
  (*Disabled: datyx doesn't train this group. Enabling removes its
  TimeSeries.chronic.Disabled tag in OpenMetadata, and datyx queues a
  training run of it (DeepAR); removing the tag in OpenMetadata itself
  does the same.*; with several, *... and datyx queues a run for each of
  its algorithms: XGBoost, DeepAR; ...*). Enabling shows a snack bar
  (*chronic enabled: datyx queues a training run of it (DeepAR); see the
  Training tab.*, or *care enabled: datyx queues a run for each of its
  algorithms: XGBoost, DeepAR; see the Training tab.*), as disabling does (*... tagged TimeSeries.chronic.Disabled in
  OpenMetadata, datyx doesn't train it.*). A disabled group's box is
  muted (its lines faded, its name gray, its border fainter) and shows
  its tag's FQN as a gray chip, with a line saying it isn't trained
  while the table has that tag; it can still be edited. On the table,
  the tag reads `chronic: disabled, not trained` in the group's color,
  and the badge adds how many are disabled (*3 time series: all ready,
  1 disabled*). An error shows the API's words, the group as it was.
  **Tag for training** on an untagged table, **Add a group** on a tagged
  one, and **Edit** open `TimeSeriesDialog`: for a new group, its name
  (`default` for a table's first, else empty to type; a name the table
  has already is refused there, other names by the API), starting from
  the first group's roles but its Target; for a group, the API's
  reading of it. **Trained by** DeepAR, XGBoost or both (one at least),
  the group's (a new one's starts from the group it copies, else
  DeepAR), named in the title (`Tag public.patient_days for XGBoost:
  care`, `... for XGBoost + DeepAR: care`) and sent explicitly as
  `algorithms`, so the table carries a tag for each and no other. One
  row per role (Timestamp, Target, SeriesKey, StaticCategorical,
  StaticReal, KnownCovariate, PastCovariate, with what it is to each
  algorithm picked and what it means as a tooltip), each a chip per column, one column for Timestamp
  and Target and any number for the others; the table's frequency
  (typed, or 15min, 1h, 1D, 1W, 1MS), horizon (typed, or 24h, 7D, 30D,
  90D; *required* when XGBoost is picked) and whether a missing row counts as 0 or
  is unknown, shared by its groups. **Save
  tags** sends `PUT .../timeseries` with the group, its `algorithms`
  (and the first as `algorithm`, for an API that takes one) and the
  horizon: a ready group closes
  the dialog and the card reloads; otherwise the dialog stays with the
  API's problems. **Remove group**, pressed twice, sends the group with
  no roles, which takes it off the table. The tab only shows what the API
  answers: which columns fit a role, and whether the table is ready,
  are the API's to say. Each Kafka source is a card (`StreamCatalog`)
  that loads `GET .../catalog`'s topics: "Not catalogued yet" before a
  first read; **Read topics** (then **Read again**) calls `POST
  .../catalog` and says how many topics and fields it read, and from how
  many topics with records. Each topic is a tile with its name, how many
  fields (or "no fields read") and its cleanup policies; it opens on its
  partitions, replication and retention (`1 partition · replication 1 ·
  kept 1 day`, and the size kept when limited), its description and
  tags, and its records' fields: name, OpenMetadata's type and tags, a
  record's own fields indented under it; a topic without fields says
  there was no JSON record to learn them from. S3 and folder sources are
  listed as not read yet; with authentication on and nobody signed in,
  the tab says to sign in. An error answer shows the API's own words
  (`{"error":...}`).

  Every part of the tab says what it is on hover (a tooltip, also on a
  long press): a section title, which sources it holds; a source's icon,
  its kind (`Database source`, `Kafka source`); its name, the source's
  description; its address, where datyx connects; **Read schema** and
  **Read topics**, what they read (no rows, no values) and what stays.
  A table's icon, its kind (`tableKind`: table, view, materialized view,
  partitioned table); its name, the kind, its description (or that the
  source has none) and its OpenMetadata FQN; its column count; its
  badge, ready or how many groups need work, and how many are disabled. A column's name, whether it
  is in the primary key, never empty, or untagged; the key icon; its
  type, as OpenMetadata names it. A TimeSeries tag, what the role means,
  its group, what each of the group's algorithms takes it as and the
  tag's FQN; an algorithm's tag, that datyx trains the group with it; a
  Disabled tag, that the group isn't trained; any other tag, its
  classification (`tagHelp`: `PII.None` is the None tag of PII). A
  group's box: its dot, its algorithms and group (what they train on and
  forecast), ready icon, input lines and **Edit**; **Tag for training**
  and **Add a group**. A topic's icon, name (with its FQN),
  field count, cleanup policies (`cleanupHelp`: delete removes records
  past the retention, compact keeps the latest per key) and settings
  line; a field's name and type, as the sampled values fit it. The
  words are the dashboard's; the facts in them are the API's.

- **Training** (`TrainingTab`, `?tab=training`): the models datyx
  trains, from `GET /api/training`. A card says what datyx does (each
  group tagged on the Catalog tab trained with its algorithm, XGBoost or
  DeepAR, at the API's start if it never was,
  then as often as its table's `timeSeriesRetrain` says, 1D when not
  set, when asked, and when the group is enabled, its Disabled tag
  removed on the Catalog tab or in OpenMetadata, which tells datyx at
  once, a run for each of its algorithms; a disabled group isn't
  trained; XGBoost scores the Target summed over the horizon, DeepAR
  forecasts each step of it), with a reload button; the sources whose
  catalogue couldn't be read in amber; none tagged yet, where to tag one.
  A card per model, one per group and algorithm datyx trains
  (`ModelCard`): `XGBoost · care`, its table and
  source, its latest run's status (`StatusChip`: an icon and the word,
  succeeded green, queued and running amber, failed red; *not ready*
  amber, with the API's problems), and what it scores (*Scores
  stay_hours summed over the next 30D, per run_id + person_id, from
  steps of 1D.*) or, for DeepAR, forecasts (*Forecasts admissions step
  by step over the next 1D, per run_id + hospital_id, from steps of
  1h.*, the horizon the API says it forecasts); a group the API says isn't `enabled` gets a gray
  *disabled* chip, its tooltip naming its `TimeSeries.<group>.Disabled`
  tag. **Retrain every**: the table's setting, typed or
  picked (1h, 6h, 1D, 1W, never; empty for the default) and **Save**d
  with `PUT /api/datasources/{id}/training`, which writes it to
  OpenMetadata, saying so; under it what applies and when the model is
  next due (*Next in 42 min, at ...*, *Due now*, *A run is running*,
  never, or for a disabled group *Disabled: not trained until enabled on
  the Catalog tab, which removes its TimeSeries.acute.Disabled tag.*).
  **Train now** (`POST .../training` with the model's `algorithm`; off
  while a run is on, the group isn't ready or it is disabled). When the latest run has a
  `triggerNote`, it is shown under (*The latest run (enabled):
  TimeSeries.chronic.Disabled removed in OpenMetadata (table version
  0.9, by admin, ...)*). A failed latest run shows its error in red.
  From its latest success (`GET /api/training/runs/{id}`): which run,
  when, why and how long, and how many test examples; four stat tiles
  (`StatTile`: a large value, its label above and a note below): the
  mean error, the naive forecast's, *better than naive* as a percentage
  (with an arrow icon, green when better), and the actual average (for
  DeepAR, per step, to three decimals, the error the forecast median's,
  and a fifth tile, *inside its 80% band*, the share of held-out steps
  between its 10th and 90th percentiles); for XGBoost the
  features that weighed most (`FeatureWeights`): a bar per feature, its
  share of the mean |SHAP| in the brand orange (one series, no legend;
  checked against the card's surface with the dataviz skill's
  validator), the name and the percentage in text beside it and a
  tooltip saying it; and the highest scores now (`TopScores`): a table of
  the 10 series still observed with the highest prediction, their key's
  values, the prediction and the last horizon's actual. Then
  **Activity**: every run of them all, newest first, with when it was
  queued, its status chip, the table and group, its algorithm, why
  (initial, schedule, manual, or enabled: the group's Disabled tag
  removed), a link to the group switch that queued it when the API
  gives its `eventId` (*switch #5*, which scrolls to it and outlines it
  in orange), how long, its test MAE against the naive one and its
  examples, the API's `triggerNote` when it gives one (which tag, the
  table's version in OpenMetadata, by whom and when, how datyx heard),
  and a failure's error. Then **Group switches** (`GET /api/catalog/events`, the latest
  50): each time a group was switched on or off, newest first, with
  when (the change's time, else when datyx heard), *switched on* (green)
  or *switched off* (gray), the table and group, how datyx heard (*via
  OpenMetadata's webhook*, *via the datyx API*, *via datyx's minute
  check*), who switched it, the table's version in OpenMetadata, and the
  runs it queued (*queued runs 12, 13*, one per algorithm; *no run
  queued*; *not trained while off*). It is read on its own: when it
  fails (an API without it), its card shows the API's words and the
  rest of the tab stays. While a run is queued or running the tab asks
  again (both) every 3 s.
- **Inference** (`InferenceTab`, `?tab=inference`): the account of the
  calls to the trained models, from `GET /api/inference` (the last 7
  days), with a reload button. Six stat tiles: calls, the last hour's,
  failed (a status icon, green with none, red with some, and the share),
  series scored, median and 95th-percentile latency; then **Calls per
  hour** (`CallsPerHour`): a column per hour of the last 24 on one
  baseline in the brand orange (one series, no legend), scaled to the
  tallest, which the subtitle names, the first hour and *now* under it,
  and a tooltip per column with the hour, its calls and its failures. A
  card per model (`InferenceModelCard`): `XGBoost · care`, its table and
  source, which run answers and when it was trained, what it predicts
  and per what key; its own tiles (calls and when last, failed, series
  scored, median latency with the mean, 95th percentile); and **Try it**:
  a field per key column and **Score** (on once the whole key is typed),
  or **Score all still observed**, each a real call to
  `POST /api/datasources/{id}/inference`, accounted for like any other;
  the answer shows the call's id, how many it scored, how long and which
  run, and a table of the predictions (the key, the prediction, the last
  horizon's actual, or why a series wasn't scored), and the account is
  asked again. Then **Calls**: the latest, newest first: when, the status
  chip (ok green, failed red), the model, the run, how many asked and
  scored (*all still observed* for none named), the milliseconds, who
  asked, and a failure's error.
- **aityx** (`AityxTab`, `lib/dashboard/aityx_tab.dart`, `?tab=aityx`):
  the account of the calls datyx routes to aityx through its gateway
  ([../../datyx/specs/aityx.md](../../datyx/specs/aityx.md)), from
  `GET /api/aityx?days=N`, asked when the tab is first opened, with a
  reload button and the window as chips (1 day, 7 days, the default, 30
  days; beside the title, under it on a narrow screen). Five cards, 16 px
  apart:
  - **aityx**: what the gateway is (`POST /api/aityx/v1/systemone`,
    forwarded to aityx's `POST /v1/systemone` with datyx's own key,
    HealthHub's desk triage going that way), a warning when the API says
    datyx has no aityx key (`configured` false: the gateway answers 503 and
    HealthHub calls aityx directly), whether services' calls (HealthHub's)
    are shown with the profile's own (`sharesServiceCalls`), and seven
    tiles: calls (the window's, and the last hour's), failed (not 2xx; a
    status icon, green with none, red with some, and the share), input
    tokens (compact, `48.2K`, the exact sum under it), cost (dollars as
    small as they come, `$0.00202`, with the API's price per million input
    tokens), median latency (with the mean), 95th percentile, and the last
    call (how long ago, and when). A tile's value too long for it is scaled
    down to fit (`StatTile`).
  - **The last 24 hours** (`HourColumns`): two charts side by side (one
    above the other when narrow), sharing their baseline, each on its own
    scale named in its subtitle (the tallest hour): **Calls per hour**,
    answered (2xx, the brand orange) and failed (red, the status color,
    with its icon in the legend) stacked from the baseline with a 2 px gap,
    and **Input tokens per hour**, one series, no legend. Columns are at
    most 24 px wide, rounded at the top, the first hour and *now* under the
    baseline, and each has a tooltip: the hour, its calls, failures and
    median latency, or its input tokens and calls.
  - **By purpose, model and decision** (`Breakdown`): three columns (one
    under the other when narrow), each value's calls as a bar in one hue
    scaled to the most called, its calls and failures in text, *none* in
    italics for calls without one, at most 5 and the rest counted; a
    tooltip per row with its input tokens too.
  - **Calls**: the latest 50, newest first, as a table (scrolled sideways
    below 940 px): when, the caller (a service's with a server icon, a
    user's with a person), the purpose, model · decision (and
    *personalized* when the hook changed the body), latency, input tokens
    (a dash without usage) and aityx's HTTP status as a chip (green 2xx,
    red else), a failure's error under its row. A row opens the call
    (`AityxCallDialog`): its facts at once (when, who, why, model,
    questions, mode, latency, tokens, cost, personalized or not, the
    error), then, from `GET /api/aityx/calls/{id}`, the request sent to
    aityx and its answer, pretty-printed in the Audit tab's `JsonBlock`
    (as text, said to be truncated at 64 KB, when the API kept it so;
    *none* when there was none, aityx unreached), or the API's words (a
    404 for a call not the profile's).
  - **Personalization**: coming, and clearly not active (a gray *coming:
    not active* chip, unless the API says `personalization.active`): calls
    go to aityx as their callers send them; what datyx's hook
    (`AityxPersonalizer`) will do per profile, before a call goes to
    aityx: a profile's preferred Jev model, extra context from what datyx
    knows of its data, its own variants of a decision; and that such a
    call will say *personalized* in the calls. Shown signed out too.

  Signed out (authentication on), the tab asks nothing and says to sign
  in; the API's error, when it answers one, is shown in the first card,
  and the other cards but Personalization wait; with no call, the charts
  say *none in the last 24 hours*, the breakdowns *none yet*, and the
  calls that HealthHub's triage goes through datyx when
  `HEALTHHUB_AITYX_VIA_DATYX` is on and both share
  `DATYX_SERVICE_TOKEN`.
- **Audit** (`CallsPanel`): every call made, newest first, up to 100,
  under the title *API calls* and on a tab labelled *Audit*, neither
  with a count (the refresh every 15 s soon fills it to 100): method,
  path with its query, status (or
  pending, or error), time of day and duration; expanded, the request and
  the response bodies pretty-printed. A button clears it. The calls are
  kept across a reload of the page.

- **Health** (`HealthTab`): cards from `GET /api/health`'s checks: API
  (the `datyx` check: name and version, its profile, launch mode and
  `jvm` or `native`, as `dev profile, development, jvm`, uptime, started
  at), PostgreSQL (ok, or the error), OpenMetadata (version and URL, or
  the error, and where datyx's tagging is seen there: **TimeSeries tags,
  and the tables that carry them**, the classification's page in
  OpenMetadata (`/tags/TimeSeries`), each tag leading to its tables and
  columns, and **Alerts: datyx-catalog-events tells datyx of tag
  changes**, OpenMetadata's notification alerts (`/settings/notifications/alerts`),
  where datyx's event subscription is listed), Sign-in (off, with no `OIDC_CLIENT_ID` on the API; on and
  nobody signed in; or the issuer, whom the API sees and their profile
  id, from `GET /api/me`), and Dashboard: this build's version, when built by the scripts
  (`dash 0.1.202610291200`; a bare `flutter run` or a test has none), and
  how often it asks the API. A green dot when the part is ok, red
  otherwise, and the same red line when the API didn't answer. Three
  cards end with a link, opened in a new tab (`noopener`): the API's, its
  health check (`/api/health` where the app calls the API: its own
  origin, or `API_BASE_URL`); OpenMetadata's, the URL its check reports
  (the API's view of it, so behind Docker Compose it may be a name only
  the API resolves); the Dashboard's, this page without its query.

- **Profile** (`ProfileTab`): the caller's profile from
  `GET /api/profile`, which the API makes the first time an identity
  signs in: its name, id, since when and how many data sources it owns,
  a line saying their access details are encrypted with a key of the
  profile's own, then its identities, one row each with the picture,
  the email (else the name, else the subject), the name, the provider
  (the issuer's host, or `local`), when it was added and last seen. With
  authentication on and nobody signed in, it says to sign in and the
  profile isn't asked.

The API's hello, greetings and status endpoints are gone; the health
replaces the status.

## Kept across a reload

A reload of the page comes back as it was:

- The open tab, kept in the page's address as `?tab=<name>` (`sources`,
  `catalog`, `training`, `inference`, `aityx`, `audit`, `health`, `profile`; `lib/persist/address.dart`),
  replaced in place as tabs change, so the back button leaves the page
  rather than walking the tabs. A bookmark or a shared link opens the
  same tab. Flutter's own route, after the `#`, is left alone.
- The sign-in: the ID token, kept in the browser tab's session storage
  (`lib/persist/session_store.dart`, key `datyx.idToken`) from sign-in to
  sign-out. At start, a kept token that was issued for the API's client
  id and expires in more than a minute signs in at once, with the user's
  name, email and picture read from it, and Google isn't asked; an
  expired or foreign one is dropped. When it expires, or the API refuses
  it, Google is asked to renew it silently; if it can't, the user is
  signed out here and the sign-in button shows. The dashboard reads the
  token's expiry and audience only; the API verifies it.
- The audit: the calls, in session storage as `datyx.calls`, the latest
  100. A call still waiting at the reload shows as never answered.

Session storage belongs to the browser tab: closing it forgets all this,
and another tab starts signed out. The data itself lives in the API.

## Sign-in

`AuthController` (`lib/auth/auth_controller.dart`) takes the API's
`GET /api/auth/config` at start, asked again with a growing delay (3 s
up to 30 s) while the API doesn't answer, so a dashboard opened before
the API is up still gets its sign-in. Off: nothing happens and every call goes
out anonymous. On: it initializes `google_sign_in` with the client id the
API published (nothing is built in), listens to its sign-in and sign-out
events, and tries a silent sign-in from a previous session. The web
renders Google's own button (`google_sign_in_web`'s `renderButton`, in
`sign_in_button_web.dart`, chosen by a conditional import); other
platforms get a button of ours that calls `authenticate()`. The signed-in
account's ID token (an OpenID Connect token, audience the client id) is
what `HttpDatyxApi` sends as `Authorization: Bearer` on every call; after
a 401 it asks for a silent re-sign-in once and retries, since Google's
tokens live an hour. Signing in or out refreshes the screen.

## The API client

`DatyxApi` (`lib/api/datyx_api.dart`): `authConfig()`, `me()`,
`profile()`, `status()`, `dataSources(limit)`, `addDataSource(NewDataSource)`,
`removeDataSource(id)`, `syncCatalog(id)`, `catalog(id)` (a database's
tables), `topics(id)` (a Kafka source's topics, `CatalogTopic` and
`CatalogField`), `timeSeries(id)`, `setTimeSeries(id, roles)`,
`setGroupEnabled(id, table, group, enabled)` (`PUT
.../timeseries/enabled`, answering the group; `TimeSeriesSpec.enabled`,
true when the API doesn't say, and `disabledTag(group)`, the tag's FQN),
`TimeSeriesSpec.algorithms` (the API's `algorithms`, else
`[algorithm]`; `algorithm` its first), `TimeSeriesRoles.algorithms`
(sent as `algorithms`), `training()`, `trainingRun(id)`,
`trainNow(source, table, group, algorithm)` (`algorithm` sent when
given) and `setRetrain(source, table, retrain)`
(`TrainingRunInfo.triggerNote` and `eventId`, `TrainingModel.enabled`),
`groupEvents(limit)` (`GET /api/catalog/events?limit=50`, `{"events":
[...]}` read as `GroupEvent`: id, source, table, name, group, enabled,
via, version, by, at, receivedAt, runIds), `inference()` and
`score(source, table, group, series, limit)`, `aityx(days)` (`GET
/api/aityx?days=7`, read as `AityxAccount`: `configured`,
`sharesServiceCalls`, `pricePerMillionInputTokens`,
`AityxPersonalization`, `AityxStats` totals, `lastHour`, `AityxHour`s,
`AityxCount` breakdowns and `AityxCallInfo` calls) and `aityxCall(id)`
(`GET /api/aityx/calls/{id}`, `AityxCallDetail`: the call, `request` and
`response` as the JSON or the text the API kept, and whether each was
truncated), those in `lib/api/aityx_account.dart`, exported by
`datyx_api.dart`, and the `CallLog` the Audit tab listens to.
`HttpDatyxApi` is the real one, over `package:http`, with a token
provider for the bearer and one for a refresh after a 401, a 20 s timeout
on every call, and request bodies logged with their secrets (`password`,
`secretAccessKey`) replaced by dots; `API_BASE_URL`
at build time is the API's base, empty meaning the app's own origin, so
the app calls `/api/...` and whatever serves it proxies that to the API.
A non-2xx answer or a failed call throws `ApiException`, except a 503
from `/api/health`, which is a check down with the checks in the body. `DataSource`
keeps the access details as the API answers them (a map under the
type's key, secrets replaced by `passwordSet` and `secretAccessKeySet`)
and summarizes them on one line; `NewDataSource` is the `POST` body.
`Profile` and `ProfileIdentity` read `GET /api/profile`; `Me` carries
the profile id.
`SystemStatus.fromHealth` reads what the cards show from the health's
checks by name (`datyx`, `Database connections health check`,
`OpenMetadata`); `Dependency.fromCheck` takes a check's status, version,
URL and error (`data.error`, else its other value, where the database
check puts it).

## Serving

Under `/app/` (base href), with `/api/` and `/q/` reaching the API on the
same origin, so there's no CORS and a forwarded port works:

- `scripts/flutter-web.sh` in release mode (`devbox services up`): the
  release build, served by `bin/web_server.dart` (`lib/web_server.dart`,
  dart:io only) compiled to `build/web_server`: files under `/app/` with
  `index.html` as the fallback, `/api/` and `/q/` proxied to
  `DATYX_API_URL`, `/` redirected to `/app/`.
- `scripts/flutter-web.sh` in debug mode (`devbox run web`): Flutter's dev
  server on the web-server device with hot reload, its proxy generated in
  `web_dev_config.yaml` (git-ignored).
- Docker Compose: nginx (`docker/nginx.conf.template`) with the same
  shape, `DATYX_API_URL` filled in when the container starts.

Web is the only platform so far; `flutter create --platforms <name> .`
adds another, and `scripts/make.sh` a target for it.

## Tests

`flutter test` in `datyx_dashboard/`: a `FakeDatyxApi` answers from
memory with authentication off; the Data sources tab opens first and the
Health tab shows the fake's values and the missing version; the Audit tab
counts and lists the calls made at start and empties on clear; the
Profile tab shows the fake's profile with its local and Google
identities; a filesystem data source added through the dialog appears
with its path and author, is counted on the Health tab, its `POST` is in
the Audit tab, and it is gone after the remove button and its
confirmation; the tabs stand in their order and the Catalog lists a
folder source as not read yet, under its section; a Kafka source added
through the dialog sends its servers trimmed and plain text, shows as
`kafka://`, sits in Streams below Databases with room between the
cards, and its topics are read and opened on their settings, fields,
a nested field indented and a tag, an empty topic saying it has no
fields, with tooltips on the source, the topic (its FQN), a cleanup
policy, a tag and a nested field; a database source's schema is read,
its source, Read schema, table (kind, description and FQN, shown on a
long press), columns, key icons and types having tooltips, and
its hourly table tagged for DeepAR, the dialog showing the API's problem
until a target is picked, then sending the roles, frequency and missing
rows in the default group, its tags, group, badge and ready icon then
saying what they are; a table's kind, a tag's classification and a
cleanup policy are named; a tagged table gets a second group, named
`acute`, from the default's roles but its target, a second group of the
same name is refused, its box and tags take a color other than the
default's, and removing it sends it with no roles; a group tagged for
XGBoost with a 30D horizon sends both, and the table then says who
trains it (closed and open, the algorithm's tag in the group's color),
what it scores and each role in XGBoost's terms, and its Edit starts
from XGBoost and the horizon; a group tagged for both XGBoost and
DeepAR (the picker taking several, one at least) sends both, XGBoost
first, shows both on the table, its box, its tags and its roles,
says enabling queues a run for each in its tooltip and snack bar, and
its Edit starts from both; a group's `algorithms` are read (falling
back to `algorithm`, then DeepAR) and sent, a `GroupEvent` and a run's
`eventId` read; a table with `chronic` disabled shows it
switched off and muted, with its `TimeSeries.chronic.Disabled` chip, the
table's tag and the badge's count, and is still editable; switching it
on sends the table, the group and true, says a training run is queued,
and drops the tag, while switching the default group off sends false and
shows `TimeSeries.Disabled`; a refused switch shows the API's words and
leaves the group as it was; groups' colors go
by name, the default first, gray past the third; the tab the address names opens; and,
with a session store in memory, the audit is read back after a reload
(a waiting call as never answered), a fresh token signs in without
Google, an expired, foreign or malformed one is dropped, a refused one
that can't be renewed signs out, and signing out forgets it. The
Training tab shows a model's scope, its next run, its latest run's
failure, its latest success's tiles (3.10 against 5.20, 40% better),
its features' bars in proportion with their shares, its scores and
every run newest first; **Train now** (with the model's algorithm) and
saving *never* call the API. Runs show their algorithm and link to the
group switch that queued them, which is outlined when followed; the
group switches show on and off, how datyx heard, by whom, the version
and the runs queued, newest first; when they can't be read, their card
says so and the training still shows. A DeepAR model says it forecasts
step by step over its horizon, shows its error per step (0.005, the
median's) and its band's tile (99%), no feature weights, and its scores.
A run triggered by enabling a group shows *enabled* and its note, in the
activity and under its model; a disabled group says so, is never next
and can't be trained now.
The Inference tab shows the totals' tiles, the hours' columns in
proportion with the tallest, a model's account and calls with their
failure; **Score** waits for the whole key, then sends it and shows the
answer, and scoring all sends no series.
The aityx tab asks for 7 days when opened (not before), shows the tiles
(12 calls, 3 in the last hour, 48.2K tokens, $0.00202 at $0.042 per M,
2.1 s and 4.8 s, 3 min ago), the calls' columns in proportion with the
tallest, answered and failed stacked with their 2 px gap and at most 24
px wide, the tokens' columns, the tooltips, the breakdowns (a call with
no purpose as *none*), a service's and a user's call with their tokens,
status and a failure's error, and Personalization as coming, not active;
a row opens the call's request as JSON and its answer as the truncated
text kept, closes, and a call the API won't show says its 404; another
window asks again. With no key and no call it says both, the charts
none, the last call never and only the profile's own calls; an API
error shows its words, the account's cards gone but Personalization's;
signed out it asks nothing until signed in; at 400 px nothing
overflows. `HttpDatyxApi` asks `/api/aityx?days=7` and
`/api/aityx/calls/51` and reads the spec's JSON (nulls, a failure by its
status, a 404's words); counts, tokens, dollars and latency are said
briefly (48,210, 48.2K, $0.000175, 769 ms, 2.1 s).
