/// Plays the leaderboard's tournaments, one at a time, when asked: by
/// the schedule (lib/schedule.dart: four times a day) or by an admin
/// (POST /api/tournaments). Three to nine strategies at a table, as
/// many as a draw says, none twice (the ones with the fewest tournaments
/// first), every decision an aityx call on
/// the host's key, until one has every chip, the hands run out, or the
/// time does (on AWS, a Lambda function's fifteen minutes): then the
/// chips decide, the places are recorded, and the runner is done until
/// the next call. Its state, and the tournament being played, go to the
/// store as live.json, where the API reads them (on AWS the API is
/// another function).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:poker_core/engine/game.dart';

import 'aityx.dart';
import 'leaderboard.dart';
import 'store.dart';

/// A seat of the tournament being played, for the leaderboard.
typedef LiveSeat = ({String name, String strategyId, int stack, int? place});

/// The runner's state as the API shows it: idle, playing (with the
/// tournament), waiting (one was played; the schedule says when the
/// next is) or error, with a line of detail, and when it was written.
class LiveState {
  LiveState({required this.state, required this.detail, this.current, DateTime? updatedAt})
    : updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory LiveState.fromJson(Map<String, Object?> json) => LiveState(
    state: json['state'] as String? ?? 'idle',
    detail: json['detail'] as String? ?? '',
    current: json['current'] is Map ? (json['current'] as Map).cast<String, Object?>() : null,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  /// The file's name in the store.
  static const name = 'live.json';

  /// A tournament that hasn't said a word for this long is taken for
  /// dead (a function that ran out of time, a server killed): longer
  /// than a Lambda function may run.
  static const staleAfter = Duration(minutes: 16);

  final String state;
  final String detail;

  /// The tournament being played: its number, hand, aityx calls so far,
  /// and each seat's stack or finishing place.
  final Map<String, Object?>? current;
  final DateTime updatedAt;

  bool stale(DateTime now) => state == 'playing' && now.toUtc().difference(updatedAt) > staleAfter;

  Map<String, Object?> toJson() => {
    'state': state,
    'detail': detail,
    'current': current,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// live.json from [store], or null when there is none (or it is not
/// readable).
Future<LiveState?> readLive(Store store) async {
  final stored = await store.read(LiveState.name);
  if (stored == null) return null;
  try {
    final json = jsonDecode(stored.text);
    if (json is Map) return LiveState.fromJson(json.cast<String, Object?>());
  } catch (_) {}
  return null;
}

class Runner {
  Runner({
    required this.boards,
    required this.decider,
    this.maxHands = 300,
    this.tableSize = 9,
    this.minPlayers = 3,
    Random? random,
    this.log = true,
    this.progressEvery = const Duration(seconds: 5),
  }) : _random = random ?? Random();

  final Boards boards;
  final AityxDecider decider;

  /// A tournament longer than this ends on chips.
  final int maxHands;
  final int tableSize;

  /// The fewest a table is drawn with, when that many can play.
  final int minPlayers;
  final Random _random;
  final bool log;

  /// How often, at most, the tournament being played is written to the
  /// store for the API to show.
  final Duration progressEvery;

  Store get store => boards.store;

  /// What the store last heard from this runner.
  LiveState live = LiveState(state: 'idle', detail: 'no tournament yet');

  bool _playing = false;
  bool _stopped = false;
  PokerGame? _game;
  int _calls = 0;
  int _number = 0;
  Map<int, TourEntry> _seated = const {};
  DateTime _written = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether a tournament is being played by this runner.
  bool get playing => _playing;

  /// The tournament being played, or null between two.
  Map<String, Object?>? get current {
    final game = _game;
    if (game == null) return null;
    return {
      'number': _number,
      'hand': game.handNumber,
      'calls': _calls,
      'seats': [
        for (final s in game.seats)
          {'name': s.name, 'strategyId': s.strategyId, 'stack': s.stack, 'place': s.place},
      ],
    };
  }

  /// The entries at the table now, by seat id.
  Map<int, TourEntry> get seated => _seated;

  void stop() => _stopped = true;

  /// One tournament among the entries that can play: picked, played and
  /// recorded; its result, or null when fewer than two can play, when
  /// the table stalled, or when the time ran out while aityx didn't
  /// answer. Never throws: what went wrong is in the live state. By
  /// [deadline] the tournament is over whatever the chips say (a Lambda
  /// function's time limit).
  Future<TournamentResult?> play({DateTime? deadline}) async {
    if (_playing) return null;
    _playing = true;
    try {
      final board = await boards.read();
      final players = board.playable;
      if (players.length < 2) {
        await _set('idle', 'fewer than two strategies can play', force: true);
        return null;
      }
      return await playOne(board, players, deadline: deadline);
    } catch (error, stack) {
      stderr.writeln('runner: $error\n$stack');
      _game = null;
      await _set('error', 'the tournament failed: $error', force: true);
      return null;
    } finally {
      _playing = false;
    }
  }

  /// Who sits: a number drawn at random from [minPlayers] to
  /// [tableSize] (fewer when fewer can play) of [players], none twice,
  /// the fewest tournaments first, ties at random.
  List<TourEntry> pick(Leaderboard board, List<TourEntry> players) {
    final shuffled = [...players]..shuffle(_random);
    shuffled.sort((a, b) => board.recordOf(a.id).tournaments - board.recordOf(b.id).tournaments);
    final most = min(tableSize, shuffled.length);
    final least = min(minPlayers, most);
    return shuffled.take(least + _random.nextInt(most - least + 1)).toList();
  }

  /// One tournament among [players] of [board]; its result once
  /// recorded. A strategy aityx refuses is marked broken and folds for
  /// the rest; aityx not answering is retried after a growing pause,
  /// while there is time.
  Future<TournamentResult?> playOne(Leaderboard board, List<TourEntry> players, {DateTime? deadline}) async {
    final seated = pick(board, players);
    final game = PokerGame(random: _random);
    final byName = <String>{};
    final seats = <int, TourEntry>{};
    for (final entry in seated) {
      var name = entry.strategy.name;
      var n = 2;
      while (!byName.add(name)) {
        name = '${entry.strategy.name} $n';
        n++;
      }
      final seat = game.addPlayer(name, entry.id);
      if (seat != null) seats[seat.id] = entry;
    }
    _game = game;
    _seated = seats;
    _calls = 0;
    _number = board.tournamentsPlayed + 1;
    final playing = 'tournament #$_number, ${seated.length} players';
    await _set('playing', playing, force: true);
    var retry = const Duration(seconds: 30);
    var outOfTime = false;
    while (!_stopped) {
      if (deadline != null && !DateTime.now().isBefore(deadline)) {
        outOfTime = true;
        break;
      }
      if (game.handNumber >= maxHands && !game.handInProgress) break;
      final step = game.next();
      switch (step) {
        case TournamentOver():
          break;
        case Waiting(:final reason):
          _game = null;
          await _set('error', 'the table stalled: $reason', force: true);
          return null;
        case HandOver():
          await _set('playing', playing);
          continue;
        case NeedsAction(:final seat, :final situation):
          final entry = seats[seat.id];
          if (entry == null || entry.broken != null) {
            game.apply(PlayerAction(ActionKind.fold));
            continue;
          }
          try {
            final action = await decider.act(entry.strategy, situation);
            _calls++;
            game.apply(PlayerAction(ActionKind.parse(action['action'] as String), raiseTo: action['raise_to'] as num));
            retry = const Duration(seconds: 30);
          } on DecisionException catch (e) {
            if (e.strategyFault) {
              _calls++;
              _say('${entry.strategy.name} is left out: ${e.message}');
              entry.broken = e.message;
              await boards.update((b) => b.markBroken(entry.id, e.message));
              game.apply(PlayerAction(ActionKind.fold));
            } else if (e.keyFault) {
              _game = null;
              await _set('error', '${e.message}: the leaderboard cannot play until the host sets a working key', force: true);
              return null;
            } else {
              // The network, aityx down: wait and ask again, while there is time.
              if (deadline != null && !DateTime.now().add(retry).isBefore(deadline)) {
                _game = null;
                await _set('error', '${e.message}; the tournament was abandoned, out of time', force: true);
                return null;
              }
              await _set('error', '${e.message}; trying again in ${retry.inSeconds} s', force: true);
              await _sleep(retry);
              if (retry < const Duration(minutes: 5)) retry *= 2;
              await _set('playing', playing, force: true);
            }
          }
          continue;
        default:
          continue;
      }
      break;
    }
    if (_stopped) {
      _game = null;
      return null;
    }
    if (outOfTime && game.handNumber == 0) {
      _game = null;
      await _set('error', 'no time to play a hand; nothing recorded', force: true);
      return null;
    }
    // The places: the winner first; a tournament cut short ranks the
    // players still in by their chips.
    final order = game.standings;
    final places = <({String id, String name, int place})>[];
    for (final (i, seat) in order.indexed) {
      final entry = seats[seat.id];
      if (entry == null) continue;
      places.add((id: entry.id, name: seat.name, place: seat.place ?? i + 1));
    }
    final result = await boards.update((b) => b.finish(places, hands: game.handNumber, calls: _calls));
    final summary = places.map((p) => '${p.place}. ${p.name}').join(', ');
    _say('tournament #${result.number} over after ${game.handNumber} hands, $_calls aityx calls: $summary');
    _game = null;
    _seated = const {};
    await _set(
      'waiting',
      'tournament #${result.number} over after ${game.handNumber} hands${outOfTime ? ' (out of time: the chips decided)' : ''}: $summary',
      force: true,
    );
    return result;
  }

  /// Sets the live state and writes it to the store: always when
  /// [force], else at most every [progressEvery].
  Future<void> _set(String state, String detail, {bool force = false}) async {
    live = LiveState(state: state, detail: detail, current: current);
    final now = DateTime.now();
    if (!force && now.difference(_written) < progressEvery) return;
    _written = now;
    try {
      await store.write(LiveState.name, jsonEncode(live.toJson()));
    } catch (error) {
      stderr.writeln('runner: could not write ${LiveState.name}: $error');
    }
  }

  void _say(String line) {
    if (log) stdout.writeln('runner: $line');
  }

  Future<void> _sleep(Duration d) async {
    // In small steps, so a stop is seen soon.
    final until = DateTime.now().add(d);
    while (!_stopped && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}
