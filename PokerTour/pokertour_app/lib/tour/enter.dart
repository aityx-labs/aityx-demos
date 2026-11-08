import 'package:flutter/material.dart';
import 'package:poker_core/table.dart' show Strategy;

import 'files.dart';
import 'tour_api.dart';
import 'tour_session.dart';

/// What entering a strategy came to, for the screen that asked.
typedef EnterOutcome = ({bool ok, String text});

/// Whether this screen can enter strategies in the tour: there is a
/// session and someone allowed to play.
bool canEnterTour(BuildContext context) => TourScope.of(context)?.player != null;

/// Enters [strategy] in the tour, for the signed-in user, and says how it
/// went, in a snackbar too.
Future<EnterOutcome> enterInTour(BuildContext context, Strategy strategy) async {
  final session = TourScope.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (session == null || session.player == null) {
    const text = 'Sign in to enter a strategy in the tour.';
    messenger?.showSnackBar(const SnackBar(content: Text(text)));
    return (ok: false, text: text);
  }
  try {
    final entered = await session.enter(strategy);
    final next = switch (entered.tournament) {
      'started' => 'a tournament is starting for it.',
      'queued' => 'a tournament for it is queued, after the one being played.',
      'waiting' => 'it plays in the tournament waiting its turn.',
      _ => 'the leaderboard seats it from the next tournament.',
    };
    final out = (ok: true, text: '${entered.strategy.name} is in the tour: $next');
    messenger?.showSnackBar(SnackBar(content: Text(out.text)));
    return out;
  } on TourException catch (e) {
    final out = (ok: false, text: 'Not entered: ${e.message}');
    messenger?.showSnackBar(SnackBar(content: Text(out.text)));
    return out;
  }
}

/// Picks a strategy file and enters it in the tour (the Players and
/// Profile views' "Upload a strategy"); null when nothing was picked.
Future<EnterOutcome?> uploadToTour(BuildContext context) async {
  final picked = await pickTextFile();
  if (picked == null || !context.mounted) return null;
  final Strategy strategy;
  try {
    strategy = Strategy.parse(picked.text, id: 'upload');
  } on FormatException catch (e) {
    final text = '${picked.name}: ${e.message}';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
    return (ok: false, text: text);
  }
  return enterInTour(context, strategy);
}

/// `<name>.json`, from the strategy's name.
String strategyFileName(Strategy strategy) {
  final slug = strategy.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return '${slug.isEmpty ? 'strategy' : slug}.json';
}
