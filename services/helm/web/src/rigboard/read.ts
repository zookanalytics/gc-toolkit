// The page's reads of the helm service: the city's rigs, and one rig's document
// (internal/server/rigboard.go). Both are document-relative: the page is served
// under a runtime-city-named prefix (/v0/city/<city>/svc/helm/), so an absolute
// '/helm/...' would address the supervisor root and 404.

import type { Response as RigResponse, Rigs } from './document.gen';

/** A read the service refused, or one that never reached it (status 0). */
export class ReadError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ReadError';
  }
}

// How long one read may stay unanswered before the page drops it. The service
// bounds a gather at 30 s (gatherTimeout in internal/server/server.go), so a
// read open twice that long is a connection that will not answer.
export const READ_TIMEOUT_MS = 60_000;

async function readJSON<T>(url: string, signal: AbortSignal): Promise<T> {
  let res: globalThis.Response;
  try {
    res = await fetch(url, { signal, headers: { Accept: 'application/json' } });
  } catch (cause) {
    if (cause instanceof DOMException && cause.name === 'AbortError') throw cause;
    throw new ReadError(0, 'could not reach the board service');
  }
  // Read the body once, then interpret: a proxy's HTML error page must not
  // turn into a parse error that hides the status.
  const raw = await res.text();
  let body: unknown;
  try {
    body = raw === '' ? undefined : JSON.parse(raw);
  } catch {
    body = undefined;
  }
  if (!res.ok) {
    const error = (body as { error?: unknown } | undefined)?.error;
    throw new ReadError(
      res.status,
      typeof error === 'string' && error !== '' ? error : `the board service answered HTTP ${res.status}`,
    );
  }
  if (body === undefined) throw new ReadError(res.status, 'the board service answered with no JSON');
  return body as T;
}

/** GET <mount>/helm/rigs: the city's rigs by name. */
export function readRigs(signal: AbortSignal): Promise<Rigs> {
  return readJSON<Rigs>('helm/rigs', signal);
}

/** GET <mount>/helm/rigs/{rig}: one rig's document and the time it was read. */
export function readRig(rig: string, signal: AbortSignal): Promise<RigResponse> {
  return readJSON<RigResponse>(`helm/rigs/${encodeURIComponent(rig)}`, signal);
}

/** The rig the address names (?rig=<name>), or null when it names none. */
export function rigFromAddress(search: string): string | null {
  const rig = new URLSearchParams(search).get('rig')?.trim() ?? '';
  return rig === '' ? null : rig;
}

/** The address of one rig's page, relative to the page itself. */
export function rigAddress(rig: string): string {
  return `?rig=${encodeURIComponent(rig)}`;
}
