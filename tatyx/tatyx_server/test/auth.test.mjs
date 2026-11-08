// The sessions and the secret that signs them: `node --test`.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { RENEW_AFTER_SECONDS, SESSION_SECONDS, sessions, storedSecret } from '../auth.mjs';
import { fileStore } from '../store.mjs';

const user = { email: 'player@aletyx.com', name: 'Player', picture: null };

test('the secret is made once and kept, mode 600: a restart keeps the sessions', async () => {
  const dir = join(await mkdtemp(join(tmpdir(), 'tatyx-auth-')), 'data');
  const file = join(dir, 'session-secret');
  const store = fileStore(dir);
  const first = await storedSecret(store);
  assert.equal(await storedSecret(store), first);
  assert.equal((await readFile(file, 'utf8')).trim(), first);
  assert.equal((await stat(file)).mode & 0o777, 0o600);
  const cookie = sessions(first).issue(user);
  assert.equal(sessions(await storedSecret(fileStore(dir))).read(cookie)?.email, user.email);
  assert.equal(sessions('another secret, another server').read(cookie), null);
});

test('a session lasts 30 days and is renewed once it is a day old', () => {
  const s = sessions('a secret');
  const now = Date.now();
  const read = s.read(s.issue(user, now), now);
  assert.equal(SESSION_SECONDS, 30 * 24 * 60 * 60);
  assert.equal(s.stale(read, now), false);
  assert.equal(s.stale(read, now + (RENEW_AFTER_SECONDS + 1) * 1000), true);
  assert.notEqual(s.read(s.issue(user, now), now + (SESSION_SECONDS - 1) * 1000), null);
  assert.equal(s.read(s.issue(user, now), now + (SESSION_SECONDS + 1) * 1000), null);
});
