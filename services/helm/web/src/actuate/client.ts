// Engaging a conversation from the page: the client half of
// POST <mount>/helm/engage, which Start the conversation and Rejoin the
// conversation call.
//
// The route is helm-svc's own, not on the supervisor's OpenAPI, so there is no
// generated client: this is a plain fetch, like the page's own reads. Its shapes
// are mirrored here by hand, beside the fetch that reads them, small and flat.
// Their Go originals are actuateResponse and actuateErrorBody in
// internal/server/actuate.go.

import { SVC_WRITE_HEADERS } from '../svcWrite';

/** The 200 body of POST <mount>/helm/engage. Mirrors Go `actuateResponse`. */
export interface ActuateResult {
  bead: string;
  verb: string;
  /**
   * The tool's own stdout, trimmed: its success sentence, and the follow-on
   * "attach: <command>" line that names the command to run. May be empty, which
   * a caller renders as a default sentence rather than a blank.
   */
  message: string;
}

/**
 * Why an engage failed, as a stable slug keyed off the tool's exit code.
 *
 * Branch on this, never on the message text: the message is the tool's own
 * sentence and is expected to get more specific over time, and this surface is
 * built so that when the script's sentences change, the browser shows the new
 * ones and nothing here changes.
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

/** A failed engage, carrying the server's reason slug and its sentence. */
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

/** Document-relative: the page is served under a runtime-city-named prefix, so
 *  an absolute '/helm/engage' would address the supervisor root and 404. */
const ENGAGE_URL = 'helm/engage';

/**
 * Engage `bead`: a question, a decision or a conversation, which the server's
 * tool resolves to the conversation it concerns.
 *
 * NOTE WHAT ENGAGE DOES NOT DO. It spawns the sitting server-side (the route
 * runs the tool with --no-attach) and attaches nothing: the page mounts no
 * terminal, so the operator runs the attach command the answer names. Callers
 * must say so rather than implying the conversation is on screen.
 */
export async function engage(bead: string, signal?: AbortSignal): Promise<ActuateResult> {
  let res: Response;
  try {
    res = await fetch(ENGAGE_URL, {
      method: 'POST',
      signal,
      headers: SVC_WRITE_HEADERS,
      body: JSON.stringify({ bead }),
    });
  } catch (cause) {
    // The request never reached the service: offline, the tailnet dropped, the
    // service is down. None of the writes is atomic, so a dropped connection
    // loses the response, not necessarily the write.
    if (cause instanceof DOMException && cause.name === 'AbortError') throw cause;
    throw new ActuateError(
      0,
      'unavailable',
      'could not reach the board service — if the request had already been sent, a sitting may still have been spawned',
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
    const { error, reason } = body as ActuateErrorBody;
    throw new ActuateError(
      res.status,
      reason ?? 'internal',
      error !== undefined && error !== '' ? error : `the board service answered HTTP ${res.status}`,
    );
  }
  return body as ActuateResult;
}

/**
 * The command a line of an engage answer names to run, from a line of the form
 * "attach: <command>", or null for any other line.
 */
export function attachCommand(line: string): string | null {
  const m = /^\s*attach:\s*(\S.*?)\s*$/.exec(line);
  return m === null ? null : m[1];
}
