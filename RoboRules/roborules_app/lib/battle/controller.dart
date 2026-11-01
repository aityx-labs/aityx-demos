import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../sound/sounds.dart';
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

/// A call to aityx: what was asked, what it answered, and how long it
/// took. Only the last few keep their payloads.
class AityxCall {
  AityxCall({
    required this.number,
    required this.what,
    required this.request,
    required this.response,
    this.millis,
    this.result,
  });

  final int number;

  /// 'turns 21–40 of round 1' or 'the score of round 1'.
  final String what;

  /// How long aityx took to answer.
  final int? millis;

  /// What came back, when there's something to say: a round's scores.
  final String? result;
  Object? request;
  Object? response;

  /// Whether what was sent and answered is still here: only the last few
  /// calls' are.
  bool kept = true;
}

/// A line of the battle log: what happened, and the aityx call behind it,
/// if any: the call that played the turn of a rule switch, shot, hit,
/// loss or round's end, the score that named a round's winner, or the
/// last score, for the battle's end. The calls themselves aren't lines:
/// the latest is shown below the log ([BattleController.lastCall]).
class BattleEvent {
  const BattleEvent(this.text, {this.call, this.isShot = false});

  final String text;
  final AityxCall? call;

  /// Whether the line is a robot firing a shot.
  final bool isShot;
}

/// A round as aityx scored it, for the battlefield to announce: its
/// winner (an index into the robots, null when none) and the winner's
/// points.
class RoundWinner {
  const RoundWinner(this.round, this.robot, this.points);

  final int round;
  final int? robot;
  final int points;
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
/// playing them at [turnsPerSecond], scoring each round on aityx, and
/// sounding its collisions, hits and losses as it shows them.
class BattleController extends ChangeNotifier {
  BattleController({BattleApi? api, RobotFactory? factory, Sounds? sounds})
    : _api = api ?? AityxBattleApi(),
      factory = factory ?? RobotFactory(),
      sounds = sounds ?? Sounds() {
    soundOn = this.sounds.saved ?? true;
  }

  final BattleApi _api;
  final RobotFactory factory;

  /// Plays the battle's sounds, while [soundOn].
  final Sounds sounds;

  /// Whether the battle makes sounds: on, unless the user turned them off
  /// in this browser.
  late bool soundOn;

  /// The least time between two sounds of a kind, so that turns played
  /// fast don't make a wall of noise.
  Duration soundGap = const Duration(milliseconds: 100);
  final _soundAt = <BattleSound, DateTime>{};

  List<Robot> robots = [];
  int rounds = 3;

  /// A round ends when one robot is left, or after this many turns.
  int maxTurns = 1500;

  /// The chosen playback speed, where a battle starts; 0 means as fast as
  /// aityx answers.
  double turnsPerSecond = 10;

  /// Every [speedUpEvery] of play (pauses don't count), playback speeds up
  /// by [speedUpBy] turns a second, up to [speedUpTo]: see [pace].
  Duration speedUpEvery = const Duration(seconds: 15);
  double speedUpBy = 5;
  double speedUpTo = 40;

  /// How long the battle has played since it started, or since the speed
  /// was chosen: a [_tickEvery] for each tick while running.
  Duration _played = Duration.zero;

  /// How often the battle ticks: shows a turn when due, and repaints.
  static const _tickEvery = Duration(milliseconds: 16);

  /// How fast turns are shown now: the chosen speed, sped up for every
  /// [speedUpEvery] played, up to [speedUpTo] (never below the choice); 0,
  /// as fast as aityx, stays 0.
  double get pace {
    if (turnsPerSecond <= 0) return 0;
    final steps = _played.inMicroseconds ~/ speedUpEvery.inMicroseconds;
    return max(
      turnsPerSecond,
      min(speedUpTo, turnsPerSecond + steps * speedUpBy),
    );
  }

  /// Turns asked of aityx per call.
  int turnsPerCall = 20;

  BattleState state = BattleState.setup;
  int round = 0;

  /// The round just scored, announced until the next one begins.
  RoundWinner? roundWinner;

  /// How long the winner is announced before the next round.
  Duration announceFor = const Duration(milliseconds: 3000);
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

  /// Turns aityx played, not shown yet, each with the call that played it.
  final _buffer = ListQueue<(World, AityxCall)>();

  /// The call that played the turn on the battlefield.
  AityxCall? _shownCall;
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

  void _log(String text, {AityxCall? call, bool isShot = false}) {
    events.add(BattleEvent(text, call: call, isShot: isShot));
    if (events.length > maxEvents) events.removeRange(0, events.length ~/ 4);
  }

  AityxCall _recordCall(
    String what,
    Object? request,
    Object? response, {
    int? millis,
    String? result,
  }) {
    final call = AityxCall(
      number: calls.length + 1,
      what: what,
      request: request,
      response: response,
      millis: millis,
      result: result,
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

  /// Chooses the speed: playback goes on from it, speeding up again.
  void setSpeed(double tps) {
    turnsPerSecond = tps;
    _played = Duration.zero;
    notifyListeners();
  }

  /// Turns the sound [on] or off, and remembers it in this browser.
  void setSound(bool on) {
    soundOn = on;
    sounds.save(on);
    notifyListeners();
  }

  /// Plays [sound], when the sound is on and that kind hasn't sounded in
  /// the last [soundGap].
  void _play(BattleSound sound, DateTime now) {
    if (!soundOn) return;
    final last = _soundAt[sound];
    if (last != null && now.difference(last) < soundGap) return;
    _soundAt[sound] = now;
    sounds.play(sound);
  }

  void _reset() {
    _battleId++;
    _stopTimer();
    _fetching = false;
    _roundEnds = false;
    _unscored = null;
    state = BattleState.setup;
    round = 0;
    roundWinner = null;
    world = _startWorld();
    previous = null;
    _buffer.clear();
    _shownCall = null;
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
    _played = Duration.zero;
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
    _timer ??= Timer.periodic(_tickEvery, (_) => _tick());
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
      _played += _tickEvery;
      final speed = pace;
      final interval = speed <= 0 ? 0 : 1000 / speed;
      if (_buffer.isNotEmpty &&
          now.difference(shownAt).inMilliseconds >= interval) {
        _advance();
      }
    }
    _fetch();
    // Repaint for smooth movement and fading explosions.
    notifyListeners();
  }

  /// Shows the next buffered turn: explosions and sounds for hits and
  /// losses, sounds for collisions, and the round's end when it was its
  /// last.
  void _advance() {
    if (_buffer.isEmpty) return;
    final (next, call) = _buffer.removeFirst();
    _shownCall = call;
    final before = world;
    previous = before;
    world = next;
    shownAt = DateTime.now();
    final t = 'Turn ${next.tick}';
    final hitters = <Bot>[];
    final heard = <BattleSound>{};
    for (final b in next.bots) {
      final was = before?.bots.where((o) => o.id == b.id).firstOrNull;
      if (b.hit) {
        explosions.add(Explosion(b.x, b.y, false, shownAt));
        heard.add(BattleSound.hit);
      }
      if (was != null && was.alive && !b.alive) {
        explosions.add(Explosion(b.x, b.y, true, shownAt));
        heard.add(BattleSound.loss);
      }
      if (was == null) continue;
      if (collided(b, was, next)) heard.add(BattleSound.collision);
      if (b.alive && b.rule > 0 && b.rule != was.rule) {
        final why = _ruleOf(b)?.why ?? '';
        _log(
          '$t · ${_name(b.id)} follows rule ${b.rule}'
          '${why.isEmpty ? '' : ': $why'}',
          call: call,
        );
      }
      if (b.fired > 0) {
        final power = b.fired == b.fired.roundToDouble()
            ? b.fired.toStringAsFixed(0)
            : '${b.fired}';
        _log(
          '$t · ${_name(b.id)} fires a shot of power $power',
          call: call,
          isShot: true,
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
          call: call,
        );
      }
      if (was.alive && !b.alive) {
        _log('$t · ${_name(b.id)} is lost', call: call);
      }
    }
    // A robot lost drowns out the rest of its turn.
    if (heard.contains(BattleSound.loss)) {
      _play(BattleSound.loss, shownAt);
    } else {
      for (final s in heard) {
        _play(s, shownAt);
      }
    }
    if (_buffer.isEmpty && _roundEnds) unawaited(_endRound(next));
    notifyListeners();
  }

  /// Whether [b], [was] the turn before, ran into a wall or rammed
  /// another robot this turn in [world]. The world model stops a robot
  /// either way: at a wall it stays [robotRadius] from it, and when two
  /// robots come closer than 36 px both stay where they were. So a robot
  /// that was moving and now stands still, at a wall or where it was with
  /// another robot close by, collided; one that stays stuck doesn't again.
  @visibleForTesting
  static bool collided(Bot b, Bot was, World world) {
    if (!b.alive || !was.alive || b.v != 0 || was.v == 0) return false;
    const edge = robotRadius + 0.01;
    if (b.x <= edge ||
        b.y <= edge ||
        b.x >= arenaWidth - edge ||
        b.y >= arenaHeight - edge) {
      return true;
    }
    if (b.x != was.x || b.y != was.y) return false;
    // Both rammed robots stay put, and either may have moved up to 8 px
    // before the ram undid it.
    return world.bots.any(
      (o) =>
          o.id != b.id &&
          (o.alive || o.died == world.tick) &&
          (o.x - b.x) * (o.x - b.x) + (o.y - b.y) * (o.y - b.y) <
              (2 * robotRadius + 16) * (2 * robotRadius + 16),
    );
  }

  /// Asks aityx for the next turns when the buffer runs low.
  Future<void> _fetch() async {
    if (_disposed || _fetching || _roundEnds) return;
    if (state != BattleState.running && state != BattleState.paused) return;
    // After a failed call, wait for Resume rather than retry while paused.
    if (state == BattleState.paused && error != null) return;
    if (_buffer.length >= turnsPerCall) return;
    final from = _buffer.isNotEmpty ? _buffer.last.$1 : world;
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
        millis: ms,
      );
      error = null;
      for (final f in turns.frames) {
        _buffer.add((f, call));
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
        call: _shownCall,
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
      final ms = DateTime.now().difference(started).inMilliseconds;
      final call = _recordCall(
        'the score of round $round',
        score.request,
        score.response,
        millis: ms,
        result: score.scores.map((s) => '${_name(s.id)} ${s.total}').join(', '),
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
      final i = score.winner == null
          ? null
          : int.tryParse(score.winner!.substring(1));
      final winner = i != null && i >= 1 && i <= robots.length ? i - 1 : null;
      final points =
          score.scores.where((s) => s.id == score.winner).firstOrNull?.total ??
          0;
      roundWinner = RoundWinner(round, winner, points);
      _log(
        winner == null
            ? 'Round $round has no winner'
            : '${robots[winner].name} wins round $round, with $points points',
        call: call,
      );
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
    notifyListeners();
    await Future<void>.delayed(announceFor);
    if (stale() || state != BattleState.scoring) return;
    if (round >= rounds) {
      state = BattleState.over;
      final best = ranking.first;
      _log(
        'Battle over: ${robots[best].name} wins with '
        '${totals['r${best + 1}']?.total ?? 0} points',
        call: lastCall,
      );
      _stopTimer();
      notifyListeners();
      return;
    }
    round += 1;
    roundWinner = null;
    world = _startWorld();
    previous = null;
    _roundEnds = false;
    _buffer.clear();
    _shownCall = null;
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
