// Locating ttyd from inside the board, and proving it is actually there.
//
// DEPLOYMENT SHAPE (verified against the live city, 2026-08-11). ttyd runs as
// its own process on loopback and is published by a *separate* tailscale-serve
// mapping from the supervisor's:
//
//   ttyd:  ttyd -i 127.0.0.1 -p 7681 -b /terminal -W gc session attach <session>
//   serve: https://<host>/terminal  -> http://127.0.0.1:7681/terminal
//          https://<host>/v0        -> http://127.0.0.1:8372/v0
//
// So on the published origin the board (under /v0/city/<city>/svc/helm/) and
// ttyd (under /terminal/) are SAME-ORIGIN, which is what makes this embed
// possible at all: the socket is admitted by the board's own strict
// `connect-src 'self'` CSP with no widening, and no CORS is involved.
//
// That is a property of the tailscale mapping, NOT of the supervisor. Reach
// the board directly on the supervisor's loopback port instead and ttyd is a
// different port, so a different origin, and the terminal cannot connect. The
// plan flagged this as non-obvious and untested; it is now tested, and the
// check below is the test made permanent.

/** Where ttyd is published on the board's own origin. */
export const DEFAULT_TERMINAL_BASE = '/terminal';

/**
 * Reads the terminal base path, honouring a `?terminal=` override.
 *
 * The override exists so an operator can point the tile at a differently
 * mapped ttyd without a rebuild (this bundle is committed and served by
 * go:embed). It accepts only a same-origin absolute path: a full URL would
 * silently be blocked by the board's `connect-src 'self'` CSP, and accepting
 * one would turn a config knob into a way to aim the operator's terminal
 * session at another host.
 */
export function resolveTerminalBase(search: string): string {
  const raw = new URLSearchParams(search).get('terminal');
  if (raw === null) return DEFAULT_TERMINAL_BASE;
  // "//host/path" is protocol-relative — a different origin wearing a path's
  // clothing — so require exactly one leading slash.
  if (!raw.startsWith('/') || raw.startsWith('//')) return DEFAULT_TERMINAL_BASE;
  return stripTrailingSlash(raw);
}

function stripTrailingSlash(path: string): string {
  return path.replace(/\/+$/, '');
}

/** The token endpoint ttyd serves under its base path. */
export function tokenURL(base: string): string {
  return `${stripTrailingSlash(base)}/token`;
}

/**
 * The WebSocket URL for ttyd's base path, on the current origin.
 *
 * An https document must use wss: — a ws: socket from a secure page is blocked
 * as mixed content — and the board is served over https wherever tailscale
 * publishes it.
 */
export function socketURL(base: string, location: Pick<Location, 'protocol' | 'host'>): string {
  const scheme = location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${scheme}//${location.host}${stripTrailingSlash(base)}/ws`;
}

/** The outcome of {@link probeTerminal}. */
export type TerminalProbe =
  | { reachable: true; token: string }
  | { reachable: false; reason: string };

/**
 * Confirms ttyd is reachable on this origin, and returns its auth token.
 *
 * WHY THIS IS NOT JUST A STATUS CHECK. The supervisor serves a single-page app
 * at its root with a catch-all that answers *every* unmatched path with a 200
 * and an HTML shell. Probing for `/terminal` by status code therefore succeeds
 * on an origin where ttyd is not routed at all — verified: on the supervisor's
 * own port, `GET /terminal/token` returns `200 text/html` with the dashboard
 * shell, while real ttyd returns `200 application/json` with `{"token": ""}`.
 * A status-only probe reports a working terminal and the operator finds out
 * when the socket dies instead. Discriminating on content type is what makes
 * the check honest.
 *
 * An empty token is normal and not a failure: ttyd only issues a non-empty one
 * when it is configured with credentials.
 */
export async function probeTerminal(
  base: string,
  fetchImpl: typeof fetch = fetch,
  signal?: AbortSignal,
): Promise<TerminalProbe> {
  let res: Response;
  try {
    res = await fetchImpl(tokenURL(base), { signal, headers: { Accept: 'application/json' } });
  } catch (err) {
    return { reachable: false, reason: `terminal endpoint unreachable: ${describe(err)}` };
  }
  if (!res.ok) {
    return { reachable: false, reason: `terminal endpoint returned HTTP ${res.status}` };
  }
  const contentType = res.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().includes('application/json')) {
    return {
      reachable: false,
      reason:
        `${base} is not ttyd on this origin (got ${contentType || 'no content-type'}). ` +
        'ttyd is published by its own mapping; this origin routes the board but not the terminal.',
    };
  }
  let body: unknown;
  try {
    body = await res.json();
  } catch (err) {
    return { reachable: false, reason: `terminal token was not JSON: ${describe(err)}` };
  }
  if (typeof body !== 'object' || body === null || !('token' in body)) {
    return { reachable: false, reason: 'terminal token response had no token field' };
  }
  const token = (body as { token: unknown }).token;
  if (typeof token !== 'string') {
    return { reachable: false, reason: 'terminal token was not a string' };
  }
  return { reachable: true, token };
}

function describe(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
