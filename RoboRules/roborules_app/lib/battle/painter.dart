import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'controller.dart';
import 'model.dart';

/// The battlefield as Robocode drew it: a dark ground, tanks with treads,
/// a turret and a radar, each gun's line of sight, bullets, explosions and
/// the scorch marks of robots lost, each robot's energy above it and its
/// name below; positions eased between turns.
class BattlefieldPainter extends CustomPainter {
  BattlefieldPainter({
    required this.previous,
    required this.current,
    required this.t,
    required this.robots,
    required this.explosions,
    required this.selected,
    required this.now,
  });

  final World? previous;
  final World? current;

  /// How far from [previous] to [current], 0 to 1.
  final double t;
  final List<Robot> robots;
  final List<Explosion> explosions;
  final int? selected;
  final DateTime now;

  static const _groundColor = Color(0xFF15171A);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / arenaWidth, size.height / arenaHeight);
    canvas.save();
    canvas.translate(
      (size.width - arenaWidth * scale) / 2,
      (size.height - arenaHeight * scale) / 2,
    );
    canvas.scale(scale);
    canvas.clipRect(const Rect.fromLTWH(0, 0, arenaWidth, arenaHeight));
    _drawGround(canvas);
    final world = current;
    if (world != null) {
      for (final b in world.bots) {
        if (!b.alive) _scorch(canvas, b);
      }
      final poses = <int, _Pose>{
        for (var i = 0; i < world.bots.length; i++)
          if (world.bots[i].alive) i: _pose(world.bots[i]),
      };
      for (final MapEntry(key: i, value: p) in poses.entries) {
        _sight(canvas, p, i, poses);
      }
      for (final b in world.bullets) {
        _bullet(canvas, b);
      }
      for (var i = 0; i < world.bots.length; i++) {
        final b = world.bots[i];
        if (!b.alive) continue;
        _tank(canvas, b, _pose(b), i, world.tick);
      }
    }
    for (final e in explosions) {
      _explosion(canvas, e);
    }
    canvas.restore();
  }

  /// Dark ground with a faint, fixed speckle, like Robocode's tiles.
  void _drawGround(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, arenaWidth, arenaHeight),
      Paint()..color = _groundColor,
    );
    final random = Random(7);
    final dot = Paint()..color = const Color(0xFF22262B);
    for (var i = 0; i < 1400; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          random.nextDouble() * arenaWidth,
          random.nextDouble() * arenaHeight,
          2,
          2,
        ),
        dot,
      );
    }
    final grid = Paint()
      ..color = const Color(0xFF1B1E22)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= arenaWidth; x += 100) {
      canvas.drawLine(Offset(x, 0), Offset(x, arenaHeight), grid);
    }
    for (var y = 0.0; y <= arenaHeight; y += 100) {
      canvas.drawLine(Offset(0, y), Offset(arenaWidth, y), grid);
    }
  }

  double _lerp(double a, double b) => a + (b - a) * t;

  /// The angle between [a] and [b] the short way round.
  double _lerpAngle(double a, double b) {
    final d = ((b - a + 540) % 360) - 180;
    return a + d * t;
  }

  /// Where [b] is drawn now, eased from the turn before.
  _Pose _pose(Bot b) {
    final before = previous?.bots
        .where((o) => o.id == b.id && o.alive)
        .firstOrNull;
    if (before == null) return (x: b.x, y: b.y, heading: b.heading, gun: b.gun);
    return (
      x: _lerp(before.x, b.x),
      y: _lerp(before.y, b.y),
      heading: _lerpAngle(before.heading, b.heading),
      gun: _lerpAngle(before.gun, b.gun),
    );
  }

  /// The gun's line of sight, as Robocode drew radar beams: a cone in the
  /// robot's color, 10 degrees either side of the gun (where the world
  /// model has an enemy `enemy_in_sight`), fading with distance; brighter
  /// while the nearest enemy is in it.
  void _sight(Canvas canvas, _Pose p, int index, Map<int, _Pose> poses) {
    const half = 10.0;
    const reach = 1000.0;
    final color = index < robots.length ? robots[index].color : Colors.grey;
    _Pose? nearest;
    var best = double.infinity;
    for (final MapEntry(key: i, value: o) in poses.entries) {
      if (i == index) continue;
      final d = (Offset(o.x, o.y) - Offset(p.x, p.y)).distanceSquared;
      if (d < best) {
        best = d;
        nearest = o;
      }
    }
    var locked = false;
    if (nearest != null) {
      final bearing = atan2(nearest.x - p.x, p.y - nearest.y) * 180 / pi;
      locked = (((bearing - p.gun + 540) % 360) - 180).abs() <= half;
    }
    canvas.save();
    canvas.translate(p.x, p.y);
    canvas.rotate(p.gun * pi / 180);
    final spread = reach * tan(half * pi / 180);
    final cone = Path()
      ..moveTo(0, 0)
      ..lineTo(-spread, -reach)
      ..lineTo(spread, -reach)
      ..close();
    final alpha = locked ? 0.38 : 0.16;
    canvas.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0, -reach),
          [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.5),
            color.withValues(alpha: 0),
          ],
          [0, 0.45, 1],
        ),
    );
    canvas.restore();
  }

  void _tank(Canvas canvas, Bot b, _Pose p, int index, int tick) {
    final robot = index < robots.length ? robots[index] : null;
    final color = robot?.color ?? Colors.grey;
    final (:x, :y, :heading, :gun) = p;
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    final light = Color.lerp(color, Colors.white, 0.25)!;

    if (selected == index) {
      canvas.drawCircle(
        Offset(x, y),
        28,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Body and treads, turned to the heading.
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(heading * pi / 180);
    final tread = Paint()..color = const Color(0xFF3A3D40);
    final treadLine = Paint()
      ..color = const Color(0xFF55595D)
      ..strokeWidth = 1;
    for (final side in [-1, 1]) {
      final r = Rect.fromLTWH(side < 0 ? -17 : 11, -18, 6, 36);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        tread,
      );
      for (var k = -16.0; k < 18; k += 4) {
        final shift = (tick * (b.v.sign)) % 4;
        canvas.drawLine(
          Offset(r.left, k + shift),
          Offset(r.right, k + shift),
          treadLine,
        );
      }
    }
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-11, -15, 22, 30),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(-11, -15),
          const Offset(11, 15),
          [light, dark],
        ),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();

    // Turret and gun, turned to the gun's heading; the radar spins.
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(gun * pi / 180);
    canvas.drawRect(
      const Rect.fromLTWH(-2, -24, 4, 18),
      Paint()..color = Color.lerp(color, Colors.white, 0.1)!,
    );
    canvas.drawCircle(Offset.zero, 8, Paint()..color = color);
    canvas.drawCircle(
      Offset.zero,
      8,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate((tick * 45 % 360) * pi / 180);
    canvas.drawArc(
      const Rect.fromLTWH(-6, -6, 12, 12),
      pi,
      pi,
      false,
      Paint()
        ..color = light
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();

    // Energy above, name and the rule below, as Robocode labels robots.
    _label(
      canvas,
      b.energy.toStringAsFixed(1),
      Offset(x, y - 34),
      10,
      Colors.white70,
    );
    _label(
      canvas,
      '${robot?.name ?? b.id}${b.rule > 0 ? '  · rule ${b.rule}' : ''}',
      Offset(x, y + 26),
      10,
      Colors.white,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          shadows: const [Shadow(blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, 0));
  }

  void _bullet(Canvas canvas, Bullet b) {
    final r = 1.5 + b.power;
    canvas.drawCircle(
      Offset(b.x, b.y),
      r + 2,
      Paint()..color = const Color(0x55FFD27A),
    );
    canvas.drawCircle(
      Offset(b.x, b.y),
      r,
      Paint()..color = const Color(0xFFFFF1C2),
    );
  }

  /// A burst in the style of an old arcade sprite: it steps through a few
  /// frames instead of easing, a white flash, a ragged fireball cooling
  /// from yellow to red, square sparks flying out and, for a robot lost,
  /// a shock ring and rising smoke.
  void _explosion(Canvas canvas, Explosion e) {
    final frames = e.big ? 20 : 8;
    final age = now.difference(e.at).inMilliseconds / e.millis;
    if (age >= 1 || age < 0) return;
    final q = (age * frames).floor() / frames;
    final at = Offset(e.x, e.y);
    final random = Random((e.x * 7919 + e.y * 104729).round());
    final size = e.big ? 44.0 : 12.0;

    if (q < 0.12) {
      canvas.drawCircle(
        at,
        size * 0.9,
        Paint()..color = const Color(0xFFFFFDE8),
      );
    }

    if (e.big) {
      // The shock ring, then the smoke.
      if (q < 0.5) {
        canvas.drawCircle(
          at,
          size * (0.6 + q * 3.2),
          Paint()
            ..color = Color.fromRGBO(255, 220, 160, 0.6 * (1 - q * 2))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      for (var k = 0; k < 7; k++) {
        final a = random.nextDouble() * 2 * pi;
        final r = size * (0.2 + random.nextDouble() * 0.5);
        final start = 0.25 + random.nextDouble() * 0.15;
        if (q < start) continue;
        final s = (q - start) / (1 - start);
        canvas.drawCircle(
          at + Offset(cos(a) * r, sin(a) * r - s * 30),
          size * (0.3 + s * 0.45),
          Paint()..color = Color.fromRGBO(70, 66, 62, 0.55 * (1 - s)),
        );
      }
    }

    // The fireball: rings of jagged flame, each frame a new shape.
    final burn = e.big ? (q < 0.7 ? 1 - q / 0.7 : 0.0) : 1 - q;
    if (burn > 0) {
      final grow = 0.5 + (1 - burn) * 0.8;
      final flame = Random(random.nextInt(1 << 30) + (q * frames).round());
      for (final (scale, color) in [
        (1.0, const Color(0xFFB8261A)),
        (0.78, const Color(0xFFF26B1D)),
        (0.55, const Color(0xFFFFC23A)),
        (0.3, const Color(0xFFFFF4C8)),
      ]) {
        final r = size * grow * scale * (scale < 0.5 ? burn : 1);
        if (r < 1) continue;
        final points = 12;
        final path = Path();
        for (var k = 0; k < points * 2; k++) {
          final a = k * pi / points;
          final rr = r * (k.isEven ? 1.0 : 0.62 + flame.nextDouble() * 0.2);
          final pt = at + Offset(cos(a) * rr, sin(a) * rr);
          k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        path.close();
        canvas.drawPath(
          path,
          Paint()..color = color.withValues(alpha: min(1, burn * 1.6)),
        );
      }
    }

    // Square sparks, like pixels thrown out.
    final sparks = e.big ? 18 : 6;
    for (var k = 0; k < sparks; k++) {
      final a = random.nextDouble() * 2 * pi;
      final speed = size * (1 + random.nextDouble() * 1.6);
      final d = speed * q;
      final fade = 1 - q;
      final side = (e.big ? 4.0 : 2.0) * fade + 1;
      canvas.drawRect(
        Rect.fromCenter(
          center: at + Offset(cos(a) * d, sin(a) * d + q * q * 18),
          width: side,
          height: side,
        ),
        Paint()
          ..color =
              (k.isEven ? const Color(0xFFFFE08A) : const Color(0xFFFF7A2A))
                  .withValues(alpha: fade),
      );
    }
  }

  /// Where a robot was lost: a dark, ragged splat that stays the round.
  void _scorch(Canvas canvas, Bot b) {
    final random = Random(b.id.hashCode);
    final path = Path();
    const points = 14;
    for (var k = 0; k < points * 2; k++) {
      final a = k * pi / points + random.nextDouble() * 0.2;
      final r = k.isEven
          ? 26 + random.nextDouble() * 12
          : 8 + random.nextDouble() * 8;
      final pt = Offset(b.x + cos(a) * r, b.y + sin(a) * r);
      k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xCC07080A));
    canvas.drawCircle(
      Offset(b.x, b.y),
      12,
      Paint()..color = const Color(0xFF050506),
    );
  }

  @override
  bool shouldRepaint(BattlefieldPainter old) => true;
}

/// A robot as drawn: where it is and where it and its gun point.
typedef _Pose = ({double x, double y, double heading, double gun});
