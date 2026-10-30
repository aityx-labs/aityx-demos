/// A pilot's strategy: rules, the first that matches deciding what the
/// plane does. The app turns it into an aityx FIRST decision table (see
/// lib/aityx/decision_request.dart, which checks the same sensors and
/// commands).
library;

/// How a sensor's cells are written: a number test (`< 40`, `[10..50]`),
/// true or false, or one or more of a few words (`left, right`).
enum SensorKind { number, boolean, words }

class Sensor {
  const Sensor(this.id, this.kind, this.description, [this.words = const []]);

  final String id;
  final SensorKind kind;
  final String description;

  /// The words of a [SensorKind.words] sensor.
  final List<String> words;
}

/// What a plane senses, in the table's column order.
const sensors = [
  Sensor('fuel', SensorKind.number, 'Fuel left, 0 (empty) to 100 (full)'),
  Sensor('speed', SensorKind.words, 'How fast the plane flies up the river', [
    'slow',
    'normal',
    'fast',
  ]),
  Sensor(
    'land_ahead',
    SensorKind.boolean,
    'Is there land (a bank or an island) straight ahead, within 48 pixels?',
  ),
  Sensor(
    'land_distance',
    SensorKind.number,
    'Pixels to the nearest land straight ahead (999 when none in sight)',
  ),
  Sensor(
    'channel',
    SensorKind.words,
    'Where the open water is, 48 pixels ahead',
    ['left', 'right', 'ahead'],
  ),
  Sensor('room_left', SensorKind.number, 'Pixels of water to the left'),
  Sensor('room_right', SensorKind.number, 'Pixels of water to the right'),
  Sensor(
    'enemy_ahead',
    SensorKind.boolean,
    'Is a ship, helicopter or jet in the line of fire, within 120 pixels?',
  ),
  Sensor(
    'enemy_distance',
    SensorKind.number,
    'Pixels to the nearest enemy in the line of fire (999 when none)',
  ),
  Sensor(
    'threat',
    SensorKind.words,
    'An enemy about to collide with the plane, within 40 pixels',
    ['none', 'left', 'right', 'ahead'],
  ),
  Sensor(
    'fuel_ahead',
    SensorKind.boolean,
    'Is a fuel depot in the line of fire, within 120 pixels?',
  ),
  Sensor(
    'fuel_side',
    SensorKind.words,
    'Where the nearest fuel depot ahead is, within 120 pixels',
    ['none', 'left', 'right', 'ahead'],
  ),
  Sensor(
    'bridge_ahead',
    SensorKind.boolean,
    'Is a bridge still standing within 120 pixels ahead?',
  ),
  Sensor('leading', SensorKind.boolean, 'Is this plane the furthest up?'),
  Sensor(
    'missile_ready',
    SensorKind.boolean,
    'Can the plane fire? (one missile in the air at a time)',
  ),
];

Sensor sensorById(String id) => sensors.firstWhere((s) => s.id == id);

/// The steer commands, with what each does.
const steers = {
  'to_channel': 'Toward the open water ahead',
  'to_fuel': 'Toward the nearest fuel depot ahead (else the open water)',
  'dodge': 'Away from the threat (else toward the open water)',
  'left': 'Left',
  'right': 'Right',
  'straight': 'Straight on',
};

const throttles = {'slow': 'Slow', 'normal': 'Normal', 'fast': 'Fast'};

/// A rule: the cells it tests, by sensor (only those that aren't `-`),
/// what the plane then does, and why.
class Rule {
  Rule({
    Map<String, String>? when,
    this.steer = 'to_channel',
    this.throttle = 'normal',
    this.fire = false,
    this.why = '',
  }) : when = when ?? {};

  Map<String, String> when;
  String steer;
  String throttle;
  bool fire;
  String why;

  Rule copy() => Rule(
    when: {...when},
    steer: steer,
    throttle: throttle,
    fire: fire,
    why: why,
  );

  Map<String, Object?> toJson() => {
    'when': when,
    'then': {'steer': steer, 'throttle': throttle, 'fire': fire},
    'why': why,
  };

  /// "fuel < 45 · fuel_side is left, right", or "always".
  String get whenText => when.isEmpty
      ? 'always'
      : [
          for (final s in sensors)
            if (when[s.id] case final cell?)
              switch (s.kind) {
                SensorKind.number => '${s.id} $cell',
                SensorKind.boolean => cell == 'true' ? s.id : 'not ${s.id}',
                SensorKind.words => '${s.id} is $cell',
              },
        ].join(' · ');

  /// "to_fuel · slow · fire".
  String get thenText => '$steer · $throttle · ${fire ? 'fire' : 'hold fire'}';
}

/// A named list of rules.
class Strategy {
  Strategy(this.name, this.rules, {this.about = ''});

  String name;
  List<Rule> rules;

  /// What it does, in a sentence.
  final String about;

  Strategy copy() =>
      Strategy(name, [for (final r in rules) r.copy()], about: about);
}

/// The strategies to pick from, made fresh each time.
final List<Strategy Function()> presets = [
  careful,
  daredevil,
  sharpshooter,
  rookie,
];

Strategy careful() => Strategy('Careful', [
  Rule(
    when: {'land_distance': '< 36'},
    steer: 'to_channel',
    throttle: 'slow',
    why: 'Land straight ahead: slow down and turn for the open water.',
  ),
  Rule(
    when: {'threat': 'left, right, ahead'},
    steer: 'dodge',
    throttle: 'slow',
    fire: true,
    why: 'Something is about to hit: get out of its way, and shoot.',
  ),
  Rule(
    when: {'fuel': '< 45', 'fuel_side': 'left, right, ahead'},
    steer: 'to_fuel',
    throttle: 'slow',
    why: 'Low on fuel: fly slowly over the depot to fill up.',
  ),
  Rule(
    when: {'bridge_ahead': 'true'},
    fire: true,
    why: 'A bridge ahead: shoot it down to pass.',
  ),
  Rule(
    when: {'enemy_ahead': 'true'},
    fire: true,
    why: 'An enemy in the line of fire: shoot it.',
  ),
  Rule(why: 'Nothing in the way: fly up the middle of the channel.'),
], about: 'Slow and steady: dodges, refuels early, shoots what is ahead.');

Strategy daredevil() => Strategy('Daredevil', [
  Rule(
    when: {'land_distance': '< 50'},
    steer: 'to_channel',
    why: 'Land ahead, and coming fast: ease off and turn for the water.',
  ),
  Rule(
    when: {'threat': 'left, right, ahead'},
    steer: 'dodge',
    throttle: 'fast',
    fire: true,
    why: 'Something in the way: swerve and shoot.',
  ),
  Rule(
    when: {'fuel': '< 25', 'fuel_side': 'left, right, ahead'},
    steer: 'to_fuel',
    why: 'Running on fumes: grab the fuel.',
  ),
  Rule(
    when: {'fuel_ahead': 'true'},
    throttle: 'fast',
    fire: true,
    why: 'A fuel depot is worth 80 points: shoot it.',
  ),
  Rule(
    when: {'enemy_ahead': 'true'},
    throttle: 'fast',
    fire: true,
    why: 'Shoot everything in the line of fire.',
  ),
  Rule(
    when: {'bridge_ahead': 'true'},
    throttle: 'fast',
    fire: true,
    why: '500 points: shoot the bridge.',
  ),
  Rule(throttle: 'fast', why: 'Full throttle up the river.'),
], about: 'Full throttle: shoots everything, fuel too, refuels late.');

Strategy sharpshooter() => Strategy('Sharpshooter', [
  Rule(
    when: {'land_distance': '< 30'},
    steer: 'to_channel',
    throttle: 'slow',
    why: 'Land ahead: slow down and turn.',
  ),
  Rule(
    when: {'threat': 'left, right, ahead'},
    steer: 'dodge',
    fire: true,
    why: 'Something is close: dodge and shoot.',
  ),
  Rule(
    when: {'fuel': '< 35', 'fuel_side': 'left, right, ahead'},
    steer: 'to_fuel',
    throttle: 'slow',
    why: 'Low on fuel: fill up.',
  ),
  Rule(
    when: {'missile_ready': 'true', 'fuel_ahead': 'false'},
    fire: true,
    why: 'Fire whenever the missile is ready, but spare the fuel.',
  ),
  Rule(why: 'Fly up the channel.'),
], about: 'Fires whenever it can, spares the fuel depots.');

Strategy rookie() => Strategy('Rookie', [
  Rule(steer: 'straight', fire: true, why: 'Fly straight and keep firing.'),
], about: 'One rule: straight ahead, firing. Add rules to teach it.');
