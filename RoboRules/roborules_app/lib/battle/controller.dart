import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'model.dart';
import 'random_robots.dart';

/// Where a battle is.
enum BattleState { setup, running, paused, scoring, over }

/// The most robots a battle takes: the colors run out, and the field gets
/// crowded.
const maxRobots = 10;

/// A burst drawn where a robot was hit or died.
class Explosion {
  Explosion(this.x, this.y, this.big, this.at);

  final double x;
  final double y;
  final bool big;
  final DateTime at;

  /// How long it burns: a hit flashes, a robot lost blows up for longer.
  int get millis => big ? 1600 : 700;
}

/// A call to aityx: what was asked and what it answered. Only the last
/// few keep their payloads; the rest keep their line in the log.
class AityxCall {
  AityxCall({
    required this.number,
    required this.what,
    required this.request,
    required this.response,
  });

  final int number;

  /// 'turns 21–40 of round 1' or 'the score of round 1'.
  final String what;
  Object? request;
  Object? response;

  /// Whether what was sent and answered is still here: only the last few
  /// calls' are.
  bool kept = true;
}

/// A line of the battle log: what happened, and the aityx call behind it
/// when it was one.
class BattleEvent {
  const BattleEvent(this.text, {this.call});

  final String text;
  final AityxCall? call;
}

/// A robot's totals over the battle's rounds.
class Totals {
  int total = 0;
  int survival = 0;
  int lastSurvivor = 0;
  int bulletDamage = 0;
  int firsts = 0;
}

/// Runs a battle: its rounds, fetching turns from aityx ahead of time and
/// playing them at [turnsPerSecond], scoring each round on aityx.
class BattleController extends ChangeNotifier {
  BattleController({BattleApi? api, RobotFactory? factory})
    : _api = api ?? HttpBattleApi(),
      factory = factory ?? RobotFactory();

  final BattleApi _api;
  final RobotFactory factory;

  List<Robot> robots = [];
  int rounds = 3;

  /// A round ends when one robot is left, or after this many turns.
  int maxTurns = 1500;

  /// Playback speed; 0 means as fast as aityx answers.
  double turnsPerSecond = 15;

  /// Turns asked of aityx per call.
  int turnsPerCall = 20;

  BattleState state = BattleState.setup;
  int round = 0;
  World? world;
  World? previous;
  DateTime shownAt = DateTime.now();
  final explosions = <Explosion>[];
  final roundScores = <RoundScore>[];
  final totals = <String, Totals>{};
  String? error;

  /// Everything that happened, oldest first: rule changes, hits, losses,
  /// rounds and their scores, every call to aityx, errors.
  final events = <BattleEvent>[];

  /// Every call to aityx this battle, oldest first; the last [keptCalls]
  /// keep what was sent and answered, for the viewer.
  final calls = <AityxCall>[];
  int keptCalls = 10;
  int maxEvents = 2000;

  /// The last call to aityx, for the viewer.
  AityxCall? get lastCall => calls.lastOrNull;
  Object? get lastRequest => lastCall?.request;
  Object? get lastResponse => lastCall?.response;

  /// How fast aityx plays turns, measured.
  double? aityxTurnsPerSecond;

  final _buffer = ListQueue<World>();
  bool _disposed = false;
  bool _fetching = false;
  bool _roundEnds = false;
  int _battleId = 0;
  Timer? _timer;

  /// A finished round aityx couldn't score yet: [retryScore] tries again.
  World? _unscored;

  int get buffered => _buffer.length;
  bool get waitingForAityx => _fetching && _buffer.isEmpty;
  bool get canRetryScore => _unscored != null && state == BattleState.scoring;

  /// [n] new robots with random rules.
  void randomRobots(int n) {
    robots = [];
    for (var i = 0; i < n; i++) {
      robots.add(factory.make(taken: robots));
    }
    _reset();
  }

  /// The battle's robots, as New Battle picked them; the battle starts over.
  void setRobots(List<Robot> picked) {
    robots = picked.take(maxRobots).toList();
    _reset();
  }

  /// Adds [robot] to the battle, which starts over; no more than
  /// [maxRobots].
  void addRobot(Robot robot) {
    if (robots.length >= maxRobots) return;
    robots = [...robots, robot];
    _reset();
  }

  /// Takes robot [index] out of the battle, which starts over.
  void removeRobot(int index) {
    if (index < 0 || index >= robots.length) return;
    robots = [...robots]..removeAt(index);
    _reset();
  }

  void replaceRobot(int index, Robot robot) {
    final was = robots[index].name;
    robots[index] = robot;
    _log(
      was == robot.name
          ? "${robot.name}'s rules changed: ${robot.rules.length} rules"
          : "$was is now ${robot.name}: ${robot.rules.length} rules",
    );
    notifyListeners();
  }

  void _log(String text, {AityxCall? call}) {
    events.add(BattleEvent(text, call: call));
    if (events.length > maxEvents) events.removeRange(0, events.length ~/ 4);
  }

  AityxCall _recordCall(String what, Object? request, Object? response) {
    final call = AityxCall(
      number: calls.length + 1,
      what: what,
      request: request,
      response: response,
    );
    calls.add(call);
    if (calls.length > keptCalls) {
      calls[calls.length - keptCalls - 1]
        ..kept = false
        ..request = null
        ..response = null;
    }
    return call;
  }

  /// The rule [b] followed this turn, as the robot's rules are now.
  Rule? _ruleOf(Bot b) {
    final i = int.tryParse(b.id.substring(1));
    if (i == null || i < 1 || i > robots.length) return null;
    final rules = robots[i - 1].rules;
    return b.rule >= 1 && b.rule <= rules.length ? rules[b.rule - 1] : null;
  }

  String _name(String id) {
    final i = int.tryParse(id.substring(1));
    return i != null && i >= 1 && i <= robots.length ? robots[i - 1].name : id;
  }

  void setSpeed(double tps) {
    turnsPerSecond = tps;
    notifyListeners();
  }

  void _reset() {
    _battleId++;
    _stopTimer();
    _fetching = false;
    _roundEnds = false;
    _unscored = null;
    state = BattleState.setup;
    round = 0;
    world = _startWorld();
    previous = null;
    _buffer.clear();
    explosions.clear();
    roundScores.clear();
    events.clear();
    calls.clear();
    totals
      ..clear()
      ..addAll({for (var i = 0; i < robots.length; i++) 'r${i + 1}': Totals()});
    error = null;
    notifyListeners();
  }

  World _startWorld() {
    final places = factory.places(robots.length);
    return World(
      tick: 0,
      bots: [
        for (var i = 0; i < robots.length; i++)
          Bot.start('r${i + 1}', places[i].x, places[i].y, places[i].heading),
      ],
      bullets: const [],
    );
  }

  /// Starts the battle from round 1.
  void start() {
    if (robots.length < 2) return;
    _reset();
    round = 1;
    state = BattleState.running;
    _log(
      'Battle: ${robots.map((r) => r.name).join(', ')}; '
      '$rounds round${rounds == 1 ? '' : 's'}',
    );
    _log('Round 1 begins');
    _startTimer();
    _fetch();
    notifyListeners();
  }

  void pause() {
    if (state != BattleState.running) return;
    state = BattleState.paused;
    notifyListeners();
  }

  void resume() {
    if (state != BattleState.paused) return;
    error = null;
    state = BattleState.running;
    shownAt = DateTime.now();
    notifyListeners();
  }

  /// Shows the next turn while paused.
  void nextTurn() {
    if (state == BattleState.paused) _advance();
  }

  void stop() => _reset();

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    final now = DateTime.now();
    explosions.removeWhere(
      (e) => now.difference(e.at).inMilliseconds > e.millis,
    );
    if (state == BattleState.running) {
      final interval = turnsPerSecond <= 0 ? 0 : 1000 / turnsPerSecond;
      if (_buffer.isNotEmpty &&
          now.difference(shownAt).inMilliseconds >= interval) {
        _advance();
      }
    }
    _fetch();
    // Repaint for smooth movement and fading explosions.
    notifyListeners();
  }

  /// Shows the next buffered turn: explosions for hits and losses, and
  /// the round's end when it was its last.
  void _advance() {
    if (_buffer.isEmpty) return;
    final next = _buffer.removeFirst();
    final before = world;
    previous = before;
    world = next;
    shownAt = DateTime.now();
    final t = 'Turn ${next.tick}';
    final hitters = <Bot>[];
    for (final b in next.bots) {
      final was = before?.bots.where((o) => o.id == b.id).firstOrNull;
      if (b.hit) explosions.add(Explosion(b.x, b.y, false, shownAt));
      if (was != null && was.alive && !b.alive) {
        explosions.add(Explosion(b.x, b.y, true, shownAt));
      }
      if (was == null) continue;
      if (b.alive && b.rule > 0 && b.rule != was.rule) {
        final why = _ruleOf(b)?.why ?? '';
        _log(
          '$t · ${_name(b.id)} follows rule ${b.rule}'
          '${why.isEmpty ? '' : ': $why'}',
        );
      }
      if (b.damage > was.damage) hitters.add(b);
    }
    for (final b in next.bots) {
      final was = before?.bots.where((o) => o.id == b.id).firstOrNull;
      if (was == null) continue;
      if (b.hit) {
        final taken = (was.energy - b.energy).toStringAsFixed(1);
        final by = hitters.length == 1 ? ' by ${_name(hitters.single.id)}' : '';
        _log(
          '$t · ${_name(b.id)} is hit$by: −$taken, '
          '${b.energy.toStringAsFixed(1)} left',
        );
      }
      if (was.alive && !b.alive) _log('$t · ${_name(b.id)} is lost');
    }
    if (_buffer.isEmpty && _roundEnds) unawaited(_endRound(next));
    notifyListeners();
  }

  /// Asks aityx for the next turns when the buffer runs low.
  Future<void> _fetch() async {
    if (_disposed || _fetching || _roundEnds) return;
    if (state != BattleState.running && state != BattleState.paused) return;
    // After a failed call, wait for Resume rather than retry while paused.
    if (state == BattleState.paused && error != null) return;
    if (_buffer.length >= turnsPerCall) return;
    final from = _buffer.isNotEmpty ? _buffer.last : world;
    if (from == null) return;
    final n = min(turnsPerCall, maxTurns - from.tick);
    if (n <= 0) return;
    _fetching = true;
    final started = DateTime.now();
    final battleAtStart = _battleId;
    final roundAtStart = round;
    bool stale() =>
        _disposed || battleAtStart != _battleId || round != roundAtStart;
    try {
      final turns = await _api.turns(robots, from, n);
      if (stale()) return;
      final ms = DateTime.now().difference(started).inMilliseconds;
      aityxTurnsPerSecond = n * 1000 / max(ms, 1);
      final played = turns.frames.isEmpty
          ? 'no turns'
          : 'turns ${from.tick + 1}–${turns.frames.last.tick}';
      final call = _recordCall(
        '$played of round $round',
        turns.request,
        turns.response,
      );
      _log('aityx played $played in $ms ms (call ${call.number})', call: call);
      error = null;
      for (final f in turns.frames) {
        _buffer.add(f);
        if (f.alive <= 1 || f.tick >= maxTurns) {
          _roundEnds = true;
          break;
        }
      }
    } on BattleException catch (e) {
      if (stale()) return;
      error = e.message;
      _log('The call failed: ${e.message}');
      if (state == BattleState.running) state = BattleState.paused;
    } finally {
      if (battleAtStart == _battleId) _fetching = false;
      notifyListeners();
    }
  }

  /// Scores the finished round again, after aityx failed to.
  void retryScore() {
    final last = _unscored;
    if (last != null && state == BattleState.scoring) {
      unawaited(_endRound(last));
    }
  }

  Future<void> _endRound(World last) async {
    final battleAtStart = _battleId;
    bool stale() => _disposed || battleAtStart != _battleId;
    if (state != BattleState.scoring) {
      final left = last.bots.where((b) => b.alive).map((b) => _name(b.id));
      _log(
        'Round $round is over on turn ${last.tick}: '
        '${left.isEmpty
            ? 'no robot is left'
            : left.length == 1
            ? '${left.single} is the last one standing'
            : '${left.join(', ')} are still standing'}',
      );
    }
    state = BattleState.scoring;
    _unscored = null;
    error = null;
    notifyListeners();
    final started = DateTime.now();
    try {
      final score = await _api.score(last);
      if (stale()) return;
      roundScores.add(score);
      final call = _recordCall(
        'the score of round $round',
        score.request,
        score.response,
      );
      final ms = DateTime.now().difference(started).inMilliseconds;
      _log(
        'aityx scored round $round in $ms ms (call ${call.number}): '
        '${score.scores.map((s) => '${_name(s.id)} ${s.total}').join(', ')}',
        call: call,
      );
      for (final s in score.scores) {
        final t = totals[s.id];
        if (t == null) continue;
        t
          ..total += s.total
          ..survival += s.survival
          ..lastSurvivor += s.lastSurvivor
          ..bulletDamage += s.bulletDamage;
      }
      if (score.winner case final w?) totals[w]?.firsts += 1;
    } on BattleException catch (e) {
      if (stale()) return;
      // Keep the round until it's scored: moving on would leave it out of
      // the totals and could change the ranking.
      error = 'Scoring failed: ${e.message}';
      _log('Scoring round $round failed: ${e.message}');
      _unscored = last;
      notifyListeners();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (stale() || state != BattleState.scoring) return;
    if (round >= rounds) {
      state = BattleState.over;
      final best = ranking.first;
      _log(
        'Battle over: ${robots[best].name} wins with '
        '${totals['r${best + 1}']?.total ?? 0} points',
      );
      _stopTimer();
      notifyListeners();
      return;
    }
    round += 1;
    world = _startWorld();
    previous = null;
    _roundEnds = false;
    _buffer.clear();
    state = BattleState.running;
    _log('Round $round begins');
    notifyListeners();
  }

  /// The robots in order of their battle total, best first.
  List<int> get ranking {
    final ids = List.generate(robots.length, (i) => i);
    ids.sort(
      (a, b) => (totals['r${b + 1}']?.total ?? 0).compareTo(
        totals['r${a + 1}']?.total ?? 0,
      ),
    );
    return ids;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}
