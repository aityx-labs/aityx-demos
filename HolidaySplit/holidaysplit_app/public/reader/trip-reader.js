// The trip reader's prompt and its answer: what a small LLM, run on the
// device, reads from a group chat (who comes, for how many nights, the
// kids' ages and parents, what was spent and by whom), as the lists the
// app shows. Shared by reader-worker.js and the tests. No judgement here:
// who isn't paying and who doesn't drink are Jev's questions, and the
// split is the decision's.

export const SYSTEM = `You read a family's group chat about a holiday trip and list the facts, as JSON. Only facts written in the chat: never guess.

Answer with one JSON object and nothing else:
{"start":"MM-DD","nights":N,"host":"Name","people":[{"name":"Name","age":null,"nights":N,"parents":[]}],"expenses":[{"kind":"lodging|groceries|drinks|other","what":"Short label","amount":0,"by":"Name"}]}

- start: the first day, as month-day numbers.
- nights: the nights of the whole trip; 1 for a dinner or a one-day event.
- host: who booked the place, or whose house it is.
- people: every person the chat names, each once, with the name as the chat writes it, even one named only to say they don't drink or don't pay. An adult's age is null. A kid has the age written in brackets and parents: the adults who bring them. nights: the trip's nights, fewer only for who comes late or leaves early (a night early: one fewer).
- expenses: each amount spent, as a number of dollars, and by: who paid it. lodging is the place, groceries is food, drinks is alcohol, wine, beer or champagne.`;

const EXAMPLE_IN = `Christmas at a cabin in the Smokies, 5 nights from Dec 23, $1,850. Sam booked it and paid. Jan and Mo are bringing the kids, Lily (4) and Max (12). Grandma Rose is coming too, she doesn't drink. Leo only makes it for the last 2 nights. Mo did the grocery run, $420. Sam also got the wine and beer, $180.`;
const EXAMPLE_OUT = `{"start":"12-23","nights":5,"host":"Sam","people":[{"name":"Sam","age":null,"nights":5,"parents":[]},{"name":"Jan","age":null,"nights":5,"parents":[]},{"name":"Mo","age":null,"nights":5,"parents":[]},{"name":"Lily","age":4,"nights":5,"parents":["Jan","Mo"]},{"name":"Max","age":12,"nights":5,"parents":["Jan","Mo"]},{"name":"Grandma Rose","age":null,"nights":5,"parents":[]},{"name":"Leo","age":null,"nights":2,"parents":[]}],"expenses":[{"kind":"lodging","what":"Cabin","amount":1850,"by":"Sam"},{"kind":"groceries","what":"Groceries","amount":420,"by":"Mo"},{"kind":"drinks","what":"Wine and beer","amount":180,"by":"Sam"}]}`;
const EXAMPLE2_IN = `Thanksgiving at Grandma June's on Nov 26. Hal bought the turkey and groceries, $260. Ivy brought wine, $70. Ivy's partner Cy is coming. Hal brings his kids, Ty (6) and Em (13).`;
const EXAMPLE2_OUT = `{"start":"11-26","nights":1,"host":"Grandma June","people":[{"name":"Grandma June","age":null,"nights":1,"parents":[]},{"name":"Hal","age":null,"nights":1,"parents":[]},{"name":"Ivy","age":null,"nights":1,"parents":[]},{"name":"Cy","age":null,"nights":1,"parents":[]},{"name":"Ty","age":6,"nights":1,"parents":["Hal"]},{"name":"Em","age":13,"nights":1,"parents":["Hal"]}],"expenses":[{"kind":"groceries","what":"Turkey and groceries","amount":260,"by":"Hal"},{"kind":"drinks","what":"Wine","amount":70,"by":"Ivy"}]}`;

/** The chat messages for the model: the rules, two worked examples, the chat. */
export function messages(chat) {
  return [
    { role: 'system', content: SYSTEM },
    { role: 'user', content: EXAMPLE_IN },
    { role: 'assistant', content: EXAMPLE_OUT },
    { role: 'user', content: EXAMPLE2_IN },
    { role: 'assistant', content: EXAMPLE2_OUT },
    { role: 'user', content: chat.trim() },
  ];
}

const KINDS = new Set(['lodging', 'groceries', 'drinks', 'other']);

/** The first JSON object in the model's text, or null. */
export function firstObject(text) {
  const s = String(text).replace(/<think>[\s\S]*?<\/think>/g, '');
  const from = s.indexOf('{');
  if (from < 0) return null;
  let depth = 0, inStr = false, esc = false;
  for (let i = from; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
    } else if (c === '"') inStr = true;
    else if (c === '{') depth++;
    else if (c === '}' && --depth === 0) {
      try { return JSON.parse(s.slice(from, i + 1)); } catch { return null; }
    }
  }
  return null;
}

const slug = (name) => String(name).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  .replace(/^(grandma|grandpa|uncle|aunt|auntie|cousin)\s+/, '').replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '') || 'p';
const num = (v) => {
  if (v == null || (typeof v === 'string' && !/\d/.test(v))) return null;
  const n = typeof v === 'number' ? v : Number(String(v ?? '').replace(/[$,\s]/g, ''));
  return Number.isFinite(n) ? n : null;
};

/** The first day: month-day, in the year it next comes after `today`, as YYYY-MM-DD. */
export function startDate(mmdd, today = new Date()) {
  const m = /^(\d{1,2})-(\d{1,2})$/.exec(String(mmdd ?? '').trim());
  if (!m) return null;
  const month = Number(m[1]), day = Number(m[2]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  const pad = (n) => String(n).padStart(2, '0');
  const y = today.getUTCFullYear();
  const thisYear = `${y}-${pad(month)}-${pad(day)}`;
  const todayIso = today.toISOString().slice(0, 10);
  return thisYear >= todayIso ? thisYear : `${y + 1}-${pad(month)}-${pad(day)}`;
}

/** Whether `name` (or one of its words, past a title: "Grandma Rose") is written in `chat`. */
export function named(chat, name) {
  if (chat == null) return true;
  const text = ` ${String(chat).toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ')} `;
  const words = String(name ?? '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim().split(' ')
    .filter((w) => w.length > 1 && !TITLES.has(w));
  return words.length > 0 && words.some((w) => text.includes(` ${w} `));
}
const TITLES = new Set(['grandma', 'grandpa', 'uncle', 'aunt', 'auntie', 'cousin']);

/** The dollar amounts written in `chat` ($1,850, $42.50), as numbers. */
export function amounts(chat) {
  return [...String(chat ?? '').matchAll(/\$\s?(\d[\d,]*(?:\.\d+)?)/g)].map((m) => Number(m[1].replace(/,/g, '')));
}

/**
 * The model's answer as the app's lists: {start, host, people, expenses,
 * notes}. People get ids from their names; a kid's parents and an
 * expense's payer must be people in the list (a payer the chat names but
 * the list misses is added as an adult). With the `chat`, the answer is
 * held to it: a person whose name isn't in the chat, or an amount that
 * isn't, is left out (a small model copies its examples), and an amount
 * the chat has but the lists miss is noted. Throws when there is nothing
 * to split: no people or no amounts.
 */
export function toTrip(answer, today = new Date(), chat = null) {
  if (!answer || typeof answer !== 'object') throw new Error('the model gave no JSON');
  const notes = [];
  const trip = Math.max(1, Math.round(num(answer.nights) ?? 1));
  const people = [];
  const byName = new Map();
  const idOf = (name) => byName.get(String(name ?? '').trim().toLowerCase())
    ?? byName.get(slug(name))
    ?? [...byName.entries()].find(([k]) => k.split(/\s+/).includes(String(name ?? '').trim().toLowerCase()))?.[1];
  const add = (name, age, nights) => {
    let id = slug(name);
    while (people.some((p) => p.id === id)) id += '_2';
    const p = { id, name: String(name).trim(), age, nights, drinks: age == null || age >= 21, guardians: [] };
    people.push(p);
    byName.set(p.name.toLowerCase(), id);
    byName.set(slug(p.name), id);
    return p;
  };
  for (const raw of Array.isArray(answer.people) ? answer.people : []) {
    const name = String(raw?.name ?? '').trim();
    if (!name || idOf(name)) continue;
    if (!named(chat, name)) { notes.push(`left out ${name}, who isn't in the chat`); continue; }
    let age = num(raw.age);
    if (age != null && (age < 0 || age > 120)) age = null;
    if (age != null && age >= 18) age = null; // the lists only keep kids' ages
    const nights = Math.min(trip, Math.max(1, Math.round(num(raw.nights) ?? trip)));
    const p = add(name, age, nights);
    p.parents = Array.isArray(raw.parents) ? raw.parents : [];
  }
  for (const p of people) {
    const parents = (p.parents || []).map(idOf).filter((id) => id && id !== p.id);
    if (p.age != null) {
      p.guardians = [...new Set(parents)].filter((id) => people.find((q) => q.id === id)?.age == null);
      if (!p.guardians.length) {
        p.age = null; // no adult to pay for them: counted as an adult
        notes.push(`${p.name} has no parent in the list, so counts as an adult`);
      }
      p.drinks = false;
    }
    delete p.parents;
  }
  const expenses = [];
  for (const raw of Array.isArray(answer.expenses) ? answer.expenses : []) {
    const amount = num(raw?.amount);
    if (amount == null || amount <= 0) continue;
    if (chat != null && !amounts(chat).includes(amount)) continue;
    let by = idOf(raw.by);
    if (!by && String(raw.by ?? '').trim() && named(chat, raw.by)) by = add(String(raw.by).trim(), null, trip).id;
    if (!by) { notes.push(`no one paid for ${raw.what ?? 'an expense'}, so it was left out`); continue; }
    const kind = KINDS.has(raw.kind) ? raw.kind : 'other';
    if (expenses.some((e) => e.amount === amount && e.by === by)) continue;
    expenses.push({ kind, what: String(raw.what ?? '').trim() || kind[0].toUpperCase() + kind.slice(1), amount: Math.round(amount * 100) / 100, by });
  }
  const missed = [...new Set(amounts(chat))].filter((a) => !expenses.some((e) => e.amount === a));
  if (chat != null && missed.length) {
    const many = missed.length > 1;
    notes.push(`${missed.map((a) => `$${a.toLocaleString('en-US')}`).join(', ')} ${many ? 'are' : 'is'} in the chat but not in the lists: add ${many ? 'them' : 'it'} below`);
  }
  if (!people.some((p) => p.age == null)) throw new Error('the model found no one to pay');
  if (!expenses.length) throw new Error('the model found no amounts spent');
  const host = idOf(answer.host) ?? expenses.find((e) => e.kind === 'lodging')?.by ?? people[0].id;
  const start = startDate(answer.start, today) ?? today.toISOString().slice(0, 10);
  if (!startDate(answer.start, today)) notes.push('no start date found, so it starts today');
  return { start, host, people, expenses, notes };
}
