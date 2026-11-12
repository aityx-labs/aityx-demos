// aityx from the browser, for Health Plan: the key, where calls go, and the
// key check. A plain-JS twin of packages/aityx_js (TypeScript) and
// packages/aityx_web (Dart), with the same storage entries and rules, so the
// key the user sets once on the index page (/demos/#aityx-key) works here
// too: the page and every demo share one origin, and so the browser's
// storage. While there is no key at all, the page asks for it itself and
// saves it there (save), for the index page and every other demo.
//
// Where the key comes from, in order:
//   1. the user's key: sessionStorage['aityx.key'] ("only this session"),
//      else localStorage['aityx.key'], with aityx.url beside it (default
//      https://api.aityx.ai). Calls go straight to <url>/v1/systemone with
//      Authorization: Bearer <key>.
//   2. the dev key: with no user key, GET ../aityx/config (the index
//      server's /demos/aityx/config). When the server holds a key it
//      answers {"available": true, "url", "source"}, never the key, and
//      calls go to ../aityx/v1/systemone, where the server adds it.
//   3. none: {"available": false}, a 404 or an HTML page (a static host),
//      or no answer.
//
// Never log or show conn.headers(): they hold the key.
'use strict';

const Aityx = (() => {
  const DEFAULT_URL = 'https://api.aityx.ai';
  const KEY_NAME = 'aityx.key';
  const URL_NAME = 'aityx.url';
  // Beside the page's folder: /demos/healthplan/ -> /demos/aityx/ and /demos/.
  const proxyBase = () => new URL('../aityx/', document.baseURI);
  const keyPage = () => new URL('../#aityx-key', document.baseURI).href;
  // Embedded in the aityx website (?embed=1): the light asks the page around
  // it for the key instead of leaving for the index page.
  const embedded = new URLSearchParams(location.search).get('embed') === '1' && window.parent !== window;

  function storageGet(store, name) {
    try { const v = window[store].getItem(name); return v && v.trim() ? v.trim() : null; } catch (_) { return null; }
  }
  // The user's key and its URL, from the storage that holds the key.
  function stored() {
    for (const store of ['sessionStorage', 'localStorage']) {
      const key = storageGet(store, KEY_NAME);
      if (key) return { key, url: storageGet(store, URL_NAME) };
    }
    return null;
  }
  function normalizeUrl(url) {
    let t = (url || '').trim();
    while (t.endsWith('/')) t = t.slice(0, -1);
    try {
      const u = new URL(t);
      if ((u.protocol === 'https:' || u.protocol === 'http:') && u.hostname) return t;
    } catch (_) {}
    return DEFAULT_URL;
  }

  function connection(source, endpoint, url, key, from) {
    const base = endpoint.endsWith('/') ? endpoint : endpoint + '/';
    return {
      source, url, from,
      systemone: new URL('v1/systemone', base).href,
      headers() {
        const h = { 'Content-Type': 'application/json' };
        if (key) h.Authorization = 'Bearer ' + key;
        return h;
      },
      // Whose key, for people.
      get whose() {
        return source === 'user' ? 'your key'
          : source === 'dev' ? (from === '.env' ? 'the dev key from .env' : from === 'environment' ? 'the dev key from the environment' : 'the dev key')
          : 'no key';
      },
    };
  }
  const NONE = connection('none', DEFAULT_URL, '', null, null);
  // A key as typed, before it is saved: where its check goes.
  const userConnection = (key, url) => connection('user', url, url, key, null);

  // The aityx URL as typed, as the index page takes it: the default when
  // empty, else https on a host under aityx.ai (all the page's content
  // security policy lets it reach), no trailing slash. Null when it isn't.
  function cleanUrl(text) {
    const t = (text || '').trim();
    if (!t) return DEFAULT_URL;
    let u;
    try { u = new URL(t); } catch (_) { return null; }
    if (u.protocol !== 'https:' || u.search || u.hash || u.username || u.password || !u.hostname.endsWith('.aityx.ai')) return null;
    return (u.origin + u.pathname).replace(/\/+$/, '');
  }

  // Saves the key on this device (localStorage, as the index page's
  // "Remember on this device"), with its URL when it isn't the default.
  // False when the browser refuses the storage.
  function save(key, url) {
    try {
      for (const store of ['sessionStorage', 'localStorage']) {
        try { window[store].removeItem(KEY_NAME); window[store].removeItem(URL_NAME); } catch (_) {}
      }
      localStorage.setItem(KEY_NAME, key);
      if (url && url !== DEFAULT_URL) localStorage.setItem(URL_NAME, url);
      return storageGet('localStorage', KEY_NAME) === key;
    } catch (_) {
      return false;
    }
  }

  async function resolve() {
    const s = stored();
    if (s) { const url = normalizeUrl(s.url); return connection('user', url, url, s.key, null); }
    if (location.protocol !== 'http:' && location.protocol !== 'https:') return NONE;
    try {
      const r = await fetch(new URL('config', proxyBase()), { headers: { Accept: 'application/json' }, cache: 'no-store', signal: AbortSignal.timeout(10000) });
      const c = await r.json().catch(() => null);
      if (r.status !== 200 || !c || c.available !== true) return NONE;
      return connection('dev', proxyBase().href, typeof c.url === 'string' ? c.url : '', null, typeof c.source === 'string' ? c.source : null);
    } catch (_) {
      return NONE;
    }
  }

  // Does aityx take the key? POSTs {} to systemone, which checks the key
  // first: a working key gets 400 invalid_request without running a model,
  // a bad one 401. Spends one request of the user's quota. Never throws.
  // kind: ready | noKey | rejected | unreachable | failing.
  async function check(conn) {
    if (conn.source === 'none') return { kind: 'noKey', detail: '' };
    let r, body;
    try {
      r = await fetch(conn.systemone, { method: 'POST', headers: conn.headers(), body: '{}', signal: AbortSignal.timeout(15000) });
      body = await r.json().catch(() => null);
    } catch (e) {
      const where = conn.source === 'dev' ? 'the dev proxy' : conn.url;
      return { kind: 'unreachable', detail: e && e.name === 'TimeoutError' ? `no answer from ${where} in 15 s` : `no answer from ${where} (network, CORS or a blocker)` };
    }
    const code = body && body.code, detail = body && body.detail;
    if (r.status === 400 && code === 'invalid_request') return { kind: 'ready', detail: 'aityx accepts the key' };
    if (r.status === 401 || r.status === 403) return { kind: 'rejected', detail: detail || `HTTP ${r.status}` };
    if (conn.source === 'dev' && r.status === 502 && (code === 'proxy_unreachable' || code === 'proxy_redirect')) {
      return { kind: 'unreachable', detail: detail || 'the dev proxy could not reach aityx' };
    }
    return { kind: 'failing', detail: `aityx answered HTTP ${r.status}${detail ? `: ${detail}` : ''}` };
  }

  // Removes the user's key and URL from the browser, for every demo.
  function forget() {
    for (const store of ['sessionStorage', 'localStorage']) {
      try { window[store].removeItem(KEY_NAME); window[store].removeItem(URL_NAME); } catch (_) {}
    }
  }

  // The index page's key section, in the same tab; embedded, the page around asks.
  function openKeyPage() {
    if (embedded) { window.parent.postMessage('aityx:key', '*'); return; }
    location.href = keyPage();
  }

  return { NONE, resolve, check, userConnection, cleanUrl, save, forget, keyPage, openKeyPage, embedded, KEY_NAME, URL_NAME };
})();
