// Filing a conversation from the page: the client half of POST <mount>/helm/open,
// which Discuss's form calls.
//
// The route is helm-svc's own, not on the supervisor's OpenAPI, so there is no
// generated client: this is a plain `fetch`, like the page's own reads. Its two
// shapes are mirrored here by hand, beside the fetch that reads them, small and
// flat so hand-mirroring stays cheap. Their Go originals are openResponse and the
// error body in internal/server/actuate.go.

import { SVC_WRITE_HEADERS } from '../svcWrite';

/** Document-relative: the page is served under a runtime-city-named prefix, so
 *  an absolute '/helm/open' would address the supervisor root and 404. */
const OPEN_URL = 'helm/open';

/**
 * What the city did. `filed` is a new conversation in the operator's queue;
 * `existing` means one was already waiting on this bead and a second was
 * deliberately NOT created — those must read differently to the operator, or
 * clicking twice would misdescribe the city. `opened` is the honest fallback for
 * a success sentence the server could not classify: the conversation exists,
 * the phrasing was just unfamiliar.
 */
export type OpenOutcome = 'filed' | 'existing' | 'opened';

/** The 200 body of POST <mount>/helm/open. Mirrors Go `openResponse`. */
export interface OpenResult {
  bead: string;
  outcome: OpenOutcome;
  /** The conversation task's id, when the server's tool named one. */
  conversation?: string;
  /** The tool's own sentence, verbatim. */
  message: string;
}

/**
 * Why an open failed, as a stable slug keyed off the tool's exit code.
 *
 * Branch on this, never on the message text: the message is the tool's own
 * sentence and is expected to get MORE specific over time (gc-helm.sh's exit 3
 * currently collapses three distinct environment failures, and this surface
 * is built so that when the script separates them, the browser
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
 * File a conversation on `bead` in the operator's queue; no session is spawned
 * until an operator engages it.
 *
 * NOTE WHAT THIS DOES NOT DO: it neither starts a sitting nor attaches the
 * operator to one. Engaging the queued conversation (Rejoin the conversation on
 * the page, or `gc-helm engage`) is what spawns the sitting, and the page
 * mounts no terminal. Callers must say so rather than implying a conversation
 * is on screen.
 */
export async function openConversation(bead: string, signal?: AbortSignal): Promise<OpenResult> {
  let res: Response;
  try {
    res = await fetch(OPEN_URL, {
      method: 'POST',
      signal,
      headers: SVC_WRITE_HEADERS,
      body: JSON.stringify({ bead }),
    });
  } catch (cause) {
    // The request never reached the service: offline, the tailnet dropped, the
    // service is down. Distinct from every server-decided failure below.
    if (cause instanceof DOMException && cause.name === 'AbortError') throw cause;
    throw new OpenError(
      0,
      'unavailable',
      'could not reach the board service — if the request had already been sent, a conversation may still have been filed',
    );
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
