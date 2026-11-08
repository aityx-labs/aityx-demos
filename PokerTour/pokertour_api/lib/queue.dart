/// The tournaments asked for, one at a time: the schedule's, an admin's
/// and a new strategy's are queued in the tour's table (lib/tour_db.dart,
/// DynamoDB), at most one waiting from each, and played in the order
/// asked by whoever holds the runner's lock, an item of the same table
/// taken with a conditional write: never two tournaments at once, on a
/// laptop or on AWS, where the API and the runner are separate functions.
/// A lock whose holder died (a server killed, a function out of time)
/// lapses after [LiveState.staleAfter], longer than a tournament may run.
library;

import 'runner.dart' show LiveState;
import 'tour_db.dart';

/// Who asks for a tournament.
abstract final class TournamentSource {
  /// The schedule (lib/schedule.dart).
  static const schedule = 'schedule';

  /// An admin's "Play a tournament now".
  static const admin = 'admin';

  /// A player entered a strategy.
  static const strategy = 'strategy';

  static const all = [schedule, admin, strategy];
}

/// A tournament asked for and waiting its turn.
class TournamentRequest {
  const TournamentRequest({required this.source, required this.at, this.by});

  factory TournamentRequest.fromJson(Map<String, Object?> json) => TournamentRequest(
    source: json['source'] as String,
    at: DateTime.tryParse(json['at'] as String? ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    by: json['by'] as String?,
  );

  /// One of [TournamentSource.all].
  final String source;

  /// When it was asked for.
  final DateTime at;

  /// Who asked: the owner id of the admin or the player; null for the
  /// schedule.
  final String? by;

  /// For the store; and for the API, which leaves [by] out.
  Map<String, Object?> toJson({bool withBy = true}) => {
    'source': source,
    'at': at.toUtc().toIso8601String(),
    if (withBy) 'by': by,
  };
}

/// What asking for a tournament did.
enum Asked {
  /// Queued, and nothing was being played: it starts now.
  started,

  /// Queued behind the tournament being played (or waiting before it).
  queued,

  /// One from the same source was waiting already: it stands for this one.
  waiting,
}

class TournamentQueue {
  TournamentQueue(this.db, {required this.holder, this.lease = LiveState.staleAfter});

  final TourDb db;

  /// Who this process is when it holds the runner's lock.
  final String holder;

  /// How long the lock holds without its holder: longer than a
  /// tournament may run.
  final Duration lease;

  /// The tournaments waiting, the oldest first.
  Future<List<TournamentRequest>> waiting() async => (await db.queued())..sort((a, b) => a.at.compareTo(b.at));

  /// Asks for a tournament from [source] (by [by]): queued, unless one
  /// from it is waiting already; [Asked.started] when nobody holds the
  /// lock, so the caller's drain will play it next.
  Future<Asked> ask(String source, {String? by, DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    if (!await db.enqueue(TournamentRequest(source: source, at: at, by: by))) return Asked.waiting;
    return await db.locked(at) ? Asked.queued : Asked.started;
  }

  /// Plays the waiting tournaments with [play], the oldest first, one at
  /// a time, while this holder can take the lock: none when another
  /// holds it (it plays them). At most [max] when given (a Lambda
  /// function plays one per invocation). How many were played.
  Future<int> drain(Future<void> Function(TournamentRequest request) play, {int? max}) async {
    var played = 0;
    while (max == null || played < max) {
      final now = DateTime.now().toUtc();
      if (!await db.lock(holder, now.add(lease), now)) return played;
      var held = true;
      try {
        final next = (await waiting()).firstOrNull;
        if (next == null) {
          await db.unlock(holder);
          held = false;
          // One asked for while the lock was still held found it held and
          // left it to us: look once more now that it is free.
          if ((await db.queued()).isEmpty) return played;
          continue;
        }
        if (!await db.dequeue(next.source)) continue;
        await play(next);
        played++;
      } finally {
        if (held) await db.unlock(holder);
      }
    }
    return played;
  }
}
