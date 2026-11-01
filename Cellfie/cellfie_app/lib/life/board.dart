/// The board: a sparse set of live cells on an infinite grid, and what the
/// app counts on it for aityx: every distinct situation (alive or not, how
/// many live neighbours), and every cluster of live cells with its shape.
/// Pure Dart, so it's tested without Flutter and shared with the catalogue
/// tool (tool/catalogue.dart).
library;

import 'dart:math';

import 'seeds.dart';

/// A cell's coordinates; y grows downwards.
typedef Cell = ({int x, int y});

/// A situation a cell can be in: alive or not, with 0 to 8 live neighbours.
typedef SituationKey = ({bool alive, int neighbours});

/// A distinct situation on the board, and how many cells are in it.
class Situation {
  const Situation(this.alive, this.neighbours, this.cells);

  final bool alive;
  final int neighbours;

  /// How many cells are in this situation.
  final int cells;

  SituationKey get key => (alive: alive, neighbours: neighbours);

  Map<String, Object?> toJson() => {
    'alive': alive,
    'neighbours': neighbours,
    'cells': cells,
  };
}

/// A group of live cells that are close together (within two cells of
/// each other), or form a penta-decathlon phase, with its bounding box
/// and its canonical shape.
class Cluster {
  Cluster(this.cells)
    : minX = cells.map((c) => c.x).reduce(min),
      minY = cells.map((c) => c.y).reduce(min),
      maxX = cells.map((c) => c.x).reduce(max),
      maxY = cells.map((c) => c.y).reduce(max);

  final Set<Cell> cells;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;

  /// The shape, the same whichever way the cluster is turned or flipped
  /// (see [canonicalShape]).
  late final String shape = canonicalShape(cells);

  /// The shape's own width and height: those of the bounding box, or
  /// swapped, when the canonical form is the cluster turned on its side.
  int get shapeWidth => shape.split('/').first.length;
  int get shapeHeight => '/'.allMatches(shape).length + 1;

  /// What's sent to aityx: the count and the canonical shape with its own
  /// width and height, so the catalogue matches a blinker standing or lying.
  Map<String, Object?> toJson() => {
    'cells': cells.length,
    'width': shapeWidth,
    'height': shapeHeight,
    'shape': shape,
  };
}

/// The 8 neighbours' offsets.
const _around = <(int, int)>[
  (-1, -1),
  (0, -1),
  (1, -1),
  (-1, 0),
  (1, 0),
  (-1, 1),
  (0, 1),
  (1, 1),
];

/// How many live neighbours every cell that has any has: the live cells'
/// neighbours, counted cell by cell. A cell missing here has none.
Map<Cell, int> neighbourCounts(Set<Cell> alive) {
  final counts = <Cell, int>{};
  for (final cell in alive) {
    for (final (dx, dy) in _around) {
      final neighbour = (x: cell.x + dx, y: cell.y + dy);
      counts[neighbour] = (counts[neighbour] ?? 0) + 1;
    }
  }
  return counts;
}

/// Every distinct situation on the board, with the cells in each: live
/// cells, and dead cells with at least one live neighbour. Dead cells with
/// none, the rest of the infinite board, stay dead whatever the rules say,
/// so they're left out. Live cells first, then by neighbours.
Map<SituationKey, List<Cell>> situationsOf(Set<Cell> alive) {
  final counts = neighbourCounts(alive);
  final groups = <SituationKey, List<Cell>>{};
  for (final cell in alive) {
    final key = (alive: true, neighbours: counts[cell] ?? 0);
    (groups[key] ??= []).add(cell);
  }
  for (final MapEntry(key: cell, value: count) in counts.entries) {
    if (alive.contains(cell)) continue;
    final key = (alive: false, neighbours: count);
    (groups[key] ??= []).add(cell);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a.alive != b.alive) return a.alive ? -1 : 1;
      return a.neighbours.compareTo(b.neighbours);
    });
  return {for (final key in keys) key: groups[key]!};
}

/// The clusters of live cells: cells within two steps of each other (so
/// one empty cell between them, as in a beacon or a pulsar, keeps them
/// together) are in the same cluster. Disconnected pieces of a supported
/// penta-decathlon phase are joined so the catalogue can recognize it.
/// Top to bottom, left to right.
List<Cluster> clustersOf(Set<Cell> alive) {
  final seen = <Cell>{};
  final clusters = <Cluster>[];
  for (final start in alive) {
    if (!seen.add(start)) continue;
    final cells = <Cell>{start};
    final queue = [start];
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          if (dx == 0 && dy == 0) continue;
          final other = (x: cell.x + dx, y: cell.y + dy);
          if (alive.contains(other) && seen.add(other)) {
            cells.add(other);
            queue.add(other);
          }
        }
      }
    }
    clusters.add(Cluster(cells));
  }
  final phases = _patternPhases['pentadecathlon']!;
  final maxCells = _pentadecathlonCellCounts.reduce(max);
  bool mergePhase() {
    for (var i = 0; i < clusters.length; i++) {
      final chosen = [i];
      final cells = {...clusters[i].cells};
      bool findMatch(int start) {
        if (chosen.length > 1 && phases.contains(canonicalShape(cells))) {
          clusters[i] = Cluster({...cells});
          for (final index in chosen.skip(1).toList().reversed) {
            clusters.removeAt(index);
          }
          return true;
        }
        for (var j = start; j < clusters.length; j++) {
          final candidate = clusters[j];
          if (cells.length + candidate.cells.length > maxCells) continue;
          final minX = min(
            clusters[i].minX,
            min(candidate.minX, cells.map((c) => c.x).reduce(min)),
          );
          final maxX = max(
            clusters[i].maxX,
            max(candidate.maxX, cells.map((c) => c.x).reduce(max)),
          );
          final minY = min(
            clusters[i].minY,
            min(candidate.minY, cells.map((c) => c.y).reduce(min)),
          );
          final maxY = max(
            clusters[i].maxY,
            max(candidate.maxY, cells.map((c) => c.y).reduce(max)),
          );
          if (maxX - minX + 1 > 16 || maxY - minY + 1 > 14) continue;
          chosen.add(j);
          cells.addAll(candidate.cells);
          if (findMatch(j + 1)) return true;
          cells.removeAll(candidate.cells);
          chosen.removeLast();
        }
        return false;
      }

      if (findMatch(i + 1)) return true;
    }
    return false;
  }

  while (mergePhase()) {}
  clusters.sort((a, b) {
    if (a.minY != b.minY) return a.minY.compareTo(b.minY);
    return a.minX.compareTo(b.minX);
  });
  return clusters;
}

/// [cells] as rows of `o` (alive) and `.` (dead) joined by `/`, from the
/// top left of their bounding box, in the one of their 8 turned and
/// flipped forms that sorts first: a glider reads the same whichever way
/// it flies, so the catalogue needs one row per phase, not per direction.
String canonicalShape(Set<Cell> cells) {
  String? best;
  for (var transform = 0; transform < 8; transform++) {
    final text = _shape([for (final c in cells) transformCell(c, transform)]);
    if (best == null || text.compareTo(best) < 0) best = text;
  }
  return best!;
}

/// [c] under one of the 8 symmetries of the square: 0 as it is, 1 to 3
/// turned, 4 to 7 flipped and turned.
Cell transformCell(Cell c, int transform) => switch (transform) {
  0 => (x: c.x, y: c.y),
  1 => (x: -c.y, y: c.x),
  2 => (x: -c.x, y: -c.y),
  3 => (x: c.y, y: -c.x),
  4 => (x: -c.x, y: c.y),
  5 => (x: c.y, y: c.x),
  6 => (x: c.x, y: -c.y),
  _ => (x: -c.y, y: -c.x),
};

String _shape(List<Cell> cells) {
  final minX = cells.map((c) => c.x).reduce(min);
  final minY = cells.map((c) => c.y).reduce(min);
  final width = cells.map((c) => c.x).reduce(max) - minX + 1;
  final height = cells.map((c) => c.y).reduce(max) - minY + 1;
  final rows = List.generate(height, (_) => List.filled(width, '.'));
  for (final c in cells) {
    rows[c.y - minY][c.x - minX] = 'o';
  }
  return rows.map((row) => row.join()).join('/');
}

/// The cells of a shape written as [canonicalShape] writes one, from
/// ([x], [y]) at its top left.
Set<Cell> cellsOf(String shape, {int x = 0, int y = 0}) {
  final cells = <Cell>{};
  final rows = shape.split('/');
  for (var row = 0; row < rows.length; row++) {
    for (var column = 0; column < rows[row].length; column++) {
      if (rows[row][column] == 'o') cells.add((x: x + column, y: y + row));
    }
  }
  return cells;
}

/// Conway's rules, run here: what aityx answers for a situation. The
/// catalogue tool simulates each pattern's phases with it, and the tests
/// check the model against it; the app never uses it for the board.
bool conway({required bool alive, required int neighbours}) =>
    alive ? neighbours == 2 || neighbours == 3 : neighbours == 3;

/// The next generation by [conway], for the tool and the tests.
Set<Cell> nextByConway(Set<Cell> alive) => {
  for (final MapEntry(key: situation, value: cells) in situationsOf(
    alive,
  ).entries)
    if (conway(alive: situation.alive, neighbours: situation.neighbours))
      ...cells,
};

final _patternPhases = {
  for (final seed in seeds)
    seed.id: () {
      var cells = cellsOf(seed.shape);
      final phases = <String>{};
      for (var phase = 0; phase < seed.period; phase++) {
        phases.add(canonicalShape(cells));
        cells = nextByConway(cells);
      }
      return phases;
    }(),
};

final _pentadecathlonCellCounts = {
  for (final shape in _patternPhases['pentadecathlon']!)
    shape.replaceAll(RegExp(r'[^o]'), '').length,
};

/// Whether [shape] is a supported phase of the named pattern.
bool isPatternPhase(String id, String shape) =>
    _patternPhases[id]?.contains(shape) ?? false;

/// The board: the live cells, the generation, and which cells were born
/// and which died in it (for the colors).
class Board {
  const Board({
    this.alive = const {},
    this.generation = 0,
    this.born = const {},
    this.died = const {},
  });

  final Set<Cell> alive;
  final int generation;

  /// The cells of [alive] born in this generation.
  final Set<Cell> born;

  /// The cells alive in the generation before this one and dead in it.
  final Set<Cell> died;

  int get population => alive.length;

  /// A random soup over the [width] × [height] cells from ([x], [y]), each
  /// alive with probability [density]; generation 0.
  factory Board.random({
    required int x,
    required int y,
    required int width,
    required int height,
    double density = 0.35,
    Random? random,
  }) {
    final rng = random ?? Random();
    return Board(
      alive: {
        for (var j = 0; j < height; j++)
          for (var i = 0; i < width; i++)
            if (rng.nextDouble() < density) (x: x + i, y: y + j),
      },
    );
  }

  /// The board with [cell] flipped: alive if it was dead, dead if alive.
  Board toggled(Cell cell) {
    final next = {...alive};
    if (!next.remove(cell)) next.add(cell);
    return Board(alive: next, generation: generation, born: born, died: died);
  }

  /// The situations on the board, each with its cells (see
  /// [situationsOf]).
  Map<SituationKey, List<Cell>> get situations => situationsOf(alive);

  /// The clusters of live cells (see [clustersOf]).
  List<Cluster> get clusters => clustersOf(alive);

  /// The next generation, given whether the cells of each situation, in
  /// the order of [situations], are alive next. Cells born and cells that
  /// died are marked.
  Board next(Map<SituationKey, List<Cell>> groups, List<bool> aliveNext) {
    final next = <Cell>{};
    final born = <Cell>{};
    var i = 0;
    for (final MapEntry(key: situation, value: cells) in groups.entries) {
      if (aliveNext[i++]) {
        next.addAll(cells);
        if (!situation.alive) born.addAll(cells);
      }
    }
    return Board(
      alive: next,
      generation: generation + 1,
      born: born,
      died: alive.difference(next),
    );
  }
}

/// What **Random start** can fill the view with.
enum StartKind {
  sparse('Sparse soup', 'A few cells here and there: most die out, some settle.'),
  soup('Soup', 'A third of the cells alive: the classic random start.'),
  dense('Dense soup', 'Most cells alive: the first generation is a massacre.'),
  islands('Islands', 'A dozen small dense blobs, each on its own.'),
  gliders('Glider fleet', 'Gliders flying in every direction.'),
  zoo('Zoo', 'One of each pattern in the catalogue, scattered and turned at random.'),
  rPentomino('R-pentomino', 'Five cells that take 1,103 generations to settle.'),
  acorn('Acorn', 'Seven cells that grow for 5,206 generations.');

  const StartKind(this.label, this.summary);

  final String label;
  final String summary;
}

/// A board of [kind] over the [width] × [height] cells from ([x], [y]),
/// the cells in view, at generation 0.
Board startBoard(
  StartKind kind, {
  required int x,
  required int y,
  required int width,
  required int height,
  Random? random,
}) {
  final rng = random ?? Random();
  Board soup(double density) => Board.random(
    x: x,
    y: y,
    width: width,
    height: height,
    density: density,
    random: rng,
  );
  Board centered(String shape) {
    final cells = cellsOf(shape);
    final w = cells.map((c) => c.x).reduce(max) + 1;
    final h = cells.map((c) => c.y).reduce(max) + 1;
    return Board(
      alive: cellsOf(shape, x: x + (width - w) ~/ 2, y: y + (height - h) ~/ 2),
    );
  }

  switch (kind) {
    case StartKind.sparse:
      return soup(0.06);
    case StartKind.soup:
      return soup(0.35);
    case StartKind.dense:
      return soup(0.6);
    case StartKind.islands:
      final cells = <Cell>{};
      final n = (width * height / 600).round().clamp(4, 16);
      for (var i = 0; i < n; i++) {
        final cx = x + rng.nextInt(width);
        final cy = y + rng.nextInt(height);
        final r = 3 + rng.nextInt(4);
        for (var dy = -r; dy <= r; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            final inside = dx * dx + dy * dy <= r * r;
            final cell = (x: cx + dx, y: cy + dy);
            if (inside && _within(cell, x, y, width, height) && rng.nextDouble() < 0.55) {
              cells.add(cell);
            }
          }
        }
      }
      return Board(alive: cells);
    case StartKind.gliders:
      final cells = <Cell>{};
      final n = (width * height / 400).round().clamp(3, 20);
      final glider = cellsOf(seedById('glider').shape);
      for (var i = 0; i < n; i++) {
        _place(cells, glider, x, y, width, height, rng);
      }
      return Board(alive: cells);
    case StartKind.zoo:
      final cells = <Cell>{};
      for (final seed in seeds) {
        _place(cells, cellsOf(seed.shape), x, y, width, height, rng);
      }
      return Board(alive: cells);
    case StartKind.rPentomino:
      return centered(seedById('r_pentomino').shape);
    case StartKind.acorn:
      return centered(seedById('acorn').shape);
  }
}

bool _within(Cell c, int x, int y, int width, int height) =>
    c.x >= x && c.x < x + width && c.y >= y && c.y < y + height;

/// Adds [shape], turned or flipped at random, somewhere in the region
/// where its bounding box, with two cells around it, holds no cell yet,
/// so it stays a cluster of its own. Gives up after 40 tries.
bool _place(
  Set<Cell> cells,
  Set<Cell> shape,
  int x,
  int y,
  int width,
  int height,
  Random rng,
) {
  final transform = rng.nextInt(8);
  final turned = [for (final c in shape) transformCell(c, transform)];
  final minX = turned.map((c) => c.x).reduce(min);
  final minY = turned.map((c) => c.y).reduce(min);
  final w = turned.map((c) => c.x).reduce(max) - minX + 1;
  final h = turned.map((c) => c.y).reduce(max) - minY + 1;
  if (w > width || h > height) return false;
  for (var attempt = 0; attempt < 40; attempt++) {
    final ox = x + rng.nextInt(width - w + 1);
    final oy = y + rng.nextInt(height - h + 1);
    final free = cells.every(
      (c) => c.x < ox - 2 || c.x > ox + w + 1 || c.y < oy - 2 || c.y > oy + h + 1,
    );
    if (!free) continue;
    cells.addAll([for (final c in turned) (x: ox + c.x - minX, y: oy + c.y - minY)]);
    return true;
  }
  return false;
}
