// The trip reader's prompts and answers: what a model run on the device
// reads from a group chat (who comes, for how many nights, the kids' ages
// and parents, what was spent and by whom), as the lists the app shows.
// Two ways to ask, for the two models (see src/reader.js):
//   - one JSON answer, held to SCHEMA, for the browser's built-in model;
//   - three short passes (who comes, who stays fewer nights, who paid each
//     amount), for a smaller model run by transformers.js, which is far
//     more accurate on narrow questions than on one long answer.
// Either way toTrip holds the answer to the chat. No judgement here: who
// isn't paying and who doesn't drink are aityx's questions, and the split
// is the decision's. Used by the page, by reader-worker.js and by the tests.

const INTRO = "You read a family's group chat about a holiday trip and list the facts. Only facts written in the chat: never guess.";

const HEAD_RULES = `- start: the first day, as month-day numbers.
- nights: the nights of the whole trip; 1 for a dinner or a one-day event.
- host: who booked the place, or whose house it is.`;
const PEOPLE_RULE = `every person who comes, each once, with the name as the chat writes it, even one named only to say they don't drink or don't pay. Not someone the chat says isn't coming. A kid has the age the chat gives and the parents: the adults who bring them.`;
const KIND_RULE = `lodging is the place to stay, groceries is food, drinks is alcohol (wine, beer, champagne), other is anything else.`;

/** The system prompt for the one JSON answer. */
export const SYSTEM = `${INTRO}

Answer with one JSON object and nothing else:
{"start":"MM-DD","nights":N,"host":"Name","people":[{"name":"Name","age":null,"nights":N,"parents":[]}],"expenses":[{"kind":"lodging|groceries|drinks|other","what":"Short label","amount":0,"by":"Name"}]}
An adult's age is null and parents is [].

${HEAD_RULES}
- people: ${PEOPLE_RULE} Each person's nights are the trip's nights, fewer only for who comes late or leaves early (a night early: one fewer).
- expenses: every dollar amount in the chat, once each, with who paid it. ${KIND_RULE}`;

/** The JSON answer's schema, for a model that can be held to one (the Prompt API's responseConstraint). */
export const SCHEMA = {
  type: 'object',
  required: ['start', 'nights', 'host', 'people', 'expenses'],
  additionalProperties: false,
  properties: {
    start: { type: 'string', pattern: '^[0-9]{1,2}-[0-9]{1,2}$' },
    nights: { type: 'integer', minimum: 1 },
    host: { type: 'string' },
    people: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'age', 'nights', 'parents'],
        additionalProperties: false,
        properties: {
          name: { type: 'string' },
          age: { type: ['integer', 'null'] },
          nights: { type: 'integer', minimum: 1 },
          parents: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    expenses: {
      type: 'array',
      items: {
        type: 'object',
        required: ['kind', 'what', 'amount', 'by'],
        additionalProperties: false,
        properties: {
          kind: { type: 'string', enum: ['lodging', 'groceries', 'drinks', 'other'] },
          what: { type: 'string' },
          amount: { type: 'number' },
          by: { type: 'string' },
        },
      },
    },
  },
};

// Worked examples, none of them one of the app's stories. The third, where
// everyone stays the whole trip, is for the nights pass.
export const EXAMPLES = [
  {
    chat: `Christmas in a lodge near Aspen, 4 nights from Dec 22, $2,000. Greta booked it and paid. Hugo and Isla bring their son Jack (7). Kira arrives on the 24th, so only 2 nights. Nico heads home a night early. Hugo did the groceries, $350.25. Greta got the wine, $90. Isla doesn't drink. Kira paid for the sleigh ride, $160.`,
    answer: {
      start: '12-22', nights: 4, host: 'Greta',
      people: [
        { name: 'Greta', age: null, nights: 4, parents: [] },
        { name: 'Hugo', age: null, nights: 4, parents: [] },
        { name: 'Isla', age: null, nights: 4, parents: [] },
        { name: 'Jack', age: 7, nights: 4, parents: ['Hugo', 'Isla'] },
        { name: 'Kira', age: null, nights: 2, parents: [] },
        { name: 'Nico', age: null, nights: 3, parents: [] },
      ],
      expenses: [
        { kind: 'lodging', what: 'Lodge', amount: 2000, by: 'Greta' },
        { kind: 'groceries', what: 'Groceries', amount: 350.25, by: 'Hugo' },
        { kind: 'drinks', what: 'Wine', amount: 90, by: 'Greta' },
        { kind: 'other', what: 'Sleigh ride', amount: 160, by: 'Kira' },
      ],
    },
  },
  {
    chat: `Thanksgiving at Grandma Wren's on Nov 26. Wren made the turkey, $110. Otis brought beer, $36. Otis's partner Lark is coming with her daughters Fern (4) and Posy (13). Cousin Moss can't make it this year.`,
    answer: {
      start: '11-26', nights: 1, host: 'Grandma Wren',
      people: [
        { name: 'Grandma Wren', age: null, nights: 1, parents: [] },
        { name: 'Otis', age: null, nights: 1, parents: [] },
        { name: 'Lark', age: null, nights: 1, parents: [] },
        { name: 'Fern', age: 4, nights: 1, parents: ['Lark'] },
        { name: 'Posy', age: 13, nights: 1, parents: ['Lark'] },
      ],
      expenses: [
        { kind: 'groceries', what: 'Turkey', amount: 110, by: 'Grandma Wren' },
        { kind: 'drinks', what: 'Beer', amount: 36, by: 'Otis' },
      ],
    },
  },
  {
    chat: `New Year's at a chalet in Stowe, 3 nights from Dec 30, $1,500, on Bram's card. It's Bram, Cleo and Dax. Cleo bought the food, $210. Dax got the champagne, $75.`,
    answer: {
      start: '12-30', nights: 3, host: 'Bram',
      people: [
        { name: 'Bram', age: null, nights: 3, parents: [] },
        { name: 'Cleo', age: null, nights: 3, parents: [] },
        { name: 'Dax', age: null, nights: 3, parents: [] },
      ],
      expenses: [
        { kind: 'lodging', what: 'Chalet', amount: 1500, by: 'Bram' },
        { kind: 'groceries', what: 'Food', amount: 210, by: 'Cleo' },
        { kind: 'drinks', what: 'Champagne', amount: 75, by: 'Dax' },
      ],
    },
  },
];

/** The messages for the one JSON answer: the rules, two worked examples, the chat. */
export function messages(chat) {
  return [
    { role: 'system', content: SYSTEM },
    ...EXAMPLES.slice(0, 2).flatMap((e) => [
      { role: 'user', content: e.chat },
      { role: 'assistant', content: JSON.stringify(e.answer) },
    ]),
    { role: 'user', content: chat.trim() },
  ];
}

const unthought = (text) => String(text).replace(/<think>[\s\S]*?<\/think>/g, '');

/** The first JSON object in the model's text, or null. */
export function firstObject(text) {
  const s = unthought(text);
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

// The three passes: each has its rules, its own short form, and how the
// worked examples look in it.
const PASSES = {
  people: {
    examples: [0, 1],
    system: `${INTRO}

List who comes, in exactly this form and nothing else:
start: MM-DD
nights: N
host: Name
people:
Name | adult
Name | AGE | Parent, Parent

${HEAD_RULES}
- people: ${PEOPLE_RULE} One person per line.`,
    user: (chat) => chat,
    answer: (a) => [`start: ${a.start}`, `nights: ${a.nights}`, `host: ${a.host}`, 'people:',
      ...a.people.map((p) => (p.age == null ? `${p.name} | adult` : `${p.name} | ${p.age} | ${p.parents.join(', ')}`))].join('\n'),
  },
  nights: {
    examples: [0, 2],
    system: `${INTRO}

List only the people who stay fewer nights than the whole trip, because they come late or leave early, one per line, in this form and nothing else:
Name | NIGHTS

- Someone who leaves a night early stays one night fewer than the trip.
- Someone who arrives late stays only the nights that are left.
- If everyone stays the whole trip, answer: everyone`,
    user: (chat, ctx) => `${chat}\n\nThe trip is ${ctx.nights} nights. The people: ${ctx.names.join(', ')}.`,
    answer: (a) => {
      const few = a.people.filter((p) => p.nights < a.nights);
      return few.length ? few.map((p) => `${p.name} | ${p.nights}`).join('\n') : 'everyone';
    },
  },
  expenses: {
    examples: [0, 1],
    system: `${INTRO}

For each dollar amount in the chat, one line, in this form and nothing else:
AMOUNT | KIND | Short label | Name

- KIND is lodging, groceries, drinks or other: ${KIND_RULE}
- Name is who paid it.`,
    user: (chat, ctx) => `${chat}\n\nThe amounts: ${ctx.amounts.join(', ')}.`,
    answer: (a) => a.expenses.map((e) => `${e.amount} | ${e.kind} | ${e.what} | ${e.by}`).join('\n'),
  },
};

/** The messages of one pass ("people", "nights" or "expenses"): its rules, its worked examples, the chat. */
export function passMessages(pass, chat, ctx = {}) {
  const p = PASSES[pass];
  return [
    { role: 'system', content: p.system },
    ...p.examples.map((i) => EXAMPLES[i]).flatMap((e) => [
      { role: 'user', content: p.user(e.chat, { nights: e.answer.nights, names: e.answer.people.map((x) => x.name), amounts: amounts(e.chat) }) },
      { role: 'assistant', content: p.answer(e.answer) },
    ]),
    { role: 'user', content: p.user(chat.trim(), ctx) },
  ];
}

const lines = (text) => unthought(text).split('\n').map((l) => l.replace(/^[\s\-*•]+/, '').trim()).filter(Boolean);
const cells = (line) => line.split('|').map((c) => c.trim());
const names = (text) => String(text ?? '').split(/,|\band\b|\+/).map((x) => x.trim()).filter(Boolean);

/** The people pass's text: {start, nights, host, people: [{name, age, parents}]}. */
export function readPeople(text) {
  const out = { people: [] };
  for (const line of lines(text)) {
    const head = /^(start|nights|host|people)\s*:\s*(.*)$/i.exec(line);
    if (head && !line.includes('|')) {
      if (head[1].toLowerCase() !== 'people') out[head[1].toLowerCase()] = head[2].trim();
      continue;
    }
    // A person's line, with or without the "people:" line before it.
    const c = cells(line);
    if (c[0] && c.length >= 2) out.people.push({ name: c[0], age: /^\d+$/.test(c[1]) ? Number(c[1]) : null, parents: names(c[2]) });
  }
  return out;
}

/** The nights pass's text: a Map of name, in lower case, to nights. */
export function readNights(text) {
  const out = new Map();
  for (const line of lines(text)) {
    const c = cells(line);
    const n = Number(String(c[1] ?? '').replace(/[^\d]/g, ''));
    if (c[0] && c.length >= 2 && n > 0) out.set(c[0].toLowerCase(), n);
  }
  return out;
}

/** The expenses pass's text: [{amount, kind, what, by}]. */
export function readExpenses(text) {
  return lines(text).map(cells).filter((c) => c.length >= 4).map((c) => ({ amount: c[0], kind: c[1].toLowerCase(), what: c[2], by: c[3] }));
}

/**
 * Reads `chat` in three passes with `ask(messages) => text`, and gives the
 * same answer object the one JSON answer has, for toTrip. The nights pass
 * is skipped for a one-day event, the expenses pass without amounts.
 */
export async function readInPasses(chat, ask) {
  const head = readPeople(await ask(passMessages('people', chat)));
  const nights = Math.max(1, Math.round(tripNights(chat) ?? (Number(String(head.nights ?? '').replace(/[^\d]/g, '')) || 1)));
  const who = head.people.map((p) => p.name);
  const fewer = nights > 1 && who.length ? readNights(await ask(passMessages('nights', chat, { nights, names: who }))) : new Map();
  const spent = amounts(chat);
  const expenses = spent.length ? readExpenses(await ask(passMessages('expenses', chat, { amounts: spent }))) : [];
  const nightsOf = (name) => {
    const key = name.toLowerCase();
    return fewer.get(key) ?? [...fewer].find(([k]) => key.split(/\s+/).includes(k) || k.split(/\s+/).includes(key))?.[1] ?? nights;
  };
  return { start: head.start, nights, host: head.host, people: head.people.map((p) => ({ ...p, nights: nightsOf(p.name) })), expenses };
}

const KINDS = new Set(['lodging', 'groceries', 'drinks', 'other']);

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

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** The dates the chat writes ("Dec 23", "december 23rd", "12/23"), in order, as MM-DD. */
export function dates(chat) {
  const text = String(chat ?? '');
  const found = [];
  for (const m of text.matchAll(/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?!\s*(?:nights?|days?|people|adults|kids|of us))/gi)) {
    found.push([m.index, `${MONTHS.indexOf(m[1].toLowerCase()) + 1}-${Number(m[2])}`]);
  }
  for (const m of text.matchAll(/(?<![\d$/.])(\d{1,2})\/(\d{1,2})(?![\d/])/g)) found.push([m.index, `${Number(m[1])}-${Number(m[2])}`]);
  return found.sort((x, y) => x[0] - y[0]).map(([, d]) => d).filter((d) => startDate(d, new Date(Date.UTC(2000, 0, 1))) !== null);
}

/** The trip's nights when the chat counts them ("5 nights from Dec 23"): the most it says, or null. */
export function tripNights(chat) {
  const all = [...String(chat ?? '').matchAll(/\b(\d{1,2})\s+nights?\b/gi)].map((m) => Number(m[1])).filter((n) => n > 0);
  return all.length ? Math.max(...all) : null;
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
 * The ages the chat writes in brackets after names, by name in lower
 * case: "Lily (4), Max (12)", and "the twins, Ari and Eli (7)", where one
 * age is for both (only right after "twins", "kids" and the like: in
 * "Kim and Leo (10)", Kim is no kid).
 */
export function ages(chat) {
  const text = String(chat ?? '');
  const found = new Map();
  const name = "\\p{Lu}[\\p{L}'-]*";
  const pattern = new RegExp(`((?:${name}(?:,\\s*|\\s+and\\s+))*)(${name})\\s*\\((\\d{1,2})\\)`, 'gu');
  for (const m of text.matchAll(pattern)) {
    const age = Number(m[3]);
    found.set(m[2].toLowerCase(), age);
    if (!/(twins|kids|sons|daughters|children|boys|girls|grandkids)[,:]?\s+$/i.test(text.slice(0, m.index))) continue;
    for (const n of m[1].matchAll(new RegExp(name, 'gu'))) {
      const key = n[0].toLowerCase();
      if (!found.has(key)) found.set(key, age);
    }
  }
  return found;
}

/** Whether the chat gives `age` right after `name`: "eli who's 9", "Sami, 14". Not "Leo ... 2 nights". */
function agedInChat(chat, name, age) {
  const word = String(name).trim().split(/\s+/).at(-1).replace(/[^\p{L}'-]/gu, '');
  if (!word) return false;
  return new RegExp(`(?<![\\p{L}])${word}(?![\\p{L}])[^.\\d$]{0,20}(?<![\\d$.,])${age}(?![\\d.,]*\\d|\\s*(?:nights?|days?|st|nd|rd|th)\\b)`, 'iu').test(chat);
}

/** The chat's sentences. */
const sentences = (chat) => String(chat ?? '').split(/(?<=[.!?;])\s+|\n+/).map((x) => x.trim()).filter(Boolean);

/** Where `name` (its last word: "Rose" of "Grandma Rose") is written in `text`: each index. */
function mentions(text, name) {
  const word = String(name).trim().split(/\s+/).at(-1).replace(/[^\p{L}'-]/gu, '');
  if (!word) return [];
  return [...text.matchAll(new RegExp(`(?<![\\p{L}])${word}(?![\\p{L}])`, 'giu'))].map((m) => m.index);
}

/**
 * Who stays fewer nights than the trip's `trip`, as the chat's own words
 * say it, by id: the people named in a sentence that counts nights ("Leo
 * only makes it for the last 2 nights, and Tess comes with him"), says "a
 * night early", or gives the day someone arrives or leaves ("Ruth arrives
 * on the 30th", from the trip's `start`, YYYY-MM-DD). No model.
 */
export function nightsInChat(chat, people, trip, start) {
  const out = new Map();
  if (trip < 2) return out;
  const day0 = Date.parse(`${start}T00:00:00Z`);
  // The days from the start to "the 25th": this month, or the next when the day is before the start's.
  const until = (day) => {
    const first = new Date(day0);
    return Math.round((Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + (day < first.getUTCDate() ? 1 : 0), day) - day0) / 864e5);
  };
  const set = (who, nights) => { if (nights >= 1 && nights < trip) for (const person of who) out.set(person.id, nights); };
  for (const sentence of sentences(chat)) {
    const named = people.flatMap((person) => mentions(sentence, person.name).map((i) => [i, person])).sort((x, y) => x[0] - y[0]);
    if (!named.length) continue;
    const all = [...new Set(named.map(([, person]) => person))];
    // A whole stay's count stays in, to tell whose the shorter one is: in "Alice stays 2 nights but Bob
    // stays all 4", Bob's 4 (set() keeps no full stay). A sentence with only full stays counts none.
    const counts = [...sentence.matchAll(/\b(\d{1,2})\s+nights?\b/gi)].map((m) => [m.index, Number(m[1])]).filter(([, n]) => n <= trip);
    const short = counts.filter(([, n]) => n < trip);
    if (counts.length === 1 && short.length) set(all, counts[0][1]);
    else if (short.length) {
      // "Leo 2 nights and Tess 3": each count is for the people named since the count before it.
      let from = 0;
      counts.forEach(([i, n], k) => {
        const to = k === counts.length - 1 ? Infinity : i;
        set(named.filter(([j]) => j >= from && j < to).map(([, person]) => person), n);
        from = i;
      });
    } else {
      const early = /\b(a|one|1|two|2)\s+(?:nights?|days?)\s+early\b/i.exec(sentence);
      const leaves = /\b(?:leav\w*|head\w*\s+(?:home|back|out)|go(?:es|ing)?\s+home|check\w*\s+out)\b[^.]*?\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b/i.exec(sentence);
      const arrives = /\b(?:arriv\w*|join\w*|com(?:e|es|ing)|driv\w*\s+up|fl(?:y|ies|ying)\s+in|get(?:s|ting)?\s+(?:in|there)|show\w*\s+up)\b[^.]*?\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b/i.exec(sentence);
      if (early) set(all, trip - (/^(two|2)$/i.test(early[1]) ? 2 : 1));
      else if (leaves) set(all, until(Number(leaves[1])));
      else if (arrives) set(all, trip - until(Number(arrives[1])));
    }
  }
  return out;
}

/** Whether a sentence that names `person` talks of coming late or leaving early: then a model may say they stay fewer nights. */
function mayStayLess(chat, person) {
  return sentences(chat).some((sentence) => mentions(sentence, person.name).length
    && /\b(nights?|early|late|arriv\w*|leav\w*|join\w*|until|only|last|first|heads?|driv\w*|fl(?:y|ies|ying)|makes?\s+it|comes?\s+(?:on|for))\b/i.test(sentence));
}

const TITLE = '(?:grandma|grandpa|uncle|aunt|auntie|cousin)';

const NOT_COMING = /\b(?:can['’]?t|cannot|won['’]?t|isn['’]?t|is\s+not|not|aren['’]?t)\s+(?:make\s+it|come|coming|be\s+(?:there|coming|joining)|join(?:ing)?)\b(?!\s+(?:for|until|till|before|on|the)\b)|\bmight\s+come\b|\bhasn['’]?t\s+confirmed\b|\bdon['’]?t\s+count\b/i;

/** Where a sentence turns to someone else: "Alice is coming but Bob can't come". */
const CONTRAST = /\b(?:but|while|whereas|although|though|however|yet)\b/i;

const COMING = /\b(?:is|are|will)\s+(?:coming|come|joining|be\s+there)\b|\b(?:comes|joins|arrives)\b/gi;

/**
 * Whether a clause says `person` isn't coming: it names them and says no one comes, and doesn't
 * say first that they do ("Alice is coming and Bob cannot come" says it of Bob, not Alice).
 */
function saysNotComing(clause, person) {
  const at = mentions(clause, person.name), no = NOT_COMING.exec(clause);
  return at.length > 0 && !!no && !at.some((i) => i < no.index && [...clause.slice(i, no.index).matchAll(COMING)].length);
}

/** Whether the chat names `person` only to say they aren't coming: "Cousin Gil can't make it". No model. */
export function notComing(chat, person) {
  const about = sentences(chat).filter((sentence) => mentions(sentence, person.name).length);
  return about.length > 0 && about.every((sentence) => sentence.split(CONTRAST).some((clause) => saysNotComing(clause, person)));
}

const NOT_NAMES = new Set(['everyone', 'everybody', 'all', 'kids', 'me', 'us', 'them', 'you', 'we', 'i', 'he', 'she', 'they', 'others', 'family', 'friends', 'the', 'rest', 'more', 'co']);

/**
 * The names the chat lists together with people already known, who aren't
 * known themselves: in "It's Hal, Ines, Jax, Kay and Lon", Hal and Jax,
 * when the model listed the other three. Only single names (or a title and
 * a name), written with a capital when the known ones are. No model.
 */
export function listedWith(chat, people) {
  const known = (word) => people.some((person) => mentions(word, person.name).length);
  const word = `(?:${TITLE}\\s+)?[\\p{L}'’-]+`;
  const found = [];
  for (const sentence of sentences(chat)) {
    for (const list of sentence.matchAll(new RegExp(`(?:${word},\\s*)+${word},?\\s+and\\s+${word}`, 'giu'))) {
      const items = list[0].split(/,\s*and\s+|\s+and\s+|,\s*/).map((item) => item.replace(/['’]s$/, '').trim()).filter(Boolean);
      const knownItems = items.filter(known);
      if (knownItems.length < 2) continue;
      const capitals = knownItems.some((item) => /^\p{Lu}/u.test(item));
      for (const item of items) {
        const last = item.split(/\s+/).at(-1);
        if (known(item) || last.length < 2 || NOT_NAMES.has(last.toLowerCase())) continue;
        if (capitals && !/^\p{Lu}/u.test(last)) continue;
        if (!found.includes(item)) found.push(item);
      }
    }
  }
  return found;
}

/**
 * The parents of each kid (a person with an age), as the chat's own words
 * say it, by id: the adults named before the kid in the kid's sentence.
 * "Jo's daughter Mia": Jo. "Lark is coming with her daughters Fern and
 * Posy": Lark. "Oren's wife Uma and their baby Vic": both. "Jan and Mo
 * are bringing the kids, Lily, Max and Zoe": the adults listed together.
 * A kid whose sentence names no adult before it isn't in the map. No model.
 */
export function parentsInChat(chat, people) {
  const out = new Map();
  const adults = people.filter((person) => person.age == null);
  const kids = people.filter((person) => person.age != null);
  for (const sentence of sentences(chat)) {
    const kidsAt = kids.flatMap((kid) => mentions(sentence, kid.name).slice(0, 1).map((i) => [i, kid])).sort((x, y) => x[0] - y[0]);
    if (!kidsAt.length) continue;
    const adultsAt = adults.flatMap((adult) => mentions(sentence, adult.name).map((i) => [i, adult])).sort((x, y) => x[0] - y[0]);
    let group = null;
    let from = 0;
    for (const [i, kid] of kidsAt) {
      // The adults named since the kid before: none means this kid is one more of the same parents'.
      const before = adultsAt.filter(([j]) => j >= from && j < i);
      if (before.length) group = parentsBefore(sentence, before, i);
      if (group?.length) out.set(kid.id, [...new Set(group.map((adult) => adult.id))]);
      from = i;
    }
  }
  return out;
}

function parentsBefore(sentence, before, kidAt) {
  const [at, nearest] = before.at(-1);
  const tail = sentence.slice(at, kidAt);
  // "Jo's daughter ": at most two words between the name's and the kid.
  if (/^[\p{L}-]+['’]s\s+(?:[\p{L}-]+\s+){0,2}$/u.test(tail)) return [nearest];
  if (/\b(?:his|her)\b/i.test(tail)) return [nearest];
  if (/\btheir\b/i.test(tail)) return before.slice(-2).map(([, adult]) => adult);
  // The adults listed together, ending with the nearest: "Jan and Mo", "Dev, Maya and Uncle Ray".
  const group = [nearest];
  for (let k = before.length - 2; k >= 0; k--) {
    const gap = sentence.slice(before[k][0], before[k + 1][0]).replace(/^[\p{L}'’-]+/u, '');
    if (!new RegExp(`^\\s*(?:,|and|&|,\\s*and)?\\s*${TITLE}?\\s*$`, 'i').test(gap)) break;
    group.unshift(before[k][1]);
  }
  return group;
}

// A word that names someone: someone already known, or a capitalized word that isn't a common one.
const NAME = "[\\p{L}][\\p{L}'’-]*";
const KID = '(?:sons?|daughters?|kids?|child|children|twins|baby|boys?|girls?|grandsons?|granddaughters?|grandkids)';
const PAID = '(?:made|makes|bought|buys|brought|brings|got|gets|paid|pays|did|does|covered|covers|picked|grabbed|cooked|booked|ordered|took|spent|put)';
const isName = (word, people) => {
  const last = String(word).trim().split(/\s+/).at(-1).replace(/['’]s$/, '');
  if (people.some((person) => mentions(last, person.name).length)) return true;
  return /^\p{Lu}/u.test(last) && last.length > 1 && !NOT_NAMES.has(last.toLowerCase()) && !NOT_SUBJECTS.has(last.toLowerCase());
};
/** Whether the model's `name` could be a person's: a word or two, not "Hal's kids" or "the twins". */
const personLike = (name) => {
  const words = String(name ?? '').trim().split(/\s+/);
  return words.length >= 1 && words.length <= 3 && !/['’]s$/.test(words[0]) && !words.some((w) => new RegExp(`^${KID}$`, 'i').test(w) || NOT_NAMES.has(w.toLowerCase()));
};
const NOT_SUBJECTS = new Set(['it', 'who', 'that', 'this', 'someone', 'somebody', 'nobody', 'then', 'also', 'and', 'but', 'so', 'if', 'christmas', 'thanksgiving', 'friendsgiving', 'new', 'year', 'eve', 'airbnb', 'costco']);

/**
 * The adults the chat says bring kids, as it names them: the one before
 * "brings his kids" or "is coming with her daughter", and the one in "Jo's
 * daughter". They come too, whether or not the model listed them. No model.
 */
export function bringers(chat, people = []) {
  const found = [];
  const take = (name) => { if (isName(name, people) && !found.includes(name)) found.push(name); };
  const text = String(chat ?? '');
  for (const m of text.matchAll(new RegExp(`(?<![\\p{L}'’-])((?:${TITLE}\\s+)?${NAME})\\s+(?:is\\s+|are\\s+)?(?:brings?|bringing|comes?\\s+with|coming\\s+with)\\s+(?:his|her|their|the)\\s+(?:\\p{L}+\\s+)?${KID}\\b`, 'giu'))) take(m[1]);
  for (const m of text.matchAll(new RegExp(`(?<![\\p{L}'’-])((?:${TITLE}\\s+)?${NAME})['’]s\\s+(?:\\p{L}+\\s+)?${KID}\\b`, 'giu'))) take(m[1]);
  return found;
}

// Words of alcohol: what's drunk, kinds of it, and where it's bought or served.
const DRINKS = /\b(?:wines?|beers?|champagne|prosecco|cava|bubbly|drinks?|booze|boozy|alcohol|liquor|spirits|eggnog|nog|whiske?y|bourbon|scotch|brandy|cognac|rum|gin|vodka|tequila|mezcal|sake|soju|cider|ales?|lagers?|ipas?|stouts?|kegs?|six[- ]packs?|cocktails?|margaritas?|sangria|mimosas?|martinis?|mojitos?|negronis?|spritz(?:es)?|hard\s+seltzers?|merlot|cabernet|chardonnay|pinot|riesling|malbec|ros[ée]|sauvignon|zinfandel|shiraz|chianti|toddy|toddies|mulled|spiked|bar\s+tab|open\s+bar|the\s+bar|minibar|pub|brewery|winery|happy\s+hour)\b/i;
// "Isla doesn't drink" is about a person, not an amount.
const NO_DRINK = /\b(?:doesn['’]?t|don['’]?t|not|never|won['’]?t|can['’]?t|isn['’]?t)\s+(?:a\s+)?drink(?:s|ing|er)?\b/gi;
// The words right after an amount that are still about it: "$85 for beer and wine" up to the next clause.
const tailOf = (after) => { const i = after.search(/[,;!?(]|\.(?:\s|$)|\s(?:and|but|while|so|plus)\s/); return i < 0 ? after : after.slice(0, i); };
const FOOD = /\b(?:grocer(?:y|ies)|food|turkey|ham|pies?|sides|desserts?|snacks|cooked|breakfast|brunch|bbq|meat|veggies|bread)\b/i;
const PLACE = /\b(?:nights?|cabin|house|lodge|chalet|airbnb|loft|hotel|condo|cottage|farmhouse|villa|apartment|booked)\b/i;

/**
 * Each dollar amount of the chat, in its order, with what the words around
 * it settle: {amount, by, drinks, kind, what}. `by` is who paid, as the
 * chat names them, or null: the one before the amount with a verb ("Mo did
 * the grocery run, $420"), else the one who booked or paid right after
 * ("$2,450. Sam booked it and paid", "$4,200, on Hana's card"). `drinks`
 * is whether the words about it are of alcohol: those between the amount
 * before and this one, the few right after it ("$85 for beer"), and, when
 * those say nothing of what it was, the sentence before ("Leo picked up
 * the wine. It was $90."). `plain` is whether those words say nothing of
 * what it was (no drinks, food or place). `kind` and `what` are a guess,
 * for an amount the model missed or labeled with words that aren't in its
 * `clause`. No model.
 */
export function spending(chat, people = []) {
  const text = String(chat ?? '');
  const ends = [0, ...[...text.matchAll(/[.!?;]\s+|\n+/g)].map((m) => m.index + m[0].length), text.length];
  // Someone, then within a few words a verb of paying or bringing: every such pair, even overlapping.
  const subject = new RegExp(`(?<![\\p{L}'’-])(?=((?:${TITLE}\\s+)?${NAME})\\s+((?:[^\\s,.;:$()]+\\s+){0,3}?)(${PAID})\\b)`, 'giu');
  const last = (pattern, where) => [...where.matchAll(pattern)].filter((m) => isName(m[1], people)).at(-1);
  const out = [];
  let from = 0;
  let previous = null; // The amount before, when it's in the same sentence: [its sentence's start, who paid it].
  for (const m of text.matchAll(/\$\s?(\d[\d,]*(?:\.\d+)?)/g)) {
    const start = ends.filter((e) => e <= m.index).at(-1);
    const end = ends.find((e) => e > m.index + m[0].length - 1) ?? text.length;
    const before = text.slice(Math.max(start, from), m.index);
    const after = text.slice(m.index + m[0].length, end);
    const next = text.slice(end, ends.find((e) => e > end) ?? text.length);
    const said = last(subject, before);
    // "Aunt Cora brought": the name with its title, though "Cora brought" matches too.
    const title = said && new RegExp(`(${TITLE})\\s+$`, 'i').exec(before.slice(0, said.index));
    if (title) said[1] = `${title[1]} ${said[1]}`;
    const card = new RegExp(`\\bon\\s+((?:${TITLE}\\s+)?${NAME})['’]s\\s+card\\b`, 'giu');
    const paid = new RegExp(`(?<![\\p{L}'’-])((?:${TITLE}\\s+)?${NAME})\\s+(?:also\\s+)?(?:paid|put|covered)\\b`, 'giu');
    const booked = new RegExp(`(?<![\\p{L}'’-])((?:${TITLE}\\s+)?${NAME})\\s+(?:booked|got|reserved)\\b`, 'giu');
    // After the amount, only when no one is before it; a later amount's own payer isn't this one's.
    const then = after.includes('$') ? '' : after;
    const by = said?.[1]
      // "Cora brought the sides, $60, and the wine, $54": the second is Cora's too.
      ?? (previous && previous[0] === start ? previous[1] : null)
      ?? [card, paid, booked].map((pattern) => last(pattern, then)).find(Boolean)?.[1]
      ?? (then === after && !/\$/.test(next) ? [paid, card, booked].map((pattern) => last(pattern, next)).find(Boolean)?.[1] : null)
      ?? null;
    const words = said ? before.slice(before.indexOf(said[3], said.index) + said[3].length) : before;
    const tail = tailOf(after);
    const says = (s) => DRINKS.test(s.replace(NO_DRINK, '')) || FOOD.test(s) || PLACE.test(s);
    let about = `${before} ${tail}`;
    // Nothing about what it was, and no amount before it in its sentence: the sentence before says it.
    if (!says(about) && start >= from) {
      const prev = text.slice(ends.filter((e) => e < start).at(-1) ?? start, start);
      if (!prev.includes('$')) about = `${prev} ${about}`;
    }
    const drinks = DRINKS.test(about.replace(NO_DRINK, ''));
    const plain = !says(about);
    const kind = drinks ? 'drinks' : FOOD.test(words) ? 'groceries' : PLACE.test(words) && !said ? 'lodging' : said ? 'other' : 'lodging';
    const label = words.replace(/^[\s,]*(?:for\s+|up\s+|in\s+)?(?:(?:the|a|an|some|everyone['’]s|our)\s+)?/i, '').replace(/[\s,:(]+$/, '').replace(/\s+on\s+the\s+\d+\w*$/i, '');
    // "Ana booked it, $1,200": "it" says nothing, so the label is the kind's (`generic`).
    const generic = !(said && label && label.length <= 40) || /^(?:it|them|this|that|these|those|both|everything|all|one)$/i.test(label);
    const what = generic ? kind[0].toUpperCase() + kind.slice(1) : label[0].toUpperCase() + label.slice(1);
    out.push({ amount: Number(m[1].replace(/,/g, '')), by, drinks, plain, kind, what, generic, clause: `${before} ${tail}`, start });
    from = m.index + m[0].length;
    previous = [start, by];
  }
  // "$3,600, plus the loft, $640. Priya booked both and paid": the first is Priya's too.
  for (let i = out.length - 2; i >= 0; i--) {
    if (out[i].by === null && out[i + 1].start === out[i].start) out[i].by = out[i + 1].by;
  }
  return out.map(({ start, ...rest }) => rest);
}

/** Whose place the chat's first sentence says it is ("Thanksgiving at Grandma June's on Nov 26"), or null: they come too. No model. */
export function atWhose(chat, people = []) {
  const first = sentences(chat)[0] ?? '';
  return [...first.matchAll(new RegExp(`\\bat\\s+((?:${TITLE}\\s+)?${NAME})['’]s(?![\\p{L}])`, 'giu'))].map((m) => m[1]).find((name) => isName(name, people)) ?? null;
}

/** The host as the chat names them, or null: "at Mom's", "Hal's name is on the booking", "Sam booked it". No model. */
export function hostInChat(chat, people = []) {
  const text = String(chat ?? '');
  const find = (pattern) => [...text.matchAll(pattern)].map((m) => m[1]).find((name) => isName(name, people)) ?? null;
  return find(new RegExp(`\\bat\\s+((?:${TITLE}\\s+)?${NAME})['’]s(?![\\p{L}])`, 'giu'))
    ?? find(new RegExp(`(?<![\\p{L}'’-])((?:${TITLE}\\s+)?${NAME})['’]s\\s+name\\s+is\\s+on\\s+the\\s+booking`, 'giu'))
    ?? find(new RegExp(`(?<![\\p{L}'’-])((?:${TITLE}\\s+)?${NAME})\\s+(?:booked|rented|reserved)\\b`, 'giu'));
}

/**
 * The model's answer as the app's lists: {start, host, people, expenses,
 * notes}. People get ids from their names; a kid's parents and an
 * expense's payer must be people in the list (a payer the chat names but
 * the list misses is added as an adult). With the `chat`, the answer is
 * held to it: a person whose name isn't in the chat, or an amount that
 * isn't, is left out (a small model copies its examples); what the chat's
 * own words settle wins over the model's (an age in brackets, the trip's
 * nights and first day, a kid's parents, who comes late or leaves early,
 * who isn't coming, who is listed with the others or brings kids, who paid
 * an amount, whether it's drinks, the host); and an amount the chat has
 * but the lists still miss is noted. Throws when
 * there is nothing to split: no people or no amounts.
 */
export function toTrip(answer, today = new Date(), chat = null) {
  if (!answer || typeof answer !== 'object') throw new Error('nothing readable came back');
  const notes = [];
  // The nights the chat counts win over the model's.
  const trip = Math.max(1, Math.round(tripNights(chat) ?? num(answer.nights) ?? 1));
  const written = chat == null ? new Map() : ages(chat);
  const people = [];
  const byName = new Map();
  const idOf = (name) => byName.get(String(name ?? '').trim().toLowerCase())
    ?? byName.get(slug(name))
    ?? [...byName.entries()].find(([k]) => k.split(/\s+/).includes(String(name ?? '').trim().toLowerCase()))?.[1];
  const add = (name, age, nights) => {
    let id = slug(name);
    while (people.some((p) => p.id === id)) id += '_2';
    const p = { id, name: String(name).trim(), age, nights, drinks: age == null, guardians: [] };
    people.push(p);
    byName.set(p.name.toLowerCase(), id);
    byName.set(slug(p.name), id);
    return p;
  };
  for (const raw of Array.isArray(answer.people) ? answer.people : []) {
    const name = String(raw?.name ?? '').trim();
    if (!name || idOf(name) || !personLike(name)) continue;
    if (!named(chat, name)) continue; // A name the model made up, or took from its examples.
    // The age the chat writes in brackets, else the model's when the chat
    // gives it right after the name (a small model makes ages up).
    let age = written.get(name.toLowerCase().split(/\s+/).at(-1)) ?? num(raw.age);
    if (age != null && chat != null && !written.has(name.toLowerCase().split(/\s+/).at(-1)) && !agedInChat(chat, name, age)) age = null;
    // The lists keep an age below 21 (kids, and who can't drink yet).
    if (age != null && (age < 0 || age >= 21)) age = null;
    const nights = Math.min(trip, Math.max(1, Math.round(num(raw.nights) ?? trip)));
    const p = add(name, age, nights);
    p.parents = Array.isArray(raw.parents) ? raw.parents : [];
  }
  // The adults a kid's line names as parents, and the names the chat lists
  // with the others, are people too, when the model's list missed them.
  for (const p of [...people]) {
    for (const parent of p.parents) {
      if (personLike(parent) && !idOf(parent) && chat != null && named(chat, parent)) add(String(parent).trim(), null, trip).parents = [];
    }
  }
  if (chat != null) {
    for (const name of [atWhose(chat, people), ...bringers(chat, people), ...listedWith(chat, people)]) {
      if (name && !idOf(name)) add(name, null, trip).parents = [];
    }
    // A kid the chat gives an age in brackets, as it writes the name.
    for (const [kid, age] of written) {
      const as = new RegExp(`(?<![\\p{L}])${kid}(?![\\p{L}])`, 'iu').exec(chat)?.[0];
      if (as && !idOf(kid) && age < 21) add(as, age, trip).parents = [];
    }
  }
  // What the chat's words settle about each amount: who paid, and whether it's drinks.
  const spent = chat == null ? [] : spending(chat, people);
  const used = new Set();
  const settled = (amount) => {
    const i = spent.findIndex((x, k) => x.amount === amount && !used.has(k));
    if (i < 0) return null;
    used.add(i);
    return spent[i];
  };
  const payer = (name) => idOf(name) ?? (personLike(name) && String(name ?? '').trim() && named(chat, name) ? Object.assign(add(String(name).trim(), null, trip), { parents: [] }).id : null);
  const inChat = amounts(chat);
  const times = (list, amount) => list.filter((a) => a === amount).length;
  const expenses = [];
  for (const raw of Array.isArray(answer.expenses) ? answer.expenses : []) {
    const amount = num(raw?.amount);
    if (amount == null || amount <= 0) continue;
    // An amount as many times as the chat writes it, and no more.
    const taken = times(expenses.map((e) => e.amount), amount);
    if (chat != null ? taken >= times(inChat, amount) : expenses.some((e) => e.amount === amount && e.by === idOf(raw.by))) continue;
    const said = settled(amount);
    const by = (said?.by ? payer(said.by) : null) ?? payer(raw.by);
    if (!by) { notes.push(`no one paid for ${raw.what ?? 'an expense'}, so it was left out`); continue; }
    // Drinks when the chat's words about it are of alcohol; the model's "drinks" stands only when those
    // words say nothing of what it was (no food, no place), and never against them.
    let kind = KINDS.has(raw.kind) ? raw.kind : 'other';
    if (said) kind = said.drinks ? 'drinks' : kind === 'drinks' && !said.plain ? said.kind : kind;
    // The model's label, unless none of its words is in the chat's words about this amount; when those
    // words say nothing ("Ana booked it, $1,200"), unless none is in the chat at all.
    let what = String(raw.what ?? '').trim();
    const inWords = (where) => what.toLowerCase().split(/[^\p{L}]+/u).some((w) => w.length > 2 && where.toLowerCase().includes(w));
    if (said && !inWords(said.clause) && !(said.generic && chat != null && inWords(chat))) what = said.what;
    expenses.push({ kind, what: what || kind[0].toUpperCase() + kind.slice(1), amount: Math.round(amount * 100) / 100, by });
  }
  // An amount the model missed, when the chat says who paid it.
  spent.forEach((said, k) => {
    if (used.has(k) || !said.by) return;
    const by = payer(said.by);
    if (by) expenses.push({ kind: said.kind, what: said.what, amount: said.amount, by });
  });
  // Someone the chat names only to say they aren't coming, who paid nothing, is left out.
  if (chat != null) {
    for (const p of [...people]) {
      if (expenses.some((e) => e.by === p.id) || !notComing(chat, p)) continue;
      people.splice(people.indexOf(p), 1);
      for (const [key, id] of [...byName]) if (id === p.id) byName.delete(key);
      notes.push(`left out ${p.name}: the chat says they aren't coming`);
    }
  }
  // A kid's parents as the chat's wording says them, else the model's.
  const parentsSaid = chat == null ? new Map() : parentsInChat(chat, people);
  for (const p of people) {
    const parents = parentsSaid.get(p.id) ?? (p.parents || []).map(idOf).filter((id) => id && id !== p.id);
    if (p.age != null) {
      p.guardians = [...new Set(parents)].filter((id) => people.find((q) => q.id === id)?.age == null);
      if (!p.guardians.length && p.age < 18) {
        p.age = null; // no adult to pay for them: counted as an adult
        p.drinks = true;
        notes.push(`${p.name} has no parent in the list, so counts as an adult`);
      }
    }
    delete p.parents;
  }
  const missed = [...new Set(inChat)].filter((a) => !expenses.some((e) => e.amount === a));
  if (chat != null && missed.length) {
    const many = missed.length > 1;
    notes.push(`${missed.map((a) => `$${a.toLocaleString('en-US')}`).join(', ')} ${many ? 'are' : 'is'} in the chat but not in the lists: add ${many ? 'them' : 'it'} below`);
  }
  if (!people.some((p) => !p.guardians.length)) throw new Error('found no one to pay');
  if (!expenses.length) throw new Error('found no amounts spent');
  const host = (chat == null ? null : idOf(hostInChat(chat, people))) ?? idOf(answer.host) ?? expenses.find((e) => e.kind === 'lodging')?.by ?? people[0].id;
  // The model's first day when the chat writes that date, else the first date the chat writes.
  const inChatDates = dates(chat);
  const same = (d) => inChatDates.some((x) => startDate(x, today) === startDate(d, today));
  const first = startDate(chat == null || !inChatDates.length || same(answer.start) ? answer.start : inChatDates[0], today)
    ?? startDate(inChatDates[0], today);
  const start = first ?? today.toISOString().slice(0, 10);
  if (!first) notes.push('no start date found, so it starts today');
  if (chat != null) {
    // Who stays fewer nights: the chat's own wording first; the model's word
    // only for someone the chat says comes late or leaves early; and a kid
    // no longer than the parent who stays longest.
    const nightsSaid = nightsInChat(chat, people, trip, start);
    for (const p of people) {
      if (nightsSaid.has(p.id)) p.nights = nightsSaid.get(p.id);
      else if (p.nights < trip && !mayStayLess(chat, p)) p.nights = trip;
    }
    for (const p of people) {
      if (!p.guardians.length || nightsSaid.has(p.id)) continue;
      p.nights = Math.min(p.nights, Math.max(...p.guardians.map((id) => people.find((q) => q.id === id).nights)));
    }
  }
  return { start, host, people, expenses, notes };
}
