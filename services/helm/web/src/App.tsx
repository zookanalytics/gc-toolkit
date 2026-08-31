import { useCallback, useEffect, useMemo, useState } from 'react';
import { CitySignals, DrillPanel } from './drill';

import { TerminalTile } from './terminal/TerminalTile';
import { resolveTerminalBase, resolveTerminalSession } from './terminal/endpoint';
import type { Board, Sitting, Tile } from './contract';

// The board shape lives in ./contract.ts — the hand-written mirror of the Go
// structs in internal/board, guarded by the parity check in
// contract_parity_test.go. Do not redeclare any part of the wire shape here;
// a second copy is the drift this app is built to avoid.

// The server caches each computed board for 45s, so polling faster than that
// only re-reads the same bytes. This surface is pull-only by charter: it
// refreshes in place and never notifies.
const REFRESH_MS = 30_000;

// The board arrives as ONE ranked list carrying two different kinds of answer.
// Every kind but this one is something that wants doing, ranked by how badly. A
// `parked` tile is a conversation that already reached a takeaway: it wants
// nothing, it only has to stay FINDABLE. Ranking those against stranded epics is
// what tk-2v08m asks not to do — the LOW band already floors them, and splitting
// them into their own section keeps them out of the contest visually too.
//
// EXCEPT a tile whose `disposition_due` is set. That row was waiting on work
// that has since landed, so "wants nothing" has stopped being true of it: it
// owes the operator a disposition, and the service already bands it ELEVATED.
// Leaving it in the parked section would re-hide the one row this distinction
// exists to surface — the section's own sub-heading promises nothing there is
// waiting on work (tk-2plde).
//
// And EXCEPT a tile with OPEN CHILDREN. "Wants nothing" is equally untrue of a
// subject whose routed work is still in flight, and that work reaches the board
// only through this tile's roll-up — a plain child bead is never a tile of its
// own — so the quiet section is where it would disappear. The service bands
// these by their roll-up rather than flooring them (tk-a9k0l); this is the same
// row set, kept out of the same section for the same reason.
const PARKED_KIND = 'parked';

// A tile that belongs in the quiet parked section rather than the attention
// table: parked, not owed a disposition, and with no open work under it.
const isParked = (tile: Tile): boolean =>
  tile.kind === PARKED_KIND && !tile.disposition_due && tile.open === 0;

// A sitting is finished when its visit bead closed; anything else is a
// conversation someone is still in. Reading the status rather than the presence
// of closed_at keeps a sitting whose stamp could not be read on the running
// side, which is the side that shows a row rather than hides one.
const isRunning = (s: Sitting): boolean => s.status !== 'closed';

// How long ago a stamp was, in the coarsest unit that still says something. An
// absent stamp is unknown, never "just now": the sitting whose timestamp the
// source could not read must not read as the freshest one.
function shortAge(stamp: string | undefined, now: number): string {
  if (!stamp) return '?';
  const ms = Date.parse(stamp);
  if (Number.isNaN(ms)) return '?';
  const mins = Math.max(0, Math.floor((now - ms) / 60_000));
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 48) return `${hours}h`;
  return `${Math.floor(hours / 24)}d`;
}

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

// The drill-in entry point, shared by both tables. A button rather than a
// clickable row so it is reachable by keyboard and announced as an action.
function DrillOpen({ id, onOpen }: { id: string; onOpen: (id: string) => void }) {
  return (
    <button type="button" className="drill-open" onClick={() => onOpen(id)}>
      {id}
    </button>
  );
}

// The conversation record: what is being talked about right now, and what the
// sittings that just ended concluded.
//
// A section rather than rows in the ranked table, for the reason parked
// conversations are one: a sitting is an event, not a demand, and ranking it
// against a stranded epic would be answering a question nobody asked. The
// ranked table says what needs doing; this says what is being said.
function Sittings({ sittings, now, onOpen }: { sittings: Sitting[]; now: number; onOpen: (id: string) => void }) {
  if (sittings.length === 0) return null;
  const running = sittings.filter(isRunning).length;

  return (
    <section className="sittings" aria-labelledby="sittings-heading">
      <h2 id="sittings-heading">converse sittings</h2>
      <p className="sub">
        {running} running · {sittings.length - running} closed recently. A running sitting is a
        conversation someone is still in; a closed one shows the outcome it closed on and, when
        that sitting is the one that wrote it, the takeaway it left.
      </p>
      <table>
        <thead>
          <tr>
            <th>state</th>
            <th>sitting</th>
            <th>rig</th>
            <th>subject</th>
            <th>age</th>
            <th>outcome</th>
            <th>headline</th>
          </tr>
        </thead>
        <tbody>
          {sittings.map((s) => {
            const live = isRunning(s);
            return (
              <tr key={s.id} className={live ? 'sitting-running' : undefined}>
                <td>{live ? 'running' : 'closed'}</td>
                <td>{s.id}</td>
                <td>{s.rig}</td>
                <td>
                  {/* The subject is an anchor, so it drills in like any tile id. */}
                  <DrillOpen id={s.subject} onOpen={onOpen} />
                </td>
                <td>{shortAge(live ? s.opened_at : s.closed_at, now)}</td>
                {/* A running sitting has not concluded; the em dash is the
                    absence of an outcome, not an empty one. */}
                <td>{s.outcome || '—'}</td>
                <td>{s.takeaway || s.title}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </section>
  );
}

export function App() {
  const [board, setBoard] = useState<Board | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [reloadToken, setReloadToken] = useState(0);
  // The tile being drilled into, or null. A tile's id IS a bead id, which is
  // all the drill plane needs to open it.
  const [drillTarget, setDrillTarget] = useState<string | null>(null);

  const refresh = useCallback(() => setReloadToken((n) => n + 1), []);

  // Read once: these overrides are launch-time knobs, and re-reading them on
  // every render would tear the terminal down whenever the board refreshes.
  const terminalBase = useMemo(() => resolveTerminalBase(window.location.search), []);
  const terminalSession = useMemo(() => resolveTerminalSession(window.location.search), []);

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
  // Sitting ages are measured from the board's OWN generated_at, so a tab left
  // open does not age every row past what the gather actually saw. A board
  // without a readable stamp falls back to the wall clock.
  const renderedAt = useMemo(() => {
    const t = board ? Date.parse(board.generated_at) : NaN;
    return Number.isNaN(t) ? Date.now() : t;
  }, [board]);
  const attention = tiles.filter((tile) => !isParked(tile));
  const parked = tiles.filter(isParked);

  return (
    <main>
      <header>
        <h1>helm</h1>
        <p className="sub">
          {board
            ? `${attention.length} anchors${
                parked.length ? ` · ${parked.length} parked` : ''
              } · generated ${board.generated_at}`
            : loading
              ? 'loading the board…'
              : 'no board'}
        </p>
        <button type="button" onClick={refresh} disabled={loading}>
          {loading ? 'refreshing…' : 'refresh'}
        </button>
        <CitySignals />
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

      {board && attention.length === 0 && !error && <p>No anchors need attention.</p>}

      {attention.length > 0 && (
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
            {/* The drilled row is marked with a class, not aria-selected: that
                attribute is only meaningful on a grid/treegrid row, and this is
                a plain table. */}
            {attention.map((tile) => (
              <tr key={tile.id} className={tile.id === drillTarget ? 'drilled' : undefined}>
                <td>{tile.severity}</td>
                <td>
                  <DrillOpen id={tile.id} onOpen={setDrillTarget} />
                </td>
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

      {parked.length > 0 && (
        <section className="parked" aria-labelledby="parked-heading">
          <h2 id="parked-heading">parked conversations</h2>
          <p className="sub">
            Open beads whose visit ended with a takeaway. Nothing here is owed a disposition and
            nothing here has open work under it — either one moves the row up to the anchor
            table. These are threads to pick back up: press prefix+a and type the id.
          </p>
          {/* No progress columns. Every row that reaches this section has an
              empty open frontier — that is the filter — so open/wip reads 0 on
              all of them, and any row whose roll-up is still saying something
              is in the anchor table by construction. (Those columns are
              questionable there too; that is tk-x55wt's bead, not this one.) */}
          <table>
            <thead>
              <tr>
                <th>id</th>
                <th>rig</th>
                <th>title</th>
                <th>stale</th>
                <th>needs</th>
              </tr>
            </thead>
            <tbody>
              {parked.map((tile) => (
                <tr key={tile.id} className={tile.id === drillTarget ? 'drilled' : undefined}>
                  <td>
                    <DrillOpen id={tile.id} onOpen={setDrillTarget} />
                  </td>
                  <td>{tile.rig}</td>
                  <td>{tile.title}</td>
                  <td>{tile.stale_days}d</td>
                  <td>{tile.needs}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      <Sittings sittings={board?.sittings ?? []} now={renderedAt} onOpen={setDrillTarget} />

      {/* One terminal, not one per anchor — and that is now a LAYOUT decision,
          not a wiring limit. The city still runs a single ttyd, but its attach
          target is chosen per connection (`?arg=`, tk-rbf9r) rather than baked
          into the systemd unit, so this tile can be pointed at any live session
          and `?session=` does exactly that. What remains open is how many
          terminals a board should show and how they are arranged, which is the
          design handoff on tk-mw9qz — see the Terminal section of
          services/helm/README.md.

          What is deliberately NOT wired here is drill-target -> session: the
          board contract carries no session for a tile (contract.ts), and
          inventing a name from a bead's rig would be a guess that the guard
          would then refuse. Naming that mapping is part of tk-mw9qz. */}
      <TerminalTile
        label={terminalSession ?? 'city terminal'}
        base={terminalBase}
        session={terminalSession}
      />
      <DrillPanel beadId={drillTarget} onClose={() => setDrillTarget(null)} />
    </main>
  );
}
