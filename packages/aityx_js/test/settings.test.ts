import { describe, expect, it } from 'vitest';
import { AITYX_KEY_NAME, AITYX_URL_NAME, AityxClient, AityxNoKey, memoryKeyStore, resolveConnection } from '../src/index';

const origin = new URL('http://localhost:9710/app/');

function fetchWith(config: unknown, status = 200): typeof globalThis.fetch {
  return (async (input: RequestInfo | URL) => {
    if (String(input).endsWith('/aityx/config')) {
      return new Response(typeof config === 'string' ? config : JSON.stringify(config), { status });
    }
    return new Response('{"ok":true}', { status: 200 });
  }) as typeof globalThis.fetch;
}

describe('resolveConnection', () => {
  it('takes the user key first', async () => {
    const store = memoryKeyStore({ local: { [AITYX_KEY_NAME]: 'mine' } });
    const to = await resolveConnection({ store, origin, fetch: fetchWith({ available: true }) });
    expect(to.source).toBe('user');
    expect(to.key).toBe('mine');
  });
  it('asks the origin for a dev key next', async () => {
    const to = await resolveConnection({
      store: memoryKeyStore(),
      origin,
      fetch: fetchWith({ available: true, url: 'https://api.aityx.ai', source: 'environment' }),
    });
    expect(to.source).toBe('dev');
    expect(to.systemone.href).toBe('http://localhost:9710/aityx/v1/systemone');
    expect(to.whose).toBe('dev key from the environment');
  });
  it('sends the user key through the relay to the aityx it relays to, else straight', async () => {
    const relay = () => ({ url: 'https://api-stage.aityx.ai', endpoint: new URL('http://localhost:9710/aityx/') });
    const staging = memoryKeyStore({ local: { [AITYX_KEY_NAME]: 'mine', [AITYX_URL_NAME]: 'https://api-stage.aityx.ai' } });
    const through = await resolveConnection({ store: staging, origin, relay, lend: false, fetch: fetchWith({ available: true }) });
    expect(through.systemone.href).toBe('http://localhost:9710/aityx/v1/systemone');
    expect(through.headers()['Authorization']).toBe('Bearer mine');
    expect(through.url).toBe('https://api-stage.aityx.ai');
    const production = memoryKeyStore({ local: { [AITYX_KEY_NAME]: 'mine', [AITYX_URL_NAME]: 'https://api.aityx.ai' } });
    const direct = await resolveConnection({ store: production, origin, relay, lend: false });
    expect(direct.systemone.href).toBe('https://api.aityx.ai/v1/systemone');
  });
  it('lends nothing when lend is false: no key of the user\'s is none, the origin unasked', async () => {
    let asked = false;
    const fetch = (async () => {
      asked = true;
      return new Response(JSON.stringify({ available: true }), { status: 200 });
    }) as typeof globalThis.fetch;
    expect((await resolveConnection({ store: memoryKeyStore(), origin, lend: false, fetch })).source).toBe('none');
    expect(asked).toBe(false);
  });
  it('is none on a static host (an HTML page, a 404) or an unavailable config', async () => {
    expect((await resolveConnection({ store: memoryKeyStore(), origin, fetch: fetchWith('<!doctype html>') })).source).toBe('none');
    expect((await resolveConnection({ store: memoryKeyStore(), origin, fetch: fetchWith({}, 404) })).source).toBe('none');
    expect((await resolveConnection({ store: memoryKeyStore(), origin, fetch: fetchWith({ available: false }) })).source).toBe('none');
  });
});

describe('AityxClient', () => {
  it('throws AityxNoKey with no key anywhere', async () => {
    const client = new AityxClient({ store: memoryKeyStore(), origin, fetch: fetchWith({ available: false }) });
    await expect(client.systemone({})).rejects.toBeInstanceOf(AityxNoKey);
  });
  it('resolves again when the key changes', async () => {
    const store = memoryKeyStore();
    const client = new AityxClient({ store, origin, fetch: fetchWith({ available: false }) });
    expect((await client.connection()).source).toBe('none');
    store.save('later');
    const answer = await client.systemone({ x: 1 });
    expect(answer.ok).toBe(true);
    expect(answer.json).toEqual({ ok: true });
  });
});
