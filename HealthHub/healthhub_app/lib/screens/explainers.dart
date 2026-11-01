import 'package:flutter/material.dart';

import '../theme.dart';

/// Beside the map: where HealthHub's data comes from, and how the
/// simulation makes its patients, briefly.
class SimulationExplainer extends StatelessWidget {
  const SimulationExplainer({super.key});

  @override
  Widget build(BuildContext context) => const Explainer(
    key: Key('simulation-explainer'),
    icon: Icons.info_outline,
    title: 'The data, and the simulation',
    points: [
      (
        'Real care centers',
        '7,256 hospitals, clinics and health stations in seven cities, from the official registries of '
            'Spain, the US and Brazil.',
      ),
      (
        'Simulated people',
        'Twenty per city, each with a name, age, job and a home near a care center. Some live with a chronic '
            'condition; now and then anyone falls ill.',
      ),
      (
        'An hour a second',
        'When a condition calls for it, a person travels to the nearest care center the visit needs: a health '
            'station for a check-up, urgent care for a sprain, a general hospital for an emergency. They say what '
            'is wrong at the desk, stay, and go home.',
      ),
      (
        'A real stream',
        'Every move and arrival goes through Kafka. The API records the admissions, Flink sums the hours of '
            'care, and datyx learns from those tables. A restart is a new run, with new people.',
      ),
    ],
  );
}

/// Beside the triage: what aityx does at the desk, where Jev reads and
/// where the rules decide, and what aityx adds, briefly.
class AityxExplainer extends StatelessWidget {
  const AityxExplainer({super.key});

  @override
  Widget build(BuildContext context) => const Explainer(
    key: Key('aityx-explainer'),
    icon: Icons.psychology_alt_outlined,
    title: 'What aityx does at the desk',
    points: [
      (
        'Jev reads',
        'aityx\'s language model reads only what the patient said and their age, and answers twelve '
            'questions: how likely each of eight danger signs is (a threat to life, breathing, the heart, a '
            'stroke…) and four choices (pain, onset, why they came, the body system).',
      ),
      (
        'Rules decide',
        'Decision tables (DMN, first rule that matches) turn those answers into the level, the longest wait, '
            'the area and whether a nurse checks first: 14 rules for the level, 8 for the area, written by '
            'people, not learned.',
      ),
      (
        'In one call',
        'Jev and the tables run together on aityx: one call per patient, in about a quarter of a second, for '
            'a fraction of a cent.',
      ),
      (
        'Explained',
        'Every answer comes with a receipt: each reading, the rule that fired and why. A nurse sees the '
            'reason, a rule changes without retraining anything, and any triage can be audited later. Open a '
            'patient to see theirs.',
      ),
    ],
  );
}

/// A card that explains: an icon and a title, then a few points, each a
/// short heading and a sentence or two.
class Explainer extends StatelessWidget {
  const Explainer({super.key, required this.icon, required this.title, required this.points});

  final IconData icon;
  final String title;
  final List<(String, String)> points;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: Aityx.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
          for (final (heading, text) in points) ...[
            const SizedBox(height: 10),
            Text(
              heading,
              style: const TextStyle(color: Aityx.orangeLight, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(text, style: const TextStyle(color: Aityx.fg, fontSize: 13, height: 1.35)),
          ],
        ],
      ),
    ),
  );
}
