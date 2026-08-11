// City-wide "does anything need a human" signals, kept live off the same stream.
//
// These are the three the plan names for this plane and they are deliberately
// NOT per-tile: a pending tool-approval, unread mail, and a bead labelled
// gc:wait are all "someone is blocked on you" regardless of which anchor the
// operator happens to be looking at. They belong beside the board, not inside a
// drill panel, and they cost one cheap request each.
//
// Pull, never interrupt (R7): this refreshes in place. Nothing here notifies,
// flashes, or steals focus — the operator finds it when they look.

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { PendingEntry } from './client';
import { useDrillContext } from './context';

/** Event families that can change any of these counts. */
const SIGNAL_PREFIXES = ['mail.', 'session.', 'bead.'];
const REFRESH_COALESCE_MS = 3_000;

export interface CitySignals {
  /** Sessions blocked on a human decision right now. */
  pending: PendingEntry[];
  /**
   * How many the supervisor counted. Not `pending.length`: a truncated page
   * carries fewer entries than it counted, and the strip states a count.
   */
  pendingCount: number;
  unreadMail: number;
  /** Beads labelled gc:wait — work parked on an external answer. */
  waiting: number;
  /**
   * True when any of these counts is known to be incomplete — a rig store did
   * not answer, or a whole read failed. Every count above is then a floor
   * rather than a number, which is a different thing to tell an operator who is
   * deciding whether anything needs them.
   */
  partial: boolean;
  /** Per-store reasons the counts are incomplete; empty when they are not. */
  partialErrors: string[];
  loading: boolean;
  error: string | null;
  unavailable: boolean;
}

const NO_REASONS: string[] = [];

export function useCitySignals(): CitySignals {
  const ctx = useDrillContext();
  const [pending, setPending] = useState<PendingEntry[]>([]);
  const [pendingCount, setPendingCount] = useState(0);
  const [unreadMail, setUnreadMail] = useState(0);
  const [waiting, setWaiting] = useState(0);
  const [partial, setPartial] = useState(false);
  const [partialErrors, setPartialErrors] = useState<string[]>(NO_REASONS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const reload = useCallback(() => setReloadToken((n) => n + 1), []);

  useEffect(() => {
    if (ctx === null) return;
    const controller = new AbortController();
    let cancelled = false;
    setLoading(true);

    void (async () => {
      try {
        const [pendingList, mail, waitingList] = await Promise.all([
          ctx.reads.pending(controller.signal),
          ctx.reads.mailCount(controller.signal),
          ctx.reads.waitingBeads(controller.signal),
        ]);
        if (cancelled) return;
        setPending(pendingList.items);
        setPendingCount(pendingList.total ?? pendingList.items.length);
        setUnreadMail(mail.unread ?? 0);
        setWaiting(waitingList.total ?? waitingList.items.length);
        // Any incomplete leg makes the whole strip a floor. Mail was the only
        // one honoured before; a pending or gc:wait store that did not answer
        // rendered as an exact, and wrong, "0 waiting on you".
        setPartial(mail.partial === true || pendingList.partial || waitingList.partial);
        const reasons = [
          ...(mail.partial_errors ?? []),
          ...pendingList.partialErrors,
          ...waitingList.partialErrors,
        ];
        setPartialErrors(reasons.length === 0 ? NO_REASONS : reasons);
        setError(null);
      } catch (err) {
        if (cancelled || controller.signal.aborted) return;
        setError(err instanceof Error ? err.message : String(err));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [ctx, reloadToken]);

  useEffect(() => {
    if (ctx === null) return;
    let coalesceTimer: ReturnType<typeof setTimeout> | null = null;
    const scheduleReload = () => {
      if (coalesceTimer !== null) return;
      coalesceTimer = setTimeout(() => {
        coalesceTimer = null;
        reload();
      }, REFRESH_COALESCE_MS);
    };

    // These counts move only when an event says they did, so a reconnect that
    // could not resume (no cursor yet — the drop came before the first event)
    // would freeze them at whatever they were while the stream reported live.
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
        if (!SIGNAL_PREFIXES.some((prefix) => event.type.startsWith(prefix))) return;
        scheduleReload();
      },
      (state) => {
        if (state === 'connecting') {
          attempted = true;
        } else if (state === 'closed') {
          if (attempted) gapPending = true;
        } else if (state === 'open') {
          if (gapPending) {
            gapPending = false;
            scheduleReload();
          }
        }
      },
    );
    return () => {
      if (coalesceTimer !== null) clearTimeout(coalesceTimer);
      unsubscribe();
    };
  }, [ctx, reload]);

  return useMemo(
    () => ({
      pending,
      pendingCount,
      unreadMail,
      waiting,
      partial,
      partialErrors,
      loading,
      error,
      unavailable: ctx === null,
    }),
    [pending, pendingCount, unreadMail, waiting, partial, partialErrors, loading, error, ctx],
  );
}
