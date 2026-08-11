// The drill itself: everything known about one anchor, kept live.
//
// Opening a tile fetches the bead, the session working it (if any), and the
// recent activity concerning either. From then on the panel is driven by the
// event stream, in the two ways that differ in cost:
//
//   - The activity feed applies each matching event DIRECTLY. The event is the
//     data; refetching to learn what it already told us would be silly.
//   - Bead and session state is REFETCHED, coalesced. An event says "this
//     changed", not what it changed to, and a busy anchor can emit a burst —
//     so a trailing throttle turns a burst into one refetch.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { unreadList, type Bead, type CityEvent, type Session } from './client';
import { useDrillContext } from './context';
import { eventConcernsBead, eventConcernsSession, type StreamState } from './events';

/** Newest-first, capped — the panel shows a tail, not a log. */
const ACTIVITY_LIMIT = 50;
/**
 * How far back to look when seeding the feed, in events.
 *
 * The filter has to run client-side: the city event log is one shared stream
 * across every rig, and /events can be narrowed by type, actor, or time but NOT
 * by subject — so there is no way to ask the supervisor for "events about this
 * anchor". This is a scan of the tail, and it is not free: events carry their
 * payloads, so the window costs roughly 1.3KB each on the wire (measured
 * against the live city, 2026-08-11).
 *
 * 100 keeps one drill-open around 130KB while still covering the recent past of
 * a busy anchor — which is the kind an operator drills into. It runs once per
 * open, not per event; the stream carries everything after it.
 */
const HISTORY_SCAN = 100;
/** Trailing window for event-driven refetches. */
const REFETCH_COALESCE_MS = 1_500;

export interface DrillDetail {
  bead: Bead | null;
  /** The session currently working this bead, if one is. */
  session: Session | null;
  /**
   * True when the session lookup could not rule one out: the session list came
   * back incomplete and nothing in the part that answered claims this anchor.
   * `session === null` then means *not known*, not *nobody* — the difference
   * between an idle anchor and an unanswered store, which the operator has no
   * other way to tell apart.
   */
  sessionUncertain: boolean;
  /** Matching events, newest first. */
  activity: CityEvent[];
  /** True when the activity seed is known to be missing events. */
  activityIncomplete: boolean;
  /** Per-store reasons some part of this drill is incomplete; empty when none. */
  partialErrors: string[];
  loading: boolean;
  error: string | null;
  stream: StreamState;
  /** True when the plane could not resolve a supervisor origin at all. */
  unavailable: boolean;
  reload: () => void;
}

const EMPTY_ACTIVITY: CityEvent[] = [];
const NO_REASONS: string[] = [];

export function useDrill(beadId: string | null): DrillDetail {
  const ctx = useDrillContext();
  const [bead, setBead] = useState<Bead | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [sessionUncertain, setSessionUncertain] = useState(false);
  const [activity, setActivity] = useState<CityEvent[]>(EMPTY_ACTIVITY);
  const [activityIncomplete, setActivityIncomplete] = useState(false);
  const [partialErrors, setPartialErrors] = useState<string[]>(NO_REASONS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [stream, setStream] = useState<StreamState>('closed');
  const [reloadToken, setReloadToken] = useState(0);

  const reload = useCallback(() => setReloadToken((n) => n + 1), []);

  // The session id is what the event filter needs, and it changes only when the
  // session does — keep it in a ref so a new event does not re-subscribe.
  const sessionIdRef = useRef<string | null>(null);
  sessionIdRef.current = session?.id ?? null;

  // Switching anchors must drop the previous one's detail in the SAME render,
  // before the new read starts. Otherwise the panel keeps rendering tile A's
  // title/facts/session/activity under tile B's header until B's read lands —
  // and if B's bead read fails, that stale detail would sit under the error
  // alert indefinitely, since the catch below only sets `error`. Resetting here
  // (the React "adjust state when a prop changes" idiom) rather than in an
  // effect avoids painting even one stale frame; gating on `detailBeadId`
  // instead of resetting on every `reloadToken` bump keeps a coalesced
  // same-anchor refetch from blanking the panel mid-stream.
  const [detailBeadId, setDetailBeadId] = useState<string | null>(beadId);
  if (beadId !== detailBeadId) {
    setDetailBeadId(beadId);
    setBead(null);
    setSession(null);
    setSessionUncertain(false);
    setActivity(EMPTY_ACTIVITY);
    setActivityIncomplete(false);
    setPartialErrors(NO_REASONS);
    setError(null);
    setLoading(beadId !== null);
  }

  useEffect(() => {
    if (ctx === null || beadId === null) {
      setBead(null);
      setSession(null);
      setSessionUncertain(false);
      setActivity(EMPTY_ACTIVITY);
      setActivityIncomplete(false);
      setPartialErrors(NO_REASONS);
      setError(null);
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    const { signal } = controller;
    let cancelled = false;
    setLoading(true);

    void (async () => {
      try {
        const [nextBead, sessions] = await Promise.all([
          ctx.reads.bead(beadId, signal),
          // A failed session lookup must not hide the bead: liveness is a
          // secondary signal here, and the board is explicitly a
          // degrade-honestly surface. Degrading is not the same as answering,
          // though — `unreadList` keeps the failure visible instead of
          // flattening it into an empty list the panel would read as "nobody".
          ctx.reads.sessions(signal).catch((err) => unreadList<Session>(err)),
        ]);
        if (cancelled) return;
        setBead(nextBead);
        setError(null);

        const working = sessions.items.find((candidate) => candidate.active_bead === beadId) ?? null;
        // Finding a session settles the question whatever else went missing;
        // finding none settles it only if the whole list answered.
        setSessionUncertain(working === null && sessions.partial);
        // Re-read the one session with ?peek so the panel gets its latest
        // output; fall back to the list entry if the peek fails.
        let detailed = working;
        if (working !== null) {
          detailed = await ctx.reads.session(working.id, signal).catch(() => working);
        }
        if (cancelled) return;
        setSession(detailed);

        const history = await ctx.reads
          .recentEvents(HISTORY_SCAN, signal)
          .catch((err) => unreadList<CityEvent>(err));
        if (cancelled) return;
        setActivity(
          history.items
            .filter(
              (event) =>
                eventConcernsBead(event, beadId) ||
                (detailed !== null && eventConcernsSession(event, detailed.id)),
            )
            .slice(0, ACTIVITY_LIMIT),
        );
        setActivityIncomplete(history.partial);
        const reasons = [...sessions.partialErrors, ...history.partialErrors];
        setPartialErrors(reasons.length === 0 ? NO_REASONS : reasons);
      } catch (err) {
        if (cancelled || signal.aborted) return;
        setError(err instanceof Error ? err.message : String(err));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [ctx, beadId, reloadToken]);

  // Live updates. Bound to [ctx, beadId] only: the handler reads the current
  // session id through a ref, so a session appearing mid-drill does not tear
  // down and rebuild the subscription.
  useEffect(() => {
    if (ctx === null || beadId === null) {
      setStream('closed');
      return;
    }

    let coalesceTimer: ReturnType<typeof setTimeout> | null = null;
    const scheduleRefetch = () => {
      if (coalesceTimer !== null) return;
      coalesceTimer = setTimeout(() => {
        coalesceTimer = null;
        reload();
      }, REFETCH_COALESCE_MS);
    };

    // Reconnect handling. The stream resumes from `after_seq` whenever it has
    // delivered anything, so the usual drop loses nothing. The exception is a
    // connection that died before its first event: there is no cursor, the
    // replacement starts at the city head, and whatever happened in between is
    // gone. Since this panel refetches only in response to a delivered event,
    // that would leave it reading "live" over state that stopped moving. So
    // refetch on the way back up rather than trusting the gap was empty.
    //
    // A real drop is a 'closed' that follows a connection attempt. The hub hands
    // every new subscriber a synthetic 'closed' BEFORE it starts connecting, so
    // arm the reload only once we have seen 'connecting'. That also covers a
    // first connection that dies before it ever reached 'open' — the gap is
    // unrecoverable there too, and an "only after open" guard used to miss it.
    let attempted = false;
    let gapPending = false;

    const unsubscribe = ctx.hub.subscribe(
      (event) => {
        const sessionId = sessionIdRef.current;
        const matches =
          eventConcernsBead(event, beadId) ||
          (sessionId !== null && eventConcernsSession(event, sessionId));
        if (!matches) return;
        setActivity((current) => {
          // The stream can redeliver across a reconnect (Last-Event-ID resumes,
          // but a supervisor restart can replay), and history seeding may race
          // a live frame. Both show up as a repeated seq.
          if (current.some((seen) => seen.seq === event.seq)) return current;
          return [event, ...current].slice(0, ACTIVITY_LIMIT);
        });
        scheduleRefetch();
      },
      (next) => {
        setStream(next);
        if (next === 'connecting') {
          attempted = true;
        } else if (next === 'closed') {
          if (attempted) gapPending = true;
        } else if (next === 'open') {
          if (gapPending) {
            gapPending = false;
            scheduleRefetch();
          }
        }
      },
    );

    return () => {
      if (coalesceTimer !== null) clearTimeout(coalesceTimer);
      unsubscribe();
    };
  }, [ctx, beadId, reload]);

  return useMemo(
    () => ({
      bead,
      session,
      sessionUncertain,
      activity,
      activityIncomplete,
      partialErrors,
      loading,
      error,
      stream,
      unavailable: ctx === null,
      reload,
    }),
    [
      bead,
      session,
      sessionUncertain,
      activity,
      activityIncomplete,
      partialErrors,
      loading,
      error,
      stream,
      ctx,
      reload,
    ],
  );
}
