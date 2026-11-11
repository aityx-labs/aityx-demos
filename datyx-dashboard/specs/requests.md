# Requests

The history of requests that shaped the datyx dashboard, newest first.
Its earlier history, as the `datyx-dash` module inside `datyx/`, is in
[../../datyx/specs/requests.md](../../datyx/specs/requests.md).

## 2026-11-10: a reload while signed in shows the data, not a 401

Asked: fix the dashboard: with Google sign-in on, a page reloaded while
signed in, on a tab that loads what the API secures (seen on Training,
`GET /api/training answered 401`), showed the 401 until refreshed.

Found: a start-up race. The tabs were built, and asked, before
`GET /api/auth/config` answered: sign-in looked off, so the calls went
out with no token and the API refused them. The answer then turned
sign-in on and restored the kept token in the same step, so no tab ever
saw itself locked and then unlocked, which is what makes one ask again.
The screen's own refresh had the same flaw for the data sources and the
profile on every tab, and skipped the refresh that signing in asks for
when one was already under way.

Changed: fixed, in the app's start-up rather than tab by tab.
`AuthController` takes the API's answer and the kept session in one
step, tells its listeners once, and says when who calls is known
(`settled`). Until then `DashboardScreen` asks only the health, builds
only the Audit and Health tabs, and shows the others as waiting for the
sign-in settings; once settled each tab is built as whoever is signed
in, so its first call carries the token. With sign-in off the tabs load
with no token as soon as the API says so; signed out they say to sign
in, as before; a 401 mid-session still renews the token silently and
retries. A change of who calls during a refresh is followed by another
round of the secured calls. `DatyxDashApp` takes the tab to open, for
tests.

Two reviews of the fix found four more things, fixed in
`dashboard_screen.dart`: a tab polling a training run went on asking
(without a token) after a sign-out; the next user to sign in on the page
first saw the last one's data sources and tabs; an answer on its way at
a sign-out (the data sources, the profile, whom the API sees) was still
kept, so the next user could see the last one's sources, or the Health
tab name the last one for a whole session, and the round went on asking
without a token; and the API's "did not answer" line stayed above the
data once the API came back after being down at start. Each secured tab
is now made anew when who calls changes (keyed on the caller), a
sign-out empties the data sources, an answer asked for by an earlier
caller is dropped and its round stops, and the status is asked again
when the sign-in settles after it failed.

Tests: `test/sign_in_start_test.dart` (19, 59 in all): the 14 on the
start and the 3 on the reviews' findings fail without the fix, the 2 on
the 401's retry hold what was already there. [dashboard.md](dashboard.md).

## 2026-11-01: an aityx tab with the calls routed to aityx

Asked: in the datyx dashboard, add an aityx tab showing the requests
routed to aityx, and in the future personalize them. (The gateway,
`POST /api/aityx/v1/systemone`, its account, `GET /api/aityx` and
`GET /api/aityx/calls/{id}`, and the personalization hook are the API's
change, in its folder; HealthHub's triage calls go through it.)

Changed: a new tab, **aityx**, after Inference (`AityxTab`,
`?tab=aityx`): the account of the calls over 1, 7 or 30 days in tiles
(calls, failed, input tokens, cost, median and 95th-percentile latency,
last call), whether datyx has a key and shows services' calls, the calls
per hour of the last day (answered and failed stacked) beside the input
tokens per hour, the calls by purpose, model and decision, and the
latest calls as a table, a row opening its request and answer as JSON;
then **Personalization**, coming and not active, saying what it will
do. The API client reads both endpoints (`lib/api/aityx_account.dart`).
The Audit tab's body viewer is shared as `JsonBlock`; a stat tile scales
a value too long for it down, and a card's title gives way on a narrow
screen. Tests (6 more, 34 in all); `dashboard.md`.

## 2026-11-01: the Inference tab as a dashboard

Asked: that view (Inference) should be a dashboard, not so repeated,
more like the time series of inferences and statistics.

Changed: a card per model is gone. The tab is a row of headline tiles
(calls, last hour, series scored, latency p50 and p95, failure rate,
models in use, last call); **Hour by hour**, 24 hours or 7 days, three
charts drawn with `CustomPaint` (no new dependency): calls per hour
stacked by model with the failures as red dots, latency per hour (p50
and p95 lines) and series scored per hour stacked by model, each with a
legend, a crosshair and a readout, and the hours as a table on demand;
one **Models** table, a row per model (a group's algorithm) with **Try
it** first, in sight on a narrow card, scoring with the row's algorithm
in a dialog; and the latest **Calls** as a table, failures tinted red.
The palette goes to the models called in the range, the busiest three,
by name; the other called ones are gray and named in the readout. The
API answers what the charts need (datyx's change: `perHour` with series
scored, latency and calls per model, `?hours=` up to 168, a model per
group's algorithm, each model's and call's algorithm). Tests.

## 2026-11-01: space between the Training and Inference tabs' cards

Asked: on the Training view the cards are glued together: add
separation between them; same for the Inference tab.

Changed: the Training and Inference tabs put 16 px between their cards,
as their padding (`spaced`, in `card_title.dart`: the theme's cards have
no margin of their own). Tests.

## 2026-11-01: a group's buttons at its top right, and its algorithms named in full

Asked: on the Catalog tab, keep a group box's buttons at its top right
always, not floating; say "DeepAR Forecasting" and "XGBoost
Classification" in the cards, only on the big cards.

Changed: a group box's header puts its name, state and tag chip in one
expanding row, so the switch and **Edit** sit at the top right of every
box (the disabled chip and a spacer used to share the space, pushing them
inwards). The group boxes name the algorithms in full: `DeepAR
Forecasting · acute`, `XGBoost Classification · care`
(`algorithmTitle`); chips, the Training and Inference tabs keep the short
names. Tests: an enabled and a disabled group's buttons line up at the
box's right edge (160 px off before).

## 2026-11-01: DeepAR groups on the Training tab

Asked: as for XGBoost, train a DeepAR group of tags when it is enabled or
retrained (datyx's change: the API now trains DeepAR, and lists its
groups on `GET /api/training`).

Changed: the Training tab says datyx trains each tagged group with its
algorithm; a DeepAR model's card says it forecasts the Target step by
step over its horizon, its tiles are per step (three decimals, the
error the median's) with a fifth, *inside its 80% band* (`coverage`,
read by `TrainingRunDetail`), and it has no feature weights. With none
tagged, the tab says to tag one for DeepAR, or XGBoost with a horizon.
Tests.

## 2026-11-01: a group's algorithms, all trained on enabling, and the switches as events

Asked: the trigger for training is enabling the tag group, captured by
the API as an event, training every algorithm associated with the group.
(The webhook, the events and the runs per algorithm are the API's
change, in its folder.)

Changed: a group shows every algorithm it has (`XGBoost + DeepAR ·
care`), and the edit dialog picks one or more (sent as `algorithms`);
the switch's tooltip and snack bar say enabling queues a run for each
of them. The Training tab lists the group switches from
`GET /api/catalog/events` (when, table and group, on or off, through the
webhook, datyx's switch or the minute's check, who, the table's version,
the runs it queued), and a run queued by one links its event. The API
client reads `algorithms` (falling back to `algorithm`), `eventId` and
the events. Tests (26); `dashboard.md`.

## 2026-11-01: groups can be disabled; enabling one triggers its training

Asked: on the Catalog's view of a table's tag groups, let a group be
disabled, HealthHub's `chronic` group disabled by default; enabling a
group triggers a training run of it with its algorithm, the tagging
being the trigger, visible in OpenMetadata. (The Disabled tag, the
endpoint and the trainer watching the tag's removal in the table's
version history are the API's change, in its folder.)

Changed: each group's box on the Catalog tab has an Enabled/Disabled
switch, which is the table's `TimeSeries.<group>.Disabled` tag
(`TimeSeries.Disabled` for the default group) in OpenMetadata: it calls
`PUT /api/datasources/{id}/timeseries/enabled`, shows a spinner, takes
the API's answer and reads the table's tags again; its tooltip says so,
with the group's algorithm, and enabling says in a snack bar that datyx
queues a training run. A disabled group is muted, shows its tag as a
chip, reads `chronic: DeepAR, disabled` under the table's name and
`chronic: disabled, not trained` among the table's tags, is counted on
the badge, and can still be edited. The Training tab shows the
`enabled` trigger with the API's `triggerNote` (which tag was removed,
in which version of the table, by whom and when) in the activity and
under the model's latest run, and a disabled group as *disabled*, never
next and not trainable now. The API client gained
`setGroupEnabled(...)`, `TimeSeriesSpec.enabled` (true when the API
doesn't say), `disabledTag(group)`, `TrainingRunInfo.triggerNote` and
`TrainingModel.enabled`. Tests; `dashboard.md`.

## 2026-11-01: an Inference tab, the account of the calls to the models

Asked: an Inference panel on the dashboard, to account for inference
calls and their statistics. (Inference itself, and its account, are the
API's change, in its folder.)

Changed: an Inference tab after Training (`InferenceTab`,
`?tab=inference`): the last 7 days' totals as stat tiles (calls, the
last hour's, failures, series scored, median and 95th-percentile
latency), the calls per hour of the last 24 as columns, a card per model
with its own account and **Try it** (score a series by its key, or all
still observed, through the accounted endpoint, showing the
predictions), and the latest calls. The API client gained `inference()`
and `score(...)`; the status chip says ok in green. Tests;
`dashboard.md`.

## 2026-11-01: a Training tab, the models datyx trains and their runs

Asked: present the training's activity and results in a view of its
own, in the navigation; let the user set how often a model is retrained
(in OpenMetadata where possible). (The training, a component started
with the API, is datyx's change, in its folder.)

Changed: a Training tab after Catalog (`TrainingTab`, `?tab=training`):
a card per model tagged for XGBoost, with its latest status, what it
scores, **Retrain every** (saved to OpenMetadata through the API),
when it's next due, **Train now**, and its latest success's stat tiles
(its error against the naive forecast's), features' weights as bars and
highest scores; then the activity, every run newest first; asked again
every 3 s while a run is on. The API client gained the four training
calls. Tests; `dashboard.md`.

## 2026-11-01: tooltips on the Catalog

Asked: on the Catalog, add tooltips to the elements, so the user knows
what each thing is and what it's about, such as whether it is a table.

Changed: every icon, name, count, chip, badge and button of the Catalog
tab has a tooltip ([dashboard.md](dashboard.md)): the kind of a source,
a table (table, view, materialized view, partitioned) or a topic, with
its description and OpenMetadata FQN; what a column's key, constraint
and type are; what a TimeSeries role means and the DeepAR field it
becomes; which classification a tag is from; what a cleanup policy
does; what Read schema and Read topics read. `tableKind`, `tagHelp` and
`cleanupHelp` name them; tests. Column descriptions aren't in the API's
catalogue answer yet, so a column's tooltip can't show one.

Merged with groups of several algorithms, switched on and off: the
tooltips name what each of a group's algorithms takes a role as, say
what an algorithm's tag and a Disabled tag mean, count the disabled
groups on the table's badge, and the button reads **Tag for training**.

## 2026-11-01: Kafka sources, a Streams section, and cards apart

Asked: add Kafka to the data sources, with HealthHub's Kafka in the dev
profile, and show it in the Catalog in a section of its own; the
Catalog's cards were glued vertically: put some distance between them.
Kafka sources and their catalogue are the API's
([../../datyx/specs/requests.md](../../datyx/specs/requests.md)).

Changed: a Kafka kind in the dialog (bootstrap servers, security
protocol, SASL mechanism, username and password) and in the list
(`kafka://...`, a stream icon); before, a type the dashboard didn't know
showed as a folder. The Catalog groups its cards under Databases,
Streams and Not read yet, with a title and room above each section and
16 px between cards. A Kafka source's card (`StreamCatalog`) reads its
topics and shows each with its settings and the fields of its records,
nested ones indented. `DatyxApi.topics`; the fake's topics; tests.

## 2026-11-01: the algorithm that trains each group, XGBoost or DeepAR

Asked: score each patient's care in the next 30 days with XGBoost, the
horizon a parameter, by tagging a group with the XGBoost algorithm in
OpenMetadata (explicit for now) for a trainer to come; see in the
catalog clearly that XGBoost will train on the given table.

Changed: the API answers each group's `algorithm` and `horizon`, and a
table's own tags (datyx's change, in its folder). The Catalog tab shows,
under a table's name, what trains each group (`care: XGBoost, 30D
ahead`), the table's tags (`care: trained by XGBoost`), each role in
the terms of its group's algorithm, and boxes named by algorithm
(`XGBoost · care`) saying what XGBoost scores and the horizon.
**Tag for DeepAR** is **Tag for training**; the dialog picks the
algorithm (DeepAR or XGBoost, sent explicitly) and the table's horizon
(required for XGBoost). Tests; `dashboard.md`.

## 2026-11-01: a color per group of tags

Asked: give the groups of tags (each a time series here, but they could
be for other algorithms) different colors; they were all orange.

Changed: a group's tags and DeepAR box (a dot and its border) take its
color: orange, blue and aqua for the default group and then the others
by name (`groupColors`, `groupPalette`), a neutral gray past the third;
the three were validated together on the dark surface with the dataviz
skill, which no fourth hue passes beside them. The fake's catalogue
carries its groups' tags; tests for the order and the colors shown.

## 2026-11-01: groups of DeepAR tags in a table

Asked: tag separate groups in the same table, to train on it more than
once with partly the same columns (`admissions`, `acute_admissions` and
`chronic_admissions` of `admissions_hourly` as three targets with one
timestamp). The groups themselves are the API's
([../../datyx/specs/catalog.md](../../datyx/specs/catalog.md)).

Changed: the Catalog tab shows a DeepAR box per group with its own
**Edit**, a badge counting the ready series, tags with their group
(`acute: Target · target`), and **Add a group**; `TimeSeriesDialog` names
a new group, starts it from the first group's roles but its Target,
refuses a name the table has, and removes a group (**Remove group**,
twice). The API client's `TimeSeriesSpec` and `TimeSeriesRoles` carry
the `group`, and `TimeSeriesTag` reads a tag's group and role (it
replaces `TimeSeriesRole.ofTag`). The fake keeps groups; a widget test
adds, refuses and removes one.

## 2026-11-01: the Audit panel's title without the count

Asked: remove the count from the Audit panel's title too
(*API calls · 4 of the latest 100 kept*): there's no point in it.

Changed: the title is *API calls* alone, the Clear button at the right.
The widget test no longer looks for the count.

## 2026-11-01: the Audit tab without the count

Asked: the Audit tab's label read *Audit (100)*; remove the number, and
say where it came from.

Changed: the label is *Audit*. The number was the calls in the log:
the dashboard asks the API for the health, the sources and the profile
every 15 seconds, and the log keeps the latest 100 (`CallLog.keep`)
across reloads, so it soon read 100 and stayed there. The panel still
says how many it keeps. The widget test no longer looks for the count.

## 2026-11-01: links on the Health tab

Asked: make OpenMetadata's address on the Health tab clickable, and the
dashboard's, and the API's health check.

Changed: the API, OpenMetadata and Dashboard cards end with a link that
opens in a new tab (`StatusCard.link`): `/api/health` where the app
calls the API (`apiAddress`), the URL OpenMetadata's check reports, and
this page (`Address.page`). `Address.open` opens it (`window.open`,
`noopener`; off the web it records the link, for tests). A widget test
taps the three.

## 2026-10-31: the catalogue and DeepAR tags on the Catalog tab

Asked: see HealthHub's schema in the dashboard (in dev) and tag it for
machine learning, DeepAR.

Changed: the Catalog tab reads each database source's catalogue and time
series from the API (`/api/datasources/{id}/catalog` and `/timeseries`),
with **Read schema** to read it into OpenMetadata, each table's columns,
types, keys and tags, a readiness badge and DeepAR box, and
`TimeSeriesDialog` to tag a table's columns with the TimeSeries roles,
its frequency and missing rows (`PUT .../timeseries`); the API client's
models and calls for them (`CatalogTable`, `TimeSeriesRole`,
`TimeSeriesSpec`, `TimeSeriesRoles`, `CatalogSync`), and its errors carry
the API's own message; the fake and a widget test.

## 2026-10-30: the Health tab from /api/health

Asked (of the API): remove its hello, greetings and status endpoints, and
add a health check with the profile and mode it runs in.

Changed: the Health tab reads `GET /api/health` (`SystemStatus.fromHealth`,
a 503 being a check down, not a failed call); the API card shows the
profile, launch mode and `jvm` or `native`; PostgreSQL shows ok or the
error, no longer its version; the Records card is gone with the status's
counts. The health monitor checks the API on `/api/health/live`.

## 2026-10-29: the audit header fits a narrow window

Asked: fix the review's finding that the Audit tab's count of kept calls
could push the Clear button out of a narrow panel.

Changed: the count takes the room left in the header row and ends in an
ellipsis when short of it, so the Clear button always shows.

## 2026-10-29: tabs reordered, a Catalog tab, kept across a reload

Asked: the tabs in the order Data sources, Catalog, Audit, Health,
Profile, with a new Catalog tab right after Data sources showing datyx's
interpretation of the data in the data sources; and a refresh of the
page keeps everything: the sign-in, the open tab, the rest.

Changed: `DashboardTab` holds the tabs' order, labels and names, and a
`TabController` of the screen's own; `CatalogTab` explains that the API
doesn't read the sources yet and lists each as not catalogued (the
interpretation itself needs the API first); the open tab is kept in the
address as `?tab=<name>` (`lib/persist/address.dart`); the ID token and
the audit are kept in the browser tab's session storage
(`lib/persist/session_store.dart`, `package:web` now a direct
dependency): a kept, fresh token for the API's client signs in at once,
and one refused and not renewed signs out; the tests for each.

## 2026-10-29: the Profile tab

Asked: profiles on the datyx API and the dashboard (see
[../../datyx/specs/requests.md](../../datyx/specs/requests.md)).

Changed: a Profile tab (`ProfileTab`, key `tab-profile`, second) showing
`GET /api/profile`: the profile, its data source count, the note on its
key, and its identities; `Profile` and `ProfileIdentity` in the client,
`profile()`, the profile id in `Me`, and the profiles count in
`SystemStatus`, shown on the Health tab's Records and Sign-in cards; the
profile asked with every refresh when not locked; the tests.

## 2026-10-29: a favicon of its own

Asked: an appropriate favicon for datyx, in the same style and colors as
the other demos', reflecting what the project is for.

Changed: a database cylinder with its catalog cut into it, the lid and a
band as curved slots and a lineage branching from one source to two,
aityx orange on the dark page background: `assets/icon/icon.svg` and
`icon_foreground.svg`, rendered to PNG, and `flutter_launcher_icons` in
`pubspec.yaml` generating the web icons from them, which also set the
manifest's colors to the page's. The tab shows `web/favicon.svg`, the
cylinder as a flat orange glyph with no background, as aityx.ai's own
favicon is drawn; `index.html` keeps the PNG tile as the fallback. See
[App icon](app-icon.md).

## 2026-10-29: navigation tabs; hello and greetings gone

Asked: navigation tabs like the other apps: Data sources first, with the
same content as before; the health checks in a Health tab, with the
version; an Audit tab for the API calls. Remove the hello and greetings
parts, which have proved the path.

Changed: `DashboardScreen` got a `TabBar` under the app bar with Data
sources, Health and Audit (the Audit label counts the calls); the status
cards moved to `HealthTab` (`lib/dashboard/health_tab.dart`) with a
Dashboard card holding the version, which left the app bar, and the
Records card counting data sources only; the calls panel fills the Audit
tab and says how many calls it keeps; the Hello and Greetings cards, and
`hello`, `greetings`, `addGreeting` and `Greeting` in the API client, are
gone (the API still serves them). The tests follow the tabs.

## 2026-10-29: the dev containers by demo group

Asked: separate the dev containers, images and Codespaces configurations
by demo group.

Changed: the dashboard now runs in a codespace, in the datyx group's dev
container, **datyx demos** (`.devcontainer/datyx/devcontainer.json` at
the repository root), on the group's image
`docker.io/aletyxcode/samples-and-demos-datyx` (`bash
image/build-image.sh datyx`), which carries the API's GraalVM and the
dashboard's release web build and starts it with the API, HealthHub and
the index page. There was no per-demo dev container for it to replace;
the per-demo ones of the other folders were removed. The known
limitation saying it had no codespace is gone from
[dev-environment.md](dev-environment.md).

## 2026-10-28: data sources, and signing in with Google

Asked: let users add or remove data sources (databases, S3, filesystem,
each with its access details), the first entity of datyx; OIDC
authentication on the API, the dashboard and HealthHub, with the user's
identity propagated through; Google sign-in.

Changed: the data sources card and the add dialog, the Sign-in and
Records status cards, the account corner with Google's sign-in button
(`google_sign_in`, `google_sign_in_web`), `AuthController` reading the
client id from the API's `GET /api/auth/config`, the ID token as a bearer
on every call with one silent retry after a 401, the API client's new
calls, and the tests. No setting here: the client id lives with the API.

## 2026-10-28: datyx-dashboard, a folder of its own

Asked: create `datyx-dashboard`, a Flutter app like the other demos',
accessing the datyx API; the `datyx` module becomes API only, and the
dashboard a separate app that invokes it.

Changed: `datyx/datyx-dash/` moved here as `datyx_dashboard/` (package
`datyx_dashboard`), unchanged but for its name and its web server's
settings (`FLUTTER_WEB_PORT`, `DATYX_BIND_HOST`, `DATYX_API_URL`); this
folder got the demos' layout: `devbox.json` (Flutter, with the demos'
lock), `process-compose.yaml` (the dashboard and the health monitor, no
API), `compose.yaml` (nginx with the API's address as a template
variable, the host's 9900 by default), `scripts/` (`flutter-web.sh`,
`build.sh`, `make.sh`, `health-check.sh` with Dash, API and Proxy,
`env.sh`, `version.sh`), the Makefile, the id and version files
(`datyx:datyx-dashboard`, `0.1`), README, AGENTS.md, CLAUDE.md and these
specs. The port stays 9906. The repository's `start-all.sh` learned to
wait for a demo without a web app on its API's `/api/health`, the index
page got a card for the dashboard and the datyx card points at the API,
and the README lists both.
