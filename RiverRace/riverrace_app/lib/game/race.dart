/// The race: three planes up one river at once, by the original's rules.
/// Each plane flies, fires one missile at a time (it follows the plane
/// sideways, as in the original), burns fuel and fills up flying over a
/// depot, scores for what it shoots (ship 30, helicopter 60, fuel 80, jet
/// 100, bridge 500), and is lost crashing into land, an enemy or a
/// standing bridge, or running out of fuel. Planes don't collide with each
/// other; what one shoots is gone for all. The screen follows the plane
/// furthest up; a plane left behind is pushed along by its bottom edge.
///
/// The player's plane is flown by [Controls]; the aityx pilots' by the
/// [PilotAction] aityx last decided for them.
library;

import 'dart:math';

import 'river.dart';

/// The screen shows 160 rows of river.
const viewHeight = 160.0;

/// The plane furthest up flies this far above the screen's bottom; no
/// plane falls below [bottomMargin].
const leaderRow = 48.0;
const bottomMargin = 12.0;

/// Speeds up the river, in pixels a frame (60 frames a second).
const speeds = {'slow': 0.75, 'normal': 1.5, 'fast': 2.5};

/// Sideways, in pixels a frame.
const sideSpeed = 1.25;

/// The missile, in pixels a frame faster than the plane.
const missileSpeed = 5.0;

/// Fuel burned a frame (a full tank lasts about 24 seconds) and filled a
/// frame over a depot.
const burn = 0.07;
const refill = 0.9;

/// Over a depot a plane drops at once to this share of its throttle's
/// speed and holds it (the original's half, a little slower here), and beeps every
/// [refuelBeepEvery] frames.
const refuelSlow = 0.35;
const refuelBeepEvery = 6;

/// Lives at the start (one flying, seven in reserve), and an extra one
/// every 10,000 points.
const startLives = 8;
const bonusEvery = 10000;

/// How far a plane coming back after a crash can fly straight on.
const respawnClear = 40.0;

/// The plane's half width and half height.
const planeHalfWidth = 3.5;
const planeHalfHeight = 4.5;

/// How far the sensors look.
const lookAhead = 120.0;
const landLook = 48.0;
const threatLook = 40.0;

enum PlaneState { flying, exploding, out }

/// What the player is pressing.
class Controls {
  bool left = false;
  bool right = false;
  bool fast = false;
  bool slow = false;
  bool fire = false;
}

/// What an aityx pilot does, as aityx last decided, and the rule behind it.
class PilotAction {
  const PilotAction({
    this.steer = 'to_channel',
    this.throttle = 'normal',
    this.fire = false,
    this.rule,
    this.why,
  });

  factory PilotAction.fromJson(Map<String, Object?> json) => PilotAction(
    steer: json['steer'] as String? ?? 'straight',
    throttle: json['throttle'] as String? ?? 'normal',
    fire: json['fire'] == true,
    rule: (json['rule'] as num?)?.toInt(),
    why: json['why'] as String?,
  );

  final String steer;
  final String throttle;
  final bool fire;

  /// The strategy's rule that fired (1-based; 0 none matched), and why.
  final int? rule;
  final String? why;
}

class Missile {
  Missile(this.x, this.y);

  double x;
  double y;
}

class Plane {
  Plane({
    required this.id,
    required this.human,
    required this.x,
    required this.y,
  });

  /// `you`, `p1` or `p2`.
  final String id;
  final bool human;

  double x;
  double y;
  double speed = speeds['normal']!;
  String throttle = 'normal';
  double fuel = 100;
  int score = 0;
  int lives = startLives;
  int nextBonus = bonusEvery;
  PlaneState state = PlaneState.flying;
  int timer = 0;

  /// Frames left during which enemies pass through it, after a respawn.
  int shield = 0;
  Missile? missile;

  /// Bridges passed, and how far up the river it got.
  int bridges = 0;
  double best = 0;
  int lost = 0;
  String? lastLost;
  bool refueling = false;

  /// What an aityx pilot does now.
  PilotAction action = const PilotAction();

  bool get flying => state == PlaneState.flying;
}

class Thing {
  Thing(this.kind, this.x, this.y, {this.moves = false, this.vx = 0});

  final ThingKind kind;
  double x;
  final double y;
  final bool moves;
  double vx;
  bool moving = false;

  /// Frames left of its explosion; it's gone when they run out.
  int exploding = 0;
  bool gone = false;

  double get hw => thingSizes[kind]!.$1;
  double get hh => thingSizes[kind]!.$2;
  bool get solid => exploding == 0 && !gone;
}

/// A sound the game makes: a plane refueling, its pitch by how full the
/// tank is (0 to 1), or something a missile hit exploding.
sealed class RaceSound {
  const RaceSound();
}

class RefuelSound extends RaceSound {
  const RefuelSound(this.level);
  final double level;
}

class ExplosionSound extends RaceSound {
  const ExplosionSound();
}

/// Something that happened, for the race log.
class RaceEvent {
  const RaceEvent(this.frame, this.planeId, this.text);

  final int frame;
  final String planeId;
  final String text;
}

/// A bridge going down, for its explosion.
class Blast {
  Blast(this.x, this.y, this.frames);

  final double x;
  final double y;
  int frames;
}

class Race {
  Race({
    required this.seed,
    required List<String> planeIds,
    this.finishBridge = 10,
  }) : river = River(seed),
       _rng = Random(seed) {
    final xs = planeIds.length == 1
        ? [axis]
        : [
            for (var i = 0; i < planeIds.length; i++)
              axis - 20 + 40 * i / (planeIds.length - 1),
          ];
    planes = [
      for (final (i, id) in planeIds.indexed)
        Plane(id: id, human: id == 'you', x: xs[i], y: 30),
    ];
    _spawnUpTo(viewHeight * 2);
  }

  final int seed;
  final River river;
  final Random _rng;

  /// The race ends when a plane passes this bridge; 0 for no finish line,
  /// until every plane is out.
  final int finishBridge;

  late final List<Plane> planes;
  final things = <Thing>[];
  final broken = <int>{};
  final blasts = <Blast>[];
  final events = <RaceEvent>[];

  /// The sounds made since the screen last played them; it clears them.
  final sounds = <RaceSound>[];
  final controls = Controls();

  /// The river's row at the screen's bottom.
  double camera = 0;
  int frame = 0;
  bool over = false;
  int _spawned = -1;
  int _nextJet = 600;

  Plane plane(String id) => planes.firstWhere((p) => p.id == id);

  /// The winner once the race is over: the best score, then the furthest.
  Plane? get winner {
    if (!over || planes.isEmpty) return null;
    return ([...planes]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : b.best.compareTo(a.best);
        }))
        .first;
  }

  void _log(Plane p, String text) {
    events.insert(0, RaceEvent(frame, p.id, text));
    if (events.length > 60) events.removeLast();
  }

  void _spawnUpTo(double y) {
    final last = (y / sectionLength).floor();
    while (_spawned < last) {
      _spawned++;
      for (final t in river.thingsOf(_spawned)) {
        things.add(Thing(t.kind, t.x, t.y, moves: t.moves, vx: t.vx));
      }
    }
  }

  /// One frame of the race.
  void step() {
    if (over) return;
    frame++;
    _spawnUpTo(camera + viewHeight + 200);
    _jets();
    _moveThings();
    for (final p in planes) {
      _fly(p);
    }
    for (final b in blasts) {
      b.frames--;
    }
    blasts.removeWhere((b) => b.frames <= 0);
    final flying = planes.where((p) => p.flying);
    if (flying.isNotEmpty) {
      camera = max(camera, flying.map((p) => p.y).reduce(max) - leaderRow);
    }
    if (planes.every((p) => p.state == PlaneState.out) ||
        (finishBridge > 0 && planes.any((p) => p.bridges >= finishBridge))) {
      over = true;
    }
  }

  void _jets() {
    if (camera < sectionLength / 2 || frame < _nextJet) return;
    _nextJet = frame + 200 + _rng.nextInt(320);
    final fromLeft = _rng.nextBool();
    things.add(
      Thing(
        ThingKind.jet,
        fromLeft ? -8 : fieldWidth + 8,
        camera + 90 + _rng.nextDouble() * 60,
        moves: true,
        vx: fromLeft ? 2 : -2,
      )..moving = true,
    );
  }

  void _moveThings() {
    for (final t in things) {
      if (t.exploding > 0 && --t.exploding == 0) t.gone = true;
      if (!t.solid) continue;
      if (t.kind == ThingKind.jet) {
        t.x += t.vx;
        if (t.x < -16 || t.x > fieldWidth + 16) t.gone = true;
        continue;
      }
      // Ships and helicopters start to patrol once on screen.
      if (t.moves && !t.moving && t.y < camera + viewHeight - 8) {
        t.moving = true;
      }
      if (!t.moving) continue;
      final nx = t.x + t.vx;
      final edge = nx + (t.vx > 0 ? t.hw : -t.hw);
      if (river.isLand(edge, t.y)) {
        t.vx = -t.vx;
      } else {
        t.x = nx;
      }
    }
    things.removeWhere((t) => t.gone || t.y < camera - 40);
  }

  void _fly(Plane p) {
    switch (p.state) {
      case PlaneState.out:
        return;
      case PlaneState.exploding:
        if (--p.timer <= 0) {
          if (p.lives > 0) {
            _respawn(p);
          } else {
            p.state = PlaneState.out;
            _log(p, 'is out of the race');
          }
        }
        _missile(p);
        return;
      case PlaneState.flying:
        break;
    }
    final (dx, throttle, fire) = p.human ? _player() : _pilot(p);
    p.throttle = throttle;
    final target = speeds[throttle]!;
    if (p.refueling) {
      p.speed = target * refuelSlow;
    } else {
      p.speed += (target - p.speed).clamp(-0.08, 0.08);
    }
    p.x = (p.x + dx).clamp(planeHalfWidth, fieldWidth - planeHalfWidth);
    p.y += p.speed;
    if (p.y < camera + bottomMargin) p.y = camera + bottomMargin;
    p.best = max(p.best, p.y);
    if (p.shield > 0) p.shield--;
    p.fuel = max(0, p.fuel - burn);
    p.refueling = false;
    if (fire && p.missile == null) p.missile = Missile(p.x, p.y + 6);
    _missile(p);

    while (p.y > River.bridgeY(p.bridges + 1) + 4) {
      p.bridges++;
    }
    if (p.score >= p.nextBonus) {
      p.nextBonus += bonusEvery;
      p.lives++;
      _log(p, 'earned an extra plane');
    }

    // Land, a standing bridge, enemies, fuel.
    for (final (ox, oy) in const [
      (0.0, 4.0),
      (-planeHalfWidth, -1.0),
      (planeHalfWidth, -1.0),
      (-1.5, -4.0),
      (1.5, -4.0),
    ]) {
      if (river.isLand(p.x + ox, p.y + oy)) {
        return _lose(p, 'crashed into the bank');
      }
    }
    for (
      var row = p.y - planeHalfHeight;
      row <= p.y + planeHalfHeight;
      row += 2
    ) {
      final b = river.bridgeAt(row);
      if (b != null && !broken.contains(b)) {
        return _lose(p, 'hit bridge $b');
      }
    }
    for (final t in things) {
      if (!t.solid ||
          (p.x - t.x).abs() > t.hw + planeHalfWidth ||
          (p.y - t.y).abs() > t.hh + planeHalfHeight) {
        continue;
      }
      if (t.kind == ThingKind.fuel) {
        p.fuel = min(100, p.fuel + refill);
        p.refueling = true;
        if (frame % refuelBeepEvery == 0) sounds.add(RefuelSound(p.fuel / 100));
      } else if (p.shield == 0) {
        t.exploding = 16;
        return _lose(p, 'hit ${_name(t.kind)}');
      }
    }
    if (p.fuel <= 0) _lose(p, 'ran out of fuel');
  }

  void _missile(Plane p) {
    final m = p.missile;
    if (m == null) return;
    if (p.flying) m.x = p.x;
    m.y += (p.flying ? p.speed : 0) + missileSpeed;
    if (m.y > camera + viewHeight + 4) {
      p.missile = null;
      return;
    }
    for (final t in things) {
      if (t.solid &&
          (m.x - t.x).abs() <= t.hw + 1 &&
          (m.y - t.y).abs() <= t.hh + 3) {
        t.exploding = 16;
        p.score += thingPoints[t.kind]!;
        p.missile = null;
        sounds.add(const ExplosionSound());
        if (t.kind == ThingKind.fuel) _log(p, 'shot a fuel depot (+80)');
        return;
      }
    }
    for (var row = m.y - 3; row <= m.y + 3; row += 1) {
      final b = river.bridgeAt(row);
      if (b != null && !broken.contains(b)) {
        broken.add(b);
        p.score += bridgePoints;
        p.missile = null;
        blasts.add(Blast(axis, River.bridgeY(b), 30));
        sounds.add(const ExplosionSound());
        _log(p, 'blew up bridge $b (+$bridgePoints)');
        return;
      }
    }
  }

  void _lose(Plane p, String why) {
    p.state = PlaneState.exploding;
    p.timer = 50;
    p.lives--;
    p.lost++;
    p.lastLost = why;
    p.missile = null;
    _log(p, 'lost: $why');
  }

  void _respawn(Plane p) {
    final (x, y) = _respawnAt();
    p
      ..state = PlaneState.flying
      ..x = x
      ..y = y
      ..fuel = 100
      ..speed = speeds['normal']!
      ..shield = 120
      ..action = const PilotAction();
  }

  /// Where a lost plane comes back: low on the screen, mid-channel, where
  /// it can fly straight on for [respawnClear] rows without hitting the
  /// bank or a standing bridge; the widest channel if there's no such
  /// place.
  (double, double) _respawnAt() {
    for (var y = camera + 28; y <= camera + 100; y += 4) {
      final spans = river.spans(y)..sort((a, b) => b.width.compareTo(a.width));
      for (final s in spans) {
        if (_clearAhead(s.center, y)) return (s.center, y);
      }
    }
    final y = camera + 28;
    final spans = river.spans(y)..sort((a, b) => b.width.compareTo(a.width));
    return (spans.first.center, y);
  }

  bool _clearAhead(double x, double y) {
    for (var row = y - planeHalfHeight; row <= y + respawnClear; row += 2) {
      for (final dx in const [-planeHalfWidth - 2, 0.0, planeHalfWidth + 2]) {
        if (river.isLand(x + dx, row)) return false;
      }
      final b = river.bridgeAt(row);
      if (b != null && !broken.contains(b)) return false;
    }
    return true;
  }

  static String _name(ThingKind kind) => switch (kind) {
    ThingKind.ship => 'a ship',
    ThingKind.heli => 'a helicopter',
    ThingKind.fuel => 'a fuel depot',
    ThingKind.jet => 'a jet',
  };

  (double, String, bool) _player() {
    final c = controls;
    final dx = c.left == c.right ? 0.0 : (c.left ? -sideSpeed : sideSpeed);
    final throttle = c.fast == c.slow ? 'normal' : (c.fast ? 'fast' : 'slow');
    return (dx, throttle, c.fire);
  }

  (double, String, bool) _pilot(Plane p) {
    final a = p.action;
    final target = switch (a.steer) {
      'left' => p.x - 10,
      'right' => p.x + 10,
      'straight' => p.x,
      'to_fuel' => _fuelTarget(p) ?? _channelTarget(p),
      'dodge' => _dodgeTarget(p),
      _ => _channelTarget(p),
    };
    return ((target - p.x).clamp(-sideSpeed, sideSpeed), a.throttle, a.fire);
  }

  // --- What a plane senses ---

  /// The water span at [y] containing [x], else the nearest.
  Span _spanNear(double x, double y) {
    final spans = river.spans(y);
    for (final s in spans) {
      if (s.contains(x)) return s;
    }
    spans.sort((a, b) => (a.center - x).abs().compareTo((b.center - x).abs()));
    return spans.first;
  }

  /// Where the open water ahead is: the middle of the corridor of water
  /// the plane can follow up to [landLook] ahead (the water at every row,
  /// taken together). Where the river bends out of that corridor, it
  /// leans toward the water beyond, as far as the corridor allows.
  double _channelTarget(Plane p) {
    final start = _spanNear(p.x, p.y);
    var lo = start.left;
    var hi = start.right;
    const room = planeHalfWidth + 2;
    for (var d = 4.0; d <= landLook; d += 4) {
      final next = river.spans(p.y + d);
      // The stretch that continues the corridor; between two equally
      // good ones (an island's two sides), the one nearer the plane.
      Span? best;
      var score = double.negativeInfinity;
      for (final s in next) {
        final overlap = min(s.right, hi) - max(s.left, lo);
        final value = overlap - (s.center - p.x).abs() * 0.01;
        if (value > score) {
          score = value;
          best = s;
        }
      }
      final s = best!;
      final newLo = max(lo, s.left);
      final newHi = min(hi, s.right);
      if (newHi - newLo < room * 2) {
        if (hi - lo < room * 2) return (lo + hi) / 2;
        return s.center.clamp(lo + room, hi - room);
      }
      lo = newLo;
      hi = newHi;
    }
    return (lo + hi) / 2;
  }

  /// The nearest fuel depot ahead, within [lookAhead].
  Thing? _depot(Plane p) {
    Thing? best;
    for (final t in things) {
      if (!t.solid || t.kind != ThingKind.fuel) continue;
      final dy = t.y - p.y;
      if (dy < -8 || dy > lookAhead) continue;
      if (best == null || dy < best.y - p.y) best = t;
    }
    return best;
  }

  double? _fuelTarget(Plane p) => _depot(p)?.x;

  /// The nearest enemy about to collide, within [threatLook].
  Thing? _threat(Plane p) {
    Thing? best;
    for (final t in things) {
      if (!t.solid || t.kind == ThingKind.fuel) continue;
      final dy = t.y - p.y;
      if (dy < -4 || dy > threatLook) continue;
      if ((t.x - p.x).abs() > t.hw + planeHalfWidth + 6) continue;
      if (best == null || dy < best.y - p.y) best = t;
    }
    return best;
  }

  String _side(double dx) =>
      dx.abs() < 3 ? 'ahead' : (dx < 0 ? 'left' : 'right');

  double _dodgeTarget(Plane p) {
    final t = _threat(p);
    if (t == null) return _channelTarget(p);
    final span = _spanNear(p.x, p.y);
    final roomLeft = p.x - span.left;
    final roomRight = span.right - p.x;
    final side = _side(t.x - p.x);
    var goRight = side == 'left' || (side == 'ahead' && roomRight > roomLeft);
    if (goRight && roomRight < 8) goRight = false;
    if (!goRight && roomLeft < 8) goRight = true;
    return p.x + (goRight ? 10 : -10);
  }

  /// What [p] senses now, as the API and aityx take it.
  Map<String, Object> sense(Plane p) {
    var landDistance = 999;
    for (var d = 2.0; d <= lookAhead + 40; d += 2) {
      if (river.isLand(p.x, p.y + d) ||
          river.isLand(p.x - planeHalfWidth, p.y + d) ||
          river.isLand(p.x + planeHalfWidth, p.y + d)) {
        landDistance = d.round();
        break;
      }
    }
    final target = _channelTarget(p);
    final here = river.spans(p.y).where((s) => s.contains(p.x)).firstOrNull;
    double? enemy;
    var fuelAhead = false;
    for (final t in things) {
      if (!t.solid) continue;
      final dy = t.y - p.y;
      if (dy <= 0 || dy > lookAhead || (t.x - p.x).abs() > t.hw + 2) continue;
      if (t.kind == ThingKind.fuel) {
        fuelAhead = true;
      } else if (enemy == null || dy < enemy) {
        enemy = dy;
      }
    }
    final threat = _threat(p);
    final depot = _depot(p);
    var bridge = false;
    final next = p.bridges + 1;
    final by = River.bridgeY(next);
    if (!broken.contains(next) && by - p.y > 0 && by - p.y <= lookAhead) {
      bridge = true;
    }
    final top = planes.where((q) => q.flying).map((q) => q.y).fold(p.y, max);
    return {
      'fuel': p.fuel.round(),
      'speed': p.throttle,
      'land_ahead': landDistance <= landLook,
      'land_distance': landDistance,
      'channel': (target - p.x).abs() <= 4
          ? 'ahead'
          : (target < p.x ? 'left' : 'right'),
      'room_left': here == null ? 0 : (p.x - here.left).round(),
      'room_right': here == null ? 0 : (here.right - p.x).round(),
      'enemy_ahead': enemy != null,
      'enemy_distance': enemy?.round() ?? 999,
      'threat': threat == null ? 'none' : _side(threat.x - p.x),
      'fuel_ahead': fuelAhead,
      'fuel_side': depot == null ? 'none' : _side(depot.x - p.x),
      'bridge_ahead': bridge,
      'leading': p.y >= top,
      'missile_ready': p.missile == null,
    };
  }
}
