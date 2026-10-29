import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'controller.dart';
import 'model.dart';

/// The battlefield as Robocode drew it: a dark ground, tanks with treads,
/// a turret and a radar, bullets, explosions, each robot's energy above it
/// and its name below; positions eased between turns.
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
      for (final b in world.bullets) {
        _bullet(canvas, b);
      }
      for (var i = 0; i < world.bots.length; i++) {
        final b = world.bots[i];
        if (!b.alive) continue;
        final before = previous?.bots
            .where((o) => o.id == b.id && o.alive)
            .firstOrNull;
        _tank(canvas, b, before, i, world.tick);
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

  void _tank(Canvas canvas, Bot b, Bot? before, int index, int tick) {
    final robot = index < robots.length ? robots[index] : null;
    final color = robot?.color ?? Colors.grey;
    final x = before == null ? b.x : _lerp(before.x, b.x);
    final y = before == null ? b.y : _lerp(before.y, b.y);
    final heading = before == null
        ? b.heading
        : _lerpAngle(before.heading, b.heading);
    final gun = before == null ? b.gun : _lerpAngle(before.gun, b.gun);
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

  void _explosion(Canvas canvas, Explosion e) {
    final age = now.difference(e.at).inMilliseconds / 700;
    if (age >= 1) return;
    final size = (e.big ? 46 : 14) * (0.4 + age);
    final fade = 1 - age;
    canvas.drawCircle(
      Offset(e.x, e.y),
      size,
      Paint()..color = Color.fromRGBO(255, 140, 40, 0.55 * fade),
    );
    canvas.drawCircle(
      Offset(e.x, e.y),
      size * 0.55,
      Paint()..color = Color.fromRGBO(255, 230, 120, 0.8 * fade),
    );
  }

  @override
  bool shouldRepaint(BattlefieldPainter old) => true;
}
