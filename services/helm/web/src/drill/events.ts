// Live half of the drill plane: the supervisor's city event stream.
//
// Three things about this stream are easy to get wrong and are all load-bearing:
//
//  1. THE EVENT NAME IS LITERALLY "event". The supervisor sends `event: event`
//     frames, not unnamed ones. EventSource routes a NAMED event only to
//     addEventListener('<name>'); only unnamed frames reach .onmessage. Bind
//     both — the spec pins the name (`event: { const: 'event' }` on the stream
//     response) but a plain .onmessage handler alone silently receives nothing.
//  2. RECONNECTION IS OURS TO DRIVE, AND SO IS THE RESUME CURSOR. EventSource
//     retries on its own only for a clean server close; a network drop or a
//     supervisor restart surfaces as onerror with the connection dead, so we
//     reconnect with capped exponential backoff. What is easy to miss is that
//     the browser resends Last-Event-ID only on ITS OWN reconnect of the SAME
//     EventSource object — a replacement object we construct carries no header
//     and no cursor, and the supervisor documents that as "start at the current
//     city event head". Every event emitted during the gap would be dropped,
//     silently, while the indicator went back to reading "live". So the
//     replacement URL carries `after_seq` explicitly (the query-param half of
//     the same contract) pinned to the highest seq we have actually delivered.
//  3. A MALFORMED FRAME IS NOT A CRASH. The board is a pull surface the
//     operator leaves open for hours; one unparseable frame degrades the
//     indicator and is skipped.

import type { CityEvent } from './client';
import { cityUrl, type SupervisorOrigin } from './origin';

export type StreamState = 'connecting' | 'open' | 'degraded' | 'closed';

export interface SubscribeOptions {
  /** Called for each well-formed event, in arrival order. */
  onEvent: (event: CityEvent) => void;
  /** Connection state transitions, for an honest liveness indicator. */
  onState?: (state: StreamState) => void;
  /** Seeded backoff delay; doubles per failed attempt. */
  retryBaseMs?: number;
  /** Ceiling for the backoff. */
  retryMaxMs?: number;
  /**
   * EventSource implementation. Injectable so tests can drive frames
   * deterministically instead of standing up a server; defaults to the global.
   */
  eventSourceCtor?: typeof EventSource;
}

const DEFAULT_RETRY_BASE_MS = 1_000;
const DEFAULT_RETRY_MAX_MS = 30_000;

/**
 * Subscribe to the city event stream. Returns an unsubscribe that closes the
 * connection and cancels any pending reconnect; it is safe to call more than
 * once, and no callback fires after it.
 */
export function subscribeCityEvents(
  origin: SupervisorOrigin,
  options: SubscribeOptions,
): () => void {
  const {
    onEvent,
    onState,
    retryBaseMs = DEFAULT_RETRY_BASE_MS,
    retryMaxMs = DEFAULT_RETRY_MAX_MS,
    eventSourceCtor = typeof EventSource === 'function' ? EventSource : undefined,
  } = options;

  let cancelled = false;
  let source: EventSource | null = null;
  let retryTimer: ReturnType<typeof setTimeout> | null = null;
  let retryDelayMs = retryBaseMs;
  /**
   * Highest seq handed to `onEvent`, or null before the first one.
   *
   * The highest rather than the most recent: a supervisor restart can replay
   * frames we have already delivered, and a cursor that walked backwards would
   * ask for that replay again on every subsequent reconnect.
   */
  let resumeSeq: number | null = null;

  const setState = (state: StreamState) => {
    if (!cancelled) onState?.(state);
  };

  if (eventSourceCtor === undefined) {
    // No EventSource (a non-browser host). The rest of the plane still works;
    // it just does not update itself.
    setState('closed');
    return () => {};
  }

  const baseUrl = cityUrl(origin, '/events/stream');
  // No cursor on the first connection: the board opens on the live present, not
  // on a replay of the city's backlog. A cursor exists only once we have
  // delivered something to resume after.
  const streamUrl = () =>
    resumeSeq === null ? baseUrl : `${baseUrl}?after_seq=${encodeURIComponent(String(resumeSeq))}`;

  const handleFrame = (message: MessageEvent<string>) => {
    if (cancelled) return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(message.data);
    } catch {
      setState('degraded');
      return;
    }
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      setState('degraded');
      return;
    }
    if (typeof (parsed as { type?: unknown }).type !== 'string') {
      setState('degraded');
      return;
    }
    const seq = (parsed as { seq?: unknown }).seq;
    if (typeof seq === 'number' && Number.isFinite(seq) && (resumeSeq === null || seq > resumeSeq)) {
      resumeSeq = seq;
    }
    setState('open');
    onEvent(parsed as CityEvent);
  };

  const connect = () => {
    if (cancelled) return;
    setState('connecting');
    const opened = new eventSourceCtor(streamUrl());
    source = opened;

    opened.onopen = () => {
      if (cancelled || source !== opened) return;
      retryDelayMs = retryBaseMs;
      setState('open');
    };
    opened.onmessage = handleFrame;
    opened.addEventListener('event', handleFrame as EventListener);
    opened.onerror = () => {
      if (cancelled || source !== opened) return;
      opened.close();
      source = null;
      setState('closed');
      const delay = retryDelayMs;
      retryDelayMs = Math.min(retryDelayMs * 2, retryMaxMs);
      retryTimer = setTimeout(connect, delay);
    };
  };

  connect();

  return () => {
    if (cancelled) return;
    cancelled = true;
    if (retryTimer !== null) clearTimeout(retryTimer);
    retryTimer = null;
    source?.close();
    source = null;
  };
}

/**
 * A single city stream fanned out to many consumers.
 *
 * The drill panel and the city-signals strip both want live events, and they
 * come and go independently as the operator opens and closes tiles. Without a
 * hub each would open its own EventSource: two TCP connections and two full
 * event firehoses per document, for one stream of bytes. The hub ref-counts —
 * the first subscriber connects, the last one to leave disconnects — so an
 * idle board holds no connection at all and a busy one holds exactly one.
 */
export interface EventHub {
  /** Add a listener. Returns an unsubscribe; safe to call more than once. */
  subscribe: (onEvent: (event: CityEvent) => void, onState?: (state: StreamState) => void) => () => void;
}

export function createEventHub(
  origin: SupervisorOrigin,
  options: Omit<SubscribeOptions, 'onEvent' | 'onState'> = {},
): EventHub {
  const eventListeners = new Set<(event: CityEvent) => void>();
  const stateListeners = new Set<(state: StreamState) => void>();
  let disconnect: (() => void) | null = null;
  let state: StreamState = 'closed';

  const start = () => {
    disconnect = subscribeCityEvents(origin, {
      ...options,
      onEvent: (event) => {
        // Snapshot: a listener may unsubscribe (or subscribe) while dispatching.
        for (const listener of [...eventListeners]) listener(event);
      },
      onState: (next) => {
        state = next;
        for (const listener of [...stateListeners]) listener(next);
      },
    });
  };

  return {
    subscribe(onEvent, onState) {
      eventListeners.add(onEvent);
      if (onState !== undefined) {
        stateListeners.add(onState);
        // Hand the newcomer the current state rather than leaving its indicator
        // stale until the next transition, which on a healthy stream never comes.
        onState(state);
      }
      if (disconnect === null) start();

      let released = false;
      return () => {
        if (released) return;
        released = true;
        eventListeners.delete(onEvent);
        if (onState !== undefined) stateListeners.delete(onState);
        if (eventListeners.size === 0 && stateListeners.size === 0) {
          disconnect?.();
          disconnect = null;
          state = 'closed';
        }
      };
    },
  };
}

/**
 * Does `event` concern `beadId`?
 *
 * The city stamps the bead id in more than one place depending on the event
 * family, and a drill panel that watched only one of them would sit still
 * through exactly the updates the operator opened it for:
 *
 *   - `subject` carries it for bead.* events (the envelope's subject IS the id);
 *   - `payload.bead_id` for the several payload shapes that name it explicitly;
 *   - session events name the bead they are working via `payload.work_bead_ids`.
 *
 * Checked structurally rather than by enumerating event types, so a new event
 * family that follows the same convention is picked up without a change here.
 */
export function eventConcernsBead(event: CityEvent, beadId: string): boolean {
  if (event.subject === beadId) return true;
  const payload: unknown = (event as { payload?: unknown }).payload;
  if (typeof payload !== 'object' || payload === null) return false;
  const record = payload as Record<string, unknown>;
  if (record.bead_id === beadId) return true;
  const workBeads = record.work_bead_ids;
  return Array.isArray(workBeads) && workBeads.includes(beadId);
}

/** Does `event` concern the session with id `sessionId`? */
export function eventConcernsSession(event: CityEvent, sessionId: string): boolean {
  if (event.session_id === sessionId) return true;
  if (event.subject === sessionId) return true;
  const payload: unknown = (event as { payload?: unknown }).payload;
  if (typeof payload !== 'object' || payload === null) return false;
  return (payload as Record<string, unknown>).session_id === sessionId;
}
