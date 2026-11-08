import { describe, expect, it } from 'vitest';
import { AityxConnection, NO_KEY, checkAityx, classifyAityx, stateTooltip } from '../src/index';

const user = AityxConnection.user('k');
const dev = AityxConnection.dev(new URL('http://localhost:9710/app/'), '/aityx/');

describe('classifyAityx', () => {
  it('is ready on 400 invalid_request', () => {
    const state = classifyAityx({ status: 400, body: '{"code":"invalid_request"}', connection: user });
    expect(state.kind).toBe('ready');
    expect(state.ok).toBe(true);
    expect(stateTooltip(state)).toContain('https://api.aityx.ai');
  });
  it('is rejected on 401', () => {
    const state = classifyAityx({ status: 401, body: '{"detail":"bad key"}', connection: user });
    expect(state.kind).toBe('rejected');
    expect(state.detail).toContain('set a new key');
  });
  it('is unreachable when the proxy could not reach aityx', () => {
    const state = classifyAityx({ status: 502, body: '{"code":"proxy_unreachable","detail":"no answer"}', connection: dev });
    expect(state.kind).toBe('unreachable');
    expect(state.detail).toBe('no answer');
  });
  it('is failing on a redirect', () => {
    expect(classifyAityx({ status: 302, body: '', connection: user }).kind).toBe('failing');
  });
  it('is no key without a connection', () => {
    expect(classifyAityx({ status: 200, body: '', connection: AityxConnection.none })).toBe(NO_KEY);
  });
});

describe('checkAityx', () => {
  it('posts an empty object with the key and classifies the answer', async () => {
    let seen: { url: string; init: RequestInit | undefined } | null = null;
    const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      seen = { url: String(input), init };
      return new Response('{"code":"invalid_request"}', { status: 400 });
    }) as typeof globalThis.fetch;
    const state = await checkAityx({ connection: user, fetch });
    expect(state.ok).toBe(true);
    expect(seen!.url).toBe('https://api.aityx.ai/v1/systemone');
    expect(seen!.init?.body).toBe('{}');
    expect((seen!.init?.headers as Record<string, string>)['Authorization']).toBe('Bearer k');
  });
  it('is unreachable when fetch throws', async () => {
    const fetch = (async () => {
      throw new TypeError('Failed to fetch');
    }) as unknown as typeof globalThis.fetch;
    const state = await checkAityx({ connection: user, fetch });
    expect(state.kind).toBe('unreachable');
  });
});
