import { useCallback, useEffect, useMemo, useState } from 'react';

import { TerminalTile } from './terminal/TerminalTile';
import { resolveTerminalBase } from './terminal/endpoint';

// A minimal local shape of the board envelope, sufficient to render it.
//
// This is NOT the contract mirror. The hand-written TypeScript type that
// mirrors internal/board's Go struct field-for-field — and the parity check
// that fails when a field is renamed or dropped — is U7 (tk-eemvf.2), which
// lands src/contract.ts. Replace these declarations with an import from there;
// do not grow them into a second contract in the meantime.
type Tile = {
  id: string;
  rig: string;
  kind: string;
  title: string;
  severity: string;
  n_closed: number;
  m_total: number;
  open: number;
  in_progress: number;
  frontier: string;
  needs: string;
  stale_days: number;
  updated_at?: string;
  rank_score: number;
};

type Board = {
  generated_at: string;
  total: number;
  tiles: Tile[] | null;
  partial?: boolean;
  partial_errors?: string[];
};

// The server caches each computed board for 45s, so polling faster than that
// only re-reads the same bytes. This surface is pull-only by charter: it
// refreshes in place and never notifies.
const REFRESH_MS = 30_000;

// Document-relative on purpose. The app is served under a runtime-city-named
// prefix (/v0/city/<city>/svc/helm/), so an absolute '/helm' would address the
// supervisor root and 404. Relative to the document, this is <mount>/helm.
const BOARD_URL = 'helm';

async function fetchBoard(signal: AbortSignal): Promise<Board> {
  const res = await fetch(BOARD_URL, {
    signal,
    headers: { Accept: 'application/json' },
  });
  if (!res.ok) {
    throw new Error(`board request failed: HTTP ${res.status}`);
  }
  return (await res.json()) as Board;
}

export function App() {
  const [board, setBoard] = useState<Board | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [reloadToken, setReloadToken] = useState(0);

  const refresh = useCallback(() => setReloadToken((n) => n + 1), []);

  // Read once: the override is a launch-time knob, and re-reading it on every
  // render would tear the terminal down whenever the board refreshes.
  const terminalBase = useMemo(() => resolveTerminalBase(window.location.search), []);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    fetchBoard(controller.signal)
      .then((next) => {
        setBoard(next);
        setError(null);
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        setError(err instanceof Error ? err.message : String(err));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [reloadToken]);

  useEffect(() => {
    const timer = window.setInterval(refresh, REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [refresh]);

  const tiles = board?.tiles ?? [];

  return (
    <main>
      <header>
        <h1>helm</h1>
        <p className="sub">
          {board
            ? `${board.total} anchors · generated ${board.generated_at}`
            : loading
              ? 'loading the board…'
              : 'no board'}
        </p>
        <button type="button" onClick={refresh} disabled={loading}>
          {loading ? 'refreshing…' : 'refresh'}
        </button>
      </header>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      {board?.partial && (
        <p className="warn" role="status">
          Partial board — some rigs did not answer
          {board.partial_errors?.length ? `: ${board.partial_errors.join('; ')}` : '.'}
        </p>
      )}

      {board && tiles.length === 0 && !error && <p>No anchors need attention.</p>}

      {tiles.length > 0 && (
        <table>
          <thead>
            <tr>
              <th>severity</th>
              <th>id</th>
              <th>rig</th>
              <th>kind</th>
              <th>title</th>
              <th>progress</th>
              <th>open / wip</th>
              <th>stale</th>
              <th>frontier</th>
              <th>needs</th>
            </tr>
          </thead>
          <tbody>
            {tiles.map((tile) => (
              <tr key={tile.id}>
                <td>{tile.severity}</td>
                <td>{tile.id}</td>
                <td>{tile.rig}</td>
                <td>{tile.kind}</td>
                <td>{tile.title}</td>
                <td>
                  {tile.n_closed}/{tile.m_total}
                </td>
                <td>
                  {tile.open} / {tile.in_progress}
                </td>
                <td>{tile.stale_days}d</td>
                <td>{tile.frontier}</td>
                <td>{tile.needs}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {/* One terminal, not one per anchor: the city runs a single ttyd wired to
          a single session. Whether tiles get their own terminals is a ttyd
          wiring question that is deliberately still open — see the Terminal
          section of services/helm/README.md. */}
      <TerminalTile label="city terminal" base={terminalBase} />
    </main>
  );
}
