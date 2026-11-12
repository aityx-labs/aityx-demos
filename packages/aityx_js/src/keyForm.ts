// "Your aityx key": the form an app on its own origin shows, since the
// aityx index page's storage (another origin) can't reach it. The same
// entries as the index page writes, through the key store.

import { checkAityx } from './check';
import { AityxConnection, AITYX_DEFAULT_URL, normalizeAityxUrl, type AityxRelay } from './connection';
import { browserKeyStore, type AityxKeyStore } from './keyStore';

export interface KeyFormOptions {
  store?: AityxKeyStore;
  /** The fetch for the check; the global one unless given (tests). */
  fetch?: typeof fetch;
  /** After a key is checked and saved. */
  onSaved?: () => void;
  /** After the key is forgotten. */
  onForgot?: () => void;
  /** The URL the field shows with no key set: https://api.aityx.ai unless given. */
  defaultUrl?: string;
  /** The server's relay for the key, which the check goes through when it relays to the key's URL. */
  relay?: () => AityxRelay | null;
  /** The submit button's label: **Check and save** unless given (a profile's **Save profile**, say). */
  submitLabel?: string;
  /**
   * The page's own fields, saved by the same button just before the key (a
   * player's name on a leaderboard, say): resolves to what it saved, in a
   * sentence, or null when nothing changed; rejects with what went wrong.
   * With it, the button saves whatever changed: the key is checked with
   * aityx only when it or its URL changed, and an empty key field leaves
   * the key as it is.
   */
  alsoSave?: () => Promise<string | null>;
}

export interface KeyForm {
  readonly element: HTMLFormElement;
  /** Fills the fields from the store (what it holds now). */
  reset(): void;
  /** The URL to show with no key set, e.g. the app's server's, once it answers. */
  setDefaultUrl(url: string): void;
  dispose(): void;
}

const STYLE_ID = 'aityx-js-key-form';

/** Whether `key` on `url` is the key `store` holds already, on the same URL: nothing to check or save. */
export function keyUnchanged(store: Pick<AityxKeyStore, 'key' | 'url'>, key: string, url: string): boolean {
  return store.key !== null && store.key === key.trim() && normalizeAityxUrl(url) === normalizeAityxUrl(store.url ?? AITYX_DEFAULT_URL);
}

function ensureStyles(): void {
  if (typeof document === 'undefined' || document.getElementById(STYLE_ID)) return;
  const style = document.createElement('style');
  style.id = STYLE_ID;
  style.textContent = `
.aityx-key-form { display: grid; gap: 12px; font-size: 14px; }
.aityx-key-form label { display: grid; gap: 4px; color: #A9ACB6; }
.aityx-key-form input[type="password"], .aityx-key-form input[type="url"] {
  font: inherit; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px;
  color: #EFF2F4; background: #17161A; border: 1px solid #37333C; border-radius: 8px; padding: 8px 10px;
}
.aityx-key-form input:focus-visible { outline: 2px solid #EB7B58; outline-offset: 1px; }
.aityx-key-form .aityx-actions { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
.aityx-key-form button {
  font: inherit; font-weight: 600; font-size: 13.5px; cursor: pointer;
  border-radius: 8px; padding: 7px 12px; border: 1px solid #37333C; color: #EFF2F4; background: #2A272E;
}
.aityx-key-form button.aityx-primary { background: #E36742; border-color: #E36742; color: #fff; }
.aityx-key-form button:disabled { opacity: .6; cursor: default; }
.aityx-key-form .aityx-note { margin: 0; color: #A9ACB6; min-height: 1.4em; }
.aityx-key-form .aityx-note[data-tone="ok"] { color: #4CC38A; }
.aityx-key-form .aityx-note[data-tone="bad"] { color: #F0506E; }
`;
  document.head.append(style);
}

/**
 * The key form: the key (a password field), the aityx URL (the key's, or
 * the default with none set), **Check and save** (which asks aityx
 * whether it accepts the key, and saves it on this device, until
 * forgotten, only then) and **Forget**. Given `alsoSave`, the button saves
 * the page's own fields too, and the key only when it changed.
 */
export function mountKeyForm(parent: Element, options: KeyFormOptions = {}): KeyForm {
  ensureStyles();
  const store = options.store ?? browserKeyStore();
  let defaultUrl = normalizeAityxUrl(options.defaultUrl);

  const form = document.createElement('form');
  form.className = 'aityx-key-form';
  form.innerHTML = `
<label>Your aityx key
  <input name="key" type="password" autocomplete="off" spellcheck="false" placeholder="from the aityx console's API keys page" required>
</label>
<label>aityx URL
  <input name="url" type="url" autocomplete="off" spellcheck="false">
</label>
<div class="aityx-actions">
  <button type="submit" class="aityx-primary">Check and save</button>
  <button type="button" name="forget">Forget</button>
</div>
<p class="aityx-note" aria-live="polite"></p>
`;
  parent.append(form);

  const keyInput = form.elements.namedItem('key') as HTMLInputElement;
  const urlInput = form.elements.namedItem('url') as HTMLInputElement;
  const forget = form.elements.namedItem('forget') as HTMLButtonElement;
  const submit = form.querySelector<HTMLButtonElement>('button[type="submit"]')!;
  const note = form.querySelector<HTMLParagraphElement>('.aityx-note')!;
  if (options.submitLabel !== undefined) submit.textContent = options.submitLabel;
  // Saving the page's fields too, the key may stay as it is: no key field to fill first.
  if (options.alsoSave !== undefined) keyInput.required = false;

  const say = (text: string, tone: 'ok' | 'bad' | '' = '') => {
    note.textContent = text;
    note.dataset['tone'] = tone;
  };

  const reset = () => {
    keyInput.value = store.key ?? '';
    // Where the key's calls go: its own URL, else aityx's default; with no key, this app's.
    urlInput.value = store.key === null ? defaultUrl : (store.url ?? AITYX_DEFAULT_URL);
    urlInput.placeholder = defaultUrl;
    forget.disabled = store.key === null;
    say(
      store.key === null
        ? 'No key yet. It stays in your browser; every call goes from here to aityx.'
        : 'A key is set on this device, until you forget it.',
    );
  };

  const onSubmit = async (event: Event) => {
    event.preventDefault();
    const key = keyInput.value.trim();
    const url = urlInput.value || defaultUrl;
    const alsoSave = options.alsoSave;
    if (alsoSave === undefined && key === '') {
      say('Paste a key first.', 'bad');
      return;
    }
    submit.disabled = true;
    // What was saved, or not, in sentences: one note for the whole button.
    const said: string[] = [];
    let bad = false;
    const sayAll = (fallback: string) => say(said.length === 0 ? fallback : said.join(' '), bad ? 'bad' : said.length === 0 ? '' : 'ok');
    try {
      if (alsoSave !== undefined) {
        say('Saving…');
        try {
          const saved = await alsoSave();
          if (saved !== null) said.push(saved);
        } catch (error) {
          said.push(`Not saved: ${error instanceof Error ? error.message : String(error)}.`);
          bad = true;
        }
        if (key === '' && store.key === null) {
          said.push('No key yet: paste yours to play.');
          bad = true;
        }
        if (key === '' || keyUnchanged(store, key, url)) {
          sayAll('Nothing changed.');
          return;
        }
      }
      say([...said, alsoSave === undefined ? 'Checking with aityx…' : 'Checking your key with aityx…'].join(' '));
      const connection = AityxConnection.user(key, url, options.relay?.() ?? null);
      const state = await checkAityx({ connection, fetch: options.fetch });
      if (state.ok) {
        store.save(key, { url });
        said.push(alsoSave === undefined ? `Saved: ${state.detail}.` : `Key saved: ${state.detail}.`);
        forget.disabled = false;
        sayAll('');
        options.onSaved?.();
      } else {
        said.push(alsoSave === undefined ? `Not saved: ${state.detail}.` : `Key not saved: ${state.detail}.`);
        bad = true;
        sayAll('');
      }
    } finally {
      submit.disabled = false;
    }
  };

  const onForget = () => {
    store.forget();
    reset();
    say('Forgotten: no key in this browser.');
    options.onForgot?.();
  };

  form.addEventListener('submit', onSubmit);
  forget.addEventListener('click', onForget);
  reset();

  return {
    element: form,
    reset,
    setDefaultUrl: (url: string) => {
      const showing = urlInput.value;
      const was = defaultUrl;
      defaultUrl = normalizeAityxUrl(url);
      urlInput.placeholder = defaultUrl;
      // Only when the field still shows the old default: never over what the user typed.
      if (store.key === null && (showing === '' || showing === was)) urlInput.value = defaultUrl;
    },
    dispose: () => {
      form.removeEventListener('submit', onSubmit);
      forget.removeEventListener('click', onForget);
      form.remove();
    },
  };
}
