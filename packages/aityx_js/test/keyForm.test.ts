import { describe, expect, it } from 'vitest';
import { AITYX_DEFAULT_URL, keyUnchanged, memoryKeyStore } from '../src/index';

describe('keyUnchanged', () => {
  it('is false with no key stored', () => {
    expect(keyUnchanged(memoryKeyStore(), 'k', AITYX_DEFAULT_URL)).toBe(false);
  });

  it('is true for the stored key on its URL, however it is written', () => {
    const store = memoryKeyStore();
    store.save('k-1', { url: 'https://api-stage.aityx.ai' });
    expect(keyUnchanged(store, ' k-1 ', 'https://api-stage.aityx.ai/')).toBe(true);
  });

  it('is false for another key, or the same key on another URL', () => {
    const store = memoryKeyStore();
    store.save('k-1', { url: 'https://api-stage.aityx.ai' });
    expect(keyUnchanged(store, 'k-2', 'https://api-stage.aityx.ai')).toBe(false);
    expect(keyUnchanged(store, 'k-1', AITYX_DEFAULT_URL)).toBe(false);
  });

  it('takes a key saved without a URL as production\'s', () => {
    const store = memoryKeyStore({ local: { 'aityx.key': 'k-1' } });
    expect(store.url).toBeNull();
    expect(keyUnchanged(store, 'k-1', AITYX_DEFAULT_URL)).toBe(true);
  });
});
