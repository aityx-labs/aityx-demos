// aityx for Holiday Split, the way every aityx demo reaches it (aityx-js,
// the twin of packages/aityx_web):
//
// 1. the user's key, set once on the demos page (../#aityx-key) and kept in
//    this origin's storage, sent straight to aityx;
// 2. else the index server's dev key, through its proxy at ../aityx/
//    (/demos/aityx/ here), which adds the key so it never reaches the page;
// 3. else none: the page shows the recorded calls and keeps the rules locked.
//
// The status light, top right, says which, and opens the demos page's key
// section; embedded (?embed=1, the aityx website), it asks the page around
// it for the key instead, as the Flutter demos do.
import { AityxClient, browserKeyStore, mountStatusLight } from 'aityx-js';

const store = browserKeyStore();
// The demos' root (/demos/), from this app's base href (/demos/holidaysplit/).
const demosRoot = new URL('../', document.baseURI);
const proxyPath = new URL('aityx/', demosRoot).pathname;
const client = new AityxClient({ store, proxyPath });

const embedded = new URLSearchParams(location.search).get('embed') === '1' && window.parent !== window;

/** The demos page's key section, or, embedded, a request to the page around it. */
export function openKeyPage() {
  if (embedded) window.parent.postMessage('aityx:key', '*');
  else location.assign(new URL('#aityx-key', demosRoot).href);
}
export const keyPageHref = new URL('#aityx-key', demosRoot).href;

let light = null;
const listeners = [];
let last = null;

/** Mounts the light in `parent`; `listener` gets every check's AityxState. */
export function mountLight(parent) {
  light = mountStatusLight(parent, { store, proxyPath, onClick: openKeyPage });
  // The light has no event of its own: watch what it shows.
  const seen = () => {
    const st = light.state();
    if (st === last) return;
    last = st;
    if (st) listeners.forEach((f) => f(st));
  };
  new MutationObserver(seen).observe(light.element, { attributes: true, attributeFilter: ['data-state', 'title'] });
  seen();
  return light;
}

/** Calls `f` with each new AityxState ({ok, kind, whose, url, detail, source}). */
export function onState(f) {
  listeners.push(f);
  if (last) f(last);
}

/** Checks the key again (aityx refused it on a call). */
export function recheck() {
  light?.refresh();
}

/** One systemone call: an AityxAnswer, or throws AityxNoKey / AityxUnreachable. */
export function systemone(body) {
  return client.systemone(body);
}

let shownEndpoint = 'https://api.aityx.ai/v1/systemone';
let shownWhose = 'your key';
client.connection().then(remember, () => {});
store.onChange(() => client.connection().then(remember, () => {}));
function remember(c) {
  if (c.source === 'none') return;
  shownEndpoint = c.systemone.href;
  shownWhose = c.source === 'dev' ? `the server's dev key${c.url ? `, for ${c.url}` : ''}, added by its proxy` : 'Authorization: Bearer <your key>';
}

/** Where the calls go, to show with the request. */
export const endpoint = () => shownEndpoint;
/** Whose key, to show with the request. */
export const whose = () => shownWhose;
