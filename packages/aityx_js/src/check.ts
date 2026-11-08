// The status check: does aityx accept the key? The TypeScript twin of
// packages/aityx_web/lib/src/check.dart.

import { AityxConnection, type AityxSource } from './connection';
import { isRecord, resolveConnection, spoken, tryJson, type ResolveOptions } from './settings';

export type AityxStateKind =
  /** aityx accepts the key. */
  | 'ready'
  /** There's no key: neither the user's nor a dev key. */
  | 'noKey'
  /** aityx refused the key (401, 403). */
  | 'rejected'
  /** No answer: the network, CORS, an ad blocker, a timeout, or (dev mode) the proxy couldn't reach aityx. */
  | 'unreachable'
  /** aityx answered something unexpected. */
  | 'failing';

/** The result of the status check. */
export interface AityxState {
  /** Whether aityx accepts the key. */
  readonly ok: boolean;
  /** Whether there is a key (the user's or a dev key). */
  readonly key: boolean;
  readonly source: AityxSource;
  /** The aityx URL the key goes to; null without a key. */
  readonly url: string | null;
  /** Why, for people. */
  readonly detail: string;
  readonly kind: AityxStateKind;
  /** Whose key, as AityxConnection.whose says it. */
  readonly whose: string;
}

/** No key anywhere. */
export const NO_KEY: AityxState = {
  ok: false,
  key: false,
  source: 'none',
  url: null,
  detail: 'set yours with the light, top right',
  kind: 'noKey',
  whose: 'no key',
};

/** The light's tooltip, also its accessible label. */
export function stateTooltip(state: AityxState): string {
  switch (state.kind) {
    case 'ready':
      return state.url === null || state.url === ''
        ? 'aityx: ready — the key works'
        : `aityx: ready — the key works with ${state.url}`;
    case 'noKey':
      return 'aityx: no key — set yours here';
    case 'rejected':
      return `aityx: key rejected — ${state.detail}`;
    case 'unreachable':
      return `aityx: not reachable — ${state.detail}`;
    case 'failing':
      return `aityx: not working — ${state.detail}`;
  }
}

export interface CheckOptions extends ResolveOptions {
  /** The connection to check; resolved (resolveConnection) unless given. */
  connection?: AityxConnection;
}

/**
 * Asks aityx whether it accepts the key, without running a model: POSTs
 * `{}` to systemone, which checks the key first, so a working key gets
 * 400 "invalid_request" and a bad one 401. Each check spends a request of
 * the user's quota. Never throws.
 */
export async function checkAityx(options: CheckOptions = {}): Promise<AityxState> {
  const ask = options.fetch ?? ((input: RequestInfo | URL, init?: RequestInit) => globalThis.fetch(input, init));
  const to = options.connection ?? (await resolveConnection({ ...options, fetch: ask }));
  if (to.source === 'none') return NO_KEY;
  const timeoutMs = options.timeoutMs ?? 15_000;
  try {
    const answer = await ask(to.systemone, {
      method: 'POST',
      headers: to.headers(),
      body: '{}',
      signal: AbortSignal.timeout(timeoutMs),
    });
    return classifyAityx({ status: answer.status, body: await answer.text(), connection: to });
  } catch (error) {
    const where = to.source === 'dev' ? `the dev proxy (${to.endpoint.href})` : to.url;
    const timedOut = error instanceof Error && error.name === 'TimeoutError';
    return state(
      to,
      'unreachable',
      timedOut ? `no answer from ${where} in ${spoken(timeoutMs)}` : `no answer from ${where} (network, CORS or a blocker)`,
    );
  }
}

/** What aityx's answer to the check's empty POST says about the connection's key. */
export function classifyAityx(answer: { status: number; body: string; connection: AityxConnection }): AityxState {
  const { status, body, connection } = answer;
  if (connection.source === 'none') return NO_KEY;
  const json = tryJson(body);
  const field = (name: string): string | null => {
    if (!isRecord(json)) return null;
    const value = json[name];
    return typeof value === 'string' && value !== '' ? value : null;
  };
  const code = field('code');
  const detail = field('detail');
  const said = `HTTP ${status}${detail === null ? '' : `: ${detail}`}`;
  if (status === 400 && code === 'invalid_request') {
    return state(connection, 'ready', 'aityx accepts the key');
  }
  if (status === 401 || status === 403) {
    return state(
      connection,
      'rejected',
      connection.source === 'user' ? `aityx answered ${said}: set a new key` : `aityx answered ${said}`,
    );
  }
  // The server's proxy, when it couldn't reach aityx.
  if (connection.source === 'dev' && status === 502 && (code === 'proxy_unreachable' || code === 'proxy_redirect')) {
    return state(connection, 'unreachable', detail ?? 'the dev proxy could not reach aityx');
  }
  if (status >= 300 && status < 400) {
    return state(connection, 'failing', `aityx answered HTTP ${status}, a redirect: it may be behind a login`);
  }
  return state(connection, 'failing', `aityx answered ${said}`);
}

function state(to: AityxConnection, kind: AityxStateKind, detail: string): AityxState {
  return { ok: kind === 'ready', key: true, source: to.source, url: to.url, detail, kind, whose: to.whose };
}
