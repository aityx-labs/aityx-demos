// aityx from the browser, for the demos written in TypeScript (the tatyx
// group): the key, systemone calls, the status check, the status light
// and the key form. See README.md.

export {
  AITYX_DEFAULT_URL,
  AITYX_KEY_NAME,
  AITYX_URL_NAME,
  AityxConnection,
  normalizeAityxUrl,
  type AityxRelay,
  type AityxSource,
} from './connection';
export {
  MapArea,
  StorageKeyStore,
  browserKeyStore,
  memoryKeyStore,
  type AityxKeyStore,
  type StorageArea,
  type Unsubscribe,
} from './keyStore';
export { DEFAULT_PROXY_PATH, pageOrigin, resolveConnection, spoken, tryJson, type ResolveOptions } from './settings';
export { AityxAnswer, AityxClient, AityxNoKey, AityxUnreachable, type ClientOptions } from './client';
export { NO_KEY, checkAityx, classifyAityx, stateTooltip, type AityxState, type AityxStateKind, type CheckOptions } from './check';
export { LIGHT_COLORS, mountStatusLight, type StatusLight, type StatusLightOptions } from './statusLight';
export { keyUnchanged, mountKeyForm, type KeyForm, type KeyFormOptions } from './keyForm';
