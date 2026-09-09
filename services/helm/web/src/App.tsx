import { useCallback, useEffect, useMemo, useState } from 'react';
import { CitySignals, DrillPanel } from './drill';

import { TerminalTile } from './terminal/TerminalTile';
import { resolveTerminalBase, resolveTerminalSession } from './terminal/endpoint';
import type { Board, PackBuild, Sitting, Tile } from './contract';

// The board shape lives in ./contract.ts — the hand-written mirror of the Go
// structs in internal/board, guarded by the parity check in
// contract_parity_test.go. Do not redeclare any part of the wire shape here;
// a second copy is the drift this app is built to avoid.

// The server caches each computed board for 45s, so polling faster than that
// only re-reads the same bytes. This surface is pull-only by charter: it
// refreshes in place and never notifies.
const REFRESH_MS = 30_000;

// The board arrives as ONE ranked list, and every row carries the band it
// belongs to in `tile.section` and — when it is one of several sharing a
// template — the `tile.cluster_key` that folds them. Those are derived once, in
// the shared Go layer, so the CLI board and this app cannot each invent their
// own split; this file READS the fields, it does not re-derive them. The order
// the bands read in is the derive layer's SectionOrder, mirrored here.
const SECTION_ORDER = ['review', 'gate', 'stalled', 'active', 'cleanup', 'done'] as const;

// The heading and one-line promise each band makes. The `done` band keeps the
// "recently closed" heading and the dismiss/window copy it always carried.
const SECTION_META: Record<string, { title: string; blurb: string }> = {
  review: { title: 'review', blurb: 'a pull request wants you' },
  gate: { title: 'gate', blurb: 'a person must answer — a decision, a demand, or a routed bead' },
  stalled: { title: 'stalled', blurb: 'open work nothing is moving' },
  active: { title: 'active', blurb: 'healthy in-flight work' },
  cleanup: { title: 'cleanup', blurb: 'finished, empty, or ruled — dispose of it' },
  done: { title: 'recently closed', blurb: 'closed while you were away' },
};

function sectionMeta(key: string): { title: string; blurb: string } {
  return SECTION_META[key] ?? { title: key, blurb: 'uncategorised' };
}

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

// The date the row started asking. `gc.takeaway_at` is when a sitting recorded
// what is owed; `updated_at` only bounds it from below, and a backend may read
// neither. Display only — the ORDER is the service's, and re-deriving it here
// is how the two would drift.
function owedSince(tile: Tile): string {
  // pr_owed_since first: on a merge anchor it is the only stamp that dates the
  // TURN. A wedged anchor is touched by every reconcile pass, so updated_at
  // reports the most neglected row as the freshest one.
  const stamp = tile.pr_owed_since ?? tile.takeaway_at ?? tile.updated_at;
  return stamp ? stamp.slice(0, 10) : 'unknown';
}

/** A merge anchor: the row the PR round-trip renders onto. */
function isPRRow(tile: Tile): boolean {
  return tile.pr_machine !== '';
}

/**
 * The pull request this row is about, as a link when one is open.
 *
 * Before the PR opens there is no link to give and the branch is the identity —
 * which is the common case among wedged rows, not an edge one. A row that can
 * name neither says so; it is the anchor at a human state that records no
 * branch, and there the absence is the whole answer. The conversation lives in
 * GitHub and the link is the one click to it; the board never reproduces a
 * comment thread.
 */
function PRLink({ tile }: { tile: Tile }) {
  if (!isPRRow(tile)) return null;
  if (tile.pr_number > 0 && tile.pr_url) {
    return (
      <a href={tile.pr_url} target="_blank" rel="noreferrer">
        PR #{tile.pr_number}
      </a>
    );
  }
  if (tile.pr_branch) {
    return <span className="sub">{tile.pr_branch}</span>;
  }
  return <span className="sub">not open yet</span>;
}

/**
 * What the board could not read about the pull requests it holds.
 *
 * The coverage sentence's empty state is a contract: it states its coverage or
 * it states the error, never a blank. PR rows add a way for that to go quietly
 * wrong, because an axis nothing has recorded looks exactly like an axis with
 * nothing to say — so the all-clear is withheld while any position is unread.
 * `owed` is a boolean and cannot carry the third value the axes do.
 *
 * Closed rows are excluded, and they have to be: the DONE band's rows carry the
 * same axes as live ones, unknowns included, while `owed` already excludes
 * them. Counting them would withhold the all-clear over rows the queue is right
 * to omit, for as long as the done window holds them.
 */
function prCoverage(tiles: Tile[]): { rows: number; gaps: string[] } {
  const rows = tiles.filter((t) => isPRRow(t) && !t.closed_at);
  const gaps: string[] = [];
  const noPosition = rows.filter((t) => t.pr_machine === 'unknown').length;
  const noConversation = rows.filter((t) => t.pr_conversation === 'unknown').length;
  const noApproval = rows.filter((t) => t.pr_machine === 'settled' && t.pr_approval === 'unknown').length;
  if (noPosition > 0) {
    gaps.push(`${noPosition} of ${rows.length} have no position recorded by the merge cadence`);
  }
  if (noConversation > 0) {
    gaps.push(
      `${noConversation} cannot say where the conversation stands (the acknowledgement watermarks are not built yet)`,
    );
  }
  if (noApproval > 0) {
    gaps.push(`${noApproval} are green with no readable answer on whether GitHub wants a review`);
  }
  return { rows: rows.length, gaps };
}

// The pack-build strip: what each compiled component is serving, and whether it
// matches its sources.
//
// It sits above the anchors because it qualifies them. Nothing in the running
// system builds these binaries — the launchers exec what a build order
// published — so this very page can be rendered by a binary older than the
// sources that describe it, and every row below would look normal while doing
// it. Nothing else on the page can say so.
//
// Rows are unconditional whenever the city has any record at all: a strip that
// appears only on trouble is a strip nobody learns to read. A city with no
// record renders nothing rather than an invented all-clear.
function PackHealth({ rows }: { rows: PackBuild[] }) {
  if (rows.length === 0) return null;
  return (
    <section className="pack-health" aria-labelledby="pack-health-heading">
      <h2 id="pack-health-heading">pack builds</h2>
      <ul>
        {rows.map((row) => (
          <li key={row.component} className={`pack-health__row pack-health__row--${row.severity}`}>
            <span className="pack-health__sev">{row.severity}</span>
            <span className="pack-health__name">{row.component}</span>
            {/* `detail` is derived server-side so this view and the CLI cannot
                disagree about what a row means. Render it; never re-derive it. */}
            <span className="pack-health__detail">{row.detail}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

// The drill-in entry point, shared by every table. A button rather than a
// clickable row so it is reachable by keyboard and announced as an action.
function DrillOpen({ id, onOpen }: { id: string; onOpen: (id: string) => void }) {
  return (
    <button type="button" className="drill-open" onClick={() => onOpen(id)}>
      {id}
    </button>
  );
}

// A render line for a section: a single tile, or the head of a cluster with
// every member behind it. Mirrors board.ClusterRow in the Go layer; the members
// list has length one for an unclustered row.
type RenderRow = { tile: Tile; members: Tile[] };

// clusterRows folds a section's tiles into render lines. Rows sharing a
// non-empty cluster_key become ONE line whose members are all of them, placed
// where the first member fell; an empty key is always its own line. This is the
// TypeScript twin of board.ClusterRows, kept trivial so the two cannot diverge:
// the hard decision — which rows share a key — was made once on the wire.
function clusterRows(tiles: Tile[]): RenderRow[] {
  const out: RenderRow[] = [];
  const at = new Map<string, number>();
  for (const tile of tiles) {
    const key = tile.cluster_key;
    if (!key) {
      out.push({ tile, members: [tile] });
      continue;
    }
    const i = at.get(key);
    if (i !== undefined) {
      out[i].members.push(tile);
      continue;
    }
    at.set(key, out.length);
    out.push({ tile, members: [tile] });
  }
  return out;
}

// The "N/M" progress cell. "—" means the row owns no child set at all — a
// decision never does, and a human/parked bead does exactly when it decomposed
// — rather than a set that happens to be empty, which the counts would report
// as 0/0 (the tk-a9k0l distinction).
function progressCell(tile: Tile): string {
  if (tile.m_total === 0 && (tile.kind === 'decision' || tile.kind === 'human' || tile.kind === 'parked')) {
    return '—';
  }
  return `${tile.n_closed}/${tile.m_total}`;
}

// One attention band, rendered as a table under a heading that names the move
// its rows want. A run of rows sharing a template folds to a single line that
// names the count and lists the members, so the operator reads one entry rather
// than N identical peers.
function SectionTable({
  sectionKey,
  tiles,
  drillTarget,
  onOpen,
}: {
  sectionKey: string;
  tiles: Tile[];
  drillTarget: string | null;
  onOpen: (id: string) => void;
}) {
  const meta = sectionMeta(sectionKey);
  const rows = clusterRows(tiles);
  const headingId = `section-${sectionKey}`;
  return (
    <section className={`board-section board-section--${sectionKey}`} aria-labelledby={headingId}>
      <h2 id={headingId}>{meta.title}</h2>
      <p className="sub">
        {meta.blurb} · {tiles.length}
        {sectionKey === 'done' && (
          <>
            . They sit below every live band, and no row leaves for being answered:{' '}
            <code>gc-helm dismiss &lt;id&gt;</code> clears one now. A row does age out of this band on a
            clock, once it has been closed longer than <code>GC_HELM_DONE_WINDOW</code> (default 7d,{' '}
            <code>0</code> off).
          </>
        )}
      </p>
      <table>
        <thead>
          <tr>
            <th>sev</th>
            <th>id</th>
            <th>rig</th>
            <th>kind</th>
            <th>pr</th>
            <th>title</th>
            <th>progress</th>
            <th>frontier</th>
            <th>needs</th>
            <th>owed since</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) =>
            row.members.length > 1 ? (
              <tr key={row.tile.cluster_key} className="cluster-row">
                <td>{row.members.length}×</td>
                {/* The shared needs spans the row's descriptive columns; the
                    member ids follow so each is still one drill click away —
                    folding gathers the rows, it does not hide them. */}
                <td colSpan={7}>{row.tile.needs}</td>
                <td colSpan={2} className="cluster-members">
                  {row.members.map((m) => (
                    <DrillOpen key={m.id} id={m.id} onOpen={onOpen} />
                  ))}
                </td>
              </tr>
            ) : (
              <tr key={row.tile.id} className={row.tile.id === drillTarget ? 'drilled' : undefined}>
                <td>{row.tile.severity}</td>
                <td>
                  <DrillOpen id={row.tile.id} onOpen={onOpen} />
                </td>
                <td>{row.tile.rig}</td>
                <td>{row.tile.kind}</td>
                <td>
                  <PRLink tile={row.tile} />
                </td>
                <td>{row.tile.title}</td>
                <td>{progressCell(row.tile)}</td>
                <td>{row.tile.frontier}</td>
                <td>{row.tile.needs}</td>
                <td>{sectionKey === 'done' ? '' : owedSince(row.tile)}</td>
              </tr>
            ),
          )}
        </tbody>
      </table>
    </section>
  );
}

// The conversation record: what is being talked about right now, and what the
// sittings that just ended concluded.
//
// A section rather than rows in a ranked table: a sitting is an event, not a
// demand, and ranking it against a stranded epic would be answering a question
// nobody asked. The bands say what needs doing; this says what is being said.
function Sittings({ sittings, now, onOpen }: { sittings: Sitting[]; now: number; onOpen: (id: string) => void }) {
  if (sittings.length === 0) return null;
  const running = sittings.filter(isRunning).length;

  return (
    <section className="sittings" aria-labelledby="sittings-heading">
      <h2 id="sittings-heading">converse sittings</h2>
      <p className="sub">
        {running} running · {sittings.length - running} closed recently. A running sitting is a
        conversation someone is still in; a closed one shows the outcome it closed on, and a
        running one shows an outcome only when a board dismissal stamped it without closing the
        visit. The takeaway shows on the sitting that wrote it.
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
                {/* A running sitting usually has no outcome, and the em dash is
                    that absence rather than an empty string. The exception is a
                    board dismissal that stamped gc.outcome but could not close
                    the visit: it leaves a running row honestly reading
                    "dismissed", the signal that the sitting is stuck open and
                    needs a manual close. */}
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

  // Group the ranked list into its bands by reading tile.section — the split
  // the derive layer already made. The wire order (owed rows first, oldest
  // first) is preserved within each band, so a band never disagrees with the
  // order that produced it.
  const bands = useMemo(() => {
    const buckets = new Map<string, Tile[]>();
    for (const t of tiles) {
      const arr = buckets.get(t.section);
      if (arr) arr.push(t);
      else buckets.set(t.section, [t]);
    }
    const ordered: { key: string; tiles: Tile[] }[] = [];
    for (const key of SECTION_ORDER) {
      const bt = buckets.get(key);
      if (bt && bt.length > 0) {
        ordered.push({ key, tiles: bt });
        buckets.delete(key);
      }
    }
    // A band a newer derivation added shows under its own key rather than
    // vanishing, after the known ones.
    for (const key of [...buckets.keys()].sort()) {
      ordered.push({ key, tiles: buckets.get(key)! });
    }
    return ordered;
  }, [tiles]);

  const owed = tiles.filter((t) => t.owed);
  const coverage = prCoverage(tiles);
  // Live rows are everything but the DONE band — what "needs attention" counts.
  const liveCount = tiles.filter((t) => t.section !== 'done').length;
  const doneCount = tiles.length - liveCount;
  // The rows that are live and NOT already in the owed cover-sheet's count.
  // "No other anchors need attention" is a claim about these, not about a board
  // whose only live rows are the ones the queue just named.
  const otherLive = tiles.filter((t) => !t.owed && t.section !== 'done');

  return (
    <main>
      <header>
        <h1>helm</h1>
        <p className="sub">
          {board
            ? `${owed.length ? `${owed.length} owed · ` : ''}${liveCount} anchors${
                doneCount ? ` · ${doneCount} closed` : ''
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

      {/* The queue status, and the only section that renders unconditionally.
          "Nothing is owed by you" is the most consequential sentence on this
          page and it is also what every failure path produces by default, so
          this states its COVERAGE or states the error — never a blank space
          that reads as an all-clear nobody earned. The owed ROWS themselves
          are in the review and gate bands below, oldest-owed first; this
          section is the queue's cover sheet, not a second copy of it. */}
      <section className="owed" aria-labelledby="owed-heading">
        <h2 id="owed-heading">owed by you</h2>
        {!board ? (
          <p className="sub" role="status">
            {error
              ? 'The board could not be read, so nothing here is proven clear.'
              : 'reading the board…'}
          </p>
        ) : owed.length === 0 ? (
          <p className="sub" role="status">
            {board.partial
              ? 'Nothing is owed by you — but some rigs did not answer, so this is not an all-clear.'
              : coverage.gaps.length > 0
                ? `Nothing readable is owed by you — but this is NOT an all-clear. Every store answered; of ${coverage.rows} pull requests, ${coverage.gaps.join('; ')}.`
                : coverage.rows > 0
                  ? `Nothing is owed by you. Every store answered; ${coverage.rows} pull requests read, all with a position.`
                  : 'Nothing is owed by you. Every store answered.'}
          </p>
        ) : (
          <p className="sub" role="status">
            {owed.length} owed by you, oldest first — in the review and gate bands below.
          </p>
        )}
      </section>

      <PackHealth rows={board?.pack_health ?? []} />

      {board && otherLive.length === 0 && !error && (
        <p>{owed.length > 0 ? 'No other anchors need attention.' : 'No anchors need attention.'}</p>
      )}

      {bands.map((band) => (
        <SectionTable
          key={band.key}
          sectionKey={band.key}
          tiles={band.tiles}
          drillTarget={drillTarget}
          onOpen={setDrillTarget}
        />
      ))}

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
