import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/poker_api.dart';
import '../engine/game.dart';

/// One decision asked of aityx: who, when, the situation sent, and what
/// came back, or what went wrong.
class AityxCall {
  AityxCall({
    required this.number,
    required this.hand,
    required this.street,
    required this.seat,
    required this.strategy,
    required this.situation,
  });

  final int number;
  final int hand;
  final Street street;
  final Seat seat;
  final Strategy strategy;
  final Map<String, Object?> situation;
  ActResult? result;
  ActionTaken? taken;
  String? error;

  bool get pending => result == null && error == null;
}

/// Runs the table: asks the API for every decision, plays it, and paces
/// the steps so they can be watched.
class GameController extends ChangeNotifier {
  GameController({required this.api, PokerGame? game, Random? random})
    : game = game ?? PokerGame(random: random);

  final PokerApi api;
  final PokerGame game;

  /// The presets from the API, then the strategies written in the app.
  List<Strategy> strategies = [];
  bool loaded = false;
  String? loadError;

  /// Seconds between steps, 0 (as fast as aityx answers) to [maxPace].
  double pace = 1.0;
  static const maxPace = 4.0;

  bool playing = false;
  bool _busy = false;
  bool _disposed = false;

  final List<AityxCall> calls = [];
  AityxCall? thinking;
  Step? lastStep;

  /// The last failure, shown until the game moves on.
  String? error;

  int _customs = 0;

  static const _defaultNames = {
    'rock': 'Rocky',
    'maniac': 'Max',
    'station': 'Sunny',
    'mathematician': 'Ada',
    'shark': 'Finn',
  };

  /// Fetches the strategies and, at an empty table, seats one player per
  /// preset.
  Future<void> load() async {
    try {
      strategies = [...await api.strategies()];
      loadError = null;
      if (game.seats.isEmpty) {
        for (final s in strategies) {
          game.addPlayer(_defaultNames[s.id] ?? s.name, s.id);
        }
      }
    } on ApiException catch (e) {
      loadError = e.message;
    }
    loaded = true;
    _notify();
  }

  Strategy? strategyOf(Seat seat) =>
      strategies.where((s) => s.id == seat.strategyId).firstOrNull;

  /// A name no one at the table has.
  String suggestName(Strategy strategy) {
    final base = _defaultNames[strategy.id] ?? strategy.name.split(' ').last;
    var name = base;
    var n = 2;
    while (game.seats.any((s) => s.name == name)) {
      name = '$base $n';
      n++;
    }
    return name;
  }

  Seat? addPlayer(String name, Strategy strategy) {
    final seat = game.addPlayer(name, strategy.id);
    _notify();
    return seat;
  }

  void removePlayer(Seat seat) {
    game.removePlayer(seat);
    _notify();
  }

  void setStrategy(Seat seat, Strategy strategy) {
    seat.strategyId = strategy.id;
    _notify();
  }

  /// Keeps a strategy written in the app, so players can use it; a new
  /// id unless it replaces one.
  Strategy saveCustom(String text, {Strategy? replacing}) {
    final id = replacing?.id ?? 'custom-${++_customs}';
    final strategy = Strategy.parse(text, id: id);
    final at = strategies.indexWhere((s) => s.id == id);
    if (at >= 0) {
      strategies[at] = strategy;
    } else {
      strategies.add(strategy);
    }
    _notify();
    return strategy;
  }

  /// The id of the strategy a seat gets when its rules are changed at
  /// the table.
  static String ownStrategyId(Seat seat) => 'seat-${seat.id}';

  /// Gives [seat] its own strategy with [decisions]: a copy of the one it
  /// plays, named after the player, or its own one changed in place.
  Strategy personalize(Seat seat, Map<String, Object?> decisions) {
    final id = ownStrategyId(seat);
    final current = strategyOf(seat);
    final base = current?.id == id
        ? current!.tagline
        : 'Based on ${current?.name ?? seat.strategyId}, changed at the table.';
    final name = current?.id == id
        ? current!.name
        : "${seat.name}'s ${(current?.name ?? 'rules').replaceFirst(RegExp(r'^The '), '')}";
    final strategy = Strategy(
      id: id,
      name: name,
      tagline: base,
      decisions: decisions,
      custom: true,
    );
    final at = strategies.indexWhere((s) => s.id == id);
    if (at >= 0) {
      strategies[at] = strategy;
    } else {
      strategies.add(strategy);
    }
    seat.strategyId = id;
    _notify();
    return strategy;
  }

  void removeCustom(Strategy strategy) {
    if (game.seats.any((s) => s.strategyId == strategy.id)) return;
    strategies.remove(strategy);
    _notify();
  }

  void setPace(double seconds) {
    pace = seconds.clamp(0, maxPace);
    _notify();
  }

  void play() {
    if (playing) return;
    playing = true;
    error = null;
    _notify();
    unawaited(_run());
  }

  void pause() {
    playing = false;
    _notify();
  }

  /// One step, while paused.
  Future<void> step() async {
    if (playing) return;
    error = null;
    await _step();
  }

  /// A new tournament; the calls and the log start over.
  void reset() {
    playing = false;
    game.reset();
    calls.clear();
    thinking = null;
    lastStep = null;
    error = null;
    _notify();
  }

  Future<void> _run() async {
    while (playing && !_disposed) {
      final step = await _step();
      if (!playing || _disposed || step == null) break;
      final factor = switch (step) {
        HandOver() => 2.5,
        TournamentOver() => 0.0,
        HandStarted() => 0.8,
        _ => 1.0,
      };
      final wait = Duration(milliseconds: (pace * factor * 1000).round());
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  /// One step at the table; a decision is asked of the API and played.
  Future<Step?> _step() async {
    if (_busy) return null;
    _busy = true;
    try {
      final step = game.next();
      lastStep = step;
      switch (step) {
        case Waiting(:final reason):
          playing = false;
          error = reason;
          _notify();
        case TournamentOver():
          playing = false;
          _notify();
        case NeedsAction(:final seat, :final situation):
          final strategy = strategyOf(seat);
          if (strategy == null) {
            playing = false;
            error = '${seat.name} has no strategy.';
            _notify();
            break;
          }
          final call = AityxCall(
            number: calls.length + 1,
            hand: game.handNumber,
            street: game.street!,
            seat: seat,
            strategy: strategy,
            situation: situation,
          );
          calls.insert(0, call);
          thinking = call;
          _notify();
          try {
            final result = await api.act(strategy, situation);
            call.result = result;
            if (_disposed) return step;
            call.taken = game.apply(
              PlayerAction(result.kind, raiseTo: result.raiseTo),
            );
            // The log's line for the action points back at the call.
            game.log.last.call = call.number;
          } on ApiException catch (e) {
            call.error = e.message;
            error = '${seat.name} (${strategy.name}): ${e.message}';
            playing = false;
          }
          thinking = null;
          _notify();
        default:
          _notify();
      }
      return step;
    } finally {
      _busy = false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    playing = false;
    super.dispose();
  }
}
