// The trip reader's answer, without the model: the JSON it writes, turned
// into the app's lists (public/reader/trip-reader.js).
import { describe, expect, it } from 'vitest';
import { amounts, firstObject, messages, named, startDate, toTrip } from '../public/reader/trip-reader.js';

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
    expect(t.people.find((p) => p.id === 'zed')).toMatchObject({ age: null, guardians: [] });
    expect(t.notes.join()).toContain('Zed');
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
    expect(() => toTrip(null, today)).toThrow(/no JSON/);
    expect(() => toTrip({ people: [{ name: 'A' }], expenses: [] }, today)).toThrow(/no amounts/);
  });
});

describe('toTrip, held to the chat', () => {
  const chat = "Dinner at Ann's on Nov 26. Bob brought wine, $40. Ann made the food, $90.";
  // What Qwen3-0.6B wrote for it: two people from the prompt's examples, and no $90.
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

  it('leaves out people the chat never names, and says so', () => {
    expect(trip.people.map((p) => p.name)).toEqual(['Ann', 'Bob']);
    expect(trip.notes).toContain("left out Ivy, who isn't in the chat");
  });
  it('keeps only amounts written in the chat, once each', () => {
    expect(trip.expenses).toEqual([{ kind: 'drinks', what: 'Wine', amount: 40, by: 'bob' }]);
  });
  it('notes an amount the chat has but the lists miss', () => {
    expect(trip.notes.join()).toContain('$90 is in the chat but not in the lists');
  });
  it('finds names past a title, and amounts with commas and cents', () => {
    expect(named('Grandma Rose is coming', 'Rose')).toBe(true);
    expect(named('Rose is coming', 'Grandma Rose')).toBe(true);
    expect(named('Rosemary is coming', 'Rose')).toBe(false);
    expect(amounts('the cabin, $1,850, and snacks $12.50')).toEqual([1850, 12.5]);
  });
});

describe('messages', () => {
  it('ends with the chat, after the rules and two worked examples', () => {
    const m = messages('  Hi all  ');
    expect(m.map((x) => x.role)).toEqual(['system', 'user', 'assistant', 'user', 'assistant', 'user']);
    expect(m.at(-1).content).toBe('Hi all');
    for (const a of m.filter((x) => x.role === 'assistant')) expect(() => JSON.parse(a.content)).not.toThrow();
  });
});
