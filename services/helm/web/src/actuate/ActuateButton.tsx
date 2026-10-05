// One button that runs a board write verb — accept on a board row, engage
// (Discuss) or dismiss in the drill panel — and reports what the city did.
//
// It carries the same two disciplines OpenConversation does, for the same
// reasons:
//
//  1. It never claims more than happened. accept dispatches a formula and
//     dismisses the visit; engage spawns a Discuss sitting but does NOT attach the
//     operator to it (there is no pane in a browser until the embedded ttyd can be
//     retargeted — tk-rbf9r / tk-xlup8); dismiss closes the visit. The success
//     copy says exactly that and no more.
//  2. A failure says WHICH failure. The service returns a stable `reason` slug
//     beside the tool's own sentence; the sentence is shown verbatim and the slug
//     picks a next move. A button whose only failure mode is a shrug is worse than
//     no button.
//
// It renders inline (a <span> and phrasing content only) so it is valid both in a
// board row's needs cell and inside the family banner's <p>, and in the drill
// panel's session <section>.

import { useCallback, useEffect, useRef, useState } from 'react';
import {
  actuate,
  ActuateError,
  type ActuateResult,
  type ActuateVerb,
  type DismissGate,
  type GateDecision,
} from './client';

// What the operator should do next, per failure reason. Empty where the service's
// own sentence already names the move — doubling up would just add noise.
// `verb_failed` is deliberately absent: it is the verb's own refusal (discuss-only,
// an engaged visit, a failed sling, a rig that is down), and the script's sentence
// is the whole story and names the move itself.
const NEXT_MOVE: Record<string, string> = {
  invalid_bead: 'This row does not carry an id the board can act on. It is a board bug, not a bad click.',
  forbidden:
    'The board refused a write that did not come from its own page. Open the board directly rather than through another site.',
  environment:
    'The city could not be read, so nothing was actuated. Check the data plane (gc doctor, then dolt) and try again.',
  timeout:
    'The board stopped waiting; the action may still have gone through. Check the bead before retrying.',
  unavailable:
    'This board cannot actuate — it was started without the write tool, or the service is unreachable.',
  usage: 'The board and the write tool disagree about the request. That is a bug here, not something to retry.',
  internal: 'The write tool failed in a way the board does not recognise. Retrying is unlikely to help.',
};

// The one thing the city does not say on engage: that this did not attach
// anything. The same caveat open carries, in engage's terms.
const NOT_ATTACHED =
  'The sitting runs server-side; attach from the terminal tile or the sessions picker. This button does not attach you.';

interface VerbCopy {
  /** The resting label. accept names the formula it would dispatch. */
  idle: (formula: string | undefined) => string;
  /** The in-flight label; also disables the button. */
  busy: string;
  /** The success sentence, when the tool's own message is empty. */
  fallback: string;
}

const COPY: Record<ActuateVerb, VerbCopy> = {
  accept: {
    idle: (formula) => (formula ? `accept ▸ ${formula}` : 'accept ▸'),
    busy: 'accepting…',
    fallback: 'Accepted: the recommendation was dispatched and its visit dismissed.',
  },
  engage: {
    idle: () => 'Discuss',
    busy: 'starting…',
    fallback: 'A Discuss sitting was spawned.',
  },
  dismiss: {
    idle: () => 'Dismiss',
    busy: 'dismissing…',
    fallback: 'The visit was closed.',
  },
};

type State =
  | { phase: 'idle' }
  | { phase: 'running' }
  | { phase: 'done'; result: ActuateResult }
  | { phase: 'failed'; error: ActuateError }
  // dismiss only: the subject carries open linked gates a close would orphan, and
  // the operator must decide each before the dismiss can complete. `choices` holds
  // the per-gate resolve/leave decision (a gate absent is still undecided) and
  // `ruling` is the single decision gc-helm.sh records for every gate resolved.
  | {
      phase: 'deciding';
      gates: DismissGate[];
      message: string;
      choices: Record<string, 'resolve' | 'leave'>;
      ruling: string;
    };

type DecidingState = Extract<State, { phase: 'deciding' }>;

// A ruling is only needed when at least one gate is being resolved; leaving a gate
// open records nothing.
function anyResolve(s: DecidingState): boolean {
  return Object.values(s.choices).some((c) => c === 'resolve');
}

// The confirm is enabled once every surfaced gate has a choice, and — if any is a
// resolve — a non-empty ruling is typed. This mirrors gc-helm.sh, which holds on
// any undecided gate and refuses a resolve with no ruling.
function canConfirm(s: DecidingState): boolean {
  const allDecided = s.gates.every((g) => s.choices[g.id] !== undefined);
  return allDecided && (!anyResolve(s) || s.ruling.trim() !== '');
}

export interface ActuateButtonProps {
  beadId: string;
  verb: ActuateVerb;
  /** accept only: the formula the button names and the title spells out. */
  formula?: string;
  /** A modifier class for the board's inline affordance vs the drill's. Structure
   *  is identical; only styling (a later pass) differs. */
  compact?: boolean;
  /** Called after a successful run. The board passes its refresh so the acted-on
   *  row re-gathers; the drill passes its reload. */
  onDone?: () => void;
}

export function ActuateButton({ beadId, verb, formula, compact, onDone }: ActuateButtonProps) {
  const [state, setState] = useState<State>({ phase: 'idle' });
  // One in-flight request per mount. The service also serializes concurrent
  // writes on one subject (409 busy) — that is the real guard, since two browsers
  // can click at once, or one can Accept while another Dismisses the same row;
  // this just keeps a double-click from making a request it already knows the
  // answer to.
  const inFlight = useRef(false);
  // The bead this button is currently pointed at, readable from inside a settled
  // promise.
  const current = useRef(beadId);

  // The drill panel does not remount between tiles — it swaps `beadId` on one
  // <aside> — so without this reset a result from bead A stays on screen under
  // bead B. The board keys each row's button by id and never swaps, so this is a
  // no-op there; carried anyway so the one component is correct in both places.
  useEffect(() => {
    current.current = beadId;
    inFlight.current = false;
    setState({ phase: 'idle' });
  }, [beadId]);

  // Shared completion for the first click (run) and the decision re-submit
  // (submitDecision). A dismiss HELD for a gate decision is not done and fires no
  // onDone — nothing changed; it moves to the decision phase carrying the gates.
  // Anything else is a success (onDone) or a failure.
  const settle = useCallback(
    (target: string, p: Promise<ActuateResult>) => {
      p.then((result) => {
        if (current.current !== target) return;
        if (
          verb === 'dismiss' &&
          result.outcome === 'held_for_gate_decision' &&
          result.gates &&
          result.gates.length > 0
        ) {
          setState({ phase: 'deciding', gates: result.gates, message: result.message, choices: {}, ruling: '' });
        } else {
          setState({ phase: 'done', result });
          onDone?.();
        }
      })
        .catch((cause: unknown) => {
          if (current.current !== target) return;
          const error =
            cause instanceof ActuateError
              ? cause
              : new ActuateError(0, 'internal', cause instanceof Error ? cause.message : String(cause));
          setState({ phase: 'failed', error });
        })
        .finally(() => {
          if (current.current === target) inFlight.current = false;
        });
    },
    [verb, onDone],
  );

  const run = useCallback(() => {
    if (inFlight.current) return;
    inFlight.current = true;
    const target = beadId;
    setState({ phase: 'running' });
    settle(target, actuate(verb, target));
  }, [beadId, verb, settle]);

  // The decision re-submit: resolve/leave per gate plus the single ruling, sent
  // back to the same dismiss route. gc-helm.sh applies the decisions and then
  // closes the visit, so a success here ends the flow.
  const submitDecision = useCallback(
    (gates: DismissGate[], choices: Record<string, 'resolve' | 'leave'>, ruling: string) => {
      if (inFlight.current) return;
      inFlight.current = true;
      const target = beadId;
      const decisions: GateDecision[] = gates
        .map((g) => ({ gate: g.id, action: choices[g.id] }))
        .filter((d): d is GateDecision => d.action !== undefined);
      // The ruling rides only when a gate is being resolved; a leave-only decision
      // records nothing, so no ruling is sent (the server ignores one with no gate
      // to apply it to).
      const resolving = decisions.some((d) => d.action === 'resolve');
      setState({ phase: 'running' });
      settle(target, actuate('dismiss', target, { ruling: resolving ? ruling : undefined, decisions }));
    },
    [beadId, settle],
  );

  const choose = useCallback((gateId: string, action: 'resolve' | 'leave') => {
    setState((s) => (s.phase === 'deciding' ? { ...s, choices: { ...s.choices, [gateId]: action } } : s));
  }, []);
  const setRuling = useCallback((ruling: string) => {
    setState((s) => (s.phase === 'deciding' ? { ...s, ruling } : s));
  }, []);

  const copy = COPY[verb];
  return (
    <span className={compact ? 'actuate actuate--compact' : 'actuate'}>
      <button
        type="button"
        className={`actuate-go actuate-go--${verb}`}
        onClick={run}
        disabled={state.phase === 'running' || state.phase === 'deciding'}
        title={
          verb === 'accept' && formula
            ? `dispatch ${formula} at ${beadId} and dismiss the visit`
            : undefined
        }
      >
        {state.phase === 'running' ? copy.busy : copy.idle(formula)}
      </button>

      {state.phase === 'done' && (
        <span className="actuate-result" role="status">
          {' '}
          {state.result.message !== '' ? state.result.message : copy.fallback}
          {verb === 'engage' && <span className="muted"> {NOT_ATTACHED}</span>}
        </span>
      )}

      {state.phase === 'failed' && (
        <span className="error" role="alert">
          {' '}
          {state.error.message}
          {NEXT_MOVE[state.error.reason] !== undefined && (
            <span className="muted"> {NEXT_MOVE[state.error.reason]}</span>
          )}
        </span>
      )}

      {state.phase === 'deciding' && (
        <span className="actuate-gate-decision" role="group" aria-label="decide the open gates before dismissing">
          {' '}
          <span className="actuate-gate-prompt" role="status">
            {state.message}
          </span>
          {state.gates.map((g) => (
            <span key={g.id} className="actuate-gate">
              {' '}
              <span className="actuate-gate-demand">{g.demand !== '' ? g.demand : g.id}</span>{' '}
              <span className="muted">(blocks {g.blocks})</span>{' '}
              <button
                type="button"
                className="actuate-gate-choice"
                aria-pressed={state.choices[g.id] === 'resolve'}
                onClick={() => choose(g.id, 'resolve')}
              >
                Resolve
              </button>{' '}
              <button
                type="button"
                className="actuate-gate-choice"
                aria-pressed={state.choices[g.id] === 'leave'}
                onClick={() => choose(g.id, 'leave')}
              >
                Leave open
              </button>
            </span>
          ))}
          {anyResolve(state) && (
            <>
              {' '}
              <input
                type="text"
                className="actuate-gate-ruling"
                maxLength={140}
                placeholder="ruling (≤140 chars)"
                aria-label="ruling for the resolved gates"
                value={state.ruling}
                onChange={(e) => setRuling(e.target.value)}
              />
            </>
          )}{' '}
          <button
            type="button"
            className="actuate-go actuate-go--dismiss"
            disabled={!canConfirm(state)}
            onClick={() => submitDecision(state.gates, state.choices, state.ruling)}
          >
            Confirm dismissal
          </button>
        </span>
      )}
    </span>
  );
}
