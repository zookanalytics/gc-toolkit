// A bead's whole description, formatted, read when its Details opens. The rig's
// document carries no piece of work's description, so Details reads that one
// bead's text from the supervisor (supervisor/client.ts).

import { useEffect, useState } from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { readBead } from '../supervisor/client';
import { resolveSupervisorOrigin } from '../supervisor/origin';

type State = { phase: 'reading' } | { phase: 'read'; text: string } | { phase: 'failed'; message: string };

export function Description({ id }: { id: string }) {
  const [state, setState] = useState<State>({ phase: 'reading' });

  useEffect(() => {
    setState({ phase: 'reading' });
    const origin = resolveSupervisorOrigin(window.location);
    if (origin === null) {
      setState({
        phase: 'failed',
        message: "this page is not served under a city's mount, so it cannot reach the supervisor",
      });
      return;
    }
    const ctl = new AbortController();
    readBead(origin, id, ctl.signal)
      .then((bead) => setState({ phase: 'read', text: bead.description ?? '' }))
      .catch((cause: unknown) => {
        if (ctl.signal.aborted) return;
        setState({ phase: 'failed', message: cause instanceof Error ? cause.message : String(cause) });
      });
    return () => ctl.abort();
  }, [id]);

  switch (state.phase) {
    case 'reading':
      return <p className="muted">Reading the bead's description…</p>;
    case 'failed':
      return (
        <p className="muted" role="alert">
          The bead's description could not be read: {state.message}
        </p>
      );
    case 'read':
      if (state.text.trim() === '') return <p className="muted">No description.</p>;
      return (
        <div className="description">
          <Markdown
            remarkPlugins={[remarkGfm]}
            components={{
              a: ({ href, children }) => (
                <a href={href} target="_blank" rel="noreferrer noopener">
                  {children}
                </a>
              ),
            }}
          >
            {state.text}
          </Markdown>
        </div>
      );
  }
}
