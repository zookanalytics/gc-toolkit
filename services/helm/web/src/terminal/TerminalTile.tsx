// A tile that is a peek at rest and a live terminal on focus.
//
// SCOPE. There is exactly one terminal here, because there is exactly one ttyd
// and it wraps one fixed session (`gc session attach <session>`, baked into the
// ttyd invocation). Per-tile terminals — one per anchor — need a ttyd or
// wiring change and are deliberately not decided yet; see the Terminal section
// of services/helm/README.md.
//
// This tile owns the xterm/DOM wiring only. The protocol, the endpoint check,
// the detach invariant and the snapshot each live in their own DOM-free module
// beside this one, where they are tested.

import { useCallback, useEffect, useRef, useState } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';

import { clampSize } from './protocol';
import { DEFAULT_TERMINAL_BASE, probeTerminal, socketURL } from './endpoint';
import { TtydSession, type SessionState } from './session';
import { captureSnapshot } from './snapshot';

export interface TerminalTileProps {
  /** Human-readable name of the session ttyd is wired to. */
  label: string;
  /** ttyd's base path on this origin. */
  base?: string;
}

const STATE_TEXT: Record<SessionState, string> = {
  idle: 'at rest',
  connecting: 'attaching…',
  attached: 'live',
  detached: 'detached',
  failed: 'unavailable',
};

export function TerminalTile({ label, base = DEFAULT_TERMINAL_BASE }: TerminalTileProps) {
  const [focused, setFocused] = useState(false);
  const [state, setState] = useState<SessionState>('idle');
  const [detail, setDetail] = useState<string | null>(null);
  const [title, setTitle] = useState<string | null>(null);
  const [snapshot, setSnapshot] = useState('');
  const hostRef = useRef<HTMLDivElement | null>(null);

  const focus = useCallback(() => setFocused(true), []);
  const rest = useCallback(() => setFocused(false), []);

  useEffect(() => {
    if (!focused) return;
    const host = hostRef.current;
    if (!host) return;

    let cancelled = false;
    let terminal: Terminal | null = null;
    let session: TtydSession | null = null;
    let observer: ResizeObserver | null = null;
    const controller = new AbortController();

    setState('connecting');
    setDetail(null);

    void (async () => {
      // Prove ttyd is on this origin before opening a socket, so an origin
      // that does not route it produces a sentence instead of a silent hang.
      const probe = await probeTerminal(base, fetch, controller.signal);
      if (cancelled) return;
      if (!probe.reachable) {
        setState('failed');
        setDetail(probe.reason);
        return;
      }

      const term = new Terminal({
        convertEol: false,
        cursorBlink: false,
        fontSize: 12,
        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
        scrollback: 2000,
        theme: { background: '#11131a', foreground: '#d6dae4' },
      });
      const fit = new FitAddon();
      term.loadAddon(fit);
      term.open(host);
      terminal = term;

      // Size the local terminal to the same clamped dimensions reported to
      // ttyd, so the renderer and the PTY agree about where lines wrap.
      const applySize = () => {
        let proposed: { cols: number; rows: number } | undefined;
        try {
          proposed = fit.proposeDimensions();
        } catch {
          proposed = undefined;
        }
        const next = clampSize({
          columns: proposed?.cols ?? term.cols,
          rows: proposed?.rows ?? term.rows,
        });
        if (next.columns !== term.cols || next.rows !== term.rows) {
          term.resize(next.columns, next.rows);
        }
        session?.resize(next);
      };
      applySize();

      const live = new TtydSession(
        socketURL(base, window.location),
        probe.token,
        { columns: term.cols, rows: term.rows },
        {
          onOutput: (data) => term.write(data),
          onTitle: (next) => setTitle(next),
          onStateChange: (next, why) => {
            setState(next);
            if (why !== undefined) setDetail(why);
          },
        },
      );
      term.onData((data) => live.send(data));
      session = live;
      live.attach();

      observer = new ResizeObserver(() => applySize());
      observer.observe(host);
    })();

    return () => {
      cancelled = true;
      controller.abort();
      observer?.disconnect();
      // Take the peek before tearing anything down — it is what the tile shows
      // once it is no longer live.
      if (terminal) setSnapshot(captureSnapshot(terminal));
      // Detach first, dispose second. detach() closes the socket and writes
      // nothing; see session.ts — this teardown must never reach the PTY.
      session?.detach();
      terminal?.dispose();
    };
  }, [focused, base]);

  return (
    <section className="terminal-tile">
      <header className="terminal-tile__head">
        <h2>{title ?? label}</h2>
        <span className={`terminal-tile__state terminal-tile__state--${state}`}>
          {STATE_TEXT[state]}
        </span>
        {focused ? (
          <button type="button" onClick={rest}>
            detach
          </button>
        ) : (
          <button type="button" onClick={focus}>
            attach
          </button>
        )}
      </header>

      {detail && (
        <p className="terminal-tile__detail" role={state === 'failed' ? 'alert' : 'status'}>
          {detail}
        </p>
      )}

      {focused ? (
        <div className="terminal-tile__live" ref={hostRef} />
      ) : (
        <pre className="terminal-tile__peek">
          {snapshot || `${label} is not attached. Attaching runs \`gc session attach\`.`}
        </pre>
      )}

      <footer className="terminal-tile__foot">
        Detaching closes the connection only — the session and whatever is running in it keep
        going.
      </footer>
    </section>
  );
}
