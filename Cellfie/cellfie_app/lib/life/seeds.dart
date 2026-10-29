/// The patterns of the catalogue, as Wikipedia's Game of Life page lists
/// them: each with its id in the model, its name, its period (1 for a
/// still life; a methuselah's seed is one phase) and one phase's layout.
/// tool/catalogue.dart turns them into the model's catalogue; the Zoo
/// start scatters them on the board.
library;

class Seed {
  const Seed(this.id, this.name, this.period, this.shape);

  final String id;
  final String name;
  final int period;

  /// Rows of `o` (alive) and `.` (dead) joined by `/`.
  final String shape;
}

const seeds = [
  // Still lifes
  Seed('block', 'Block', 1, 'oo/oo'),
  Seed('beehive', 'Beehive', 1, '.oo./o..o/.oo.'),
  Seed('loaf', 'Loaf', 1, '.oo./o..o/.o.o/..o.'),
  Seed('boat', 'Boat', 1, 'oo./o.o/.o.'),
  Seed('tub', 'Tub', 1, '.o./o.o/.o.'),
  // Oscillators
  Seed('blinker', 'Blinker', 2, 'ooo'),
  Seed('toad', 'Toad', 2, '.ooo/ooo.'),
  Seed('beacon', 'Beacon', 2, 'oo../oo../..oo/..oo'),
  Seed(
    'pulsar',
    'Pulsar',
    3,
    '..ooo...ooo../............./o....o.o....o/o....o.o....o/o....o.o....o/'
        '..ooo...ooo../............./..ooo...ooo../o....o.o....o/o....o.o....o/'
        'o....o.o....o/............./..ooo...ooo..',
  ),
  Seed('pentadecathlon', 'Penta-decathlon', 15, '..o....o../oo.oooo.oo/..o....o..'),
  // Spaceships
  Seed('glider', 'Glider', 4, '.o./..o/ooo'),
  Seed('lwss', 'Light-weight spaceship', 4, 'o..o./....o/o...o/.oooo'),
  Seed('mwss', 'Middle-weight spaceship', 4, '..o.../o...o./.....o/o....o/.ooooo'),
  Seed('hwss', 'Heavy-weight spaceship', 4, '...oo../.o....o/o....../o.....o/oooooo.'),
  // Methuselahs: recognized as seeded, before they grow
  Seed('r_pentomino', 'R-pentomino', 1, '.oo/oo./.o.'),
  Seed('diehard', 'Diehard', 1, '......o./oo....../.o...ooo'),
  Seed('acorn', 'Acorn', 1, '.o...../...o.../oo..ooo'),
];

Seed seedById(String id) => seeds.firstWhere((s) => s.id == id);
