// Sign-in for the tatyx server: Google's ID tokens, verified here (RS256
// against Google's published keys, the issuer, the audience, the expiry,
// a verified email in an allowed domain), and the session they open, an
// HMAC-signed cookie (HttpOnly, SameSite=Strict) that the
// leaderboard's admin calls ask for. Plain Node (node:crypto), no
// packages. Never logs a token or a cookie.

import { createHmac, createPublicKey, randomBytes, timingSafeEqual, verify } from 'node:crypto';

const GOOGLE_KEYS = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
export const SESSION_COOKIE = 'tatyx_session';
/** A session lasts this long since the player's last visit (each visit renews it), and as long as the server's secret. */
export const SESSION_SECONDS = 30 * 24 * 60 * 60;
/** A session this old is renewed on the player's next visit: at most once a day. */
export const RENEW_AFTER_SECONDS = 24 * 60 * 60;

export class AuthError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AuthError';
  }
}

let keys = null;
let keysUntil = 0;

/** Google's signing keys, cached as long as Google says. */
async function googleKeys(force = false) {
  if (!force && keys !== null && Date.now() < keysUntil) return keys;
  const answer = await fetch(GOOGLE_KEYS, { signal: AbortSignal.timeout(10_000) });
  if (!answer.ok) throw new AuthError(`Google's keys could not be read (HTTP ${answer.status})`);
  const body = await answer.json();
  const maxAge = /max-age=(\d+)/.exec(answer.headers.get('cache-control') ?? '');
  keysUntil = Date.now() + (maxAge ? Number(maxAge[1]) * 1000 : 3_600_000);
  keys = Array.isArray(body.keys) ? body.keys : [];
  return keys;
}

const fromB64 = (part) => Buffer.from(part, 'base64url');

/**
 * The claims of a Google ID token for `clientId`, once its signature,
 * issuer, audience, expiry and email check out; throws AuthError
 * otherwise.
 */
export async function verifyGoogleIdToken(token, clientId, now = Date.now()) {
  if (typeof token !== 'string' || token.length > 8192) throw new AuthError('not a token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new AuthError('not a token');
  let header;
  let claims;
  try {
    header = JSON.parse(fromB64(parts[0]).toString('utf8'));
    claims = JSON.parse(fromB64(parts[1]).toString('utf8'));
  } catch {
    throw new AuthError('not a token');
  }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new AuthError('not a Google token');
  let jwk = (await googleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) jwk = (await googleKeys(true)).find((k) => k.kid === header.kid);
  if (!jwk) throw new AuthError('signed with a key Google does not publish');
  const signed = Buffer.from(`${parts[0]}.${parts[1]}`);
  if (!verify('RSA-SHA256', signed, createPublicKey({ key: jwk, format: 'jwk' }), fromB64(parts[2]))) {
    throw new AuthError('the signature does not check out');
  }
  if (!ISSUERS.has(claims.iss)) throw new AuthError('not issued by Google');
  if (claims.aud !== clientId) throw new AuthError('issued for another app');
  if (typeof claims.exp !== 'number' || claims.exp * 1000 < now - 60_000) throw new AuthError('expired');
  if (typeof claims.email !== 'string' || !(claims.email_verified === true || claims.email_verified === 'true')) {
    throw new AuthError('no verified email');
  }
  return claims;
}

/** The domain of an email, lower case. */
export function domainOf(email) {
  return String(email).split('@').pop().toLowerCase();
}

/** A session's cookie value and its reading, signed with `secret`. */
export function sessions(secret = randomBytes(32)) {
  const key = typeof secret === 'string' ? Buffer.from(secret, 'utf8') : secret;
  const sign = (body) => createHmac('sha256', key).update(body).digest('base64url');
  return {
    /** A cookie value for `user` ({email, name, picture}). */
    issue(user, now = Date.now()) {
      const body = Buffer.from(JSON.stringify({ ...user, exp: Math.floor(now / 1000) + SESSION_SECONDS })).toString('base64url');
      return `${body}.${sign(body)}`;
    },
    /** The user of a cookie value, or null when it is missing, forged or expired. */
    read(value, now = Date.now()) {
      if (typeof value !== 'string') return null;
      const at = value.lastIndexOf('.');
      if (at <= 0) return null;
      const body = value.slice(0, at);
      const given = Buffer.from(value.slice(at + 1));
      const expected = Buffer.from(sign(body));
      if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
      try {
        const user = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
        if (typeof user.exp !== 'number' || user.exp * 1000 < now) return null;
        return user;
      } catch {
        return null;
      }
    },
    /** Whether a session read from a cookie is old enough to renew. */
    stale(user, now = Date.now()) {
      return user.exp - Math.floor(now / 1000) < SESSION_SECONDS - RENEW_AFTER_SECONDS;
    },
  };
}

/**
 * The secret that signs the sessions when TATYX_SESSION_SECRET is unset:
 * the one in `store` (session-secret), else a new random one written there
 * once, so a restart keeps everyone signed in; two starting at once agree
 * on the first one written.
 */
export async function storedSecret(store, name = 'session-secret') {
  const kept = (await store.read(name))?.trim() ?? '';
  if (kept.length >= 32) return kept;
  const secret = randomBytes(32).toString('hex');
  if (kept === '' && (await store.create(name, `${secret}\n`))) return secret;
  // Another start wrote one meanwhile: that one, if it is whole; a short one is never a key.
  const other = (await store.read(name))?.trim() ?? '';
  if (other.length >= 32) return other;
  await store.write(name, `${secret}\n`);
  return secret;
}

/** The value of a cookie in a request's Cookie header. */
export function cookieOf(request, name) {
  for (const part of (request.headers.cookie ?? '').split(';')) {
    const at = part.indexOf('=');
    if (at > 0 && part.slice(0, at).trim() === name) return part.slice(at + 1).trim();
  }
  return null;
}

/** The Set-Cookie header for a session (or its end, with a null value). */
export function sessionHeader(value, secure) {
  const common = `Path=/; HttpOnly; SameSite=Strict${secure ? '; Secure' : ''}`;
  return value === null ? `${SESSION_COOKIE}=; Max-Age=0; ${common}` : `${SESSION_COOKIE}=${value}; Max-Age=${SESSION_SECONDS}; ${common}`;
}
