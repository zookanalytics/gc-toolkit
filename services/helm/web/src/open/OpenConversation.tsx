// The drill panel's one write action: start a conversation on this bead.
//
// It lives in the panel's `session` section because that is the section about
// who is working the anchor, and this is how the operator causes someone to.
//
// TWO THINGS IT IS CAREFUL ABOUT, both of them the operator's complaint about
// the tmux affordance ("not enough details to really be the main action"):
//
//  1. It never claims more than happened. Filing a visit queues a conversation;
//     it does not put the operator in one. There is no pane to attach to in a
//     browser until the embedded ttyd can be retargeted (tk-rbf9r / tk-xlup8,
//     unapplied), so the success copy says a conversation is being opened and
//     points at the terminal tile — it does not say "you are in it".
//  2. A failure says which failure. The service returns a stable `reason` slug
//     beside the tool's own sentence; the sentence is shown verbatim and the
//     slug picks a next move. A button whose only failure mode is a shrug is
//     worse than no button.

import { useCallback, useEffect, useRef, useState } from 'react';
import { OpenError, openConversation, type OpenResult } from './client';

/** What the operator should do next, per failure. Empty where the service's own
 *  sentence already names the move — doubling up would just add noise. */
const NEXT_MOVE: Record<string, string> = {
  invalid_bead: 'This row does not carry an id the board can open. It is a board bug, not a bad click.',
  forbidden:
    'The board refused a write that did not come from its own page. Open the board directly rather than through another site.',
  environment:
    'The city could not be read, so no visit was filed. Check the data plane (gc doctor, then dolt) and try again.',
  timeout:
    'The board stopped waiting; the filing may still have gone through. Check the bead before retrying, then try again once the city is responding.',
  unavailable:
    'This board cannot file visits — it was started without the visit tool, or the service is unreachable.',
  usage: 'The board and the visit tool disagree about the request. That is a bug here, not something to retry.',
  internal: 'The visit tool failed in a way the board does not recognise. Retrying is unlikely to help.',
};

type State =
  | { phase: 'idle' }
  | { phase: 'opening' }
  | { phase: 'done'; result: OpenResult }
  | { phase: 'failed'; error: OpenError };

export interface OpenConversationProps {
  beadId: string;
}

export function OpenConversation({ beadId }: OpenConversationProps) {
  const [state, setState] = useState<State>({ phase: 'idle' });
  // One in-flight request per mount. The service also collapses concurrent
  // opens of the same bead (409 busy) — that is the real guard, since two
  // browsers can click at once; this just keeps a double-click from making a
  // request it already knows the answer to.
  const inFlight = useRef(false);
  // The bead this component is currently pointed at, readable from inside a
  // settled promise. See the reset below for why that matters.
  const current = useRef(beadId);

  // THE PANEL DOES NOT REMOUNT BETWEEN TILES. DrillPanel renders one
  // <aside> and swaps `beadId` on it, so without this reset a result from bead
  // A stays on screen under bead B's title — telling the operator a
  // conversation was opened on a row where it was not. Same reason the
  // late-response guard below exists: a request started on A must not report
  // itself once the panel has moved on.
  useEffect(() => {
    current.current = beadId;
    inFlight.current = false;
    setState({ phase: 'idle' });
  }, [beadId]);

  const open = useCallback(() => {
    if (inFlight.current) return;
    inFlight.current = true;
    const target = beadId;
    setState({ phase: 'opening' });
    openConversation(target)
      .then((result) => {
        if (current.current === target) setState({ phase: 'done', result });
      })
      .catch((cause: unknown) => {
        if (current.current !== target) return;
        const error =
          cause instanceof OpenError
            ? cause
            : new OpenError(0, 'internal', cause instanceof Error ? cause.message : String(cause));
        setState({ phase: 'failed', error });
      })
      .finally(() => {
        if (current.current === target) inFlight.current = false;
      });
  }, [beadId]);

  return (
    <div className="open-conversation">
      <button
        type="button"
        className="open-conversation-go"
        onClick={open}
        disabled={state.phase === 'opening'}
      >
        {state.phase === 'opening' ? 'opening…' : 'start a conversation'}
      </button>

      {state.phase === 'done' && <OpenedNotice result={state.result} />}

      {state.phase === 'failed' && (
        <p className="error" role="alert">
          {state.error.message}
          {NEXT_MOVE[state.error.reason] !== undefined && (
            <>
              {' '}
              <span className="muted">{NEXT_MOVE[state.error.reason]}</span>
            </>
          )}
        </p>
      )}
    </div>
  );
}

/**
 * What happened, in the city's own words plus the one thing the city does not
 * say: that this did not attach anything.
 *
 * `filed` and `existing` are deliberately different sentences. Told "filed"
 * twice, an operator would reasonably believe two conversations exist.
 */
function OpenedNotice({ result }: { result: OpenResult }) {
  return (
    <p className="open-conversation-result" role="status">
      <strong>
        {result.outcome === 'existing'
          ? 'A conversation is already open on this bead.'
          : 'A conversation is being opened.'}
      </strong>{' '}
      {result.message}{' '}
      <span className="muted">
        {result.outcome === 'existing'
          ? 'Attach to it from the sessions picker or the terminal tile.'
          : 'A converse session will pick it up; attach from the sessions picker or the terminal tile. This button does not attach you.'}
      </span>
    </p>
  );
}
