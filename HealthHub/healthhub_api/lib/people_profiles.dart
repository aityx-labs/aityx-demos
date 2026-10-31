/// Who the simulated people are: a name typical of their city, an adult
/// age, a sex and an occupation. Pure, so it is tested with a seeded
/// Random.
library;

import 'dart:math';

import 'conditions.dart' show maxAdultAge, minAdultAge;

/// The name lists a city's people draw from.
enum NameLocale { catalan, us, brazilian }

/// The locale of [city]'s names: Catalan and Spanish for the Catalan
/// towns, Brazilian Portuguese for the Brazilian cities, American English
/// for the Florida ones and anywhere else.
NameLocale localeOf(String city) => switch (city) {
  'Cornudella de Montsant' || 'Reus' || 'Barcelona' => NameLocale.catalan,
  'Rio de Janeiro' || 'São Paulo' => NameLocale.brazilian,
  _ => NameLocale.us,
};

/// A person's details, as the complaint templates use them.
class Profile {
  const Profile({
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.sex,
    required this.occupation,
  });

  final String firstName;

  /// Every surname: two for Catalan and Spanish names, one or two for
  /// Brazilian ones.
  final String lastName;
  final int age;

  /// man or woman.
  final String sex;

  /// A noun that reads after "a": every template says "a {occupation}".
  final String occupation;

  String get name => '$firstName $lastName';
}

/// The age from which everyone is retired.
const retirementAge = 67;

/// A random adult's profile for [city].
Profile randomProfile(String city, Random random) {
  final age = randomAge(random);
  // Women outlive men: more of the oldest are women.
  final woman = random.nextDouble() < (age >= 80 ? 0.62 : 0.5);
  final names = _names[localeOf(city)]!;
  final first = _pick(woman ? names.female : names.male, random);
  final last1 = _pick(names.last, random);
  String other() {
    for (;;) {
      final last = _pick(names.last, random);
      if (last != last1) return last;
    }
  }

  final lastName = switch (localeOf(city)) {
    NameLocale.catalan => '$last1 ${other()}',
    NameLocale.brazilian => random.nextBool() ? '$last1 ${other()}' : last1,
    NameLocale.us => last1,
  };
  return Profile(
    firstName: first,
    lastName: lastName,
    age: age,
    sex: woman ? 'woman' : 'man',
    occupation: randomOccupation(age, random),
  );
}

/// The adult age bands and their share of the adult population, roughly
/// that of Spain, Brazil and the US: most adults are 30 to 64, few over 80.
const _ageBands = [(18, 29, 0.19), (30, 44, 0.26), (45, 64, 0.33), (65, 79, 0.17), (80, maxAdultAge, 0.05)];

/// A random adult age, [minAdultAge] to [maxAdultAge], by [_ageBands].
int randomAge(Random random) {
  var draw = random.nextDouble();
  for (final (from, to, share) in _ageBands) {
    draw -= share;
    if (draw < 0) return from + random.nextInt(to - from + 1);
  }
  final (from, to, _) = _ageBands.last;
  return max(minAdultAge, from + random.nextInt(to - from + 1));
}

/// An occupation for someone [age] years old: retired from
/// [retirementAge], a student at times when young, else a job.
String randomOccupation(int age, Random random) {
  if (age >= retirementAge || (age >= 63 && random.nextDouble() < 0.4)) {
    return 'retired ${_pick(occupations, random)}';
  }
  if (age <= 24 && random.nextDouble() < 0.45) return 'university student';
  return _pick(occupations, random);
}

/// Jobs, each starting with a consonant sound, as the templates say "a
/// {occupation}".
const occupations = [
  'teacher',
  'nurse',
  'bus driver',
  'cook',
  'waiter',
  'construction worker',
  'lawyer',
  'cleaner',
  'farmer',
  'mechanic',
  'police officer',
  'hairdresser',
  'pharmacist',
  'delivery driver',
  'journalist',
  'plumber',
  'receptionist',
  'sales representative',
  'warehouse worker',
  'security guard',
  'graphic designer',
  'social worker',
  'software developer',
  'bank clerk',
  'carpenter',
  'shop assistant',
  'taxi driver',
  'chef',
  'dentist',
  'physiotherapist',
  'librarian',
  'civil servant',
  'translator',
  'painter',
  'baker',
  'postal worker',
  'lab technician',
  'nursing assistant',
  'payroll administrator',
  'factory worker',
];

T _pick<T>(List<T> list, Random random) => list[random.nextInt(list.length)];

class _Names {
  const _Names({required this.male, required this.female, required this.last});

  final List<String> male;
  final List<String> female;
  final List<String> last;
}

const _names = {
  NameLocale.catalan: _Names(
    male: [
      'Jordi',
      'Josep',
      'Joan',
      'Marc',
      'Pau',
      'Oriol',
      'Albert',
      'Xavier',
      'Carles',
      'Sergi',
      'Jaume',
      'Antoni',
      'Francesc',
      'Miquel',
      'Pere',
      'Ramon',
      'Enric',
      'Manuel',
      'José',
      'Javier',
      'David',
      'Daniel',
      'Alejandro',
      'Pablo',
      'Àlex',
      'Arnau',
      'Guillem',
      'Roger',
      'Víctor',
      'Lluís',
    ],
    female: [
      'Montserrat',
      'Núria',
      'Laia',
      'Marta',
      'Anna',
      'Mercè',
      'Rosa',
      'Carme',
      'Maria',
      'Laura',
      'Cristina',
      'Elena',
      'Lucía',
      'Carmen',
      'Pilar',
      'Isabel',
      'Meritxell',
      'Neus',
      'Gemma',
      'Sílvia',
      'Judit',
      'Aina',
      'Júlia',
      'Clara',
      'Paula',
      'Teresa',
      'Dolors',
      'Roser',
      'Eulàlia',
      'Ariadna',
    ],
    last: [
      'Garcia',
      'Martínez',
      'López',
      'Puig',
      'Ferrer',
      'Vidal',
      'Soler',
      'Font',
      'Serra',
      'Roca',
      'Sala',
      'Pujol',
      'Mas',
      'Vila',
      'Bosch',
      'Costa',
      'Riera',
      'Prat',
      'Camps',
      'Batlle',
      'Casals',
      'Martí',
      'Rovira',
      'Torres',
      'Fernández',
      'Sánchez',
      'Rodríguez',
      'Pérez',
      'Gómez',
      'Ruiz',
      'Navarro',
      'Molina',
      'Romero',
      'Jiménez',
      'Moreno',
      'Domènech',
      'Coll',
      'Valls',
      'Ribas',
      'Gil',
      'Castells',
      'Sabaté',
      'Grau',
      'Esteve',
      'Pons',
      'Ventura',
    ],
  ),
  NameLocale.us: _Names(
    male: [
      'James',
      'John',
      'Robert',
      'Michael',
      'William',
      'David',
      'Richard',
      'Joseph',
      'Thomas',
      'Charles',
      'Christopher',
      'Daniel',
      'Matthew',
      'Anthony',
      'Mark',
      'Steven',
      'Andrew',
      'Joshua',
      'Kevin',
      'Brian',
      'Carlos',
      'Luis',
      'Jorge',
      'Tyrone',
      'Marcus',
      'Ethan',
      'Jacob',
      'Ryan',
      'Kenneth',
      'Gregory',
    ],
    female: [
      'Mary',
      'Patricia',
      'Jennifer',
      'Linda',
      'Elizabeth',
      'Barbara',
      'Susan',
      'Jessica',
      'Sarah',
      'Karen',
      'Nancy',
      'Lisa',
      'Ashley',
      'Emily',
      'Michelle',
      'Amanda',
      'Melissa',
      'Stephanie',
      'Rebecca',
      'Laura',
      'Maria',
      'Ana',
      'Yolanda',
      'Keisha',
      'Danielle',
      'Rachel',
      'Megan',
      'Hannah',
      'Olivia',
      'Sofia',
    ],
    last: [
      'Smith',
      'Johnson',
      'Williams',
      'Brown',
      'Jones',
      'Garcia',
      'Miller',
      'Davis',
      'Rodriguez',
      'Martinez',
      'Hernandez',
      'Lopez',
      'Gonzalez',
      'Wilson',
      'Anderson',
      'Thomas',
      'Taylor',
      'Moore',
      'Jackson',
      'Martin',
      'Lee',
      'Perez',
      'Thompson',
      'White',
      'Harris',
      'Sanchez',
      'Clark',
      'Ramirez',
      'Lewis',
      'Robinson',
      'Walker',
      'Young',
      'Allen',
      'King',
      'Wright',
      'Scott',
      'Torres',
      'Nguyen',
      'Hill',
      'Flores',
      'Green',
      'Adams',
      'Nelson',
      'Baker',
      'Rivera',
      'Campbell',
      'Mitchell',
      'Carter',
      'Cohen',
      'Murphy',
    ],
  ),
  NameLocale.brazilian: _Names(
    male: [
      'João',
      'José',
      'Antônio',
      'Francisco',
      'Carlos',
      'Paulo',
      'Pedro',
      'Lucas',
      'Luiz',
      'Marcos',
      'Gabriel',
      'Rafael',
      'Daniel',
      'Marcelo',
      'Bruno',
      'Eduardo',
      'Felipe',
      'Raimundo',
      'Rodrigo',
      'Gustavo',
      'Thiago',
      'Mateus',
      'Leonardo',
      'Fernando',
      'Ricardo',
      'Sérgio',
      'Vinícius',
      'André',
      'Diego',
      'Caio',
    ],
    female: [
      'Maria',
      'Ana',
      'Francisca',
      'Antônia',
      'Adriana',
      'Juliana',
      'Márcia',
      'Fernanda',
      'Patrícia',
      'Aline',
      'Sandra',
      'Camila',
      'Amanda',
      'Bruna',
      'Jéssica',
      'Letícia',
      'Júlia',
      'Luciana',
      'Vanessa',
      'Mariana',
      'Beatriz',
      'Larissa',
      'Gabriela',
      'Renata',
      'Cláudia',
      'Tatiana',
      'Rafaela',
      'Débora',
      'Simone',
      'Isabela',
    ],
    last: [
      'Silva',
      'Santos',
      'Oliveira',
      'Souza',
      'Rodrigues',
      'Ferreira',
      'Alves',
      'Pereira',
      'Lima',
      'Gomes',
      'Costa',
      'Ribeiro',
      'Martins',
      'Carvalho',
      'Almeida',
      'Lopes',
      'Soares',
      'Fernandes',
      'Vieira',
      'Barbosa',
      'Rocha',
      'Dias',
      'Nascimento',
      'Andrade',
      'Moreira',
      'Nunes',
      'Marques',
      'Machado',
      'Mendes',
      'Freitas',
      'Cardoso',
      'Ramos',
      'Gonçalves',
      'Santana',
      'Teixeira',
      'Araújo',
      'Pinto',
      'Campos',
      'Moura',
      'Cavalcanti',
      'Monteiro',
      'Correia',
    ],
  ),
};

/// How many names [locale] has: first names (both sexes) and surnames.
(int, int) nameCounts(NameLocale locale) {
  final names = _names[locale]!;
  return (names.male.length + names.female.length, names.last.length);
}
