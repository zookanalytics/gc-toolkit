// The side panel, where the design draws its terminal. The page mounts no
// terminal: the panel shows what Start the conversation or Rejoin the
// conversation answered, with the command to run and a copy control, or
// Discuss's form for filing a conversation on a bead.

import { useEffect, useRef, useState } from 'react';
import { attachCommand } from '../actuate/client';
import { OpenConversation } from '../open/OpenConversation';
import type { EngageAnswer, PanelState } from './view';

// What the operator should do next, per failure reason. Absent where the
// service's own sentence already names the move: `verb_failed` is the engage
// tool's own refusal, and its sentence is the whole story.
const NEXT_MOVE: Record<string, string> = {
  invalid_bead: 'This row does not carry an id the board can act on. It is a board bug, not a bad click.',
  forbidden:
    'The board refused a write that did not come from its own page. Open the board directly rather than through another site.',
  busy: 'Wait for that to finish, then try again.',
  environment:
    'The city could not be read, so nothing was started. Check the data plane (gc doctor, then dolt) and try again.',
  timeout: 'The board stopped waiting; the sitting may still have started. Check the bead before retrying.',
  unavailable: 'This board cannot start a conversation: it was started without the write tool, or the service is unreachable.',
  usage: 'The board and the write tool disagree about the request. That is a bug here, not something to retry.',
  internal: 'The write tool failed in a way the board does not recognise. Retrying is unlikely to help.',
};

export function SidePanel({
  panel,
  onClose,
  onWrote,
}: {
  panel: PanelState;
  onClose: () => void;
  /** Called once a write has landed, so the page reads its document again. */
  onWrote: () => void;
}) {
  const heading = panel.kind === 'engage' ? 'Conversation' : 'Discuss';
  // Below about 1080px the panel sits after the whole board. When it opens or
  // turns to another bead or kind, it scrolls into view, which moves the page
  // only where the panel is out of sight, and focus moves into it. The answer
  // an engage writes into an open panel moves nothing.
  const aside = useRef<HTMLElement>(null);
  useEffect(() => {
    const el = aside.current;
    if (el === null) return;
    el.scrollIntoView({ block: 'nearest' });
    el.focus({ preventScroll: true });
  }, [panel.kind, panel.bead]);
  return (
    <aside ref={aside} className="panel" aria-label={heading} tabIndex={-1}>
      <div className="panel-head">
        <span className="panel-titles">
          <span className="panel-title">{heading}</span>
          <span className="panel-sub" title={`${panel.bead} · ${panel.title}`}>
            {panel.bead} · {panel.title}
          </span>
        </span>
        <button type="button" className="panel-close" onClick={onClose}>
          Close
        </button>
      </div>
      <div className="panel-body">
        {panel.kind === 'engage' ? (
          <Engaged answer={panel.answer} />
        ) : (
          <OpenConversation beadId={panel.bead} onFiled={onWrote} />
        )}
      </div>
    </aside>
  );
}

function Engaged({ answer }: { answer: EngageAnswer }) {
  switch (answer.phase) {
    case 'running':
      return <p className="panel-dim">Starting the conversation…</p>;
    case 'failed':
      return (
        <div role="alert">
          <p className="panel-error">{answer.error.message}</p>
          {NEXT_MOVE[answer.error.reason] !== undefined && <p className="panel-dim">{NEXT_MOVE[answer.error.reason]}</p>}
        </div>
      );
    case 'done': {
      const message = answer.result.message;
      return (
        <div role="status">
          {message === '' ? (
            <p className="panel-line">The conversation was engaged.</p>
          ) : (
            message.split('\n').map((line, i) => {
              const command = attachCommand(line);
              return command === null ? (
                <p key={i} className="panel-line">
                  {line}
                </p>
              ) : (
                <Command key={i} command={command} />
              );
            })
          )}
          <p className="panel-dim">
            The sitting runs in the city, and this page attaches nothing: run the command in a terminal to join it.
          </p>
        </div>
      );
    }
  }
}

/** The command to run, with a control that copies it. */
function Command({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    try {
      const done = navigator.clipboard.writeText(command);
      done.catch(() => {});
    } catch {
      // A page without clipboard access still shows the command to select.
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1200);
  };
  return (
    <div className="command">
      <span className="panel-dim">attach:</span>
      <code>{command}</code>
      <button type="button" className="panel-copy" onClick={copy}>
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  );
}
