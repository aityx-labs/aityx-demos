# aityx in HealthHub

What HealthHub does with [aityx.ai](https://aityx.ai), feature by feature:
what each decides, how Jev and aityx split the work, the questions and the
rules, sample cases with what aityx answered and why, and how to run and
change it. The [specs](../specs/README.md) say how the software is built;
this document says what aityx does in it.

aityx is a decision API with one endpoint, `POST /v1/systemone`. A call
carries up to three things:

- **Questions for Jev**, about text: Jev reads it and answers each with a
  probability (`noul`), one of a set of options (`choice`), or a score.
- **A decision**: typed inputs, decision tables and expressions, which
  aityx runs on the facts it is given and on Jev's answers. The same
  facts always give the same answer.
- **The state**: the facts of this one case.

The answer holds every answer, and a **receipt**: which inputs came from
Jev and which from the state, and for every decision its value and the
rule that produced it.

| Feature | What aityx decides | Where |
|---|---|---|
| [Triage at the desk](#triage-at-the-desk) | How soon each patient arriving at a hospital must be seen, where in the hospital they go, and whether a nurse checks first, from what they say at the desk | Every admission, in the API; home's **Triage at the desk** card |

## Triage at the desk

### What it does

Every simulated patient who arrives at a hospital says what is wrong at
the desk, in their own words ([conditions.md](../specs/conditions.md)):

> Hi, I'm Núria Puig Soler, I'm 86. I've had a high fever and a cough with
> rusty-coloured phlegm for three days, and now I get a sharp pain on the
> right side of my chest when I breathe in.

HealthHub sends that sentence and the patient's age to aityx, and nothing
else: not the condition, which the simulation knows and a desk wouldn't.
One call answers:

- **The level**, on a five-level scale after the Manchester Triage
  System's: 🔴 immediate, 🟠 very urgent, 🟡 urgent, 🟢 standard,
  🔵 non-urgent.
- **The longest wait**: 0, 10, 60, 120 or 240 minutes.
- **The area**: resuscitation, the emergency department, the mental
  health team, minor illness and injury, outpatients, or the day unit.
- **Whether a nurse checks** the level first, because a danger sign is in
  doubt.
- **Why**: the rule behind the level and the rule behind the area, each
  with its reason.

For Núria: 🟡 urgent, seen within 60 minutes, in the emergency department,
because of "a fever with signs of serious illness" (Jev's probability of a
serious infection: 0.94), and a nurse checks first, since she is 86.

### How Jev and aityx share the work

```
 the desk                     one call to aityx                                  HealthHub
┌──────────────┐   ┌──────────────────────────────────────────────────────┐   ┌──────────────┐
│ complaint    │──▶│ Jev reads the complaint:                             │   │ level, wait, │
│ age          │   │   8 danger signs, each a probability                 │──▶│ area, nurse, │
└──────────────┘   │   4 choices: pain, onset, visit purpose, body system │   │ the rules,   │
                   │ the decision runs the triage policy on them:         │   │ the receipt  │
                   │   thresholds → signs present or in doubt             │   └──────────────┘
                   │   level table → wait table → area table → nurse      │
                   └──────────────────────────────────────────────────────┘
```

**Jev does the reading.** A complaint is free text: "I can hardly
breathe", "my lips felt blue on the stairs", "I can't finish a sentence"
all mean one danger sign, and "breathless on the stairs, as usual" means
none. Jev turns each into a probability, one question per sign, so the
policy never has to parse language.

**The decision does the deciding.** The triage policy is a set of tables
anyone can read: which sign, at which probability, makes which level;
which level goes to which area. Its thresholds are numbers in the model,
0.7 for a sign to count and 0.35 for a nurse to check, not a judgement
inside a language model. Given the same readings it always gives the same
level, and its receipt says which rule fired. Changing the policy means
editing a table and running the cases again
([Running and changing it](#running-and-changing-it)), not rewording a
prompt and hoping.

**A nurse covers the doubt.** A sign between 0.35 and 0.7 doesn't change
the level, but sets `nurse_check`: the patient waits at the level the
present signs give, and a nurse confirms it first. So does a fever at 65
or older, when sepsis moves fast.

### What Jev is asked

Twelve questions, each with criteria for its answers
([data/triage/triage.json](../healthhub_api/data/triage/triage.json)
has them in full). The eight danger signs are `noul` questions, a
probability from 0 to 1:

| Question | Jev's answer: the probability that the complaint describes |
|---|---|
| `life_threat_probability` | An immediate threat to life: choking or not breathing; swelling of the face, lips, tongue or throat; collapse or fainting with a racing heart; shock; heavy bleeding that pours or spurts despite pressure; crushing chest pain at rest with sweating, nausea or vomiting |
| `breathing_probability` | Breathing beyond the patient's usual: breathless at rest, talking, lying flat or waking up gasping; breathless across a room or getting dressed; a reliever needed far more often or no longer helping; a low peak flow; blue lips; oxygen at 94 or below |
| `cardiac_probability` | Chest pain or pressure that could come from the heart and is new, worse or at rest (heavy, squeezing, central, spreading to the arm, jaw or back), or a racing, irregular heartbeat with breathlessness, light-headedness or weakness. A burning after meals, or stable angina at a booked review, doesn't count |
| `stroke_probability` | A sudden problem in the brain: weakness or numbness of the face, an arm or a leg, slurred or lost speech, sudden confusion or loss of vision, a fit, a thunderclap headache |
| `major_injury_probability` | An injury that needs prompt treatment: a limb that looks broken, a joint that can't be moved after a fall, a deep or gaping wound, a wound still bleeding, a head injury |
| `serious_infection_probability` | A fever with signs of serious illness: high with chills or rigors, with confusion or breathlessness, with pain in the side or back, or with red, hot, spreading skin |
| `dehydration_probability` | Fluid loss with a sign of dehydration: vomiting or diarrhoea and unable to keep fluids down, very little urine, a dry mouth, dizzy on standing |
| `self_harm_probability` | Thoughts of suicide, of self-harm or of harming others. Low mood or hopelessness alone doesn't count |

The four choices pick one option each:

| Question | Options |
|---|---|
| `pain`: the worst pain now | `severe` (unbearable, 8 to 10), `moderate` (stops them walking, swallowing, bearing weight or sleeping; 5 to 7), `mild` (an ache they get on with, or a long-standing pain; 1 to 4), `none` |
| `onset`: when it started or last got worse | `today`, `this_week`, `longer` |
| `visit_purpose`: why they came today | `new_problem`, `worse` (clearly worse, or a new symptom), `follow_up` (a booked review, check, result or wound check, symptoms carrying on included), `treatment_session` (dialysis, chemotherapy, an infusion) |
| `body_system`: what it is mainly about | breathing, heart, brain and nerves, digestion, kidneys and urine, bones and joints, skin and wounds, eyes, ears and throat, mental health, hormones and metabolism, cancer, general |

### The decision

The decision, **HealthHub · Triage at the desk**, takes the age from the
desk and Jev's twelve answers. A sign is present at a probability of
`evidence`, **0.7**, and in doubt from `doubt`, **0.35**. A patient is
`older` at 65, and the problem is `recent` unless its onset is `longer`.

**The level** is the first rule that applies, top to bottom (aityx's FIRST
hit policy), so the most dangerous sign present wins:

| # | When | Level | Why (the rule's `# why`) |
|---:|---|---|---|
| 1 | a threat to life | 🔴 red | An immediate threat to life: seen at once, in resuscitation. |
| 2 | signs of a stroke | 🟠 orange | Signs of a stroke or another sudden problem in the brain: every minute counts. |
| 3 | struggling to breathe | 🟠 orange | Struggling to breathe at rest or while talking. |
| 4 | heart pain or palpitations | 🟠 orange | Chest pain or palpitations that may come from the heart, until a tracing says otherwise. |
| 5 | thoughts of self-harm | 🟠 orange | Thoughts of self-harm: seen within 10 minutes and not left alone. |
| 6 | severe pain | 🟠 orange | Severe pain, which is treated within 10 minutes whatever its cause. |
| 7 | an injury needing treatment | 🟡 yellow | An injury that needs prompt treatment: a possible fracture, a deep wound or a head injury. |
| 8 | a serious infection | 🟡 yellow | A fever with signs of serious illness. |
| 9 | dehydrated | 🟡 yellow | Losing fluids faster than they can be kept down. |
| 10 | moderate pain | 🟡 yellow | Moderate pain: it hurts to move, swallow or bear weight. |
| 11 | a booked treatment session | 🔵 blue | A booked treatment session, with no danger signs: it goes to its unit for its slot. |
| 12 | a booked review or check | 🔵 blue | A booked review or check, with no danger signs: seen at its appointment. |
| 13 | a recent problem | 🟢 green | A new or recent problem with no danger signs. |
| 14 | anything else | 🔵 blue | A long-standing problem with no danger signs and nothing new. |

**The wait** follows the level: 🔴 at once, 🟠 within 10 minutes,
🟡 within 60, 🟢 within 120, 🔵 within 240, or at the appointment.

**The area**, again the first rule that applies:

| # | When | Area | Why |
|---:|---|---|---|
| 1 | the level is red | Resuscitation room | Immediate threats to life go to the resuscitation room. |
| 2 | thoughts of self-harm | Mental health team | The mental health liaison team sees a patient at risk, in a safe room. |
| 3 | the level is orange or yellow | Emergency department | Very urgent and urgent patients are seen in the emergency department. |
| 4 | a booked treatment session | Day unit | Booked treatments, such as dialysis or chemotherapy, run in the day unit. |
| 5 | a booked review or check | Outpatients clinic | Booked reviews and checks are seen in the specialty's clinic. |
| 6 | about mental health | Mental health team | Low mood, anxiety and memory worries are seen by the mental health team. |
| 7 | not recent | Outpatients clinic | A long-standing problem with nothing new is booked into the specialty's clinic. |
| 8 | anything else | Minor illness and injury | A recent problem with no danger signs goes to the minor illness and injury stream. |

**The nurse's check** (`nurse_check`) is true when any of the signs that
raise the level, a threat to life, breathing, heart, stroke, injury or
self-harm, is in doubt (0.35 to 0.7), or when a patient 65 or older may
have a serious infection (0.35 or more).

### Sample classifications

Real aityx answers, from the run of every complaint
([aityx-triage-cases.md](aityx-triage-cases.md), 369 of them). "Jev read"
lists the signs at 0.2 or more and the choices; the rule is the level
table's. The **reference** is the level a nurse applying the same policy
gives the same words ([How well it agrees](#how-well-it-agrees)).

**Every level, and every area**

| The patient said | Jev read | Rule | aityx | Area | Reference |
|---|---|---:|---|---|---|
| "I ate a cake with nuts in it twenty minutes ago and my throat is closing up, my lips and tongue are swelling and I can hardly breathe." (49) | threat to life 0.99, breathing 0.92; no pain, today, new | 1 | 🔴 Immediate | Resuscitation | 🔴 ✅ |
| "I woke up with a heavy weight on my chest that won't go away, I'm drenched in a cold sweat, grey in the face according to my partner, and I've vomited." (62) | threat to life 0.98, heart 0.96; today, new | 1 | 🔴 Immediate | Resuscitation | 🔴 ✅ |
| "About forty minutes ago my right arm suddenly went weak and heavy, I dropped my cup, and my wife says the side of my face is drooping." (40) | stroke 0.97; no pain, today, new | 2 | 🟠 Very urgent | Emergency | 🟠 ✅ |
| "I smoked for thirty years and now I get out of breath walking to the shop; this week I can barely get dressed without stopping." (63) | breathing 0.92; this week, worse | 3 | 🟠 Very urgent | Emergency | 🟠 ✅ |
| "For three weeks I've had a heavy, squeezing pain in the middle of my chest when I walk uphill, it goes into my left arm, and it eases after a few minutes of rest." (57) | heart 0.83; mild pain, longer, new | 4 | 🟠 Very urgent | Emergency | 🟠 ✅ |
| "I woke up with severe low back pain, it hurts to sit, walk or turn over in bed, but I have no numbness." (44) | no sign; severe pain, today, new | 6 | 🟠 Very urgent | Emergency | 🟠 ✅ |
| "I fell off my bike an hour ago and put my hand out, now I can't move my wrist and my fingers feel tingly." (77) | injury 0.96; today, new | 7 | 🟡 Urgent | Emergency | 🟡 ✅ |
| "I've had a high fever and a cough with rusty-coloured phlegm for three days, and now I get a sharp pain on the right side of my chest when I breathe in." (86) | serious infection 0.94; mild pain, this week, new | 8 | 🟡 Urgent, a nurse checks | Emergency | 🟡 ✅ |
| "Since last night I've been vomiting and had watery diarrhoea more than ten times, I can't keep water down and I feel dizzy." (81) | dehydration 0.98; today, new | 9 | 🟡 Urgent | Emergency | 🟡 ✅ |
| "My throat is so sore I can barely swallow, I have a fever of 38.8 and there are white spots on my tonsils, but no cough." (55) | no sign; moderate pain, today, new | 10 | 🟡 Urgent | Emergency | 🟡 ✅ |
| "Here for my dialysis session. I've put on two kilos since last time, I've tried to keep to the fluid limit, and the buzz in my fistula feels normal." (46) | no sign; treatment session | 11 | 🔵 Non-urgent | Day unit | 🔵 ✅ |
| "I'm here to have my stitches taken out, the cut looks well healed." (46) | no sign; follow-up | 12 | 🔵 Non-urgent | Outpatients | 🔵 ✅ |
| "For the last three days I've had a sore throat, a blocked runny nose and I keep sneezing, and paracetamol only helps a little." (18) | no sign; mild pain, this week, new | 13 | 🟢 Standard | Minor illness and injury | 🟢 ✅ |
| "For months I've felt exhausted, cold all the time, and I've put on five kilos without eating more; my hair is thinning too." (67) | no sign; longer, new | 14 | 🔵 Non-urgent | Outpatients | 🔵 ✅ |
| "I've been crying most days and lost my appetite for over a month; I don't want to hurt myself, but I feel like there's no point." (40) | self-harm 0.29; longer, about mental health | 14 | 🔵 Non-urgent | Mental health team | 🔵 ✅ |

**Where reading words well matters**

| The patient said | What Jev made of it | aityx | Reference |
|---|---|---|---|
| "I had a spell of shaking, sweating, and a tight chest this morning; it's been building for half a year and I can't switch my mind off." (35, anxiety) | A tight chest with sweating is chest pain that may be the heart (0.82) until a tracing says otherwise, though the story is anxiety's | 🟠 Very urgent | 🟠 ✅ |
| "I've had heartburn for weeks; last night it was bad enough that I worried it was my heart, but it's a burning that goes up into my throat." (51, reflux) | The patient's own worry isn't heart pain: a burning that rises into the throat (heart 0.07) | 🔵 Non-urgent | 🟢 one level apart |
| "Last night I had the same tightness in my chest again while lying in bed, it lasted ten minutes and the spray helped." (69, after a heart attack) | Chest tightness at rest after a heart attack (heart 0.91), on what reads like a review | 🟠 Very urgent | 🟠 ✅ |
| "Here for the scan of my heart arteries. The chest pain still comes on with brisk walking, though it's less often." (87, angina) | Known, stable angina at a booked review (heart 0.23): no danger sign | 🔵 Non-urgent | 🔵 ✅ |
| "I cut my hand on a kitchen knife about an hour ago, it's a deep cut on my palm and it keeps bleeding through the towel." (32) | An injury needing treatment (0.99), but not a threat to life (0.34): bleeding through a towel isn't pouring | 🟡 Urgent | 🟡 ✅ |
| "A few hours ago I saw zigzag lines in my vision, then a severe pounding headache started behind my right eye and I feel very sick." (45, migraine) | Severe pain; a migraine's aura is not a stroke, but stroke at 0.36 is in doubt | 🟠 Very urgent, a nurse checks | 🟠 ✅ |
| "My smartwatch keeps alerting me to an irregular rhythm, and for a week I've had palpitations and been tired on my usual walks." (65) | Palpitations without breathlessness or light-headedness: heart at 0.57, in doubt | 🟢 Standard, a nurse checks | 🟢 ✅ |
| "I slipped on the stairs and turned my ankle, I heard a pop and now there's a big swelling below the ankle bone." (50) | A possible fracture, in doubt (0.54) | 🟢 Standard, a nurse checks | 🟡 one level apart |
| "I've been coughing at night and short of breath on the stairs for two weeks, I've used my inhaler a lot more than usual, and this morning I was really frightened." (46, asthma) | A reliever needed far more than usual: struggling to breathe (0.81) | 🟠 Very urgent | 🟢 two levels apart |

The last three are disagreements, and they show the pattern of the rest.
Where aityx is less urgent than the reference, a sign is nearly always in
doubt, and the nurse's check catches it. Where it is more urgent, it reads
a word like "a lot more than usual" more cautiously than the reference
did.

### How well it agrees

To measure the triage, each of the 369 complaint templates has a
**reference level** (`triage` in
[data/conditions/*.json](../healthhub_api/data/conditions/), one per
template): the level a nurse applying the same policy, the tables above,
gives what the template says. The simulation knows which template each
patient said, so every admission is compared with it as it is triaged.

The run of every template ([aityx-triage-cases.md](aityx-triage-cases.md),
1 November 2026):

| | Complaints | Share |
|---|---:|---:|
| The same level as the reference | 345 of 369 | 93.5% |
| Within one level | 361 | 97.8% |
| Less urgent than the reference | 11 | 3.0% |
| More urgent than the reference | 13 | 3.5% |
| For a nurse to check | 21 | 5.7% |

| Reference ↓ · aityx → | 🔴 | 🟠 | 🟡 | 🟢 | 🔵 |
|---|---:|---:|---:|---:|---:|
| 🔴 Immediate | 5 | · | · | · | · |
| 🟠 Very urgent | · | 31 | · | · | · |
| 🟡 Urgent | · | 1 | 35 | 1 | · |
| 🟢 Standard | · | 1 | 1 | 26 | 10 |
| 🔵 Non-urgent | · | · | 7 | 3 | 248 |

Every immediate and very urgent complaint got its level. The one urgent
complaint triaged lower, the ankle that "popped", went to a nurse. Most
of the rest are standard against non-urgent on a return visit: a
patient whose cold still keeps them up, which the reference reads as
worse and Jev as carrying on.

These figures are of one run. Jev's readings vary a little from call to
call, so a run gives a few more or fewer matches, and the complaints that
change are the ones near a threshold, which the nurse's check is for.

**How the questions got here.** The first run matched 85.1% of the
references, and 18 complaints came out less urgent, most of them
breathlessness that wasn't at rest: COPD, heart failure and asthma
flare-ups. The questions were made more precise (breathless across a
room, lying flat, or with a reliever no longer helping; a cut that oozes
isn't pouring; pain the patient lives with is mild; a symptom that
carries on is a follow-up, not worse), with the policy and the references
unchanged. The second run matched 93.5%.

**Whose reference.** The reference levels were written for this demo by
applying the policy to each template, not by clinicians, and the policy
is a demo's, after the Manchester Triage System's levels and
discriminators, not a clinical one. The agreement says how well Jev reads
complaints as the policy means them, not how good the policy is.

### Explainable

Every triage keeps, with the admission:

- **What Jev read**: the eight probabilities and four choices, with
  Jev's confidence in each.
- **The rules**: the level's rule and its why, the area's rule and its
  why.
- **aityx's receipt**, as aityx returned it. Its `read` lists each of
  Jev's answers with `source: jev`; its `provenance` says where every
  input came from (`age`: `state`, the rest `jev`); and for every
  decision its value, the rule that fired, and for each rule before it
  which condition didn't hold:

```json
"level": {
  "value": "yellow",
  "rule": 9,
  "rows": "xxxxxxxxF...++",
  "cells": ["FTTTTTTTTTT", "TFTTTTTTTTT", "TTFTTTTTTTT", "…", "TTTTTTFTTTT", "TTTTTTTTTTT", "…"]
}
```

That is the receipt of a patient "throwing up since yesterday" with a dry
mouth: rule 9, dehydration, fired. Each of `cells` is a rule, a letter
per column of the table: the `F` in each of rules 1 to 8 is the condition
that kept it from applying (no threat to life, no stroke sign, and so on),
and rule 9's are all true.

In the app, a tap on a triage on home opens all of it: the complaint,
each sign's probability against the two thresholds, the choices, each
rule of the level and area tables tried in order with ✗ until the ✓ that
fired, the nurse's check, the reference, and the receipt. `GET
/api/triage/{eventId}` answers the same.

### In the API and the app

- The API triages each admission when it first records it, in the
  background, four at a time, so the feed never waits on aityx
  ([lib/triage.dart](../healthhub_api/lib/triage.dart)). It keeps the
  triage in `admission_triage` ([database.md](../specs/database.md)), and
  a failure with its reason.
- `GET /api/triage?limit=20` answers the summary of every triage, against
  the references, and the latest triages; `GET /api/triage/{eventId}`
  answers one with its receipt ([api.md](../specs/api.md)).
- Home's **Triage at the desk** card lists the latest triages under the
  map, with the summary above them ([home.md](../specs/home.md)).
- On with an aityx key unless `HEALTHHUB_TRIAGE=off`; the key stays in
  the API. In development the calls go through datyx's aityx gateway,
  with datyx's key, so its dashboard's aityx tab accounts for them, and
  to aityx directly when datyx can't pass them on
  ([triage.md](../specs/triage.md#which-way-through-datyx-or-directly)).

### Cost and speed

A triage is one call of about 4,200 input tokens (the questions and the
decision are most of it), at $0.042 per million: under $0.0002 a patient.
The median call took 270 ms. The simulation's ten or so admissions a
minute cost about $0.11 an hour. The run of all 369 complaints took 20 seconds,
six at a time, for $0.065.

### Running and changing it

- The model is [data/triage/triage.json](../healthhub_api/data/triage/triage.json):
  the questions and the decision, as aityx takes them (paste it into the
  [aityx console](https://console.aityx.ai) to try a complaint by hand).
  After changing it, `dart run tool/generate_triage.dart` in
  `healthhub_api/` compiles it into the API.
- `scripts/model-test.sh` runs the decision on aityx with Jev's readings
  given as facts, at every rule and threshold (no Jev, so the same answer
  every time): 20 checks.
- `scripts/triage-cases.sh` triages every complaint template and writes
  [aityx-triage-cases.md](aityx-triage-cases.md) and the agreement
  above; run it after changing the questions, the policy or the
  complaints.
- The references are the `triage` of each condition in
  [data/conditions/](../healthhub_api/data/conditions/), one per template;
  after changing them, `dart run tool/generate_conditions.dart`.

### Limits

- A demo's triage, on simulated patients: not a medical device, and not
  for real patients. The policy and the references haven't been through
  clinical review.
- Each admission is triaged once, on arrival. A later admission isn't
  triaged again, and admissions recorded before the triage was on, or
  while aityx was down, stay untriaged.
- The desk knows only the complaint and the age: no vital signs, no
  history, no observation. A real triage would add them as facts the
  decision takes.
- aityx keeps no history: what HealthHub keeps, the triage and the
  receipt in its database, is the record.
