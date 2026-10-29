/// The rules the Life model knows, as the app offers them: each is a
/// switch in the request's `state.rules`, and a row (or rows) of the
/// model's fate table that only fires when it's on.
class LifeRule {
  const LifeRule(this.id, this.name, this.summary, {required this.on});

  /// The key in `state.rules`, and the fate table's column.
  final String id;
  final String name;
  final String summary;

  /// Whether it's on when the app opens.
  final bool on;
}

const lifeRules = [
  LifeRule(
    'conway',
    'Conway\'s rules',
    'B3/S23: a dead cell with three live neighbours is born; a live cell '
        'with two or three lives on, and dies of loneliness or crowding '
        'otherwise.',
    on: true,
  ),
  LifeRule(
    'highlife',
    'HighLife birth',
    'B6: a dead cell with exactly six live neighbours is also born, which '
        'lets replicators grow.',
    on: false,
  ),
  LifeRule(
    'no_death',
    'Life without death',
    'A live cell never dies, whatever its neighbours: patterns only grow, '
        'into ladders and lace.',
    on: false,
  ),
];

/// The switches as the app opens: Conway's alone.
Map<String, bool> get defaultRules => {
  for (final rule in lifeRules) rule.id: rule.on,
};
