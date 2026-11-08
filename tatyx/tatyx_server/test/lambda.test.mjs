// The Lambda handler: function URL events through the server's own routes, on a folder store: `node --test`.
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

const dir = await mkdtemp(join(tmpdir(), 'tatyx-lambda-'));
const seedsDir = join(dir, 'strategies');
await mkdir(seedsDir);
const seed = { id: 'u-seed', owner: 'player@aletyx.com', name: 'The Seed', tagline: 'From the repository.', decisions: { build: { type: 'Build', table: [] } }, enteredAt: '2026-11-08T00:00:00.000Z' };
await writeFile(join(seedsDir, 'seed.json'), JSON.stringify(seed));
Object.assign(process.env, {
  AWS_LAMBDA_FUNCTION_NAME: 'tatyx-api-test',
  TATYX_DATA_DIR: join(dir, 'data'),
  TATYX_STRATEGIES_DIR: seedsDir,
  TATYX_LEADERBOARD: 'off',
  TATYX_VIEWER_HOST_HEADER: 'on',
});
const { handler } = await import('../lambda.mjs');

const event = (method, path, extra = {}) => ({
  rawPath: path,
  rawQueryString: '',
  headers: { host: 'abc.lambda-url.us-east-1.on.aws', ...(extra.headers ?? {}) },
  requestContext: { http: { method } },
  body: extra.body,
  isBase64Encoded: false,
  cookies: extra.cookies,
});
const body = (answer) => JSON.parse(Buffer.from(answer.body, 'base64').toString('utf8'));

test('answers the API from a function URL event', async () => {
  const health = await handler(event('GET', '/api/health'));
  assert.equal(health.statusCode, 200);
  assert.deepEqual(body(health), { ok: true });
  assert.equal(health.isBase64Encoded, true);
  const signedOut = await handler(event('GET', '/api/session', { cookies: ['tatyx_session=forged.value'] }));
  assert.equal(signedOut.statusCode, 401);
});

test("trusts the page's host from CloudFront's header, and no other origin", async () => {
  const page = { origin: 'https://d123.cloudfront.net', 'x-tatyx-host': 'd123.cloudfront.net', 'content-type': 'application/json' };
  const same = await handler(event('POST', '/api/session', { headers: page, body: '{}' }));
  assert.notEqual(same.statusCode, 403);
  const other = await handler(event('POST', '/api/session', { headers: { ...page, origin: 'https://evil.example' }, body: '{}' }));
  assert.equal(other.statusCode, 403);
});

test('starts an empty tour with the strategies kept in the repository', async () => {
  await handler(event('GET', '/api/leaderboard'));
  const kept = JSON.parse(await readFile(join(dir, 'data', 'strategies.json'), 'utf8'));
  assert.deepEqual(kept.entries.map((e) => e.id), ['u-seed']);
});
