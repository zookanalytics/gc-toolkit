// The rig board's page. One rig a page, with the rig in the address
// (?rig=<name>); with no rig there, the page lists the city's rigs as links.
// Nothing rolls up across rigs.
//
// The page reads one document per rig (GET <mount>/helm/rigs/{rig}), which
// decides every group, signal, count, ask, section and order, and lays it out
// as four pages: Epics, Needs you, Work queue and Unprioritized. It derives no
// state of its own.

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { ActuateError, engage } from '../actuate/client';
import type { Response as RigResponse } from './document.gen';
import { EpicsPage, MatchesPage, NeedsYouPage, UnprioritizedPage, WorkQueuePage } from './pages';
import { SidePanel } from './Panel';
import { READ_TIMEOUT_MS, readRigs, rigAddress, rigFromAddress } from './read';
import { Note } from './rows';
import { useRigDocument, type RigDocumentState } from './useRigDocument';
import { ViewContext, type PanelState, type View } from './view';

/** The page the address names: a rig's board, or the city's rigs. */
export function Page() {
  const rig = rigFromAddress(window.location.search);
  return rig === null ? <RigList /> : <RigBoard rig={rig} />;
}

type Tab = 'epics' | 'needs' | 'queue' | 'desk';

const TABS: { tab: Tab; label: string }[] = [
  { tab: 'epics', label: 'Epics' },
  { tab: 'needs', label: 'Needs you' },
  { tab: 'queue', label: 'Work queue' },
  { tab: 'desk', label: 'Unprioritized' },
];

function Brand() {
  return <span className="brand">helm</span>;
}

/** With no rig in the address: the city's rigs, each a link to its page. */
function RigList() {
  const [state, setState] = useState<{ rigs?: string[]; failure?: string }>({});
  useEffect(() => {
    document.title = 'helm';
    const ctl = new AbortController();
    let timedOut = false;
    const timer = window.setTimeout(() => {
      timedOut = true;
      ctl.abort();
    }, READ_TIMEOUT_MS);
    readRigs(ctl.signal)
      .then((r) => setState({ rigs: r.rigs }))
      .catch((cause: unknown) => {
        // A read the page dropped on leaving reports nothing.
        if (ctl.signal.aborted && !timedOut) return;
        setState({
          failure: timedOut
            ? 'the board service did not answer within a minute'
            : cause instanceof Error
              ? cause.message
              : String(cause),
        });
      })
      .finally(() => window.clearTimeout(timer));
    return () => {
      window.clearTimeout(timer);
      ctl.abort();
    };
  }, []);
  return (
    <div className="page">
      <header className="bar">
        <Brand />
      </header>
      <main className="main">
        {state.failure !== undefined && (
          <p className="status status--failed" role="alert">
            The city's rigs could not be read: {state.failure}
          </p>
        )}
        {state.rigs === undefined && state.failure === undefined && <Note>Reading the city's rigs…</Note>}
        {state.rigs !== undefined && (
          <nav aria-label="Rigs" className="rig-list">
            <h1>Rigs</h1>
            <ul>
              {state.rigs.map((rig) => (
                <li key={rig}>
                  <a href={rigAddress(rig)}>{rig}</a>
                </li>
              ))}
            </ul>
            {state.rigs.length === 0 && <Note>The city lists no rig.</Note>}
          </nav>
        )}
      </main>
    </div>
  );
}

function RigBoard({ rig }: { rig: string }) {
  const [state, refresh] = useRigDocument(rig);
  const [tab, setTab] = useState<Tab>('epics');
  const [query, setQuery] = useState('');
  const [open, setOpenState] = useState<Record<string, boolean>>({});
  const [panel, setPanel] = useState<PanelState | null>(null);
  const [copied, setCopied] = useState<string | null>(null);
  const copiedTimer = useRef<number | undefined>(undefined);
  // The engage whose answer the panel may show; a later click replaces it.
  const engaging = useRef(0);

  useEffect(() => {
    document.title = `helm · ${rig}`;
  }, [rig]);

  const doc = state.last?.board;

  const startEngage = useCallback(
    (bead: string, title: string) => {
      const token = ++engaging.current;
      setPanel({ kind: 'engage', bead, title, answer: { phase: 'running' } });
      engage(bead)
        .then((result) => {
          if (engaging.current !== token) return;
          setPanel({ kind: 'engage', bead, title, answer: { phase: 'done', result } });
          refresh();
        })
        .catch((cause: unknown) => {
          if (engaging.current !== token) return;
          const error =
            cause instanceof ActuateError
              ? cause
              : new ActuateError(0, 'internal', cause instanceof Error ? cause.message : String(cause));
          setPanel({ kind: 'engage', bead, title, answer: { phase: 'failed', error } });
        });
    },
    [refresh],
  );

  const view = useMemo<View | null>(() => {
    if (doc === undefined) return null;
    return {
      doc,
      isOpen: (key, def) => (key in open ? open[key] : def),
      flip: (key, def) => setOpenState((prev) => ({ ...prev, [key]: !(key in prev ? prev[key] : def) })),
      setOpen: (parts) => setOpenState((prev) => ({ ...prev, ...parts })),
      copy: (id) => {
        try {
          navigator.clipboard.writeText(id).catch(() => {});
        } catch {
          // A page without clipboard access still shows the id to select.
        }
        setCopied(id);
        window.clearTimeout(copiedTimer.current);
        copiedTimer.current = window.setTimeout(() => setCopied(null), 1200);
      },
      copied,
      show: (id) => setQuery(id),
      openPanel: (p) => {
        engaging.current++;
        setPanel(p);
      },
      engage: (bead, title) => {
        if (panel?.kind === 'engage' && panel.bead === bead && panel.answer.phase === 'running') return;
        startEngage(bead, title);
      },
    };
  }, [doc, open, copied, panel, startEngage]);

  const closePanel = () => {
    engaging.current++;
    setPanel(null);
  };

  const needs = doc?.needs_you.count ?? 0;
  let content: ReactNode = null;
  if (view !== null) {
    if (query.trim() !== '') {
      content = <MatchesPage query={query} onBack={() => setQuery('')} />;
    } else {
      content = {
        epics: <EpicsPage />,
        needs: <NeedsYouPage />,
        queue: <WorkQueuePage />,
        desk: <UnprioritizedPage />,
      }[tab];
    }
  }

  return (
    <div className="page">
      <header className="bar">
        <Brand />
        <nav aria-label="Rig" className="rig-nav">
          <a href="./" title="All of the city's rigs">
            Rigs
          </a>
          <span className="rig-current">{rig}</span>
        </nav>
        <nav aria-label="Pages" className="tabs">
          {TABS.map((t) => {
            const on = tab === t.tab && query.trim() === '';
            return (
              <button
                key={t.tab}
                type="button"
                className={on ? 'tab tab--on' : 'tab'}
                aria-pressed={on}
                onClick={() => {
                  setTab(t.tab);
                  setQuery('');
                }}
              >
                <span>{t.label}</span>
                {t.tab === 'needs' && doc !== undefined && (
                  <span className={needs > 0 ? 'pill pill--on' : 'pill'}>{needs}</span>
                )}
              </button>
            );
          })}
        </nav>
        <input
          type="search"
          className="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search this rig"
          aria-label="Search this rig"
        />
      </header>
      <div className="body">
        <main className="main">
          <ReadStatus rig={rig} state={state} />
          {view !== null && <ViewContext.Provider value={view}>{content}</ViewContext.Provider>}
        </main>
        {panel !== null && <SidePanel panel={panel} onClose={closePanel} onWrote={refresh} />}
      </div>
    </div>
  );
}

function timeOf(at: string | Date): string {
  const d = typeof at === 'string' ? new Date(at) : at;
  return Number.isNaN(d.getTime()) ? String(at) : d.toLocaleTimeString();
}

/** When the board on screen was read, and the latest read's failure beside
 *  it. A failed read never draws an empty board: with no document read yet,
 *  the page shows the failure alone. */
function ReadStatus({ rig, state }: { rig: string; state: RigDocumentState }) {
  const last: RigResponse | undefined = state.last;
  if (last === undefined) {
    if (state.failure !== undefined) {
      return (
        <p className="status status--failed" role="alert">
          The {rig} board could not be read: {state.failure.message}
        </p>
      );
    }
    return <Note>Reading the {rig} board…</Note>;
  }
  if (state.failure !== undefined) {
    return (
      <p className="status status--failed" role="alert">
        The latest read failed at {timeOf(state.failure.at)}: {state.failure.message}. This is the board read at{' '}
        {timeOf(last.read_at)}.
      </p>
    );
  }
  return <p className="status">Read at {timeOf(last.read_at)}.</p>;
}
