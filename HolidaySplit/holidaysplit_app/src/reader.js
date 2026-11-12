// The page's side of the trip reader (public/reader/reader-worker.js): one
// module Web Worker, started on the first read, that keeps the model loaded
// for the next ones. The chat goes to the worker only, never to a server.

let worker = null;
let seq = 0;
const pending = new Map();

function start() {
  if (worker) return worker;
  // Beside the page (/demos/holidaysplit/reader/), served as it is, unbundled.
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
    const error = new Error(event.message || 'the trip reader failed to start');
    for (const job of pending.values()) job.reject(error);
    pending.clear();
    worker = null;
  };
  return worker;
}

/**
 * Reads `chat` into the trip's lists, on the device: resolves to
 * {trip: {start, host, people, expenses, notes}, text, ms}. The first read
 * downloads the model (onProgress 0..1), then each token is counted
 * (onToken).
 */
export function read(chat, { onProgress, onLoaded, onToken } = {}) {
  const id = ++seq;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject, onProgress, onLoaded, onToken });
    start().postMessage({ id, type: 'read', chat, today: new Date().toISOString() });
  });
}

/** Whether this browser can run it: module workers and WebAssembly. */
export const supported = typeof Worker !== 'undefined' && typeof WebAssembly !== 'undefined';
