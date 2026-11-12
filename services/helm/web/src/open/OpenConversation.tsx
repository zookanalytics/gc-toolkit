// Discuss's form: file a conversation on this bead.
//
// A row's Details offers Discuss on every bead, and the page opens this form in
// its side panel for that bead.
//
// TWO THINGS IT IS CAREFUL ABOUT:
//
//  1. It never claims more than happened. Filing a conversation puts it in the
//     operator's queue; it does not start a sitting or put the operator in one.
//     Rejoin the conversation, on the conversation's row on Needs you, is what
//     spawns the sitting, and the page mounts no terminal. So the success copy
//     says the conversation waits in the queue and points at Needs you. It does
//     not say "you are in it".
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
    'The city could not be read, so no conversation was filed. Check the data plane (gc doctor, then dolt) and try again.',
  timeout:
    'The board stopped waiting; the filing may still have gone through. Check the bead before retrying, then try again once the city is responding.',
  unavailable:
    'This board cannot file conversations — it was started without the write tool, or the service is unreachable.',
  usage: 'The board and the write tool disagree about the request. That is a bug here, not something to retry.',
  internal: 'The write tool failed in a way the board does not recognise. Retrying is unlikely to help.',
};

type State =
  | { phase: 'idle' }
  | { phase: 'opening' }
  | { phase: 'done'; result: OpenResult }
  | { phase: 'failed'; error: OpenError };

export interface OpenConversationProps {
  beadId: string;
  /** Called once a conversation is filed or found waiting, so the page reads
   *  its document again. */
  onFiled?: () => void;
}

export function OpenConversation({ beadId, onFiled }: OpenConversationProps) {
  const [state, setState] = useState<State>({ phase: 'idle' });
  // One in-flight request per mount. The service also collapses concurrent
  // opens of the same bead (409 busy) — that is the real guard, since two
  // browsers can click at once; this just keeps a double-click from making a
  // request it already knows the answer to.
  const inFlight = useRef(false);
  // The bead this component is currently pointed at, readable from inside a
  // settled promise. See the reset below for why that matters.
  const current = useRef(beadId);

  // THE FORM CAN BE POINTED AT ANOTHER BEAD WITHOUT REMOUNTING. Without this
  // reset a result from bead A stays on screen under bead B's title, telling
  // the operator a conversation was opened on a row where it was not. Same
  // reason the late-response guard below exists: a request started on A must
  // not report itself once the form has moved on.
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
        if (current.current === target) {
          setState({ phase: 'done', result });
          onFiled?.();
        }
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
  }, [beadId, onFiled]);

  return (
    <div className="open-conversation">
      <button
        type="button"
        className="open-conversation-go"
        onClick={open}
        disabled={state.phase === 'opening'}
      >
        {state.phase === 'opening' ? 'filing…' : 'File a conversation'}
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
          ? 'A conversation already waits on this bead.'
          : 'A conversation waits in your queue.'}
      </strong>{' '}
      {result.message}{' '}
      <span className="muted">
        {result.outcome === 'existing'
          ? 'Take it up with Rejoin the conversation on its row on Needs you. This button does not attach you.'
          : 'No sitting holds it yet. Rejoin the conversation, on its row on Needs you, starts one. This button does not attach you.'}
      </span>
    </p>
  );
}
