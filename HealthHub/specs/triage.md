# Triage at the desk

Every admission the API records is triaged by aityx from what the
patient said at the desk and their age: how soon they must be seen, where
in the hospital they go, whether a nurse checks first, and why. What
aityx does, the questions, the tables, sample cases and how well they
agree with the reference levels are in [docs/aityx.md](../docs/aityx.md);
this file is how the software does it.

## The call

[lib/triage.dart](../healthhub_api/lib/triage.dart). One `POST
<AITYX_URL>/v1/systemone` per admission, with the key as a bearer token,
a 60 s timeout, and the body
[data/triage/triage.json](../healthhub_api/data/triage/triage.json) (the
Jev model `jev-latest`, twelve questions and the decision, compiled into
`lib/triage_seed.dart` by `tool/generate_triage.dart`, since the API is
one native executable; a test checks the two match) with the state
`{"complaint": <what the patient said>, "age": <years>}`. Nothing else
of the admission goes to aityx: not the name, not the condition.

aityx runs Jev first (shape `jev_aityx`): eight `noul` questions, the
probability of each danger sign (`life_threat`, `breathing`, `cardiac`,
`stroke`, `major_injury`, `serious_infection`, `dehydration`,
`self_harm`, each `<sign>_probability`), and four `choice` questions
(`pain`, `onset`, `visit_purpose`, `body_system`). The decision,
**HealthHub · Triage at the desk**, takes them with the age and answers:

- `level`: `red`, `orange`, `yellow`, `green` or `blue` (immediate, very
  urgent, urgent, standard, non-urgent), the first of 14 rules that
  applies; a sign counts at a probability of 0.7 (`evidence`);
- `wait_minutes`: 0, 10, 60, 120 or 240, by level;
- `area`: `resuscitation`, `emergency`, `mental_health`, `minor_care`,
  `outpatients` or `day_unit`, the first of 8 rules that applies;
- `nurse_check`: a sign that raises the level in doubt (0.35, `doubt`, to
  0.7), or a possible serious infection at 65 or older.

The rules are listed in [docs/aityx.md](../docs/aityx.md#the-decision).

`toTriage` reads the answer: the level, wait, area and nurse check; the
rule of the level and area tables from the receipt's `decisions` and its
`# why` from the model; the eight probabilities and the four choices with
their confidence; the receipt; the input tokens. A `decision_error`, a
missing answer or an unknown level is a `TriageFailed`, and so is an
answer other than 200, by its error code (never the key).

## When it runs

`HEALTHHUB_TRIAGE` (`on`, the default, or `off`; anything else stops the
server) and an `AITYX_API_KEY`: without both, nothing is triaged and
`/api/health` says `"triage": false`. In dev mode, the admission recorder
hands each admission it inserts, the first time only (not a replay), to
the `Triager`, which triages four at a time in the background so the feed
never waits on aityx; beyond 500 waiting, the oldest are dropped, each
logged. Each triage, or its failure, is recorded once
(`admission_triage`, [Database](database.md)): a failure keeps its
reason and isn't retried. At a stop the API gives the triages under way
5 s.

## The reference

Each complaint template has a reference level, the level a nurse applying
the same policy gives it ([Medical conditions](conditions.md#triage-reference-levels)),
and each admission says which template it was said from (`template`,
[Simulation](simulation.md#admissions)). The triage records the
reference beside aityx's level, so the summary counts how often they
agree.

## Reading it

- `GET /api/triage?limit=20` ([API](api.md)): `{"enabled", "summary",
  "triaged"}`. The summary counts every triage: `total`, `failed`,
  `compared` (with a reference), `matched`, `withinOne`, `under` (less
  urgent than the reference), `over`, `nurseChecks`, `inputTokens`,
  `medianMillis` and `levels`, how many of each. `triaged` is the latest,
  newest first, each with the admission (who, what they said, the
  condition, the visit, the hospital, the simulated day and time) and its
  triage, without the receipt.
- `GET /api/triage/{eventId}`: one, with aityx's receipt and `rules`, the
  `# why` of every rule of the level and area tables in order; 404 when
  the admission has none.
- Home's **Triage at the desk** card ([Home](home.md)).

## Checking it

- `test/triage_test.dart`: the request, a real answer (a fixture) read
  into a triage, failures, the reference lookup, the queue, the routes;
  offline.
- `scripts/model-test.sh` (`test/triage_model_test.dart`, tagged
  `aityx`, skipped without a key): the decision alone on aityx, with
  Jev's readings given as facts, at each rule and threshold.
- `scripts/triage-cases.sh` (`tool/triage_cases.dart`): every template
  of every condition, said by a sample patient, triaged as an admission
  is, against its reference; writes
  [docs/aityx-triage-cases.md](../docs/aityx-triage-cases.md).

## Known limitations

- A demo's policy and reference levels, not clinically reviewed; not for
  real patients.
- Each admission is triaged once; admissions recorded before the triage
  was on, while aityx was down, or dropped from a full queue stay
  untriaged, and nothing triages them later.
- Jev's readings vary a little between calls, so the same complaint can
  land on either side of a threshold.
- Admissions recorded before `template` existed have no reference.
