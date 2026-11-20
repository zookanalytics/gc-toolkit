import { useCallback, useEffect, useRef, useState } from 'react';
import { READ_TIMEOUT_MS } from './read';

/** A read that did not give an answer: what it said, and when. */
export interface Failure {
  message: string;
  at: Date;
}

export interface ReadState<T> {
  /** The last answer a read gave, kept on screen when a later read fails. */
  last?: T;
  /** The latest read's failure. The next read that gives an answer clears it. */
  failure?: Failure;
}

/**
 * One of the service's answers, read on mount, every refreshMs, and whenever
 * the tab is shown again. A failed read keeps the last good answer and records
 * the failure beside it, so a page never draws an empty list from a read that
 * failed. The returned refresh reads again at once, as after a write. read must
 * keep its identity between renders, since a new one reads again.
 */
export function usePolledRead<T>(read: (signal: AbortSignal) => Promise<T>, refreshMs: number): [ReadState<T>, () => void] {
  const [state, setState] = useState<ReadState<T>>({});
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
      read(ctl.signal)
        .then((answer) => {
          if (inFlight.current === ctl) setState({ last: answer });
        })
        .catch((cause: unknown) => {
          // A read a newer one replaced reports nothing.
          if (inFlight.current !== ctl) return;
          const message = timedOut
            ? 'the board service did not answer within a minute'
            : cause instanceof Error
              ? cause.message
              : String(cause);
          setState((prev) => ({ last: prev.last, failure: { message, at: new Date() } }));
        })
        .finally(() => {
          window.clearTimeout(timer);
          if (inFlight.current === ctl) inFlight.current = null;
        });
    },
    [read],
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
    const timer = window.setInterval(() => load(false), refreshMs);
    return () => window.clearInterval(timer);
  }, [load, refreshMs]);

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
