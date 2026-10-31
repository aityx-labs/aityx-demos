# Medical conditions

The common diseases and illnesses the simulated people have
([Simulation](simulation.md)): 19 acute and 19 chronic
conditions of adults, each with what it is, its usual treatment and
duration, how it brings someone to the hospital, and what a patient with
it says on arrival. The data is
[data/conditions/acute.json](../healthhub_api/data/conditions/acute.json)
and [chronic.json](../healthhub_api/data/conditions/chronic.json),
written by content writers and checked by a clinical reviewer;
[tool/generate_conditions.dart](../healthhub_api/tool/generate_conditions.dart)
compiles it into
[lib/conditions_seed.dart](../healthhub_api/lib/conditions_seed.dart),
since the API ships as a single native executable, and a test checks the
two match. At every start the API seeds it into the `medical_conditions`
and `complaint_templates` tables ([Database](database.md)), and the
simulation draws people's conditions from it.

## The data

Each file is a JSON array; each element:

| Field | What |
|---|---|
| `code` | Unique slug, lowercase `[a-z0-9_]`: the key |
| `name`, `summary` | The condition, and one sentence on what it is |
| `type` | `acute` (it passes) or `chronic` (it stays); must match the file |
| `prevalence` | How common it is among adults, relative to the others: only the ratios matter. Real-world prevalence or incidence is the guide |
| `min_age`, `max_age` | The adult ages it plausibly occurs at, 18 to 90 |
| `treatment` | The usual treatment procedure: drug classes, procedures, follow-up |
| `treatment_duration_days` | Acute: the typical days of treatment and recovery; chronic: null (ongoing) |
| `duration` | The duration as people say it (`5 to 7 days`; `lifelong, with periodic review`) |
| `visits` | `count` (visits in one course, at least 1), `interval_days` (between visits, at least 1), `stay_hours` (per visit, 1 to 72) |
| `female_share` | Optional, 0 to 1 (0.5 when absent): the share of its patients who are women. A person's condition is weighed by it ([Visits](#visits)) |
| `urgent` | Optional, `true` or `false` (`false` when absent): whether the first visit is an emergency, made at any hour of day or night as soon as the condition starts, rather than at a daytime slot |
| `follow_up_stay_hours` | Optional, 1 to 72 (`stay_hours` when absent): the stay of the visits after the first, as an appendicitis stays two days and its wound check an hour |
| `course_gap_days` | Optional, chronic only, 0 or more, or null (null when absent): the days from the last visit of a course to the first of the next. Null is a random 30 to 120; 0 is continuous, the next course starting `interval_days` after the last visit, as dialysis goes on |
| `templates` | `first`, `repeat` and `last`: exactly three complaint templates each, different from one another |

[lib/conditions.dart](../healthhub_api/lib/conditions.dart) checks every
field, and the generator reports every problem of every element at once
(file, index and code) and refuses duplicate codes. A missing file counts
as no conditions of its type; with none at all, nobody goes to the
hospital.

## Visits

A condition's `visits` are a course: `count` visits, `interval_days`
apart, the first a stay of `stay_hours` and the others of
`follow_up_stay_hours`. A person has two kinds of condition, apart:

- **Chronic**: at most one, for life, given when the person is made: 40%
  of people have none. Its visits come in courses, one after another,
  `course_gap_days` apart (30 to 120 days unless the condition says
  otherwise). Only the very first visit of the condition says a `first`
  template; every later one says a `repeat` one, and the last of each
  course a `last` one, so a patient who has been coming for a year never
  sounds new. `{visit_number}` and `{days_since_first_visit}` count
  from that first visit, across courses.
- **Acute**: episodes, drawn from the acute conditions only, that come
  and go: the first starts a random time after the simulation does, and
  each next one a random time after the last ended, exponential with a
  mean of 90 days, so a person has about one every three months. Each
  episode is one course: its first visit says a `first` template, its
  last a `last` one, those between a `repeat` one; an episode of one
  visit says a `first` one.

The two run side by side, so a chronic patient's check-ups and their
colds and sprains interleave. The simulation's side, when visits fall
and how people travel, is in [Simulation](simulation.md#visits).

A condition is drawn by `prevalence` among those of its kind whose
`min_age` to `max_age` holds the person's age (among all of them when
none does), weighed by the person's sex: `prevalence` times twice
`female_share` for a woman, and twice `1 - female_share` for a man, so a
condition with an even share weighs the same for both and the average
stays. Breast cancer, 99% women, is about a hundred times rarer in a man than
in a woman; a share of 1 never happens to a man.

## Complaint templates

What the patient says at the desk: first person, natural spoken English,
one to three sentences, with what a triage nurse routes on (onset,
location, severity, what they tried). `first` is the first time with the
complaint; `repeat` a follow-up (it's a return, how things went, the
treatment so far); `last` the final visit of the course (discharge, a
final check, results, stopping or adjusting treatment). Grammar works for
any adult age and either sex.

Placeholders, in braces, are replaced by the simulation:

| Placeholder | Replaced by |
|---|---|
| `{name}` | The full name (`Núria Puig Soler`) |
| `{first_name}` | The first name |
| `{age}` | The age in years |
| `{sex}` | `man` or `woman` |
| `{occupation}` | The occupation, a noun that reads after "a" (`teacher`, `retired bus driver`) |
| `{city}` | The city they live in |
| `{hospital}` | The hospital they arrive at |
| `{visit_number}` | The visit of the course, from 1 |
| `{days_since_first_visit}` | Days since the course's first visit (0 on it) |

No other braces are allowed. For example, Influenza's first visit:

> Hi, I'm {name}, I'm {age}. Yesterday I suddenly got a high fever, chills and aches all over my body, and I have a dry cough and a pounding headache.

## Acute conditions

| Condition | Ages | Weight | Women | Treatment | Duration | Visits |
|---|---|---|---|---|---|---|
| **Common cold (upper respiratory tract infection)** (`common_cold`): A self-limiting viral infection of the nose and throat, most often caused by rhinoviruses, with sore throat, congestion, sneezing and cough. | 18 to 90 | 30 | 50% | Supportive care only: rest, fluids, paracetamol or ibuprofen for pain and fever, saline nasal sprays or decongestants for a few days; antibiotics are not indicated. Advise return if symptoms last beyond 3 weeks or breathing becomes difficult. | 7 to 10 days (7 d) | 1, 1 h each |
| **Acute gastroenteritis** (`acute_gastroenteritis`): An acute infection of the gut, most often viral (norovirus) or food-borne bacterial, with diarrhoea, vomiting, abdominal cramps and sometimes fever. | 18 to 90 | 15 | 50% | Rehydrate with oral rehydration solution, or IV fluids if dehydrated or unable to keep fluids down, with an antiemetic where needed; antibiotics are not routine. Send a stool culture if there is blood, high fever, recent travel or prolonged symptoms, and advise hand hygiene and staying off work until 48 hours after the last episode. | 2 to 5 days (3 d) | 2, every 3 d, 4 h each |
| **Influenza** (`influenza`): An acute viral respiratory infection caused by influenza A or B, with sudden fever, muscle aches, headache, dry cough and marked fatigue. | 18 to 90 | 8 | 50% | Rest, fluids and paracetamol or ibuprofen for fever and aches; a neuraminidase inhibitor antiviral is offered within 48 hours of onset to people at high risk of complications (aged 65+, pregnant, chronic illness) or with severe disease. Admit if hypoxic or showing signs of pneumonia, and advise return if breathing worsens. | 5 to 7 days, with tiredness that can last 2 weeks (7 d) | 2, every 7 d, 3 h each |
| **Acute low back pain** (`acute_low_back_pain`): Non-specific pain in the lower back lasting less than six weeks, usually mechanical and musculoskeletal, sometimes with pain referred into the buttock or leg. | 18 to 90 | 8 | 50% | Screen for red flags (cauda equina symptoms, trauma, cancer, infection, fever); otherwise reassure, advise staying active and use an NSAID for the shortest time, avoiding routine imaging and long-term opioids. Refer to physiotherapy or a group exercise programme if not improving within a few weeks. | 2 to 6 weeks (28 d) | 2, every 14 d, 2 h each |
| **COVID-19** (`covid_19`): An acute infection with SARS-CoV-2 that ranges from a mild cold-like illness to pneumonia, with fever, cough, sore throat, fatigue and sometimes loss of taste or smell. | 18 to 90 | 6 | 50% | Most cases need only rest, fluids, antipyretics and staying away from others while unwell; people at high risk of severe disease are offered an oral or IV antiviral within the first 5 days. Patients with low oxygen saturation are admitted for oxygen and corticosteroids, with thromboprophylaxis and monitoring. | 7 to 14 days, with fatigue sometimes lasting weeks (10 d) | 2, every 5 d, 3 h each |
| **Acute sinusitis** (`acute_sinusitis`): An inflammation of the paranasal sinuses, usually following a viral cold, with blocked nose, discoloured discharge and facial pain or pressure. | 18 to 90 | 6 | 50% | Most cases are viral and settle with analgesia and saline nasal irrigation; a nasal corticosteroid spray can help if symptoms last more than 10 days. An antibiotic such as a penicillin is reserved for severe symptoms, high fever or worsening after initial improvement, with urgent review for eye swelling or severe headache. | 2 to 4 weeks (14 d) | 2, every 7 d, 1 h each |
| **Acute bronchitis** (`acute_bronchitis`): A self-limiting inflammation of the large airways, usually viral, causing a cough with or without sputum that lasts up to three weeks. | 18 to 90 | 5 | 50% | Reassurance and symptomatic care: fluids, paracetamol or ibuprofen, honey or simple cough remedies; antibiotics are not routinely given. Check for pneumonia (examination, oxygen saturation, CRP or chest X-ray if suspected) and review if the cough lasts beyond 3 weeks or breathing worsens. | 1 to 3 weeks (21 d) | 2, every 14 d, 2 h each |
| **Urinary tract infection** (`urinary_tract_infection`): A bacterial infection of the bladder (cystitis), most often by E. coli, with painful frequent urination and urgency, which can ascend to the kidneys (pyelonephritis). | 18 to 90 | 5 | 80% | Confirm with urine dipstick and send a culture where indicated; treat uncomplicated cystitis with a short course of nitrofurantoin, trimethoprim or fosfomycin according to local resistance (longer courses in men). Fever, loin pain or vomiting suggest pyelonephritis, treated with a 7 to 14 day course and admission for IV antibiotics if unwell. | 3 to 7 days (5 d) | 2, every 3 d, 2 h each |
| **Migraine attack** (`migraine_attack`): An episode of moderate to severe, usually one-sided throbbing headache lasting 4 to 72 hours, with nausea and sensitivity to light and sound, sometimes preceded by an aura. | 18 to 65 | 4 | 75% | Treat with a triptan combined with an NSAID or paracetamol plus an antiemetic; in hospital give IV fluids, an antiemetic such as metoclopramide or prochlorperazine and an NSAID, avoiding opioids. Exclude red flags (thunderclap onset, neurological deficit, fever), and refer for preventive treatment if attacks are frequent. | 4 to 72 hours (1 d) | 1, 4 h each |
| **Cellulitis** (`cellulitis`): A bacterial infection of the deep skin and subcutaneous tissue, usually streptococcal or staphylococcal, causing spreading redness, warmth, swelling and pain, most often on the lower leg. | 18 to 90 | 2.5 | 50% | Mark the edge of the redness, give an oral antibiotic such as flucloxacillin (or clarithromycin or doxycycline if penicillin-allergic) for 5 to 7 days, elevate the limb and treat entry points such as athlete's foot. Admit for IV antibiotics if systemically unwell, rapidly spreading or on the face, and review at 48 hours. | 5 to 14 days (7 d) | 3, every 3 d, 3 h the first, 1 h after |
| **Streptococcal pharyngitis (strep throat)** (`streptococcal_pharyngitis`): An acute bacterial infection of the throat and tonsils by group A Streptococcus, with severe sore throat, fever, tonsillar exudate and tender neck glands, usually without cough. | 18 to 65 | 2 | 50% | Score with Centor or FeverPAIN and confirm with a rapid antigen test where available; give a penicillin (phenoxymethylpenicillin) course, or a macrolide if penicillin-allergic, plus analgesia and fluids. Return urgently if unable to swallow, drooling or with one-sided swelling suggesting a quinsy. | 5 to 10 days of antibiotics, symptoms ease in 3 to 5 days (10 d) | 1, 1 h each |
| **Conjunctivitis** (`conjunctivitis`): An inflammation of the conjunctiva, viral, bacterial or allergic, causing a red, gritty, watery or sticky eye with normal vision. | 18 to 90 | 2 | 50% | Viral cases settle with cool compresses, lubricating drops and strict hand hygiene; bacterial cases resolve mostly on their own, with topical antibiotic drops if severe or persisting, and allergic cases respond to antihistamine drops. Pain, light sensitivity, reduced vision or contact lens wear need same-day eye assessment. | 1 to 2 weeks (7 d) | 1, 1 h each |
| **Skin laceration** (`skin_laceration`): A traumatic cut through the skin, commonly on the hand, scalp or face, that may need closure and assessment for damage to tendons, nerves or vessels. | 18 to 90 | 1.5 | 35% | Control bleeding, irrigate and explore the wound for foreign bodies and tendon or nerve injury, then close with sutures, adhesive strips or tissue glue and update tetanus protection as needed. Remove sutures after 5 to 14 days depending on the site and advise return for signs of infection. | 7 to 14 days to heal (10 d) | 2, every 7 d, 2 h the first, 1 h after; **urgent** |
| **Community-acquired pneumonia** (`community_acquired_pneumonia`): An acute infection of the lung tissue acquired outside hospital, most often caused by Streptococcus pneumoniae, with fever, productive cough, breathlessness and pleuritic chest pain. | 18 to 90 | 1 | 50% | Assess severity (CURB-65, oxygen saturation, chest X-ray, bloods); low-severity cases take an oral antibiotic such as amoxicillin, or doxycycline or a macrolide if allergic, for 5 days, while moderate or severe cases are admitted for IV antibiotics, oxygen and fluids. Review at 48 to 72 hours and arrange a repeat chest X-ray at about 6 weeks for smokers, older patients or persisting symptoms. | Antibiotics for 5 days, recovery over 3 to 6 weeks (42 d) | 3, every 21 d, 24 h the first, 2 h after; **urgent** |
| **Acute otitis externa** (`acute_otitis_externa`): An acute inflammation of the external ear canal, usually bacterial (Pseudomonas or Staphylococcus) and often after swimming, with ear pain, itch, discharge and pain on moving the ear. | 18 to 90 | 1 | 50% | Clean the ear canal (aural toilet), prescribe topical antibiotic ear drops with or without a corticosteroid, insert a wick if the canal is very swollen, give analgesia and keep the ear dry. Review if not settling within a week; spreading redness or diabetes with severe pain needs urgent review for necrotising otitis externa. | 7 to 14 days (7 d) | 2, every 7 d, 1 h each |
| **Ankle sprain** (`ankle_sprain`): A stretch or tear of the ankle ligaments, usually the lateral ligaments after an inversion injury, with pain, swelling and bruising. | 18 to 80 | 0.6 | 50% | Apply the Ottawa ankle rules to decide on an X-ray, then rest, ice, compression and elevation with NSAIDs or paracetamol, early weight-bearing in a supportive brace and progressive physiotherapy exercises. Severe sprains may need a short period in a walking boot and review if instability persists. | 2 to 6 weeks (21 d) | 2, every 14 d, 3 h each |
| **Kidney stones (renal colic)** (`renal_colic`): Severe colicky flank pain caused by a stone obstructing the ureter, radiating to the groin, often with nausea and blood in the urine. | 20 to 80 | 0.3 | 35% | Give an NSAID as first-line analgesia (opioid if contraindicated) and an antiemetic, confirm with non-contrast CT, and offer an alpha-blocker to help pass distal stones of 5 to 10 mm. Urgent decompression is needed if obstructed and infected; stones that do not pass are removed by ureteroscopy or shockwave lithotripsy, with follow-up imaging and prevention advice (fluids, diet). | Most small stones pass within 1 to 4 weeks (21 d) | 2, every 14 d, 8 h the first, 1 h after; **urgent** |
| **Distal radius (wrist) fracture** (`distal_radius_fracture`): A break of the radius just above the wrist, typically from a fall on an outstretched hand, common in older adults with osteoporosis. | 18 to 90 | 0.2 | 70% | Confirm with X-ray, reduce displaced fractures under local or regional anaesthesia and immobilise in a cast or splint for about 6 weeks, with surgical fixation (usually a volar plate) for unstable fractures. Review in fracture clinic with repeat X-rays at 1 to 2 weeks, then physiotherapy after cast removal, and assess bone health in older patients. | 6 weeks in a cast, full recovery over 3 to 6 months (42 d) | 4, every 14 d, 4 h the first, 2 h after; **urgent** |
| **Acute appendicitis** (`acute_appendicitis`): An acute inflammation of the appendix, with pain starting around the navel and moving to the right lower abdomen, loss of appetite, nausea and fever, which can perforate if untreated. | 18 to 80 | 0.1 | 50% | Keep nil by mouth, give IV fluids, analgesia and IV antibiotics, confirm with bloods and ultrasound or CT, then perform a laparoscopic appendicectomy; selected uncomplicated cases may be treated with antibiotics alone. Discharge after 1 to 3 days, with a wound review at 1 to 2 weeks and return to full activity over 2 to 4 weeks. | Surgery with a 1 to 3 day stay, recovery over 2 to 4 weeks (21 d) | 2, every 14 d, 48 h the first, 1 h after; **urgent** |

## Chronic conditions

| Condition | Ages | Weight | Women | Treatment | Duration | Visits |
|---|---|---|---|---|---|---|
| **Hypertension** (`hypertension`): Persistently raised arterial blood pressure (clinic readings of 140/90 mmHg or higher, confirmed by ambulatory or home monitoring) that increases the risk of stroke, heart, and kidney disease. | 25 to 90 | 30 | 50% | Lifestyle measures (salt reduction, weight loss, exercise, limiting alcohol, stopping smoking) plus antihypertensives stepped up to target: ACE inhibitor or ARB, calcium channel blocker, and/or thiazide-like diuretic. Bloods and urine for target-organ damage at diagnosis, then blood pressure review every few weeks while titrating and at least yearly once controlled. | lifelong, with periodic review | 3, every 30 d, 1 h each |
| **Hyperlipidemia** (`hyperlipidemia`): Raised blood levels of LDL cholesterol and/or triglycerides that accelerate atherosclerosis and raise cardiovascular risk, usually without symptoms. | 25 to 90 | 25 | 50% | Cardiovascular risk assessment and lifestyle changes (diet low in saturated fat, exercise, weight loss, stopping smoking), with a statin as first-line drug therapy when risk warrants; ezetimibe or PCSK9-targeted therapy is added if targets are not met. Lipid profile and liver tests are repeated about 3 months after starting, then annually. | lifelong, with periodic review | 2, every 90 d, 1 h each |
| **Osteoarthritis** (`osteoarthritis`): Degenerative joint disease with cartilage loss and bony change, most often in the knees, hips, and hands, causing pain on use, brief morning stiffness, and reduced function. | 40 to 90 | 15 | 60% | Education, weight loss, and structured exercise or physiotherapy as core treatment, with topical NSAIDs, then oral NSAIDs at the lowest effective dose with gastroprotection, and occasional intra-articular corticosteroid injections for flares. Joint replacement is considered when pain and disability persist despite these measures. | lifelong, with periodic review | 3, every 42 d, 2 h each |
| **Gastro-oesophageal reflux disease** (`gerd`): Recurrent reflux of stomach contents into the oesophagus causing heartburn and regurgitation at least weekly, sometimes with oesophagitis. | 18 to 90 | 15 | 50% | Lifestyle changes (weight loss, smaller meals, avoiding late meals and trigger foods, raising the head of the bed, stopping smoking) plus an 8-week course of a proton pump inhibitor, then stepping down to the lowest effective dose or on-demand use. Endoscopy if there are alarm features (difficulty swallowing, weight loss, bleeding, anaemia) or age over about 55 with new symptoms. | lifelong, with periodic review | 2, every 56 d, 2 h each |
| **Type 2 diabetes mellitus** (`type_2_diabetes`): Chronic hyperglycaemia from insulin resistance and progressive beta-cell failure, diagnosed by HbA1c of 48 mmol/mol (6.5%) or higher, with risk of cardiovascular, kidney, eye, and nerve complications. | 25 to 90 | 10 | 50% | Structured education, diet, weight management, and exercise, with metformin first line and an SGLT2 inhibitor or GLP-1 receptor agonist added for cardiovascular or kidney risk or poor control, and insulin when needed. HbA1c every 3 to 6 months, plus annual eye screening, foot checks, kidney function, and blood pressure and lipid management. | lifelong, with periodic review | 4, every 90 d, 2 h each |
| **Chronic low back pain** (`chronic_low_back_pain`): Non-specific pain in the lumbar region lasting more than 12 weeks, without a serious underlying cause, often with fluctuating flares and impact on work and sleep. | 20 to 90 | 10 | 50% | Screening for red flags, reassurance, and staying active, with structured exercise, physiotherapy, and psychological approaches such as CBT; NSAIDs short-term for flares, avoiding long-term opioids. Imaging only for red flags or before a specialist procedure, and referral to a pain clinic or spinal service for persistent disabling pain or radicular symptoms. | lifelong, with periodic review | 3, every 28 d, 2 h each |
| **Chronic kidney disease (stages 3-4)** (`chronic_kidney_disease`): Reduced kidney function (eGFR below 60 mL/min/1.73m2) and/or kidney damage such as albuminuria persisting for more than 3 months, often due to diabetes or hypertension. | 40 to 90 | 8 | 50% | Blood pressure control with an ACE inhibitor or ARB, an SGLT2 inhibitor where indicated, statin therapy, and glucose control in diabetes, avoiding nephrotoxic drugs such as NSAIDs. Regular monitoring of eGFR, albumin-to-creatinine ratio, potassium, and anaemia and bone markers, with nephrology review and planning for kidney replacement therapy if function keeps declining. | lifelong, with periodic review | 4, every 90 d, 2 h each |
| **Asthma** (`asthma`): Chronic inflammatory airway disease with variable, reversible airflow obstruction causing episodic wheeze, breathlessness, chest tightness, and cough, with periodic exacerbations. | 18 to 90 | 8 | 50% | Inhaled corticosteroid-containing maintenance therapy (often an ICS-formoterol combination as maintenance and reliever), stepped up with long-acting bronchodilators or biologics if uncontrolled, plus inhaler technique checks, trigger avoidance, and a written action plan. Exacerbations are treated with inhaled bronchodilators and a short course of oral corticosteroids, with review within days. | lifelong, with periodic review | 3, every 14 d, 4 h each |
| **Major depressive disorder** (`major_depressive_disorder`): A mood disorder with at least two weeks of persistently low mood or loss of interest plus symptoms such as sleep and appetite change, fatigue, poor concentration, guilt, and thoughts of death, often recurring. | 18 to 90 | 7 | 65% | Risk assessment including suicidality, then psychological therapy (CBT, behavioural activation, interpersonal therapy) and/or an antidepressant, usually an SSRI first line, with review within 2 to 4 weeks of starting. Antidepressants are continued for at least 6 months after remission, longer for recurrent episodes, with urgent referral to mental health services for high risk or psychotic features. | months to years, often recurring, with periodic review | 4, every 28 d, 1 h each |
| **Coronary artery disease (stable angina)** (`coronary_artery_disease`): Atherosclerotic narrowing of the coronary arteries causing exertional chest pain relieved by rest or nitrates, with a risk of acute coronary syndrome. | 40 to 90 | 6 | 40% | Antiplatelet therapy (aspirin), high-intensity statin, sublingual nitrate for attacks, and anti-anginal therapy with a beta-blocker or calcium channel blocker, plus risk-factor control and cardiac rehabilitation. CT coronary angiography or functional testing confirms the diagnosis, with invasive angiography and PCI or bypass surgery if symptoms persist on medical therapy or anatomy is high risk. | lifelong, with periodic review | 3, every 42 d, 6 h each |
| **Hypothyroidism** (`hypothyroidism`): Underactive thyroid, most often autoimmune (Hashimoto thyroiditis), with raised TSH and low free T4 causing fatigue, weight gain, cold intolerance, constipation, and dry skin. | 20 to 90 | 5 | 80% | Levothyroxine replacement, started at a dose adjusted for age and cardiac disease and titrated against TSH measured 6 to 8 weeks after each change. Once stable, TSH is checked annually and treatment is continued for life. | lifelong, with periodic review | 3, every 42 d, 1 h each |
| **Chronic obstructive pulmonary disease** (`copd`): Progressive, largely irreversible airflow limitation from chronic bronchitis and emphysema, usually caused by smoking, with chronic cough, sputum, breathlessness, and exacerbations. | 40 to 90 | 5 | 40% | Smoking cessation, vaccinations, and pulmonary rehabilitation, with inhaled long-acting bronchodilators (LAMA and LABA), adding an inhaled corticosteroid for frequent exacerbations with raised eosinophils, and long-term oxygen for chronic hypoxaemia. Exacerbations are treated with short-acting bronchodilators, a short course of oral corticosteroids, and antibiotics if sputum is purulent, with follow-up within weeks. | lifelong, with periodic review | 3, every 30 d, 6 h each |
| **Generalized anxiety disorder** (`generalized_anxiety_disorder`): Excessive, hard-to-control worry about many areas of life on most days for at least six months, with restlessness, tension, poor sleep, irritability, and physical symptoms. | 18 to 90 | 4 | 65% | Stepped care: education and guided self-help, then high-intensity CBT or applied relaxation, and/or an SSRI (or SNRI) first line, avoiding long-term benzodiazepines. Review 2 to 4 weeks after starting medication and continue for at least a year if effective. | months to years, with periodic review | 4, every 28 d, 1 h each |
| **Atrial fibrillation** (`atrial_fibrillation`): An irregularly irregular atrial arrhythmia causing palpitations, breathlessness, or fatigue, and a major risk factor for cardioembolic stroke. | 45 to 90 | 2.5 | 50% | Stroke risk assessment (CHA2DS2-VASc) with a direct oral anticoagulant when indicated, rate control with a beta-blocker or rate-limiting calcium channel blocker, and rhythm control by cardioversion, antiarrhythmic drugs, or catheter ablation for selected patients. Treatment of triggers and comorbidities (hypertension, thyroid disease, alcohol, sleep apnoea) and regular review of rate, bleeding risk, and kidney function. | lifelong, with periodic review | 3, every 30 d, 6 h each |
| **Heart failure** (`heart_failure`): A clinical syndrome in which structural or functional heart disease impairs filling or ejection, causing breathlessness, fatigue, and fluid retention, with raised natriuretic peptides. | 45 to 90 | 2.5 | 50% | Loop diuretics for congestion, and for reduced ejection fraction the four pillars titrated to tolerated doses: ACE inhibitor/ARB or sacubitril-valsartan, beta-blocker, mineralocorticoid receptor antagonist, and SGLT2 inhibitor, plus device therapy where indicated. Specialist heart failure nurse follow-up every few weeks while titrating, with daily weight monitoring, fluid and salt advice, and cardiac rehabilitation. | lifelong, with periodic review | 4, every 14 d, 8 h each |
| **Alzheimer disease** (`alzheimer_disease`): A progressive neurodegenerative dementia with insidious decline in episodic memory and later language, visuospatial, and executive function, eventually affecting independence. | 65 to 90 | 1 | 65% | Diagnosis in a memory clinic with cognitive testing, blood tests, and brain imaging, then an acetylcholinesterase inhibitor for mild to moderate disease and memantine for moderate to severe disease, with cognitive stimulation and carer support. Regular review of cognition, behaviour, safety, driving, and advance care planning, avoiding antipsychotics where possible. | lifelong and progressive, with periodic review | 3, every 90 d, 2 h each |
| **Rheumatoid arthritis** (`rheumatoid_arthritis`): A chronic autoimmune inflammatory arthritis causing symmetrical swelling, pain, and prolonged morning stiffness of the small joints of the hands and feet, leading to joint damage if untreated. | 25 to 90 | 0.8 | 75% | Early referral to rheumatology and a conventional DMARD (methotrexate first line) started promptly, with short-term corticosteroid bridging, escalating to biologic or targeted synthetic DMARDs if disease activity remains high. Monthly review with blood monitoring (blood count, liver and kidney function) until controlled, then every few months, plus physiotherapy and cardiovascular risk management. | lifelong, with periodic review | 4, every 56 d, 3 h each |
| **Breast cancer (under treatment)** (`breast_cancer`): Malignant tumour of breast tissue, usually invasive ductal or lobular carcinoma, managed by a multidisciplinary team according to stage and receptor status (ER, PR, HER2). | 30 to 90 | 0.5 | 99% | Surgery (breast-conserving surgery or mastectomy with sentinel node biopsy) combined according to stage and receptor status with chemotherapy given in cycles about every 3 weeks, HER2-targeted therapy, radiotherapy, and endocrine therapy for hormone-receptor-positive disease. Bloods and toxicity review before each chemotherapy cycle, then surveillance with clinical review and annual mammography. | months of active treatment, then years of endocrine therapy and surveillance | 6, every 21 d, 6 h each |
| **End-stage kidney disease on haemodialysis** (`end_stage_kidney_disease`): Stage 5 chronic kidney disease (eGFR below 15 mL/min/1.73m2) requiring kidney replacement therapy, here in-centre haemodialysis, with fluid, electrolyte, anaemia, and bone-mineral complications. | 30 to 90 | 0.1 | 50% | In-centre haemodialysis three times a week for about 4 hours through an arteriovenous fistula or catheter, with fluid and potassium restriction, phosphate binders, vitamin D analogues, and erythropoiesis-stimulating agents with iron for anaemia. Monthly bloods and dialysis adequacy review, vascular access surveillance, and transplant assessment where suitable. | lifelong, or until kidney transplant | 12, every 2 d, 4 h each; continuous |

## Known limitations

- At most one chronic condition per person, and one acute episode at a
  time: no comorbidities, though many of the chronic conditions come
  together in real patients.
- A chronic condition's `last` visit sounds like the end of care ("back
  to my GP"), and yet a new course follows: read it as the end of a
  round of care.
- The weights are relative, not calibrated: they make common conditions
  common, not the simulated population's prevalence match a real one.
- Every visit of every condition is to a hospital, even what a primary
  care center would see; routing is still to come.
- The templates are in English, whatever the city.
