/// The river, as in the 1982 original: 160 pixels across, mirror-symmetric
/// about its middle, with banks that widen and narrow, islands in the
/// middle, and a bridge with its road at the end of every section. It is
/// made section by section from a seed, so the same seed is the same river.
library;

import 'dart:math';

/// The playfield's width, and its middle, the river's axis.
const fieldWidth = 160.0;
const axis = fieldWidth / 2;

/// The river is made of blocks 16 pixels long, 40 to a section; a section
/// ends at a bridge.
const blockLength = 16;
const sectionBlocks = 40;
const sectionLength = blockLength * sectionBlocks;

/// The narrow neck at each bridge: half the river's width there.
const neck = 16.0;

/// A bridge's rows, from the start of its block.
const bridgeFrom = 4.0;
const bridgeTo = 12.0;

/// One block: the river's half width, the island's (0 for none), and the
/// houses on its banks.
class Block {
  const Block(this.half, this.island, {this.houseLeft, this.houseRight});

  final double half;
  final double island;

  /// Where a house stands on the left or right bank, if one does.
  final double? houseLeft;
  final double? houseRight;
}

enum ThingKind { ship, heli, fuel, jet }

/// A thing placed on the river when its section is made.
class Placement {
  const Placement(this.kind, this.x, this.y, {this.moves = false, this.vx = 0});

  final ThingKind kind;
  final double x;
  final double y;

  /// Whether it starts to move once it is on screen, and how fast.
  final bool moves;
  final double vx;
}

/// A stretch of open water at a row: from [left] to [right].
class Span {
  const Span(this.left, this.right);

  final double left;
  final double right;

  double get center => (left + right) / 2;
  double get width => right - left;
  bool contains(double x) => x >= left && x <= right;
}

/// The size of each thing, half width and half height, and its points.
const thingSizes = <ThingKind, (double, double)>{
  ThingKind.ship: (8, 3),
  ThingKind.heli: (4, 3.5),
  ThingKind.fuel: (3.5, 11),
  ThingKind.jet: (4, 2.5),
};

const thingPoints = <ThingKind, int>{
  ThingKind.ship: 30,
  ThingKind.heli: 60,
  ThingKind.fuel: 80,
  ThingKind.jet: 100,
};

/// The points for shooting down a bridge.
const bridgePoints = 500;

class River {
  River(this.seed);

  final int seed;
  final _blocks = <int, List<Block>>{};
  final _things = <int, List<Placement>>{};

  List<Block> _section(int s) => _blocks.putIfAbsent(s, () => _make(s));

  Block blockAt(int k) {
    if (k < 0) return _section(0).first;
    return _section(k ~/ sectionBlocks)[k % sectionBlocks];
  }

  /// The things of section [s], placed when it was made.
  List<Placement> thingsOf(int s) {
    _section(s);
    return _things[s]!;
  }

  /// The river's and the island's half widths at [y]: a block's own for
  /// its first half, then a slant to the next block's, as the banks step
  /// in the original.
  (double half, double island) shape(double y) {
    final k = (y / blockLength).floor();
    final f = y - k * blockLength;
    final a = blockAt(k);
    if (f < blockLength / 2) return (a.half, a.island);
    final b = blockAt(k + 1);
    final t = (f - blockLength / 2) / (blockLength / 2);
    return (
      a.half + (b.half - a.half) * t,
      a.island + (b.island - a.island) * t,
    );
  }

  /// The open water at [y], left to right.
  List<Span> spans(double y) {
    final (half, island) = shape(y);
    if (island <= 0.5) return [Span(axis - half, axis + half)];
    return [Span(axis - half, axis - island), Span(axis + island, axis + half)];
  }

  bool isWater(double x, double y) {
    final (half, island) = shape(y);
    final d = (x - axis).abs();
    return d < half && d >= island;
  }

  bool isLand(double x, double y) => x < 0 || x > fieldWidth || !isWater(x, y);

  /// The bridge whose rows include [y], if any: its number, 1 for the
  /// first, at the end of section 0.
  int? bridgeAt(double y) {
    final k = (y / blockLength).floor();
    if (k <= 0 || k % sectionBlocks != 0) return null;
    final f = y - k * blockLength;
    return f >= bridgeFrom && f < bridgeTo ? k ~/ sectionBlocks : null;
  }

  /// Where bridge [n] is: the middle of its rows.
  static double bridgeY(int n) =>
      n * sectionLength + (bridgeFrom + bridgeTo) / 2;

  /// Whether every channel of a stretch shaped [from] (half width,
  /// island) goes on into one of a stretch shaped [to], with room for a
  /// plane: 16 pixels in common.
  static bool flowsInto((double, double) from, (double, double) to) {
    List<Span> spans((double, double) shape) => shape.$2 <= 0.5
        ? [Span(axis - shape.$1, axis + shape.$1)]
        : [
            Span(axis - shape.$1, axis - shape.$2),
            Span(axis + shape.$2, axis + shape.$1),
          ];
    final next = spans(to);
    return spans(from).every(
      (a) => next.any((b) => min(a.right, b.right) - max(a.left, b.left) >= 16),
    );
  }

  List<Block> _make(int s) {
    final rng = Random(seed * 7919 + s * 104729 + 17);
    final blocks = <Block>[];
    var half = 40.0;
    var island = 0.0;
    var run = 0;
    for (var i = 0; i < sectionBlocks; i++) {
      double h, isl;
      if (s == 0 && i < 6) {
        (h, isl) = (40, 0);
      } else if ((s > 0 && i < 2) || i >= sectionBlocks - 2) {
        // The neck on either side of a bridge.
        (h, isl) = (neck, 0);
      } else {
        if (run <= 0) {
          run = 2 + rng.nextInt(4);
          // Later sections are narrower, and have more islands; none
          // near a bridge, whose neck must follow on from the water
          // before it. Every channel goes on into the next stretch.
          final prev = (half, island);
          final narrow = min(s, 8) * 2.0;
          final islands = i >= 6 && i < sectionBlocks - 7;
          for (var tries = 0; ; tries++) {
            half = (24 + (rng.nextInt(13) * 4).toDouble() - narrow).clamp(
              24,
              72,
            );
            island =
                islands &&
                    half >= 48 &&
                    rng.nextDouble() < 0.25 + min(s, 6) * 0.04
                ? 8 + (rng.nextInt(((half - 32) / 4).floor() + 1) * 4)
                : 0;
            if (flowsInto(prev, (half, island))) break;
            if (tries == 20) {
              (half, island) = (max(prev.$2 + 24, 32), 0);
              break;
            }
          }
        }
        run--;
        (h, isl) = (half, island);
      }
      double? house(double landWidth) =>
          landWidth >= 22 && rng.nextDouble() < 0.3
          ? 4 + rng.nextDouble() * (landWidth - 20)
          : null;
      final land = axis - h;
      final left = house(land);
      final right = house(land);
      blocks.add(
        Block(
          h,
          isl,
          houseLeft: left,
          houseRight: right == null ? null : fieldWidth - right - 12,
        ),
      );
    }
    _blocks[s] = blocks;
    _things[s] = _place(s, blocks, rng);
    return blocks;
  }

  List<Placement> _place(int s, List<Block> blocks, Random rng) {
    final placed = <Placement>[];
    final busy = 0.45 + min(s, 10) * 0.025;
    for (var i = s == 0 ? 10 : 3; i < sectionBlocks - 3; i++) {
      if (rng.nextDouble() > busy) continue;
      final roll = rng.nextDouble();
      final kind = roll < 0.36
          ? ThingKind.ship
          : roll < 0.7
          ? ThingKind.heli
          : ThingKind.fuel;
      final (hw, _) = thingSizes[kind]!;
      final b = blocks[i];
      final spans = b.island > 0
          ? [
              Span(axis - b.half, axis - b.island),
              Span(axis + b.island, axis + b.half),
            ]
          : [Span(axis - b.half, axis + b.half)];
      final span = spans[rng.nextInt(spans.length)];
      final from = span.left + hw + 3;
      final to = span.right - hw - 3;
      if (to <= from) continue;
      final moves =
          kind != ThingKind.fuel && rng.nextDouble() < 0.5 + min(s, 5) * 0.06;
      final speed = kind == ThingKind.ship ? 0.5 : 0.8;
      placed.add(
        Placement(
          kind,
          from + rng.nextDouble() * (to - from),
          (s * sectionBlocks + i) * blockLength + blockLength / 2,
          moves: moves,
          vx: rng.nextBool() ? speed : -speed,
        ),
      );
    }
    return placed;
  }
}
