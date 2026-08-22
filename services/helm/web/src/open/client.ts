// Filing a visit from the board — the client half of POST <mount>/helm/open.
//
// WHY THIS IS NOT IN drill/client.ts. That file is the SUPERVISOR client: every
// type in it comes from gen/supervisor.d.ts, generated from the supervisor's
// own OpenAPI document, and a path missing from those types fails to compile.
// This route is not on the supervisor at all — it is helm-svc's own, and the
// supervisor spec declares `post?: never` on all eight of its paths. So this is
// a plain `fetch`, exactly like the board read in App.tsx.
//
// WHY THE TYPES ARE NOT IN contract.ts. That file mirrors the BOARD contract,
// and web/contract_parity_test.go enforces a two-way match between its
// `export interface`s and the Go structs reachable from board.Board — an
// interface added there for this route fails that test with nothing to pair
// with. The two shapes below are therefore mirrored here, beside the fetch that
// reads them, and are deliberately small and flat so hand-mirroring stays
// cheap. Their Go originals are openResponse and openErrorBody in
// internal/server/open.go.

/** Document-relative, for the same reason the board read is (see App.tsx): the
 *  app is served under a runtime-city-named prefix, so an absolute '/helm/open'
 *  would address the supervisor root and 404. */
const OPEN_URL = 'helm/open';

/**
 * What the city did. `filed` is a new visit; `existing` means one was already
 * open on this bead and a second was deliberately NOT created — those must read
 * differently to the operator, or clicking twice would misdescribe the city.
 * `opened` is the honest fallback for a success sentence the server could not
 * classify: the visit exists, the phrasing was just unfamiliar.
 */
export type OpenOutcome = 'filed' | 'existing' | 'opened';

/** The 200 body of POST <mount>/helm/open. Mirrors Go `openResponse`. */
export interface OpenResult {
  bead: string;
  outcome: OpenOutcome;
  /** The visit bead's id, when the server's tool named one. */
  visit?: string;
  /** The tool's own sentence, verbatim. */
  message: string;
}

/**
 * Why an open failed, as a stable slug keyed off the tool's exit code.
 *
 * Branch on this, never on the message text: the message is the tool's own
 * sentence and is expected to get MORE specific over time (gc-helm.sh's exit 3
 * currently collapses three distinct environment failures — tk-lzdty half 2 —
 * and this surface is built so that when the script separates them, the browser
 * separates with it and nothing here changes).
 */
export type OpenReason =
  | 'invalid_bead'
  | 'forbidden'
  | 'busy'
  | 'usage'
  | 'environment'
  | 'verb_failed'
  | 'timeout'
  | 'unavailable'
  | 'internal';

/** A failed open, carrying the server's reason slug and its sentence. */
export class OpenError extends Error {
  constructor(
    readonly status: number,
    readonly reason: OpenReason | string,
    message: string,
  ) {
    super(message);
    this.name = 'OpenError';
  }
}

/** The non-2xx body. Mirrors Go `openErrorBody`. */
interface OpenErrorBody {
  error?: string;
  reason?: string;
}

/**
 * File a visit on `bead`, so a converse session picks it up.
 *
 * NOTE WHAT THIS DOES NOT DO: it does not put the operator into the
 * conversation. In tmux, `gc-helm.sh open` reattaches the caller; in a browser
 * there is no pane to attach until the embedded ttyd can be retargeted at the
 * new session (tk-rbf9r / tk-xlup8, unapplied). Callers must say so rather than
 * implying the conversation is on screen.
 */
export async function openConversation(bead: string, signal?: AbortSignal): Promise<OpenResult> {
  let res: Response;
  try {
    res = await fetch(OPEN_URL, {
      method: 'POST',
      signal,
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ bead }),
    });
  } catch (cause) {
    // The request never reached the service: offline, the tailnet dropped, the
    // service is down. Distinct from every server-decided failure below.
    if (cause instanceof DOMException && cause.name === 'AbortError') throw cause;
    throw new OpenError(0, 'unavailable', 'could not reach the board service — no visit was filed');
  }

  // Read the body once, then interpret. A non-JSON error body (a proxy's HTML
  // 502, say) must not turn into an unhandled parse error that hides the status.
  const raw = await res.text();
  let body: unknown;
  try {
    body = raw === '' ? {} : JSON.parse(raw);
  } catch {
    body = {};
  }

  if (!res.ok) {
    const { error, reason } = body as OpenErrorBody;
    throw new OpenError(
      res.status,
      reason ?? 'internal',
      error !== undefined && error !== '' ? error : `the board service answered HTTP ${res.status}`,
    );
  }
  return body as OpenResult;
}
