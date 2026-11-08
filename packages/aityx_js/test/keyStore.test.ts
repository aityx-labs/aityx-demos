import { describe, expect, it } from 'vitest';
import { AITYX_KEY_NAME, AITYX_URL_NAME, memoryKeyStore } from '../src/index';

describe('the key store', () => {
  it('has no key to begin with', () => {
    const store = memoryKeyStore();
    expect(store.key).toBeNull();
    expect(store.url).toBeNull();
    expect(store.sessionOnly).toBe(false);
  });

  it('saves on the device, trimmed, with its URL, production\'s too', () => {
    const store = memoryKeyStore();
    store.save('  k-1  ', { url: 'https://api.aityx.ai/' });
    expect(store.key).toBe('k-1');
    expect(store.url).toBe('https://api.aityx.ai');
    expect(store.sessionOnly).toBe(false);
  });

  it('keeps a URL that is not the default, normalized', () => {
    const store = memoryKeyStore();
    store.save('k', { url: 'https://api-stage.aityx.ai//' });
    expect(store.url).toBe('https://api-stage.aityx.ai');
  });

  it('saves for the session only and clears the device', () => {
    const store = memoryKeyStore({ local: { [AITYX_KEY_NAME]: 'old', [AITYX_URL_NAME]: 'https://x.example' } });
    store.save('new', { sessionOnly: true });
    expect(store.key).toBe('new');
    expect(store.sessionOnly).toBe(true);
    expect(store.url).toBeNull();
  });

  it('prefers the session when both hold a key', () => {
    const store = memoryKeyStore({ local: { [AITYX_KEY_NAME]: 'device' }, session: { [AITYX_KEY_NAME]: 'session' } });
    expect(store.key).toBe('session');
    expect(store.sessionOnly).toBe(true);
  });

  it('refuses an empty key', () => {
    expect(() => memoryKeyStore().save('   ')).toThrow();
  });

  it('forgets both storages and tells its listeners', () => {
    const store = memoryKeyStore({ local: { [AITYX_KEY_NAME]: 'a' }, session: { [AITYX_KEY_NAME]: 'b' } });
    let changes = 0;
    const stop = store.onChange(() => changes++);
    store.forget();
    expect(store.key).toBeNull();
    store.save('c');
    stop();
    store.forget();
    expect(changes).toBe(2);
  });
});
