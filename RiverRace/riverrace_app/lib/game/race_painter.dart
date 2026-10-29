/// Draws the race as the Atari did: blue river, green banks, the bridges
/// and their roads, houses, and pixel sprites for the planes and what they
/// shoot. The playfield is 160 by 160 pixels, scaled to the widget.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import 'race.dart';
import 'river.dart';

abstract final class Palette {
  static const water = Color(0xFF1C3FAA);
  static const land = Color(0xFF4E8F2A);
  static const road = Color(0xFF555555);
  static const dash = Color(0xFFE0D040);
  static const deck = Color(0xFFB4823C);
  static const rail = Color(0xFF5B3A14);
  static const hull = Color(0xFF202020);
  static const cabin = Color(0xFFE8E8E8);
  static const heli = Color(0xFF60D060);
  static const rotor = Color(0xFF111111);
  static const jet = Color(0xFFDCDCDC);
  static const fuelRed = Color(0xFFD03030);
  static const fuelWhite = Color(0xFFF2F2F2);
  static const wall = Color(0xFFE8E0D0);
  static const roof = Color(0xFFB03A2E);
  static const tree = Color(0xFF2A5E16);
  static const trunk = Color(0xFF6B4423);
  static const fire1 = Color(0xFFF8A030);
  static const fire2 = Color(0xFFF8E060);
}

const _plane = [
  '...#...',
  '...#...',
  '..###..',
  '.#####.',
  '#######',
  '#.###.#',
  '...#...',
  '..###..',
  '.#####.',
];

const _heli = [
  '########',
  '....#...',
  '..#####.',
  '#######.',
  '..#####.',
  '...#..#.',
  '..######',
];

const _ship = [
  '.......##.......',
  '......####......',
  '################',
  '.##############.',
  '..############..',
];

const _jet = ['#.......', '##...#..', '########', '##...#..', '#.......'];

/// Three-by-five letters for the depot's FUEL.
const _letters = {
  'F': ['###', '#..', '##.', '#..', '#..'],
  'U': ['#.#', '#.#', '#.#', '#.#', '###'],
  'E': ['###', '#..', '##.', '#..', '###'],
  'L': ['#..', '#..', '#..', '#..', '###'],
};

class RacePainter extends CustomPainter {
  RacePainter({
    required this.race,
    required this.colors,
    required this.opacity,
    super.repaint,
  });

  final Race race;

  /// Each plane's color and opacity, by id.
  final Map<String, Color> colors;
  final Map<String, double> opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / fieldWidth, size.height / viewHeight);
    final cam = race.camera.floorToDouble();
    double row(double y) => viewHeight - (y - cam);
    final paint = Paint()..isAntiAlias = false;

    void rect(double x, double y, double w, double h, Color color) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
    }

    void sprite(
      List<String> rows,
      double cx,
      double cy,
      Color color, {
      bool flip = false,
    }) {
      final h = rows.length;
      final w = rows.first.length;
      paint.color = color;
      final left = (cx - w / 2).roundToDouble();
      final top = (cy - h / 2).roundToDouble();
      for (var j = 0; j < h; j++) {
        final line = rows[j];
        for (var i = 0; i < w; i++) {
          if (line[flip ? w - 1 - i : i] == '#') {
            canvas.drawRect(Rect.fromLTWH(left + i, top + j, 1, 1), paint);
          }
        }
      }
    }

    void explosion(double cx, double cy, int frames, double spread) {
      final rng = Random(frames * 31 + cx.round() * 7 + cy.round());
      for (var i = 0; i < 14; i++) {
        final a = rng.nextDouble() * pi * 2;
        final d = rng.nextDouble() * spread * (1 - frames / 60);
        rect(
          (cx + cos(a) * d).roundToDouble(),
          (cy + sin(a) * d * 0.7).roundToDouble(),
          2,
          2,
          i.isEven ? Palette.fire1 : Palette.fire2,
        );
      }
    }

    // Banks, then the houses on them, then the water.
    rect(0, 0, fieldWidth, viewHeight, Palette.land);
    final firstBlock = (cam / blockLength).floor() - 1;
    final lastBlock = ((cam + viewHeight) / blockLength).ceil() + 1;
    for (var k = max(0, firstBlock); k <= lastBlock; k++) {
      final b = race.river.blockAt(k);
      final r = row(k * blockLength + blockLength / 2.0);
      for (final x in [b.houseLeft, b.houseRight]) {
        if (x == null) continue;
        rect(x, r - 3, 8, 5, Palette.wall);
        rect(x - 1, r - 6, 10, 3, Palette.roof);
        rect(x + 3, r - 1, 2, 3, Palette.trunk);
        rect(x + 10, r - 7, 4, 6, Palette.tree);
        rect(x + 11, r - 1, 2, 2, Palette.trunk);
      }
    }
    for (var r = 0; r < viewHeight; r++) {
      final y = cam + viewHeight - r - 0.5;
      for (final s in race.river.spans(y)) {
        rect(s.left, r.toDouble(), s.width, 1, Palette.water);
      }
    }

    // Roads and bridges.
    final firstBridge = max(1, (cam / sectionLength).floor());
    final lastBridge = ((cam + viewHeight) / sectionLength).ceil();
    for (var n = firstBridge; n <= lastBridge; n++) {
      final top = row(n * sectionLength + bridgeTo);
      final height = bridgeTo - bridgeFrom;
      rect(0, top, fieldWidth, height, Palette.road);
      for (var x = 2.0; x < fieldWidth; x += 10) {
        rect(x, top + height / 2 - 0.5, 5, 1, Palette.dash);
      }
      if (race.broken.contains(n)) {
        rect(axis - neck, top, neck * 2, height, Palette.water);
      } else {
        rect(axis - neck, top, neck * 2, height, Palette.deck);
        rect(axis - neck, top, neck * 2, 1, Palette.rail);
        rect(axis - neck, top + height - 1, neck * 2, 1, Palette.rail);
      }
    }
    for (final b in race.blasts) {
      explosion(b.x, row(b.y), b.frames, 24);
    }

    // Enemies and depots.
    for (final t in race.things) {
      final r = row(t.y);
      if (r < -16 || r > viewHeight + 16) continue;
      if (t.exploding > 0) {
        explosion(t.x, r, t.exploding, 10);
        continue;
      }
      switch (t.kind) {
        case ThingKind.ship:
          sprite(_ship, t.x, r, Palette.hull, flip: t.vx < 0);
          rect(t.x + (t.vx < 0 ? 0 : -2), r - 2, 3, 1, Palette.cabin);
        case ThingKind.heli:
          sprite(_heli, t.x, r, Palette.heli, flip: t.vx < 0);
          // The rotor turns.
          if (race.frame ~/ 4 % 2 == 0) {
            rect(t.x - 4, r - 3.5, 8, 1, Palette.rotor);
          }
        case ThingKind.jet:
          sprite(_jet, t.x, r, Palette.jet, flip: t.vx < 0);
        case ThingKind.fuel:
          final left = (t.x - 3.5).roundToDouble();
          final top = (r - 11).roundToDouble();
          rect(left, top, 7, 22, Palette.fuelRed);
          rect(left + 1, top + 1, 5, 20, Palette.fuelWhite);
          for (final (i, ch) in 'FUEL'.split('').indexed) {
            final glyph = _letters[ch]!;
            for (var j = 0; j < 5; j++) {
              for (var c = 0; c < 3; c++) {
                if (glyph[j][c] == '#') {
                  rect(
                    left + 2 + c,
                    top + 1 + i * 5 + j,
                    1,
                    1,
                    Palette.fuelRed,
                  );
                }
              }
            }
          }
      }
    }

    // Planes and missiles: the player's on top.
    final order = [...race.planes]
      ..sort((a, b) => a.human ? 1 : (b.human ? -1 : 0));
    for (final p in order) {
      final color = (colors[p.id] ?? Colors.yellow).withValues(
        alpha: opacity[p.id] ?? 1,
      );
      if (p.missile case final m?) {
        rect(m.x - 0.5, row(m.y) - 3, 1, 6, color);
      }
      switch (p.state) {
        case PlaneState.out:
          break;
        case PlaneState.exploding:
          explosion(p.x, row(p.y), p.timer, 12);
        case PlaneState.flying:
          // Blinks while shielded after a respawn.
          if (p.shield > 0 && p.shield ~/ 6 % 2 == 0) break;
          sprite(_plane, p.x, row(p.y), color);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RacePainter old) =>
      old.race != race || old.colors != colors || old.opacity != opacity;
}
