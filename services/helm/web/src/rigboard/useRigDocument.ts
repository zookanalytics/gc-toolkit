import { useCallback, useEffect, useRef, useState } from 'react';
import type { Response as RigResponse } from './document.gen';
import { READ_TIMEOUT_MS, readRig } from './read';

// The service serves one rig's document from its cache for a minute
// (server.RigBoardTTL), so reading more often than every half minute re-reads
// the same bytes.
export const REFRESH_MS = 30_000;

/** A read that did not give a document: what it said, and when. */
export interface Failure {
  message: string;
  at: Date;
}

export interface RigDocumentState {
  /** The last document a read gave, kept on screen when a later read fails. */
  last?: RigResponse;
  /** The latest read's failure. The next read that gives a document clears it. */
  failure?: Failure;
  /** True until the first read answers. */
  loading: boolean;
}

/**
 * One rig's document, read on mount, every REFRESH_MS, and whenever the tab is
 * shown again. A failed read keeps the last good document and records the
 * failure beside it, so the page never draws an empty list from a read that
 * failed. The returned refresh reads again at once, as after a write.
 */
export function useRigDocument(rig: string): [RigDocumentState, () => void] {
  const [state, setState] = useState<RigDocumentState>({ loading: true });
  const inFlight = useRef<AbortController | null>(null);

  const load = useCallback(
    (force: boolean) => {
      if (inFlight.current !== null) {
        // A poll tick never stacks a second read behind one still open.
        if (!force) return;
        inFlight.current.abort();
      }
      const ctl = new AbortController();
      inFlight.current = ctl;
      let timedOut = false;
      const timer = window.setTimeout(() => {
        timedOut = true;
        ctl.abort();
      }, READ_TIMEOUT_MS);
      readRig(rig, ctl.signal)
        .then((doc) => {
          if (inFlight.current === ctl) setState({ last: doc, loading: false });
        })
        .catch((cause: unknown) => {
          // A read a newer one replaced reports nothing.
          if (inFlight.current !== ctl) return;
          const message = timedOut
            ? 'the board service did not answer within a minute'
            : cause instanceof Error
              ? cause.message
              : String(cause);
          setState((prev) => ({ last: prev.last, failure: { message, at: new Date() }, loading: false }));
        })
        .finally(() => {
          window.clearTimeout(timer);
          if (inFlight.current === ctl) inFlight.current = null;
        });
    },
    [rig],
  );

  useEffect(() => {
    load(true);
    return () => {
      const running = inFlight.current;
      inFlight.current = null;
      running?.abort();
    };
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => load(false), REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [load]);

  // A tab that was hidden or asleep still shows what it last had, so it reads
  // again the moment it is shown.
  useEffect(() => {
    const onVisibility = () => {
      if (document.visibilityState === 'visible') load(true);
    };
    document.addEventListener('visibilitychange', onVisibility);
    return () => document.removeEventListener('visibilitychange', onVisibility);
  }, [load]);

  const refresh = useCallback(() => load(true), [load]);
  return [state, refresh];
}
