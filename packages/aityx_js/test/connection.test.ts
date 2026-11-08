import { describe, expect, it } from 'vitest';
import { AITYX_DEFAULT_URL, AityxConnection, normalizeAityxUrl } from '../src/index';

describe('normalizeAityxUrl', () => {
  it('falls back to the default', () => {
    expect(normalizeAityxUrl(null)).toBe(AITYX_DEFAULT_URL);
    expect(normalizeAityxUrl('')).toBe(AITYX_DEFAULT_URL);
    expect(normalizeAityxUrl('not a url')).toBe(AITYX_DEFAULT_URL);
    expect(normalizeAityxUrl('ftp://x.example')).toBe(AITYX_DEFAULT_URL);
  });
  it('trims and drops trailing slashes', () => {
    expect(normalizeAityxUrl(' https://api-stage.aityx.ai/// ')).toBe('https://api-stage.aityx.ai');
  });
});

describe('AityxConnection', () => {
  it('sends a user key to systemone with a bearer', () => {
    const to = AityxConnection.user('k-1');
    expect(to.source).toBe('user');
    expect(to.systemone.href).toBe('https://api.aityx.ai/v1/systemone');
    expect(to.headers()).toEqual({ 'Content-Type': 'application/json', Authorization: 'Bearer k-1' });
    expect(to.whose).toBe('your key');
    expect(String(to)).not.toContain('k-1');
  });
  it('goes through the dev proxy on the origin without a key', () => {
    const to = AityxConnection.dev(new URL('http://localhost:9710/app/'), '/aityx/', 'https://api.aityx.ai', '.env');
    expect(to.systemone.href).toBe('http://localhost:9710/aityx/v1/systemone');
    expect(to.headers()).toEqual({ 'Content-Type': 'application/json' });
    expect(to.whose).toBe('dev key from .env');
  });
  it('resolves systemone under an endpoint without a trailing slash', () => {
    const to = new AityxConnection(new URL('http://localhost:8800/demos/aityx'), 'dev', '');
    expect(to.systemone.href).toBe('http://localhost:8800/demos/aityx/v1/systemone');
  });
});
