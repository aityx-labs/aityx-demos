// The page's side of the trip reader: a model on the device turns the chat
// into the trip's lists. The chat never goes to a server for this.
//
// 1. The browser's built-in model, where it has one (Chrome's and Edge's
//    Prompt API, `LanguageModel`: Gemini Nano in Chrome): one JSON answer,
//    held to a schema. The browser downloads the model itself, once, for
//    every site.
// 2. Else a model run by transformers.js in a module Web Worker
//    (public/reader/reader-worker.js), started on the first read, that
//    keeps the model loaded for the next ones: three short passes.
//
// Either way the answer is held to the chat (public/reader/trip-reader.js).

// The prompts and the checks, beside the page (/demos/holidaysplit/reader/),
// served as they are, unbundled: the worker imports the same file.
const tripReader = () => import(/* @vite-ignore */ new URL('reader/trip-reader.js', document.baseURI).href);

// ---- 1. The built-in model --------------------------------------------------

const LANGUAGES = { expectedInputs: [{ type: 'text', languages: ['en'] }], expectedOutputs: [{ type: 'text', languages: ['en'] }] };

/** Whether the browser has a built-in model this page can use (ready, or its to download). */
export async function builtIn() {
  if (typeof LanguageModel === 'undefined') return false;
  try {
    return (await LanguageModel.availability(LANGUAGES)) !== 'unavailable';
  } catch {
    return false;
  }
}

let base = null; // A session with the rules and the worked examples; each read is a clone of it.

async function askBuiltIn(chat, R, { onProgress, onLoaded, onToken }) {
  base ??= LanguageModel.create({
    ...LANGUAGES,
    initialPrompts: R.messages('').slice(0, -1),
    monitor(m) {
      m.addEventListener('downloadprogress', (e) => onProgress?.(e.loaded));
    },
  }).catch((error) => {
    base = null;
    throw error;
  });
  const session = await (await base).clone();
  onLoaded?.('built-in');
  try {
    let text = '';
    let count = 0;
    for await (const chunk of session.promptStreaming(chat.trim(), { responseConstraint: R.SCHEMA })) {
      text += chunk;
      onToken?.(++count);
    }
    return text;
  } finally {
    session.destroy();
  }
}

// ---- 2. The worker ----------------------------------------------------------

let worker = null;
let seq = 0;
const pending = new Map();

function start() {
  if (worker) return worker;
  worker = new Worker(new URL('reader/reader-worker.js', document.baseURI), { type: 'module' });
  worker.onmessage = ({ data }) => {
    const job = pending.get(data.id);
    if (!job) return;
    if (data.type === 'progress') job.onProgress?.(data.progress);
    else if (data.type === 'loaded') job.onLoaded?.(data.device);
    else if (data.type === 'token') job.onToken?.(data.count);
    else if (data.type === 'trip') {
      pending.delete(data.id);
      job.resolve(data);
    } else if (data.type === 'error') {
      pending.delete(data.id);
      job.reject(new Error(data.message));
    }
  };
  worker.onerror = (event) => {
    const error = new Error(event.message || 'the reader failed to start');
    for (const job of pending.values()) job.reject(error);
    pending.clear();
    worker = null;
  };
  return worker;
}

function readInWorker(chat, callbacks) {
  const id = ++seq;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject, ...callbacks });
    start().postMessage({ id, type: 'read', chat, today: new Date().toISOString() });
  });
}

// -----------------------------------------------------------------------------

/**
 * Reads `chat` into the trip's lists, on the device: resolves to
 * {trip: {start, host, people, expenses, notes}, text, ms, by}, `by` being
 * "built-in" or "worker". The first read downloads the model (onProgress
 * 0..1), then each piece of the answer is counted (onToken). A built-in
 * model that fails hands over to the worker.
 */
export async function read(chat, callbacks = {}) {
  const started = performance.now();
  if (await builtIn()) {
    const R = await tripReader();
    let text = null;
    try {
      text = await askBuiltIn(chat, R, callbacks);
    } catch (error) {
      console.warn('The built-in model could not read the chat, so the downloaded one does:', error);
    }
    if (text !== null) {
      return { trip: R.toTrip(R.firstObject(text), new Date(), chat), text, ms: Math.round(performance.now() - started), by: 'built-in' };
    }
  }
  return { ...(await readInWorker(chat, callbacks)), by: 'worker' };
}

/** Whether this browser can run a reader at all: a built-in model, or module workers and WebAssembly. */
export const supported = typeof LanguageModel !== 'undefined' || (typeof Worker !== 'undefined' && typeof WebAssembly !== 'undefined');
