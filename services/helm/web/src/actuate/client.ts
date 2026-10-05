// Actuating a board recommendation from the web — the client half of
// POST <mount>/helm/{accept,engage,dismiss}.
//
// WHY THIS IS NOT IN drill/client.ts, AND WHY THE TYPES ARE NOT IN contract.ts:
// the same two reasons open/client.ts gives (which see). These routes are
// helm-svc's own, not on the supervisor's OpenAPI, so there is no generated
// client — this is a plain fetch, like the board read. And contract.ts mirrors
// the BOARD contract, whose parity test (web/contract_parity_test.go) rejects any
// `export interface` with no board.Board Go struct to pair with. So the two shapes
// below are hand-mirrored here, beside the fetch that reads them, deliberately
// small and flat. Their Go originals are actuateResponse and actuateErrorBody in
// internal/server/actuate.go.

import { SVC_WRITE_HEADERS } from '../svcWrite';

/** The three parity write verbs. open has its own richer client (open/client.ts). */
export type ActuateVerb = 'accept' | 'engage' | 'dismiss';

/**
 * The 200 body of POST <mount>/helm/{accept,engage,dismiss}. Mirrors Go
 * `actuateResponse`.
 */
export interface ActuateResult {
  bead: string;
  verb: ActuateVerb;
  /**
   * The tool's own stdout, trimmed: its success sentence, and for engage the
   * follow-on "attach: gc session attach <id>" line. May be empty, which a caller
   * renders as the verb's default sentence rather than a blank.
   */
  message: string;
}

/**
 * Why an actuation failed, as a stable slug keyed off the tool's exit code.
 *
 * Branch on this, never on the message text: the message is the tool's own
 * sentence and is expected to get MORE specific over time (gc-helm.sh's exit 3
 * still collapses three environment failures — tk-lzdty half 2 — and this surface
 * is built so that when the script separates them, the browser separates with it
 * and nothing here changes).
 */
export type ActuateReason =
  | 'invalid_bead'
  | 'forbidden'
  | 'busy'
  | 'usage'
  | 'environment'
  | 'verb_failed'
  | 'timeout'
  | 'unavailable'
  | 'internal';

/** A failed actuation, carrying the server's reason slug and its sentence. */
export class ActuateError extends Error {
  constructor(
    readonly status: number,
    readonly reason: ActuateReason | string,
    message: string,
  ) {
    super(message);
    this.name = 'ActuateError';
  }
}

/** The non-2xx body. Mirrors Go `actuateErrorBody`. */
interface ActuateErrorBody {
  error?: string;
  reason?: string;
}

/** Document-relative, for the same reason the board read is (see App.tsx): the
 *  app is served under a runtime-city-named prefix, so an absolute '/helm/<verb>'
 *  would address the supervisor root and 404. */
function actuateURL(verb: ActuateVerb): string {
  return `helm/${verb}`;
}

// What a request that never got a response may still have done, in the verb's own
// terms. None of the writes is atomic, so a dropped connection loses the RESPONSE,
// not necessarily the write — the same truth open/client.ts states for filing.
const TRANSPORT_UNCERTAINTY: Record<ActuateVerb, string> = {
  accept:
    'could not reach the board service — if the request had already been sent, the recommendation may still have been dispatched',
  engage:
    'could not reach the board service — if the request had already been sent, a Discuss sitting may still have been spawned',
  dismiss:
    'could not reach the board service — if the request had already been sent, the visit may still have been closed',
};

/**
 * Run one write verb on `bead` (a subject id, or a visit id the server resolves
 * to its subject).
 *
 * NOTE WHAT ENGAGE DOES NOT DO: like open, it does not put the operator into the
 * conversation. It spawns the Discuss sitting server-side (with --no-attach);
 * there is no pane to attach until the embedded ttyd can be retargeted at the new
 * session. Callers must say so rather than implying the conversation is on screen.
 */
export async function actuate(
  verb: ActuateVerb,
  bead: string,
  signal?: AbortSignal,
): Promise<ActuateResult> {
  let res: Response;
  try {
    res = await fetch(actuateURL(verb), {
      method: 'POST',
      signal,
      headers: SVC_WRITE_HEADERS,
      body: JSON.stringify({ bead }),
    });
  } catch (cause) {
    // The request never reached the service: offline, the tailnet dropped, the
    // service is down. Distinct from every server-decided failure below.
    if (cause instanceof DOMException && cause.name === 'AbortError') throw cause;
    throw new ActuateError(0, 'unavailable', TRANSPORT_UNCERTAINTY[verb]);
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
    const { error, reason } = body as ActuateErrorBody;
    throw new ActuateError(
      res.status,
      reason ?? 'internal',
      error !== undefined && error !== '' ? error : `the board service answered HTTP ${res.status}`,
    );
  }
  return body as ActuateResult;
}
