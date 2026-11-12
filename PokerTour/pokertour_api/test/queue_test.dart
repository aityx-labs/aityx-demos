import 'dart:async';

import 'package:pokertour_api/queue.dart';
import 'package:pokertour_api/tour_db.dart';
import 'package:test/test.dart';

/// The queue's rules, on any [TourDb]: floci_test.dart runs them on
/// DynamoDB too.
void queueRules(TourDb Function() db) {
  test('one waiting per source, played the oldest first, one at a time', () async {
    final tour = db();
    final a = TournamentQueue(tour, holder: 'a');
    final b = TournamentQueue(tour, holder: 'b');
    final t0 = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    expect(await a.ask(TournamentSource.strategy, by: 'p1', now: t0), Asked.started);
    expect(await a.ask(TournamentSource.strategy, by: 'p2', now: t0.add(const Duration(seconds: 1))), Asked.waiting);
    expect(await a.ask(TournamentSource.admin, by: 'p3', now: t0.add(const Duration(seconds: 2))), Asked.started);
    expect((await a.waiting()).map((r) => r.source), ['strategy', 'admin']);

    // While a plays the first, b can play nothing, and a schedule's waits.
    final playing = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];
    var parallel = 0;
    var most = 0;
    final draining = a.drain((r) async {
      parallel++;
      most = parallel > most ? parallel : most;
      order.add(r.source);
      if (!playing.isCompleted) {
        playing.complete();
        await release.future;
      }
      parallel--;
    });
    await playing.future;
    expect(await b.drain((r) async => order.add('b:${r.source}')), 0);
    expect(await b.ask(TournamentSource.schedule), Asked.queued);
    release.complete();
    expect(await draining, 3);
    expect(order, ['strategy', 'admin', 'schedule']);
    expect(most, 1);
    expect(await a.waiting(), isEmpty);
    expect(await tour.locked(DateTime.now()), isFalse);
  });

  test('a lock whose holder died lapses', () async {
    final tour = db();
    final now = DateTime.now().toUtc();
    expect(await tour.lock('dead', now.add(const Duration(minutes: 16)), now), isTrue);
    expect(await tour.lock('b', now.add(const Duration(minutes: 16)), now), isFalse);
    expect(await tour.lock('b', now.add(const Duration(minutes: 33)), now.add(const Duration(minutes: 17))), isTrue);
    await tour.unlock('dead');
    expect(await tour.locked(now.add(const Duration(minutes: 18))), isTrue, reason: 'only its holder lets it go');
    await tour.unlock(null);
    expect(await tour.locked(now), isFalse);
  });
}

void main() => queueRules(MemoryTourDb.new);
