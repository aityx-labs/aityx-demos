/// What the API answers, by method and path, apart from the HTTP plumbing
/// (bin/server.dart on a laptop, bin/lambda.dart on AWS), so it can be
/// tested without either.
///
///   GET  /api/health      {"ok", "aityx": the leaderboard's key is set,
///                         "auth": the sign-in is set up, "runner": its
///                         state, "entries"}
///   GET  /api/config      how to sign in and which aityx players call
///                         with their own keys (never the host's): {"auth":
///                         {"enabled", "issuer", "clientId"}, "domains",
///                         "aityxUrl"
///                         (this environment's aityx), "aityxRelay" (the
///                         path on this origin that relays to it, on a
///                         laptop; null deployed)}
///   GET  /api/leaderboard {"standings": [...], "current": the tournament
///                         being played or null, "history": the latest
///                         results, "runner": {"enabled", "state",
///                         "detail", "hoursUtc", "nextRunAt", "queue":
///                         the tournaments waiting, the oldest first,
///                         [{"source", "at"}]}}; open to all, no emails
///                         or owners in it
///   GET  /api/me          who the bearer token says is calling, with the
///                         "ownerId" the standings use, their "alias"
///                         (null: the leaderboard shows their name) and
///                         whether they are an "admin"; signed in
///   PUT  /api/me          {"alias"}: what the leaderboard calls them, up
///                         to 32 characters; empty for their name;
///                         200 with GET's answer, 400; signed in
///   GET  /api/strategies  {"strategies": [...]}: every entry's rules, the
///                         presets too, the owner by alias; signed in
///   POST /api/strategies  {"name", "tagline", "decisions"}: enters the
///                         strategy (replacing the caller's of the same
///                         name, under a new id) once aityx runs it on
///                         the sample situation, and asks for a
///                         tournament (queued behind the one being
///                         played); 201 with the entry and "tournament":
///                         what asking did (as POST /api/tournaments'
///                         status, or null when the leaderboard is off);
///                         200 with the entry, unchanged, when it is the
///                         caller's already, rules and all; 400 when it
///                         isn't a strategy or is over the limits, 422
///                         when aityx refuses it, 503 when aityx can't be
///                         asked, 409 when the player has too many, 429
///                         within [entryInterval] of their last; signed in
///   DELETE /api/strategies/{id}  withdraws the caller's entry; 204, or
///                         404 (400 for an id that isn't one); signed in
///   POST /api/tournaments asks for a tournament now: 202 with {"status":
///                         "started"; "queued" behind the one being
///                         played, never beside it; or "waiting" when an
///                         admin's is queued already}; an admin, signed
///                         in; 503 when the leaderboard is off
///
/// Signed in: a bearer token Google issued for the server's client id, for
/// an account in the tour's domains: 401 without one, 403 for another
/// domain, 503 while the server has no client id. An admin: an aletyx.com
/// or aletyx.ai account (403 otherwise).
library;

import 'dart:io';

import 'auth.dart';
import 'leaderboard.dart';
import 'queue.dart';
import 'runner.dart';
import 'schedule.dart';
import 'store.dart';
import 'tour_db.dart';

/// The longest alias.
const maxAlias = 32;

/// An answer: a status and a JSON body (null for none).
class Answer {
  const Answer(this.status, [this.body]);

  final int status;
  final Object? body;
}

/// Checks a strategy's rules on aityx before it enters the tour; throws
/// with the reason when aityx refuses them, and [CheckUnavailable] when
/// aityx can't say (no key, no answer, too busy): the entry waits.
typedef StrategyCheck = Future<void> Function(Object? strategyJson);

/// aityx couldn't be asked about a strategy: it isn't entered unchecked.
class CheckUnavailable implements Exception {
  const CheckUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How long a player waits between asking to enter strategies: each ask
/// is an aityx call on the host's key, and a tournament.
const entryInterval = Duration(minutes: 1);

/// Asks for a tournament from [source] (lib/queue.dart), by [by]: what
/// it did, one of [Asked]'s names. Throws when it can't.
typedef TournamentStarter = Future<String> Function(String source, Identity by);

/// [auth]: how the server signs users in. [who]: the bearer token's
/// verdict, when the request had one. [boards]: the tour, in its store.
/// [live]: what the runner last wrote, for the leaderboard; [schedule]
/// when it plays on its own and [runnerEnabled] whether it plays at all.
/// [start] asks for a tournament (POST /api/tournaments, and a new
/// strategy); [waiting], the tournaments queued; [check] is the aityx
/// check for POST /api/strategies, at most one per player every
/// [interval].
Future<Answer> route(
  String method,
  String path, {
  required AuthSettings auth,
  required Boards boards,
  Verified? who,
  Object? body,
  bool aityx = false,
  String aityxUrl = 'https://api.aityx.ai',
  String? aityxRelay,
  LiveState? live,
  Schedule schedule = const Schedule([]),
  bool runnerEnabled = false,
  TournamentStarter? start,
  Future<List<TournamentRequest>> Function()? waiting,
  StrategyCheck? check,
  Duration interval = entryInterval,
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();
  final cutShort = live != null && live.stale(at);

  Future<Map<String, Object?>> runnerJson() async => {
    'enabled': runnerEnabled,
    'state': cutShort ? 'error' : (live?.state ?? 'idle'),
    'detail': cutShort ? 'the last tournament was cut short' : (live?.detail ?? 'no tournament played yet'),
    ...schedule.toJson(at),
    'queue': [for (final r in await (waiting?.call() ?? Future.value(const <TournamentRequest>[]))) r.toJson(withBy: false)],
  };

  Answer signedIn() {
    if (!auth.enabled) return const Answer(503, {'error': 'the sign-in is not set up on this server (OIDC_CLIENT_ID)'});
    return switch (who?.refusal) {
      null when who?.identity != null => const Answer(200),
      Refusal.domain => Answer(403, {'error': 'the tour is for ${auth.domains.join(' and ')} accounts'}),
      _ => const Answer(401, {'error': 'sign in first'}),
    };
  }

  switch ((method, path)) {
    case ('GET', '/api/health'):
      return Answer(200, {
        'ok': true,
        'aityx': aityx,
        'auth': auth.enabled,
        'runner': await runnerJson(),
        'entries': (await boards.read()).entries.length,
      });
    case ('GET', '/api/config'):
      return Answer(200, {
        'auth': auth.toJson(),
        'domains': auth.domains,
        'aityxUrl': aityxUrl,
        'aityxRelay': aityxRelay,
      });
    case ('GET', '/api/leaderboard'):
      final board = await boards.read();
      return Answer(200, {
        'standings': board.standings(),
        'current': cutShort ? null : live?.current,
        'history': [for (final t in board.history) t.toJson()],
        'runner': await runnerJson(),
      });
    case ('GET', '/api/me'):
      final gate = signedIn();
      if (gate.status != 200) return gate;
      final me = who!.identity!;
      final player = await boards.db.player(me.ownerId);
      return Answer(200, {...me.toJson(), 'alias': player?.alias, 'admin': auth.isAdmin(me.email)});
    case ('PUT', '/api/me'):
      final gate = signedIn();
      if (gate.status != 200) return gate;
      final me = who!.identity!;
      final given = body is Map ? body['alias'] : null;
      if (given != null && given is! String) return const Answer(400, {'error': 'send {"alias": "..."}'});
      final alias = ((given as String?) ?? '').trim();
      if (alias.length > maxAlias) return const Answer(400, {'error': 'an alias has at most $maxAlias characters'});
      if (!Leaderboard.isPlainLine(alias)) return const Answer(400, {'error': 'an alias is plain text, on one line'});
      final before = await boards.db.player(me.ownerId);
      await boards.db.putPlayer(
        Player(ownerId: me.ownerId, name: me.displayName, alias: alias.isEmpty ? null : alias, lastEntryAt: before?.lastEntryAt),
      );
      return Answer(200, {...me.toJson(), 'alias': alias.isEmpty ? null : alias, 'admin': auth.isAdmin(me.email)});
    case ('GET', '/api/strategies'):
      final gate = signedIn();
      if (gate.status != 200) return gate;
      final board = await boards.read();
      return Answer(200, {
        'strategies': [for (final e in board.entries.values) board.strategyOf(e)],
      });
    case ('POST', '/api/strategies'):
      final gate = signedIn();
      if (gate.status != 200) return gate;
      if (body is! Map) return const Answer(400, {'error': 'send a JSON object: name, tagline, decisions'});
      // Checked here first (cheap), then on aityx (a call), then entered.
      try {
        Leaderboard.check(body);
      } on EntryException catch (e) {
        return Answer(400, {'error': e.message});
      }
      final me = who!.identity!;
      // The same rules again: nothing to check, enter or play.
      final same = (await boards.read()).unchanged(me, body);
      if (same != null) {
        final player = await boards.db.player(same.ownerId);
        return Answer(200, {...same.toStrategy(shownOwner: player?.shown), 'tournament': null});
      }
      // One ask a player every [interval], checked or not: each is a call
      // on the host's key.
      final player = await boards.db.player(me.ownerId);
      final last = player?.lastEntryAt;
      if (last != null && at.isBefore(last.add(interval))) {
        final wait = last.add(interval).difference(at).inSeconds + 1;
        return Answer(429, {'error': 'one strategy a player every ${interval.inSeconds} s: try again in $wait s'});
      }
      await boards.db.putPlayer(
        Player(ownerId: me.ownerId, name: player?.name ?? me.displayName, alias: player?.alias, lastEntryAt: at),
      );
      if (check != null) {
        try {
          await check(body);
        } on CheckUnavailable catch (e) {
          return Answer(503, {'error': 'aityx can\'t check the rules now ($e); try again later'});
        } on Exception catch (e) {
          return Answer(422, {'error': 'aityx refused the rules: $e'});
        }
      }
      try {
        final entry = await boards.update((b) => b.enter(me, body));
        final player = await boards.db.player(entry.ownerId);
        // A new strategy plays in the next tournament: one is asked for,
        // queued behind any being played. The entry stands if it can't be.
        String? tournament;
        if (runnerEnabled && start != null) {
          try {
            tournament = await start(TournamentSource.strategy, me);
          } on Exception catch (e) {
            // AWS's words name roles and accounts: the log has them.
            stderr.writeln('api: a tournament could not be asked for: $e');
            tournament = 'not asked for';
          }
        }
        return Answer(201, {...entry.toStrategy(shownOwner: player?.shown), 'tournament': tournament});
      } on EntryException catch (e) {
        return Answer(e.message.contains('withdraw one first') ? 409 : 400, {'error': e.message});
      } on StoreConflict {
        return const Answer(503, {'error': 'the leaderboard is busy; try again'});
      }
    case ('POST', '/api/tournaments'):
      final gate = signedIn();
      if (gate.status != 200) return gate;
      if (!auth.isAdmin(who!.identity!.email)) {
        return Answer(403, {'error': 'only the tour\'s admins (${AuthSettings.adminDomains.join(' and ')} accounts) can start a tournament'});
      }
      if (!runnerEnabled || start == null) return const Answer(503, {'error': 'the leaderboard is off on this server'});
      try {
        return Answer(202, {'status': await start(TournamentSource.admin, who.identity!)});
      } on Exception catch (e) {
        stderr.writeln('api: a tournament could not be started: $e');
        return const Answer(502, {'error': 'the tournament could not be started; the server\'s log says why'});
      }
    default:
      if (method == 'DELETE' && path.startsWith('/api/strategies/')) {
        final gate = signedIn();
        if (gate.status != 200) return gate;
        final String id;
        try {
          id = Uri.decodeComponent(path.substring('/api/strategies/'.length));
        } on ArgumentError {
          return const Answer(400, {'error': 'not an entry id'});
        }
        try {
          final gone = await boards.update((b) => b.withdraw(who!.identity!, id));
          return gone ? const Answer(204) : const Answer(404, {'error': 'no such entry of yours'});
        } on StoreConflict {
          return const Answer(503, {'error': 'the leaderboard is busy; try again'});
        }
      }
      return const Answer(404, {'error': 'not found'});
  }
}
