// The trip reader's answer, without the model: what it writes, turned
// into the app's lists and held to the chat (public/reader/trip-reader.js).
import { describe, expect, it } from 'vitest';
import { EXAMPLES, SCHEMA, ages, amounts, dates, firstObject, messages, listedWith, named, nightsInChat, notComing, parentsInChat, passMessages, atWhose, bringers, hostInChat, spending, readExpenses, readInPasses, readNights, readPeople, startDate, toTrip, tripNights } from '../public/reader/trip-reader.js';

const today = new Date('2026-11-12T00:00:00Z');

describe('firstObject', () => {
  it('finds the JSON after a thinking block and around prose', () => {
    expect(firstObject('<think>hmm {no}</think>Here: {"a":{"b":"}"}} done')).toEqual({ a: { b: '}' } });
  });
  it('is null without a whole object', () => {
    expect(firstObject('no json')).toBeNull();
    expect(firstObject('{"a":1')).toBeNull();
  });
});

describe('startDate', () => {
  it('takes the next time the day comes', () => {
    expect(startDate('12-23', today)).toBe('2026-12-23');
    expect(startDate('11-12', today)).toBe('2026-11-12');
    expect(startDate('1-2', today)).toBe('2027-01-02');
  });
  it('is null for anything else', () => {
    expect(startDate('Dec 23', today)).toBeNull();
    expect(startDate('13-01', today)).toBeNull();
    expect(startDate(null, today)).toBeNull();
  });
});

describe('toTrip', () => {
  const answer = {
    start: '12-24', nights: 3, host: 'Dana',
    people: [
      { name: 'Dana', age: null, nights: 3, parents: [] },
      { name: 'Kai', age: null, nights: 3, parents: [] },
      { name: 'Jo', age: null, nights: 3, parents: [] },
      { name: 'Mia', age: 7, nights: 3, parents: ['Jo'] },
      { name: 'Kai', age: null, nights: 3, parents: [] },
    ],
    expenses: [
      { kind: 'lodging', what: 'Lake cabin', amount: '$1,200', by: 'Dana' },
      { kind: 'snacks', what: 'Chips', amount: 30, by: 'Ben' },
      { kind: 'drinks', what: 'Drinks', amount: 0, by: 'Jo' },
    ],
  };
  const trip = toTrip(answer, today);

  it('gives people ids, once each, with kids under their parents', () => {
    expect(trip.people.map((p) => p.id)).toEqual(['dana', 'kai', 'jo', 'mia', 'ben']);
    expect(trip.people.find((p) => p.id === 'mia')).toMatchObject({ age: 7, guardians: ['jo'], drinks: false });
    expect(trip.people.find((p) => p.id === 'jo')).toMatchObject({ age: null, guardians: [], drinks: true });
  });
  it('reads amounts, keeps known kinds and adds a payer the list missed', () => {
    expect(trip.expenses).toEqual([
      { kind: 'lodging', what: 'Lake cabin', amount: 1200, by: 'dana' },
      { kind: 'other', what: 'Chips', amount: 30, by: 'ben' },
    ]);
  });
  it('dates the trip and finds the host', () => {
    expect(trip.start).toBe('2026-12-24');
    expect(trip.host).toBe('dana');
  });
  it('counts a kid with no parent in the list as an adult, and says so', () => {
    const t = toTrip({ ...answer, people: [...answer.people, { name: 'Zed', age: 9, nights: 3, parents: ['Nobody'] }] }, today);
    expect(t.people.find((p) => p.id === 'zed')).toMatchObject({ age: null, guardians: [], drinks: true });
    expect(t.notes.join()).toContain('Zed');
  });
  it('keeps an age from 18 to 20, with or without parents: they pay but can\'t drink', () => {
    const t = toTrip({ ...answer, people: [...answer.people, { name: 'Lina', age: 19, nights: 3, parents: ['Dana'] }, { name: 'Omar', age: 20, nights: 3 }, { name: 'Pat', age: 45, nights: 3 }] }, today);
    expect(t.people.find((p) => p.id === 'lina')).toMatchObject({ age: 19, guardians: ['dana'], drinks: false });
    expect(t.people.find((p) => p.id === 'omar')).toMatchObject({ age: 20, guardians: [], drinks: false });
    expect(t.people.find((p) => p.id === 'pat')).toMatchObject({ age: null, drinks: true });
  });
  it('matches "Grandma Rose" to "Rose" and keeps nights within the trip', () => {
    const t = toTrip({
      start: '12-23', nights: 5, host: 'Rose',
      people: [{ name: 'Grandma Rose', age: null, nights: 9 }],
      expenses: [{ kind: 'groceries', what: 'Food', amount: 50, by: 'Rose' }],
    }, today);
    expect(t.people).toHaveLength(1);
    expect(t.people[0]).toMatchObject({ id: 'rose', name: 'Grandma Rose', nights: 5 });
    expect(t.expenses[0].by).toBe('rose');
    expect(t.host).toBe('rose');
  });
  it('refuses a trip with nothing to split', () => {
    expect(() => toTrip(null, today)).toThrow(/nothing readable/);
    expect(() => toTrip({ people: [{ name: 'A' }], expenses: [] }, today)).toThrow(/no amounts/);
  });
});

describe('toTrip, held to the chat', () => {
  const chat = "Dinner at Ann's on Nov 26. Bob brought wine, $40. Ann made the food, $90.";
  // What a 0.6B model wrote for it: two people from the prompt's examples, and no $90.
  const answer = {
    start: '11-26', nights: 1, host: 'Ann',
    people: [
      { name: 'Ann', age: null, nights: 1, parents: [] },
      { name: 'Bob', age: null, nights: 1, parents: [] },
      { name: 'Ivy', age: null, nights: 1, parents: [] },
      { name: 'Leo', age: null, nights: 0, parents: [] },
    ],
    expenses: [
      { kind: 'drinks', what: 'Wine', amount: 40, by: 'Bob' },
      { kind: 'drinks', what: 'Wine', amount: 40, by: 'Bob' },
      { kind: 'groceries', what: 'Cake', amount: 25, by: 'Ivy' },
    ],
  };
  const trip = toTrip(answer, today, chat);

  it('leaves out people the chat never names', () => {
    expect(trip.people.map((p) => p.name)).toEqual(['Ann', 'Bob']);
    expect(trip.notes).toEqual([]);
  });
  it('keeps only amounts written in the chat, as many times as it writes them', () => {
    expect(trip.expenses.filter((e) => e.amount !== 90)).toEqual([{ kind: 'drinks', what: 'Wine', amount: 40, by: 'bob' }]);
    const twice = toTrip({ ...answer, expenses: [...answer.expenses, { kind: 'groceries', what: 'Food', amount: 40, by: 'Ann' }] }, today, 'Ann and Bob. Bob brought wine, $40. Ann made the food, $40.');
    expect(twice.expenses.map((e) => [e.amount, e.by])).toEqual([[40, 'bob'], [40, 'ann']]);
  });
  it('fills in an amount the model missed, when the chat says who paid it', () => {
    expect(trip.expenses.at(-1)).toEqual({ kind: 'groceries', what: 'Food', amount: 90, by: 'ann' });
    expect(trip.notes.join()).not.toContain('$90');
  });
  it('notes an amount the chat has but nobody is said to have paid', () => {
    const t = toTrip(answer, today, "Dinner at Ann's on Nov 26. Bob brought wine, $40. The rest was $90.");
    expect(t.notes.join()).toContain('$90 is in the chat but not in the lists');
  });
  it('finds names past a title, and amounts with commas and cents', () => {
    expect(named('Grandma Rose is coming', 'Rose')).toBe(true);
    expect(named('Rose is coming', 'Grandma Rose')).toBe(true);
    expect(named('Rosemary is coming', 'Rose')).toBe(false);
    expect(amounts('the cabin, $1,850, and snacks $12.50')).toEqual([1850, 12.5]);
  });
});

describe('ages, from the chat', () => {
  it('reads the age in brackets after a name', () => {
    expect([...ages('Jan and Mo are bringing the kids, Lily (4), Max (12) and Zoe (16).')]).toEqual([['lily', 4], ['max', 12], ['zoe', 16]]);
  });
  it('shares one age among twins, but not with the adults before a kid', () => {
    expect(Object.fromEntries(ages('Dev and Maya bring the twins, Ari and Eli (7), and baby June (1).'))).toEqual({ ari: 7, eli: 7, june: 1 });
    expect(Object.fromEntries(ages('Kim and Leo (10) are coming.'))).toEqual({ leo: 10 });
  });

  const chat = "Cabin for 3 nights from Dec 23, $900, Jo paid. Jo's daughter Mia (7) and di's son eli who's 9. Leo only makes it for the last 2 nights. Finn (9) too.";
  const trip = toTrip({
    start: '12-23', nights: 3, host: 'Jo',
    people: [
      { name: 'Jo', age: null, nights: 3, parents: [] },
      { name: 'di', age: null, nights: 3, parents: [] },
      { name: 'Mia', age: 5, nights: 3, parents: ['Jo'] },
      { name: 'eli', age: 9, nights: 3, parents: ['di'] },
      { name: 'Leo', age: 2, nights: 2, parents: ['Jo'] },
    ],
    expenses: [{ kind: 'lodging', what: 'Cabin', amount: 900, by: 'Jo' }],
  }, today, chat);

  it('takes the chat\'s age over the model\'s', () => {
    expect(trip.people.find((p) => p.id === 'mia').age).toBe(7);
  });
  it('keeps the model\'s age only when the chat gives it after the name', () => {
    expect(trip.people.find((p) => p.id === 'eli')).toMatchObject({ age: 9, guardians: ['di'] });
    expect(trip.people.find((p) => p.id === 'leo')).toMatchObject({ age: null, nights: 2, guardians: [] });
  });
  it('adds a kid the chat gives an age but the model missed', () => {
    expect(trip.people.find((p) => p.id === 'finn')).toMatchObject({ name: 'Finn', nights: 3 });
  });
});

describe('the start and the nights, from the chat', () => {
  it('finds the dates the chat writes', () => {
    expect(dates('5 nights from Dec 23, $1,850. Leo comes on december 26th. Back 12/28. May did the turkey, $120.')).toEqual(['12-23', '12-26', '12-28']);
    expect(dates('Tom and Lu leave on the 1st. $3/4 off?')).toEqual([]);
  });
  it('takes the most nights the chat counts as the trip\'s', () => {
    expect(tripNights('Leo comes for 2 nights. The cabin is 5 nights from Dec 23.')).toBe(5);
    expect(tripNights("Thanksgiving at Mom's on Nov 26.")).toBeNull();
  });
  const answer = { start: '11-12', nights: 2, host: 'bo', people: [{ name: 'bo', nights: 3 }, { name: 'fay', nights: 2 }], expenses: [{ kind: 'lodging', amount: 1980, by: 'bo' }] };
  const chat = 'the lodge is $1,980 for 3 nights starting dec 23 (bo put it on his card). fay is driving up on dec 24 so only 2 nights.';
  it('corrects a start and nights the chat contradicts', () => {
    const t = toTrip(answer, today, chat);
    expect(t.start).toBe('2026-12-23');
    expect(t.people.map((p) => p.nights)).toEqual([3, 2]);
  });
  it('keeps the model\'s start when the chat writes that date', () => {
    expect(toTrip({ ...answer, start: '12-24' }, today, chat).start).toBe('2026-12-24');
  });
});

describe('who stays fewer nights, from the chat\'s own words', () => {
  const P = (...names) => names.map((name) => ({ id: name.toLowerCase().split(' ').at(-1), name, age: null }));
  const said = (chat, people, trip, start = '2026-12-29') => Object.fromEntries(nightsInChat(chat, people, trip, start));

  it('gives the nights a sentence counts to the people it names', () => {
    expect(said('Cabin, 5 nights from Dec 23. Sam booked it. Leo only makes it for the last 2 nights, and his girlfriend Tess comes with him. Uncle Ray drives up on the 25th, so 3 nights, with his son Ben (9).',
      P('Sam', 'Leo', 'Tess', 'Uncle Ray', 'Ben'), 5, '2026-12-23')).toEqual({ leo: 2, tess: 2, ray: 3, ben: 3 });
  });
  it('splits a sentence with two counts between the people before each', () => {
    expect(said('Leo stays 2 nights and Tess 3 nights; Sam is there all week.', P('Sam', 'Leo', 'Tess'), 7)).toEqual({ leo: 2, tess: 3 });
  });
  it('counts "a night early" from the trip, and days from its first day', () => {
    const people = P('Tom', 'Lu', 'Ruth', 'Kenji', 'Priya');
    expect(said('Tom and Lu leave on the 1st, a night early. Ruth arrives on the 30th. Priya booked it.', people, 4)).toEqual({ tom: 3, lu: 3, ruth: 3 });
    expect(said('Tom and Lu leave on the 1st. Kenji heads home two nights early.', people, 4)).toEqual({ tom: 3, lu: 3, kenji: 2 });
  });
  it('says nothing of a one-day event, or of who is only named', () => {
    expect(said('Dinner for 2 nights? No. Tom comes.', P('Tom'), 1)).toEqual({});
    expect(said('It is Tom, Lu and Ruth. 4 nights from Dec 29.', P('Tom', 'Lu', 'Ruth'), 4)).toEqual({});
  });

  const chat = 'the lodge is $1,980 for 3 nights starting dec 23, bo paid. coming: bo, cy, and fay. fay is driving up on the 24th so only 2 nights.';
  const answer = (nights) => ({ start: '12-23', nights: 3, host: 'bo', people: [{ name: 'bo', nights: 3 }, { name: 'cy', nights: nights.cy }, { name: 'fay', nights: nights.fay }], expenses: [{ kind: 'lodging', amount: 1980, by: 'bo' }] });
  it('corrects a model that missed a late arrival, or made one up', () => {
    expect(toTrip(answer({ cy: 3, fay: 3 }), today, chat).people.map((p) => p.nights)).toEqual([3, 3, 2]);
    expect(toTrip(answer({ cy: 1, fay: 2 }), today, chat).people.map((p) => p.nights)).toEqual([3, 3, 2]);
  });
  it('takes the model\'s word for someone the chat says comes late, without a count', () => {
    const t = toTrip(answer({ cy: 2, fay: 2 }), today, chat.replace('coming: bo, cy, and fay.', 'coming: bo and fay. cy only makes it for the weekend.'));
    expect(t.people.map((p) => p.nights)).toEqual([3, 2, 2]);
  });
  it('keeps a kid no longer than the parent who stays longest', () => {
    const t = toTrip({ start: '12-23', nights: 3, host: 'bo', people: [{ name: 'bo', nights: 3 }, { name: 'fay', nights: 3 }, { name: 'Gus', age: 5, nights: 3, parents: ['fay'] }], expenses: [{ kind: 'lodging', amount: 1980, by: 'bo' }] },
      today, 'the lodge is $1,980 for 3 nights starting dec 23, bo paid. fay is driving up on the 24th so only 2 nights. Gus (5) is hers.');
    expect(t.people.map((p) => [p.id, p.nights])).toEqual([['bo', 3], ['fay', 2], ['gus', 2]]);
  });
});

describe('a kid\'s parents, from the chat\'s own words', () => {
  const people = (adults, kids) => [...adults.map((name) => ({ id: name.toLowerCase().split(' ').at(-1), name, age: null })), ...kids.map((name) => ({ id: name.toLowerCase(), name, age: 5 }))];
  const said = (chat, adults, kids) => Object.fromEntries(parentsInChat(chat, people(adults, kids)));

  it('takes the adults listed together before the kids', () => {
    expect(said('Sam booked it. Jan and Mo are bringing the kids, Lily (4), Max (12) and Zoe (16).', ['Sam', 'Jan', 'Mo'], ['Lily', 'Max', 'Zoe']))
      .toEqual({ lily: ['jan', 'mo'], max: ['jan', 'mo'], zoe: ['jan', 'mo'] });
    expect(said('Dev and Maya bring the twins, Ari and Eli (7), and baby June (1).', ['Dev', 'Maya'], ['Ari', 'Eli', 'June']))
      .toEqual({ ari: ['dev', 'maya'], eli: ['dev', 'maya'], june: ['dev', 'maya'] });
  });
  it('takes one parent after "Jo\'s", "his" or "her"', () => {
    expect(said("Kai, Jo and Ben are coming, plus Jo's daughter Mia (7).", ['Kai', 'Jo', 'Ben'], ['Mia'])).toEqual({ mia: ['jo'] });
    expect(said("Otis's partner Lark is coming with her daughters Fern (4) and Posy (13).", ['Otis', 'Lark'], ['Fern', 'Posy'])).toEqual({ fern: ['lark'], posy: ['lark'] });
    expect(said('Uncle Ray drives up on the 25th, so 3 nights, with his son Ben (9).', ['Uncle Ray'], ['Ben'])).toEqual({ ben: ['ray'] });
  });
  it('takes both after "their", and each family its own', () => {
    expect(said("Oren's wife Uma and their baby Vic (2) too.", ['Oren', 'Uma'], ['Vic'])).toEqual({ vic: ['oren', 'uma'] });
    expect(said('Jan brings Lily (4) and Mo brings Max (12).', ['Jan', 'Mo'], ['Lily', 'Max'])).toEqual({ lily: ['jan'], max: ['mo'] });
  });
  it('says nothing of a kid whose sentence names no adult first', () => {
    expect(said('Finn (9) is coming too. Sam booked it.', ['Sam'], ['Finn'])).toEqual({});
  });
  it('wins over the model\'s parents', () => {
    const t = toTrip({ start: '12-23', nights: 1, host: 'Sam', people: [{ name: 'Sam' }, { name: 'Jan' }, { name: 'Mo' }, { name: 'Lily', age: 4, parents: ['Sam'] }], expenses: [{ kind: 'groceries', amount: 50, by: 'Sam' }] },
      today, 'Dinner on Dec 23, Sam cooked, $50. Jan and Mo are bringing Lily (4).');
    expect(t.people.find((p) => p.id === 'lily').guardians).toEqual(['jan', 'mo']);
  });
});

describe('who comes, from the chat\'s own words', () => {
  const P = (...names) => names.map((name) => ({ id: name.toLowerCase().split(' ').at(-1), name, age: null }));

  it('knows who the chat names only to say they aren\'t coming', () => {
    const chat = "Cousin Gil can't make it. Zed might come but hasn't confirmed, don't count him. Leo can't make it for the first night. Ezra can only come for the last 2 nights. Rose is coming too, she doesn't drink.";
    expect(P('Cousin Gil', 'Zed', 'Leo', 'Ezra', 'Rose', 'Nobody').map((p) => notComing(chat, p))).toEqual([true, true, false, false, false, false]);
  });
  it('finds the names listed with people it knows', () => {
    expect(listedWith("Ski week, $3,100. It's Hal, Ines, Jax, Kay and Lon. Kay bought snacks, wine and beer.", P('Ines', 'Kay', 'Lon'))).toEqual(['Hal', 'Jax']);
    expect(listedWith("It's Mom, Carlos, Uncle Joe and Bea.", P('Mom', 'Carlos', 'Bea'))).toEqual(['Uncle Joe']);
    expect(listedWith('coming: bo, cy, fay and everyone else. Sam, Jan and the kids.', P('bo', 'cy', 'Sam', 'Jan'))).toEqual(['fay']);
    expect(listedWith('It is Hal, Ines, wine and cheese.', P('Hal', 'Ines'))).toEqual([]);
    expect(listedWith('Hal, Jax and Lon are in.', P('Lon'))).toEqual([]);
  });

  const chat = "Dinner at Pat's on Nov 26, Pat made the turkey, $140. It's Pat, Gus, Mel and Kim. Kim brings her son Leo (10). Cousin Gil can't make it.";
  const trip = toTrip({ start: '11-26', nights: 1, host: 'Pat',
    people: [{ name: 'Pat' }, { name: 'Mel' }, { name: 'Leo', age: 10, parents: ['Kim'] }, { name: 'Gil' }],
    expenses: [{ kind: 'groceries', what: 'Turkey', amount: 140, by: 'Pat' }] }, today, chat);
  it('adds a parent a kid\'s line names, and who is listed with the others', () => {
    expect(trip.people.map((p) => p.id)).toEqual(['pat', 'mel', 'leo', 'kim', 'gus']);
    expect(trip.people.find((p) => p.id === 'leo')).toMatchObject({ age: 10, guardians: ['kim'] });
  });
  it('leaves out who isn\'t coming, and says so', () => {
    expect(trip.notes).toEqual(["left out Gil: the chat says they aren't coming"]);
  });
  it('keeps someone who isn\'t coming but paid', () => {
    const t = toTrip({ start: '11-26', nights: 1, host: 'Pat', people: [{ name: 'Pat' }, { name: 'Gil' }], expenses: [{ kind: 'groceries', amount: 140, by: 'Gil' }] }, today, "Dinner at Pat's, Nov 26. Gil can't make it but paid for the turkey, $140.");
    expect(t.people.map((p) => p.id)).toEqual(['pat', 'gil']);
  });
});

describe('who paid what, from the chat\'s own words', () => {
  const by = (chat, people = []) => spending(chat, people).map((x) => [x.amount, x.by, x.drinks]);
  it('labels an amount from its own words, for one the model missed or mislabeled', () => {
    expect(spending('Mo did the grocery run, $420. Sam got the wine and beer, $180. Tess paid for everyone\'s sledding passes, $120. A cabin, $900.').map((x) => [x.kind, x.what]))
      .toEqual([['groceries', 'Grocery run'], ['drinks', 'Wine and beer'], ['other', 'Sledding passes'], ['lodging', 'Lodging']]);
    const t = toTrip({ start: '12-23', nights: 1, host: 'Mo', people: [{ name: 'Mo' }, { name: 'Sam' }], expenses: [{ kind: 'drinks', what: 'Beer', amount: 420, by: 'Sam' }, { kind: 'drinks', what: 'Wine', amount: 180, by: 'Sam' }] },
      today, 'Dinner on Dec 23. Mo did the grocery run, $420. Sam got the wine and beer, $180.');
    expect(t.expenses.map((e) => [e.kind, e.what, e.by])).toEqual([['groceries', 'Grocery run', 'mo'], ['drinks', 'Wine', 'sam']]);
  });

  it('takes the one named with a verb before the amount', () => {
    expect(by('Mo did the grocery run, $420, and Ana did the second one on the 26th, $185. Ana doesn\'t drink. Sam got the wine and beer, $180, and Ray brought the eggnog and whiskey, $95.'))
      .toEqual([[420, 'Mo', false], [185, 'Ana', false], [180, 'Sam', true], [95, 'Ray', true]]);
    expect(by('cy got food at costco $265.75. di got wine $64.', [{ name: 'cy' }, { name: 'di' }])).toEqual([[265.75, 'cy', false], [64, 'di', true]]);
  });
  it('gives a second amount with no one named to the same payer', () => {
    expect(by('Aunt Cora brought the sides, $60, and the wine, $54.')).toEqual([[60, 'Aunt Cora', false], [54, 'Aunt Cora', true]]);
  });
  it('takes who booked or paid right after an amount no one is named before', () => {
    expect(by('Christmas at a cabin, 5 nights from Dec 23, $2,450. Sam booked it and paid.')).toEqual([[2450, 'Sam', false]]);
    expect(by("Lake house, $3,600, plus the loft, $640. Priya booked both and paid.")).toEqual([[3600, 'Priya', false], [640, 'Priya', false]]);
    expect(by("Ski week, $3,100. Hal's name is on the booking but Ines paid for it.")).toEqual([[3100, 'Ines', false]]);
    expect(by("A beach house for a week, $4,200, on Hana's card.")).toEqual([[4200, 'Hana', false]]);
  });
  it('tells drinks by the words, wherever the payer is named', () => {
    expect(by('Ned and Ola brought the wine, Ned paid, $75. Kim doesn\'t drink and made the sides, $30.')).toEqual([[75, 'Ned', true], [30, 'Kim', false]]);
  });
  it('knows no payer when the chat names none', () => {
    expect(by('The rest was $90. It cost $12.')).toEqual([[90, null, false], [12, null, false]]);
  });
  it('wins over the model\'s payer and drinks', () => {
    const t = toTrip({ start: '11-26', nights: 1, host: 'May', people: [{ name: 'May' }, { name: 'Ned' }, { name: 'Pim' }],
      expenses: [{ kind: 'other', what: 'Wine', amount: 75, by: 'May' }, { kind: 'drinks', what: 'Pies', amount: 40, by: 'May' }] },
    today, "Thanksgiving at Aunt May's on Nov 26. Ned brought the wine, $75. Pim made pies, $40.");
    expect(t.expenses.map((e) => [e.amount, e.by, e.kind])).toEqual([[75, 'ned', 'drinks'], [40, 'pim', 'groceries']]);
  });
});

describe('who brings kids and whose place it is, from the chat\'s own words', () => {
  it('finds who brings kids', () => {
    expect(bringers("Uncle Joe brings his kids, Nina (3) and Theo (8). Kai, Jo and Ben are coming, plus Jo's daughter Mia (7). Remy is coming with his daughter Sol (5). Everyone brings their kids.")).toEqual(['Uncle Joe', 'Remy', 'Jo']);
  });
  it('finds the host', () => {
    expect(hostInChat("Thanksgiving at Grandma June's on Nov 26. Hal bought the turkey.")).toBe('Grandma June');
    expect(hostInChat("Ski week, $3,100. Hal's name is on the booking but Ines paid for it.")).toBe('Hal');
    expect(hostInChat('Lake house, 4 nights from Dec 29, $2,400. Priya booked it.')).toBe('Priya');
    expect(hostInChat('We split the bill.')).toBeNull();
    expect(atWhose("Friendsgiving at Noor's place on Nov 27. Dinner at Pat's after.")).toBe('Noor');
    expect(atWhose("We meet on Nov 27. Dinner at Pat's after.")).toBeNull();
  });
  it('takes no "Hal\'s kids" or "the twins" from a model as a person', () => {
    const t = toTrip({ start: '11-26', nights: 1, host: 'Hal', people: [{ name: 'Hal' }, { name: "Hal's kids" }, { name: 'the twins' }, { name: 'Ty', age: 6, parents: ["Hal's kids", 'Hal'] }], expenses: [{ kind: 'groceries', amount: 260, by: 'Hal' }] },
      today, 'Dinner on Nov 26. Hal bought the turkey, $260. Hal brings his kids, the twins and Ty (6).');
    expect(t.people.map((p) => [p.id, p.guardians.join()])).toEqual([['hal', ''], ['ty', 'hal']]);
  });
  it('adds them to the lists when the model missed them', () => {
    const t = toTrip({ start: '11-26', nights: 1, host: 'Hal', people: [{ name: 'Hal' }, { name: 'Nina', age: 3, parents: ['Hal'] }], expenses: [{ kind: 'groceries', amount: 260, by: 'Hal' }] },
      today, "Thanksgiving at Grandma June's on Nov 26. Hal bought the turkey, $260. Uncle Joe brings his kids, Nina (3) and Theo (8).");
    expect(t.people.map((p) => [p.id, p.age, p.guardians.join()])).toEqual([['hal', null, ''], ['nina', 3, 'joe'], ['june', null, ''], ['joe', null, ''], ['theo', 8, 'joe']]);
    expect(t.host).toBe('june');
  });
});

describe('the three passes', () => {
  const [aspen, wren] = EXAMPLES;
  // A model that answers each pass with the worked example's own answer.
  const perfect = (example) => async (m) => {
    const pass = ['people', 'nights', 'expenses'].find((k) => m[0].content === passMessages(k, 'x', { nights: 1, names: [], amounts: [] })[0].content);
    return passMessages(pass, 'x', { nights: 1, names: [], amounts: [] }).find((x, i) => x.role === 'assistant' && passMessages(pass, 'x', { nights: 1, names: [], amounts: [] })[i - 1].content.startsWith(example.chat)).content;
  };

  it('asks each pass with its rules, two worked examples and the chat', () => {
    for (const pass of ['people', 'nights', 'expenses']) {
      const m = passMessages(pass, '  Hi all  ', { nights: 4, names: ['A', 'B'], amounts: [10, 2.5] });
      expect(m.map((x) => x.role)).toEqual(['system', 'user', 'assistant', 'user', 'assistant', 'user']);
      expect(m.at(-1).content.startsWith('Hi all')).toBe(true);
    }
    expect(passMessages('nights', 'Hi', { nights: 4, names: ['A', 'B'] }).at(-1).content).toBe('Hi\n\nThe trip is 4 nights. The people: A, B.');
    expect(passMessages('expenses', 'Hi', { amounts: [10, 2.5] }).at(-1).content).toBe('Hi\n\nThe amounts: 10, 2.5.');
    // The nights pass shows one trip with late and early people, and one where everyone stays.
    expect(passMessages('nights', 'Hi', { nights: 2, names: [] }).filter((x) => x.role === 'assistant').map((x) => x.content)).toEqual(['Kira | 2\nNico | 3', 'everyone']);
  });
  it('reads the people pass, around bullets and a thinking block', () => {
    expect(readPeople('<think>people:\nNobody | adult</think>\nstart: 12-22\nnights: 4\nhost: Greta\nPeople:\n- Greta | adult\n- Jack | 7 | Hugo and Isla\n\nThat is all.')).toEqual({
      start: '12-22', nights: '4', host: 'Greta',
      people: [{ name: 'Greta', age: null, parents: [] }, { name: 'Jack', age: 7, parents: ['Hugo', 'Isla'] }],
    });
  });
  it('reads people lines that come without their "people:" line', () => {
    expect(readPeople('Bo | adult\nEli | 9 | Di\nFay | adult (driving up on the 24th)').people).toEqual([
      { name: 'Bo', age: null, parents: [] }, { name: 'Eli', age: 9, parents: ['Di'] }, { name: 'Fay', age: null, parents: [] },
    ]);
  });
  it('reads the nights and expenses passes', () => {
    expect([...readNights('Kira | 2\nNico | 3 nights\neveryone else stays')]).toEqual([['kira', 2], ['nico', 3]]);
    expect([...readNights('everyone')]).toEqual([]);
    expect(readExpenses('2000 | Lodging | Lodge | Greta\n$90 | drinks | Wine | Greta\nnot a line')).toEqual([
      { amount: '2000', kind: 'lodging', what: 'Lodge', by: 'Greta' }, { amount: '$90', kind: 'drinks', what: 'Wine', by: 'Greta' },
    ]);
  });
  it('puts the passes together into the same trip as the one answer', async () => {
    const asked = [];
    const ask = perfect(aspen);
    const answer = await readInPasses(aspen.chat, (m) => { asked.push(m); return ask(m); });
    expect(asked).toHaveLength(3);
    expect(toTrip(answer, today, aspen.chat)).toEqual(toTrip(aspen.answer, today, aspen.chat));
  });
  it('skips the nights pass for a one-day event', async () => {
    const asked = [];
    const ask = perfect(wren);
    const answer = await readInPasses(wren.chat, (m) => { asked.push(m); return ask(m); });
    expect(asked).toHaveLength(2);
    expect(toTrip(answer, today, wren.chat)).toEqual(toTrip(wren.answer, today, wren.chat));
  });
  it('gives late people the nights the pass says, by first name too', async () => {
    const said = { people: 'nights: 5\nhost: Sam\npeople:\nSam | adult\nUncle Ray | adult', nights: 'Ray | 3', expenses: '900 | lodging | Cabin | Sam' };
    const ask = async (m) => said[['people', 'nights', 'expenses'].find((k) => m[0].content === passMessages(k, 'x', { names: [], amounts: [] })[0].content)];
    const answer = await readInPasses('Cabin, 5 nights from Dec 23, $900, Sam paid. Uncle Ray drives up on the 25th, so 3 nights.', ask);
    expect(answer.people.map((p) => [p.name, p.nights])).toEqual([['Sam', 5], ['Uncle Ray', 3]]);
  });
});

describe('the one JSON answer', () => {
  it('ends with the chat, after the rules and two worked examples', () => {
    const m = messages('  Hi all  ');
    expect(m.map((x) => x.role)).toEqual(['system', 'user', 'assistant', 'user', 'assistant', 'user']);
    expect(m.at(-1).content).toBe('Hi all');
    for (const a of m.filter((x) => x.role === 'assistant')) expect(() => JSON.parse(a.content)).not.toThrow();
  });
  it('has a schema its own examples fit', () => {
    const fits = (schema, v) => {
      if (schema.enum) return schema.enum.includes(v);
      const types = [].concat(schema.type);
      const type = v === null ? 'null' : Array.isArray(v) ? 'array' : Number.isInteger(v) && types.includes('integer') ? 'integer' : typeof v;
      if (!types.includes(type)) return false;
      if (type === 'array') return v.every((x) => fits(schema.items, x));
      if (type === 'object') return schema.required.every((k) => k in v) && Object.keys(v).every((k) => k in schema.properties && fits(schema.properties[k], v[k]));
      if (schema.pattern) return new RegExp(schema.pattern).test(v);
      return true;
    };
    for (const e of EXAMPLES) expect(fits(SCHEMA, e.answer)).toBe(true);
    expect(fits(SCHEMA, { ...EXAMPLES[0].answer, extra: 1 })).toBe(false);
  });
});

describe('the worked examples', () => {
  it('hold to their own chats: every person, age, parent and amount is written there', () => {
    for (const e of EXAMPLES) {
      const trip = toTrip(e.answer, today, e.chat);
      expect(trip.notes).toEqual([]);
      expect(trip.people.map((p) => [p.name, p.age, p.nights])).toEqual(e.answer.people.map((p) => [p.name, p.age, p.nights]));
      expect(trip.expenses.map((x) => x.amount)).toEqual(e.answer.expenses.map((x) => x.amount));
    }
  });
});
